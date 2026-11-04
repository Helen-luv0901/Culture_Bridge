"""Request bodies are capped before they are read (app/core/body_limit.py)."""

import base64
import os

from fastapi.testclient import TestClient

from app.main import app

api = TestClient(app)
MEI = {"Authorization": "Bearer dev:mei"}


def test_an_oversized_body_is_refused_before_it_is_read():
    res = api.post("/api/client-errors", json={"message": "x" * 70_000})
    assert res.status_code == 413
    assert res.json() == {"detail": {"code": "request_too_large"}}


def test_a_normal_body_still_works():
    assert api.post("/api/client-errors", json={"message": "boom"}).status_code == 204


def test_a_body_without_content_length_is_counted_as_it_arrives():
    def chunks():
        for _ in range(10):
            yield b"x" * 10_000

    res = api.post(
        "/api/client-errors", content=chunks(), headers={"Content-Type": "application/json"}
    )
    assert res.status_code == 413 and res.json()["detail"]["code"] == "request_too_large"

    small = api.post(
        "/api/client-errors",
        content=iter([b'{"message": ', b'"boom"}']),
        headers={"Content-Type": "application/json"},
    )
    assert small.status_code == 204


def test_a_photo_sized_body_is_allowed_on_the_avatar_route(db):
    # 5 MB of noise: past the body limit, so a refusal now comes from the photo check.
    image = base64.b64encode(os.urandom(5_000_000)).decode()
    res = api.put("/api/me/avatar", json={"image": image}, headers=MEI)
    assert res.status_code == 422 and res.json()["detail"]["code"] == "avatar_invalid"
    # The same body anywhere else is refused.
    assert api.patch("/api/me", json={"image": image}, headers=MEI).status_code == 413
