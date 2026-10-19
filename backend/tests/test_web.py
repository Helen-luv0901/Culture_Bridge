import gzip

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.main import app as main_app
from app.web import mount_web_app


def make(tmp_path) -> TestClient:
    (tmp_path / "index.html").write_text("<html>app</html>")
    (tmp_path / "main.dart.js").write_text("js")
    (tmp_path / "assets").mkdir()
    (tmp_path / "assets" / "logo.png").write_bytes(b"png")
    app = FastAPI()

    @app.get("/api/ping")
    def ping() -> dict:
        return {"ok": True}

    mount_web_app(app, tmp_path)
    return TestClient(app)


def test_spa_fallback_and_files(tmp_path):
    client = make(tmp_path)
    assert client.get("/api/ping").json() == {"ok": True}
    assert client.get("/").text == "<html>app</html>"
    deep = client.get("/actions/arc/progress")
    assert deep.text == "<html>app</html>" and deep.headers["cache-control"] == "no-cache"
    assert client.get("/main.dart.js").text == "js"
    assert client.get("/assets/logo.png").content == b"png"
    assert client.get("/api/unknown").status_code == 404
    # No escaping the web directory.
    assert client.get("/..%2F..%2Fetc%2Fpasswd").text == "<html>app</html>"


def test_gzipped_copy_is_sent_when_the_browser_accepts_it(tmp_path):
    client = make(tmp_path)
    code = "console.log('culture bridge');" * 200
    (tmp_path / "main.dart.js").write_text(code)
    (tmp_path / "main.dart.js.gz").write_bytes(gzip.compress(code.encode()))

    packed = client.get("/main.dart.js", headers={"Accept-Encoding": "gzip, br"})
    assert packed.headers["content-encoding"] == "gzip"
    assert packed.headers["vary"] == "Accept-Encoding"
    assert packed.headers["content-type"].startswith("text/javascript")
    assert packed.text == code  # the test client unpacks it

    plain = client.get("/main.dart.js", headers={"Accept-Encoding": "identity"})
    assert "content-encoding" not in plain.headers and plain.text == code
    refused = client.get("/main.dart.js", headers={"Accept-Encoding": "gzip;q=0"})
    assert "content-encoding" not in refused.headers
    # Files without a packed copy are sent as they are.
    assert "content-encoding" not in client.get("/assets/logo.png").headers


def test_unchanged_files_are_not_sent_again(tmp_path):
    client = make(tmp_path)
    for path in ("/main.dart.js", "/assets/logo.png", "/", "/explore"):
        first = client.get(path)
        assert first.headers["cache-control"] == "no-cache"
        again = client.get(path, headers={"If-None-Match": first.headers["etag"]})
        assert again.status_code == 304 and again.content == b""
        assert again.headers["etag"] == first.headers["etag"]
    # After a deploy the file changes, so its tag no longer matches.
    old = client.get("/main.dart.js").headers["etag"]
    (tmp_path / "main.dart.js").write_text("new build, longer")
    assert client.get("/main.dart.js", headers={"If-None-Match": old}).status_code == 200


def test_account_deletion_page_and_config():
    client = TestClient(main_app)
    page = client.get("/account-deletion")
    assert page.status_code == 200 and "刪除帳號" in page.text and "Delete account" in page.text
    assert client.get("/api/config").json() == {"environment": "development", "firebase": None}


def test_health_routes():
    # Cloud Run answers /healthz itself, so production checks use /health.
    client = TestClient(main_app)
    for path in ("/health", "/healthz"):
        response = client.get(path)
        assert response.status_code == 200 and response.json() == {"status": "ok"}


def test_firebase_web_config_from_env(monkeypatch):
    from app.core.config import get_settings

    for key, value in {
        "FIREBASE_WEB_API_KEY": "web-key",
        "FIREBASE_PROJECT_ID": "culture-bridge",
        "FIREBASE_AUTH_DOMAIN": "culture-bridge.firebaseapp.com",
        "FIREBASE_WEB_APP_ID": "1:2:web:3",
        "FIREBASE_MESSAGING_SENDER_ID": "2",
    }.items():
        monkeypatch.setenv(key, value)
    get_settings.cache_clear()
    try:
        firebase = TestClient(main_app).get("/api/config").json()["firebase"]
    finally:
        get_settings.cache_clear()
    assert firebase["apiKey"] == "web-key" and firebase["projectId"] == "culture-bridge"


def test_cors_only_for_local_development():
    client = TestClient(main_app)
    ok = client.options(
        "/api/actions",
        headers={"Origin": "http://localhost:5174", "Access-Control-Request-Method": "GET"},
    )
    assert ok.headers.get("access-control-allow-origin") == "http://localhost:5174"
    other = client.options(
        "/api/actions",
        headers={"Origin": "https://evil.example", "Access-Control-Request-Method": "GET"},
    )
    assert "access-control-allow-origin" not in other.headers
