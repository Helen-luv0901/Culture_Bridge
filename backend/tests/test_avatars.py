"""Profile photos: upload, clean-up, and where they are (and are not) shown."""

import base64
import io

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.ai.experience_ai import get_experience_ai
from app.main import app
from tests.test_author_names import KAI, MEI, publish_as
from tests.test_experiences import FakeAI


@pytest.fixture
def api():
    app.dependency_overrides[get_experience_ai] = FakeAI
    yield TestClient(app)
    app.dependency_overrides.pop(get_experience_ai, None)


def photo(fmt: str = "PNG", size=(640, 480), exif: bool = False) -> str:
    img = Image.new("RGBA" if fmt == "PNG" else "RGB", size, (200, 80, 40))
    out = io.BytesIO()
    if exif:
        data = Image.Exif()
        data[0x010F] = "SecretCam"  # Make; a stand-in for GPS and other metadata
        img.save(out, fmt, exif=data)
    else:
        img.save(out, fmt)
    return base64.b64encode(out.getvalue()).decode()


def upload(api, image: str, headers=MEI):
    return api.put("/api/me/avatar", json={"image": image}, headers=headers)


def test_upload_is_cropped_resized_and_stripped(api):
    res = upload(api, photo("JPEG", (1200, 800), exif=True))
    assert res.status_code == 200
    url = res.json()["avatar_url"]
    assert url.startswith("/api/avatars/")
    assert api.get("/api/me", headers=MEI).json()["avatar_url"] == url

    served = api.get(url)
    assert served.headers["content-type"] == "image/jpeg"
    assert "immutable" in served.headers["cache-control"]
    img = Image.open(io.BytesIO(served.content))
    assert img.size == (256, 256)
    assert b"SecretCam" not in served.content and not img.getexif()


def test_new_upload_replaces_the_old_photo(api):
    first = upload(api, photo()).json()["avatar_url"]
    second = upload(api, photo("WEBP")).json()["avatar_url"]
    assert first != second
    assert api.get(first).status_code == 404
    assert api.get(second).status_code == 200


def test_not_a_photo_is_refused(api):
    for image in [base64.b64encode(b"<svg></svg>").decode(), "not base64!", photo("BMP")]:
        res = upload(api, image)
        assert res.status_code == 422 and res.json()["detail"]["code"] == "avatar_invalid"
    assert api.get("/api/me", headers=MEI).json()["avatar_url"] is None


def test_guests_cannot_upload(api):
    assert api.put("/api/me/avatar", json={"image": photo()}).status_code == 401


def test_remove_photo(api):
    url = upload(api, photo()).json()["avatar_url"]
    assert api.delete("/api/me/avatar", headers=MEI).status_code == 204
    assert api.get("/api/me", headers=MEI).json()["avatar_url"] is None
    assert api.get(url).status_code == 404


def test_photo_shows_only_on_signed_posts_and_comments(api):
    api.patch("/api/me", json={"nickname": "小美"}, headers=MEI)
    url = upload(api, photo()).json()["avatar_url"]
    anonymous = publish_as(api, "anonymous").json()
    signed = publish_as(api, "nickname").json()

    def post(eid):
        return api.get(f"/api/experiences/{eid}", headers=KAI).json()

    assert post(signed["id"])["author_avatar_url"] == url
    assert post(anonymous["id"])["author_avatar_url"] is None
    listed = {e["id"]: e["author_avatar_url"] for e in api.get("/api/experiences").json()["items"]}
    assert listed == {anonymous["id"]: None, signed["id"]: url}

    # Comments: the photo only on the ones signed with the nickname.
    url_c = f"/api/experiences/{signed['id']}/comments"
    api.post(url_c, json={"body": "署名", "author_display": "nickname"}, headers=MEI)
    api.post(url_c, json={"body": "匿名"}, headers=MEI)
    photos = {c["body"]: c["author_avatar_url"] for c in api.get(url_c).json()}
    assert photos == {"署名": url, "匿名": None}


def test_deleting_the_account_deletes_the_photo(api):
    url = upload(api, photo()).json()["avatar_url"]
    assert api.delete("/api/me", headers=MEI).status_code == 204
    assert api.get(url).status_code == 404
