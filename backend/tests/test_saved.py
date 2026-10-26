"""Saved experiences: a private read-later list."""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select

from app.ai.experience_ai import get_experience_ai
from app.main import app
from app.models import SavedExperience
from app.services.experiences import reactions as svc
from tests.test_experiences import FakeAI, publish_new

MEI = {"Authorization": "Bearer dev:mei"}
KAI = {"Authorization": "Bearer dev:kai"}
REVIEWER = {"Authorization": "Bearer dev:rita:reviewer"}


@pytest.fixture
def api():
    app.dependency_overrides[get_experience_ai] = FakeAI
    yield TestClient(app)
    app.dependency_overrides.pop(get_experience_ai, None)


def saved_ids(api, headers=KAI) -> list[str]:
    response = api.get("/api/me/saved", headers=headers)
    assert response.status_code == 200, response.text
    return [item["id"] for item in response.json()]


def test_save_list_and_unsave(api):
    first = publish_new(api)["id"]
    second = publish_new(api)["id"]
    assert api.put(f"/api/experiences/{first}/saved").status_code == 401
    assert api.get("/api/me/saved").status_code == 401

    saved = api.put(f"/api/experiences/{first}/saved", headers=KAI)
    assert saved.status_code == 200 and saved.json()["saved"] is True
    assert api.put(f"/api/experiences/{first}/saved", headers=KAI).status_code == 200  # idempotent
    api.put(f"/api/experiences/{second}/saved", headers=KAI)
    assert saved_ids(api) == [second, first]  # newest save first

    # Private: other readers and anonymous visitors see nothing about it.
    assert api.get(f"/api/experiences/{first}", headers=KAI).json()["saved"] is True
    assert api.get(f"/api/experiences/{first}", headers=MEI).json()["saved"] is False
    assert api.get(f"/api/experiences/{first}").json()["saved"] is False
    assert saved_ids(api, MEI) == []
    explore = api.get("/api/experiences", headers=KAI).json()["items"]
    assert {e["id"] for e in explore if e["saved"]} == {first, second}

    assert api.delete(f"/api/experiences/{first}/saved", headers=KAI).status_code == 204
    assert api.delete(f"/api/experiences/{first}/saved", headers=KAI).status_code == 204
    assert saved_ids(api) == [second]


def test_only_public_experiences_can_be_saved(api):
    draft = api.post(
        "/api/experiences",
        json={"topic_id": "life_adaptation", "identity_type": "other", "original_voice": "草稿"},
        headers=MEI,
    ).json()
    assert api.put(f"/api/experiences/{draft['id']}/saved", headers=KAI).status_code == 404
    assert api.put("/api/experiences/nope/saved", headers=KAI).status_code == 404


def test_hidden_blocked_and_deleted_drop_out(api, db):
    hidden = publish_new(api)["id"]
    blocked = publish_new(api, headers=MEI)["id"]
    deleted = publish_new(api)["id"]
    for eid in (hidden, blocked, deleted):
        api.put(f"/api/experiences/{eid}/saved", headers=KAI)

    api.post("/api/reports", json={"experience_id": hidden, "reason": "spam"}, headers=KAI)
    [item] = api.get("/api/admin/reports", headers=REVIEWER).json()
    api.post(
        f"/api/admin/reports/{item['report_id']}/resolve", json={"action": "hide"}, headers=REVIEWER
    )
    assert hidden not in saved_ids(api)
    # Unsaving still works for an experience that is no longer public.
    assert api.delete(f"/api/experiences/{hidden}/saved", headers=KAI).status_code == 204

    api.delete(f"/api/experiences/{deleted}", headers=MEI)
    assert db.scalar(select(func.count()).where(SavedExperience.experience_id == deleted)) == 0

    api.post("/api/blocks", json={"experience_id": blocked}, headers=KAI)
    assert saved_ids(api) == []


def test_saved_list_has_a_limit(api, monkeypatch):
    monkeypatch.setattr(svc, "MAX_SAVED", 1)
    first = publish_new(api)["id"]
    second = publish_new(api)["id"]
    api.put(f"/api/experiences/{first}/saved", headers=KAI)
    too_many = api.put(f"/api/experiences/{second}/saved", headers=KAI)
    assert too_many.status_code == 409
    assert too_many.json()["detail"]["code"] == "too_many_saved"


def test_account_deletion_removes_saves(api, db):
    eid = publish_new(api)["id"]
    api.put(f"/api/experiences/{eid}/saved", headers=KAI)
    assert api.delete("/api/me", headers=KAI).status_code == 204
    assert db.scalar(select(func.count()).select_from(SavedExperience)) == 0
