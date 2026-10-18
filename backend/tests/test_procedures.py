import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select

from app.core.config import get_settings
from app.main import app
from app.models import AdminAction
from app.seed import seed

STUDENT = {"Authorization": "Bearer dev:mei"}
OTHER = {"Authorization": "Bearer dev:kai"}
REVIEWER = {"Authorization": "Bearer dev:rita:reviewer"}


@pytest.fixture
def api() -> TestClient:
    return TestClient(app)


@pytest.fixture
def seeded(db):
    return seed(db, get_settings().demo_content_path)


def test_seed_is_idempotent(db, seeded):
    assert seeded == {"actions": 6, "experiences": 3}
    assert seed(db, get_settings().demo_content_path) == {"actions": 0, "experiences": 0}


def test_public_list_and_detail(api, seeded):
    actions = {a["id"]: a for a in api.get("/api/actions").json()}
    assert len(actions) == 6
    permit = actions["work-permit"]
    assert permit["title"] == {"zh": "申請工作證", "en": "Apply for a Work Permit"}
    assert permit["verification_status"] == "verified" and permit["last_verified_at"]
    assert actions["insurance"]["verification_status"] == "needs_review"
    assert actions["insurance"]["last_verified_at"] is None
    assert permit["recent_success_count"] == 0  # real completions only, not demo numbers

    detail = api.get("/api/actions/work-permit").json()
    assert [s["position"] for s in detail["steps"]] == [1, 2, 3, 4, 5]
    assert detail["steps"][0]["title"]["en"] == "Prepare your ARC"
    assert detail["sources"] and "Demo data" in detail["sources"][0]["evidence_note"]
    assert api.get("/api/actions/nope").status_code == 404


def test_student_execution_flow(api, seeded):
    assert api.post("/api/actions/arc/executions", json={}).status_code == 401
    res = api.post(
        "/api/actions/arc/executions", json={"identity_type": "degree_student"}, headers=STUDENT
    )
    assert res.status_code == 201
    execution = res.json()
    again = api.post("/api/actions/arc/executions", json={}, headers=STUDENT)
    assert again.status_code == 200 and again.json()["id"] == execution["id"]
    assert all(s["state"] == "pending" for s in execution["steps"])

    eid, first, second = execution["id"], execution["steps"][0], execution["steps"][1]
    done = api.put(
        f"/api/executions/{eid}/steps/{first['step_id']}", json={"state": "done"}, headers=STUDENT
    ).json()
    assert done["steps"][0]["state"] == "done"

    no_step = api.post(f"/api/executions/{eid}/feedback", json={"kind": "stuck"}, headers=STUDENT)
    assert no_step.status_code == 422
    stuck = api.post(
        f"/api/executions/{eid}/feedback",
        json={
            "kind": "stuck",
            "step_id": second["step_id"],
            "category": "documents",
            "original_voice": "櫃台說要多一份文件",
        },
        headers=STUDENT,
    )
    assert stuck.status_code == 201
    mine = api.get("/api/me/executions", headers=STUDENT).json()
    assert mine[0]["steps"][1]["state"] == "stuck"
    assert api.get("/api/actions/arc").json()["steps"][1]["recent_stuck_count"] == 1

    # Other students cannot see or touch it.
    assert api.get(f"/api/executions/{eid}", headers=OTHER).status_code == 404
    assert api.get("/api/me/executions", headers=OTHER).json() == []

    finished = api.post(
        f"/api/executions/{eid}/finish", json={"outcome": "success"}, headers=STUDENT
    )
    assert finished.json()["outcome"] == "success"
    assert api.get("/api/me/executions", headers=STUDENT).json() == []
    assert len(api.get("/api/me/executions?include_finished=true", headers=STUDENT).json()) == 1
    again = api.put(
        f"/api/executions/{eid}/steps/{first['step_id']}",
        json={"state": "pending"},
        headers=STUDENT,
    )
    assert again.status_code == 409
    assert api.get("/api/actions/arc").json()["recent_success_count"] == 1


NEW_ACTION = {
    "slug": "student-id",
    "title_zh": "補辦學生證",
    "title_en": "Replace a Student ID",
    "applicable_to": "逢甲大學在學學生",
    "applicable_to_en": "Students enrolled at FCU",
    "steps": [
        {"title_zh": "填寫申請表", "title_en": "Fill in the form"},
        {"title_zh": "繳費", "title_en": "Pay the fee"},
    ],
}


def test_admin_requires_staff(api, seeded):
    assert api.get("/api/admin/actions").status_code == 401
    assert api.get("/api/admin/actions", headers=STUDENT).status_code == 403


