import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select

from app.ai.experience_ai import get_experience_ai
from app.main import app
from app.models import (
    AdminAction,
    Execution,
    Experience,
    ExperienceReaction,
    Report,
    User,
    VerificationRecord,
)
from tests.test_experiences import DRAFT, FakeAI, publish_new

MEI = {"Authorization": "Bearer dev:mei"}
KAI = {"Authorization": "Bearer dev:kai"}
LIN = {"Authorization": "Bearer dev:lin"}
JO = {"Authorization": "Bearer dev:jo"}
REVIEWER = {"Authorization": "Bearer dev:rita:reviewer"}
ADMIN = {"Authorization": "Bearer dev:ada:admin"}


@pytest.fixture
def api():
    app.dependency_overrides[get_experience_ai] = FakeAI
    yield TestClient(app)
    app.dependency_overrides.pop(get_experience_ai, None)


def report(api, eid, headers, reason="spam"):
    return api.post("/api/reports", json={"experience_id": eid, "reason": reason}, headers=headers)


def test_reports_auto_hide_and_review(api):
    eid = publish_new(api)["id"]
    assert report(api, eid, MEI).status_code == 422  # not your own
    assert report(api, "nope", KAI).status_code == 404
    assert report(api, eid, KAI).status_code == 201
    assert report(api, eid, KAI).status_code == 409
    report(api, eid, LIN, "harassment")
    assert api.get(f"/api/experiences/{eid}").status_code == 200
    report(api, eid, JO, "harassment")
    # Three different people reported it: hidden until someone reviews it.
    assert api.get(f"/api/experiences/{eid}").status_code == 404

    assert api.get("/api/admin/reports", headers=KAI).status_code == 403
    [item] = api.get("/api/admin/reports", headers=REVIEWER).json()
    assert item["report_count"] == 3 and item["reasons"] == {"spam": 1, "harassment": 2}
    assert item["target_status"] == "hidden"

    resolved = api.post(
        f"/api/admin/reports/{item['report_id']}/resolve",
        json={"action": "dismiss"},
        headers=REVIEWER,
    )
    assert resolved.status_code == 204
    assert api.get(f"/api/experiences/{eid}").status_code == 200
    assert api.get("/api/admin/reports", headers=REVIEWER).json() == []
    assert len(api.get("/api/admin/reports?status=dismissed", headers=REVIEWER).json()) == 1


def test_staff_can_hide_and_restore(api, db):
    eid = publish_new(api)["id"]
    report(api, eid, KAI, "personal_info")
    [item] = api.get("/api/admin/reports", headers=REVIEWER).json()
    api.post(
        f"/api/admin/reports/{item['report_id']}/resolve", json={"action": "hide"}, headers=REVIEWER
    )
    assert api.get(f"/api/experiences/{eid}").status_code == 404
    assert api.get("/api/me/experiences", headers=MEI).json()[0]["status"] == "hidden"
    api.post(f"/api/admin/experiences/{eid}/restore", headers=REVIEWER)
    assert api.get(f"/api/experiences/{eid}").status_code == 200
    actions = set(db.scalars(select(AdminAction.action)))
    assert {"report_hide", "restore"} <= actions


def test_blocking_hides_author_for_blocker_only(api):
    first = publish_new(api)["id"]
    second = publish_new(api, original_voice="另一則經驗")["id"]
    assert api.post("/api/blocks", json={"experience_id": first}, headers=MEI).status_code == 422
    block = api.post("/api/blocks", json={"experience_id": first}, headers=KAI).json()
    assert "dev-mei" not in str(block)

    ids_for_kai = {e["id"] for e in api.get("/api/experiences", headers=KAI).json()["items"]}
    assert first not in ids_for_kai and second not in ids_for_kai  # every post by that author
    assert api.get(f"/api/experiences/{second}", headers=KAI).status_code == 404
    assert {first, second} <= {
        e["id"] for e in api.get("/api/experiences", headers=LIN).json()["items"]
    }

    [listed] = api.get("/api/me/blocks", headers=KAI).json()
    assert listed["id"] == block["id"]
    assert api.delete(f"/api/me/blocks/{block['id']}", headers=LIN).status_code == 404
    assert api.delete(f"/api/me/blocks/{block['id']}", headers=KAI).status_code == 204
    assert api.get(f"/api/experiences/{second}", headers=KAI).status_code == 200


