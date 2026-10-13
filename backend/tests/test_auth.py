import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.core.auth import (
    CurrentUser,
    FirebaseTokenVerifier,
    OptionalUser,
    RequiredUser,
    StaffUser,
)
from app.core.config import get_settings
from app.core.errors import ApiError, register_error_handlers

probe = FastAPI()
register_error_handlers(probe)


@probe.get("/optional")
def optional(user: OptionalUser) -> dict:
    return {"user": user.__dict__ if user else None}


@probe.get("/required")
def required(user: RequiredUser) -> dict:
    return {"id": user.id}


@probe.get("/staff")
def staff(user: StaffUser) -> dict:
    return {"id": user.id}


client = TestClient(probe)


def bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_guest_and_required_login():
    assert client.get("/optional").json() == {"user": None}
    res = client.get("/required")
    assert res.status_code == 401 and res.json() == {"detail": {"code": "login_required"}}


def test_dev_token_creates_user_once(db):
    first = client.get("/optional", headers=bearer("dev:mei")).json()["user"]
    again = client.get("/optional", headers={"X-Dev-User-Id": "mei"}).json()["user"]
    assert first == again == {"id": "dev-mei", "role": "student", "preferred_locale": "zh-Hant"}


def test_dev_role_and_staff_guard():
    assert client.get("/staff", headers=bearer("dev:kai")).status_code == 403
    assert client.get("/staff", headers=bearer("dev:kai:reviewer")).json() == {"id": "dev-kai"}
    assert client.get("/staff", headers=bearer("dev:kai:wizard")).status_code == 401


def test_bad_headers_are_rejected():
    assert client.get("/optional", headers={"Authorization": "Basic abc"}).status_code == 401
    assert client.get("/optional", headers=bearer("dev:../etc")).status_code == 401
    res = client.get("/optional", headers=bearer("real-firebase-token"))
    assert res.json() == {"detail": {"code": "login_not_configured"}}


def test_dev_tokens_rejected_outside_development(monkeypatch):
    monkeypatch.setenv("APP_ENV", "production")
    get_settings.cache_clear()
    try:
        assert client.get("/optional", headers=bearer("dev:mei")).status_code == 401
        assert client.get("/optional", headers={"X-Dev-User-Id": "mei"}).json() == {"user": None}
    finally:
        get_settings.cache_clear()


def test_firebase_verifier_checks_issuer(monkeypatch):
    verifier = FirebaseTokenVerifier("culture-bridge")
    monkeypatch.setattr(verifier, "_get_certs", lambda: {"k": "cert"})
    monkeypatch.setattr(
        "app.core.auth.jwt.decode",
        lambda *a, **k: {"iss": "https://securetoken.google.com/other", "sub": "u"},
    )
    with pytest.raises(ApiError):
        verifier.verify("t")
    monkeypatch.setattr(
        "app.core.auth.jwt.decode",
        lambda *a, **k: {"iss": "https://securetoken.google.com/culture-bridge", "sub": "uid1"},
    )
    assert verifier.verify("t").subject == "firebase:uid1"

    def bad(*a, **k):
        raise ValueError("expired")

    monkeypatch.setattr("app.core.auth.jwt.decode", bad)
    with pytest.raises(ApiError) as exc:
        verifier.verify("t")
    assert exc.value.code == "invalid_token"


def test_current_user_staff_flag():
    assert CurrentUser(id="x", role="admin").is_staff
    assert not CurrentUser(id="x").is_staff
