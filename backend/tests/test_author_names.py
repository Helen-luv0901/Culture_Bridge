"""Optional nickname / real name and signing an experience with one of them."""

import pytest
from fastapi.testclient import TestClient

from app.ai.experience_ai import get_experience_ai
from app.main import app
from tests.test_experiences import DRAFT, FakeAI

MEI = {"Authorization": "Bearer dev:mei"}
KAI = {"Authorization": "Bearer dev:kai"}


@pytest.fixture
def api():
    app.dependency_overrides[get_experience_ai] = FakeAI
    yield TestClient(app)
    app.dependency_overrides.pop(get_experience_ai, None)


def publish_as(api, display: str, headers=MEI):
    draft = api.post("/api/experiences", json=DRAFT, headers=headers).json()
    summary = api.post(f"/api/experiences/{draft['id']}/summaries", headers=headers).json()
    return api.post(
        f"/api/experiences/{draft['id']}/publish",
        json={"summary_id": summary["id"], "author_display": display},
        headers=headers,
    )


def test_names_are_optional_and_editable(api):
    me = api.get("/api/me", headers=MEI).json()
    assert me["nickname"] is None and me["real_name"] is None

    updated = api.patch(
        "/api/me", json={"nickname": "  小  美 ", "real_name": "王小美"}, headers=MEI
    ).json()
    assert updated["nickname"] == "小 美" and updated["real_name"] == "王小美"
    assert updated["preferred_locale"] == "zh-Hant"  # untouched fields stay

    # Only the fields sent change; "" clears a name.
    api.patch("/api/me", json={"preferred_locale": "en"}, headers=MEI)
    cleared = api.patch("/api/me", json={"real_name": ""}, headers=MEI).json()
    assert cleared == updated | {"preferred_locale": "en", "real_name": None}

    assert api.patch("/api/me", json={"nickname": "字" * 31}, headers=MEI).status_code == 422
    assert api.patch("/api/me", json={"real_name": "字" * 51}, headers=MEI).status_code == 422


def test_signing_with_a_name_needs_that_name(api):
    missing = publish_as(api, "nickname")
    assert missing.status_code == 422
    assert missing.json()["detail"]["code"] == "nickname_missing"
    assert publish_as(api, "real_name").json()["detail"]["code"] == "real_name_missing"


def test_public_name_follows_the_choice(api):
    api.patch("/api/me", json={"nickname": "小美", "real_name": "王小美"}, headers=MEI)
    anonymous = publish_as(api, "anonymous").json()
    by_nickname = publish_as(api, "nickname").json()
    by_real_name = publish_as(api, "real_name").json()
    assert by_nickname["author_display"] == "nickname"

    def name(eid, headers=None):
        return api.get(f"/api/experiences/{eid}", headers=headers or {}).json()["author_name"]

    assert name(anonymous["id"]) is None
    assert name(by_nickname["id"]) == "小美"
    assert name(by_real_name["id"], KAI) == "王小美"
    listed = {e["id"]: e["author_name"] for e in api.get("/api/experiences").json()["items"]}
    assert listed == {
        anonymous["id"]: None,
        by_nickname["id"]: "小美",
        by_real_name["id"]: "王小美",
    }
    # The account itself never appears.
    assert "dev-mei" not in api.get("/api/experiences").text

    # Names are read live: renaming updates old posts, clearing makes them anonymous.
    api.patch("/api/me", json={"nickname": "Mei", "real_name": None}, headers=MEI)
    assert name(by_nickname["id"]) == "Mei"
    assert name(by_real_name["id"]) is None


def test_deleting_the_account_removes_the_names(api):
    api.patch("/api/me", json={"nickname": "小美"}, headers=MEI)
    publish_as(api, "nickname")
    assert api.delete("/api/me", headers=MEI).status_code == 204
    assert api.get("/api/me", headers=MEI).json()["nickname"] is None
    assert "小美" not in api.get("/api/experiences").text