def test_roles_are_admin_only(api, db):
    api.get("/api/me", headers=KAI)
    assert (
        api.put(
            "/api/admin/users/dev-kai/role", json={"role": "reviewer"}, headers=REVIEWER
        ).status_code
        == 403
    )
    assert (
        api.put(
            "/api/admin/users/dev-kai/role", json={"role": "reviewer"}, headers=ADMIN
        ).status_code
        == 204
    )
    assert db.get(User, "dev-kai").role == "reviewer"
    staff = {u["id"]: u["role"] for u in api.get("/api/admin/users", headers=ADMIN).json()}
    assert staff["dev-kai"] == "reviewer" and staff["dev-ada"] == "admin"
    assert "dev-lin" not in staff
    assert api.get("/api/admin/users", headers=REVIEWER).status_code == 403
    assert (
        api.put(
            "/api/admin/users/dev-ada/role", json={"role": "student"}, headers=ADMIN
        ).status_code
        == 403
    )


def test_delete_account_removes_everything(api, db):
    from app.core.config import get_settings
    from app.seed import seed

    seed(db, get_settings().demo_content_path)
    mine = publish_new(api)["id"]
    api.post("/api/experiences", json=DRAFT, headers=MEI)  # a draft too
    api.put("/api/experiences/professor-see/reactions/helpful", headers=MEI)
    report(api, "professor-see", MEI)
    api.post("/api/blocks", json={"experience_id": "first-rental"}, headers=MEI)
    execution = api.post("/api/actions/arc/executions", json={}, headers=MEI).json()
    api.post(
        f"/api/executions/{execution['id']}/feedback",
        json={"kind": "stuck", "step_id": execution["steps"][0]["step_id"]},
        headers=MEI,
    )
    # Someone else reacted to and answered Mei's experience.
    api.put(f"/api/experiences/{mine}/reactions/helpful", headers=KAI)
    other = publish_new(api, headers=KAI, different_from_id=mine, original_voice="不同")["id"]

    assert api.delete("/api/me", headers=MEI).status_code == 204

    assert db.get(User, "dev-mei") is None
    assert db.scalar(select(func.count()).where(Experience.author_id == "dev-mei")) == 0
    assert db.scalar(select(func.count()).where(ExperienceReaction.user_id == "dev-mei")) == 0
    assert db.scalar(select(func.count()).where(Execution.user_id == "dev-mei")) == 0
    assert db.scalar(select(func.count()).where(Report.reporter_id == "dev-mei")) == 0
    assert api.get(f"/api/experiences/{mine}").status_code == 404
    # Kai's own experience stays, just no longer linked to the deleted one.
    assert api.get(f"/api/experiences/{other}").json()["responds_to_id"] is None
    assert api.get("/api/experiences/professor-see").json()["helpful_count"] == 0
    # Signing in again starts a brand-new, empty account.
    assert api.get("/api/me/experiences", headers=MEI).json() == []


def test_deleting_a_reviewer_keeps_verification_evidence(api, db):
    from app.core.config import get_settings
    from app.seed import seed

    seed(db, get_settings().demo_content_path)
    record = db.scalar(select(VerificationRecord))
    record.reviewer_id = "dev-rita"
    api.get("/api/me", headers=REVIEWER)
    db.commit()
    assert api.delete("/api/me", headers=REVIEWER).status_code == 204
    db.expire_all()
    assert db.get(VerificationRecord, record.id).reviewer_id == "deleted-staff"
    assert api.get("/api/actions/work-permit").json()["verification_status"] == "verified"