def test_admin_versioning_and_verification(api, db, seeded):
    draft = api.post("/api/admin/actions", json=NEW_ACTION, headers=REVIEWER).json()
    assert draft["version_number"] == 1 and draft["published_at"] is None
    assert api.post("/api/admin/actions", json=NEW_ACTION, headers=REVIEWER).status_code == 409
    assert "student-id" not in {a["id"] for a in api.get("/api/actions").json()}

    source = api.post(
        "/api/admin/sources",
        json={
            "title": "逢甲大學註冊組：學生證補發",
            "url": "https://example.edu.tw/student-id",
            "publisher": "逢甲大學",
            "kind": "institution",
            "accessed_at": "2026-10-13T00:00:00Z",
        },
        headers=REVIEWER,
    ).json()
    vid = draft["id"]
    no_source = {"source_id": source["id"], "decision": "verified", "note": "checked"}
    assert (
        api.post(f"/api/admin/versions/{vid}/verifications", json=no_source, headers=REVIEWER)
    ).status_code == 422
    api.put(
        f"/api/admin/versions/{vid}/sources/{source['id']}",
        json={"evidence_note": "補發流程與費用"},
        headers=REVIEWER,
    )
    published = api.post(f"/api/admin/versions/{vid}/publish", headers=REVIEWER).json()
    assert published["published_at"]
    edit = api.put(f"/api/admin/versions/{vid}", json=NEW_ACTION, headers=REVIEWER)
    assert edit.status_code == 409 and edit.json()["detail"]["code"] == "version_published"

    verified = api.post(
        f"/api/admin/versions/{vid}/verifications", json=no_source, headers=REVIEWER
    ).json()
    assert verified["verification_status"] == "verified"
    public = api.get("/api/actions/student-id").json()
    assert public["verification_status"] == "verified" and public["last_verified_at"]

    # A student is mid-way through v1 when v2 is published.
    execution = api.post("/api/actions/student-id/executions", json={}, headers=STUDENT).json()
    v2 = api.post("/api/admin/actions/student-id/versions", headers=REVIEWER).json()
    assert v2["version_number"] == 2 and v2["verification_status"] == "unverified"
    assert [s["title_zh"] for s in v2["steps"]] == ["填寫申請表", "繳費"]
    assert len(v2["sources"]) == 1
    assert api.post("/api/admin/actions/student-id/versions", headers=REVIEWER).status_code == 409
    changed = dict(
        NEW_ACTION, steps=NEW_ACTION["steps"] + [{"title_zh": "領取", "title_en": "Pick up"}]
    )
    api.put(f"/api/admin/versions/{v2['id']}", json=changed, headers=REVIEWER)
    api.post(f"/api/admin/versions/{v2['id']}/publish", headers=REVIEWER)

    public = api.get("/api/actions/student-id").json()
    assert public["version_number"] == 2 and len(public["steps"]) == 3
    assert public["verification_status"] == "unverified" and public["last_verified_at"] is None
    mine = api.get(f"/api/executions/{execution['id']}", headers=STUDENT).json()
    assert mine["version_number"] == 1 and mine["newer_version_available"] is True
    assert len(mine["steps"]) == 2

    versions = api.get("/api/admin/actions/student-id/versions", headers=REVIEWER).json()
    assert [v["version_number"] for v in versions] == [2, 1]
    assert db.scalar(select(func.count()).select_from(AdminAction)) >= 7

    api.post("/api/admin/actions/student-id/archive", headers=REVIEWER)
    assert api.get("/api/actions/student-id").status_code == 404


def test_step_notes_have_an_english_version(api, seeded):
    body = NEW_ACTION | {
        "slug": "notes-en",
        "steps": [
            {
                "title_zh": "繳費",
                "title_en": "Pay the fee",
                "notes": "費用200元。",
                "notes_en": "The fee is NT$200.",
            },
            {"title_zh": "領取", "title_en": "Pick up", "notes": "只有中文。"},
        ],
    }
    draft = api.post("/api/admin/actions", json=body, headers=REVIEWER).json()
    assert [s["notes_en"] for s in draft["steps"]] == ["The fee is NT$200.", None]
    api.post(f"/api/admin/versions/{draft['id']}/publish", headers=REVIEWER)
    steps = api.get("/api/actions/notes-en").json()["steps"]
    assert [(s["notes"], s["notes_en"]) for s in steps] == [
        ("費用200元。", "The fee is NT$200."),
        ("只有中文。", None),
    ]
    # A new version starts from the published one, English notes included.
    v2 = api.post("/api/admin/actions/notes-en/versions", headers=REVIEWER).json()
    assert v2["steps"][0]["notes_en"] == "The fee is NT$200."


def test_importer_carries_english_notes(db):
    from app.official_content import _content

    card = {
        "slug": "x",
        "title_zh": "標題",
        "title_en": "Title",
        "applicable_to": "所有人",
        "sources": [{"publisher": "移民署"}],
        "steps": [{"title_zh": "一", "title_en": "One", "notes": "看[1]", "notes_en": "See NIA"}],
    }
    step = _content(card).steps[0]
    assert (step.notes, step.notes_en) == ("看（移民署）", "See NIA")


def test_feedback_review_queue(api, seeded):
    execution = api.post("/api/actions/bank/executions", json={}, headers=STUDENT).json()
    step = execution["steps"][0]["step_id"]
    api.post(
        f"/api/executions/{execution['id']}/feedback",
        json={"kind": "stuck", "step_id": step, "category": "website"},
        headers=STUDENT,
    )
    queue = api.get("/api/admin/feedback", headers=REVIEWER).json()
    assert len(queue) == 1 and queue[0]["action_id"] == "bank"
    assert queue[0]["step_title"]["zh"]
    api.post(
        f"/api/admin/feedback/{queue[0]['id']}", json={"review_state": "reviewed"}, headers=REVIEWER
    )
    assert api.get("/api/admin/feedback", headers=REVIEWER).json() == []
    assert len(api.get("/api/admin/feedback?state=reviewed", headers=REVIEWER).json()) == 1
