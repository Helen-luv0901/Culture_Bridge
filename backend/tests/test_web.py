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


def test_account_deletion_page_and_config():
    client = TestClient(main_app)
    page = client.get("/account-deletion")
    assert page.status_code == 200 and "刪除帳號" in page.text and "Delete account" in page.text
    assert client.get("/api/config").json() == {"environment": "development", "firebase": None}


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
