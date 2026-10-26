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
    UserBlock,
    VerificationRecord,
)
from app.services import moderation
from app.services.common import DailyAllowance
from tests.test_author_names import publish_as
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


def test_a_block_hides_only_the_persona_it_was_made_from(api):
    api.patch("/api/me", json={"nickname": "小美"}, headers=MEI)
    anonymous = publish_new(api)["id"]
    named = publish_as(api, "nickname").json()["id"]
    comments = f"/api/experiences/{publish_new(api, headers=LIN)['id']}/comments"
    api.post(comments, json={"body": "匿名留言"}, headers=MEI)
    api.post(comments, json={"body": "具名留言", "author_display": "nickname"}, headers=MEI)

    def posts_for_kai() -> set[str]:
        return {e["id"] for e in api.get("/api/experiences", headers=KAI).json()["items"]}

    def comments_for_kai() -> set[str]:
        return {c["body"] for c in api.get(comments, headers=KAI).json()}

    by_anonymous = api.post("/api/blocks", json={"experience_id": anonymous}, headers=KAI).json()
    assert by_anonymous["persona"] == "anonymous"
    # The named post and the signed comment stay, so the block can't tie "小美" to the post.
    assert anonymous not in posts_for_kai() and named in posts_for_kai()
    assert comments_for_kai() == {"具名留言"}

    api.delete(f"/api/me/blocks/{by_anonymous['id']}", headers=KAI)
    by_name = api.post("/api/blocks", json={"experience_id": named}, headers=KAI).json()
    assert by_name["persona"] == "named" and by_name["id"] != by_anonymous["id"]
    assert named not in posts_for_kai() and anonymous in posts_for_kai()
    assert comments_for_kai() == {"匿名留言"}


def test_blocks_from_before_personas_still_hide_both(api, db):
    api.patch("/api/me", json={"nickname": "小美"}, headers=MEI)
    anonymous = publish_new(api)["id"]
    named = publish_as(api, "nickname").json()["id"]
    api.get("/api/me", headers=KAI)  # creates the account
    db.add(UserBlock(blocker_id="dev-kai", blocked_id="dev-mei", persona=None))
    db.commit()

    posts = {e["id"] for e in api.get("/api/experiences", headers=KAI).json()["items"]}
    assert anonymous not in posts and named not in posts
    [listed] = api.get("/api/me/blocks", headers=KAI).json()
    assert listed["persona"] is None
    # Blocking again finds the older block instead of adding one.
    again = api.post("/api/blocks", json={"experience_id": named}, headers=KAI).json()
    assert again["id"] == listed["id"]


def test_new_blocks_are_capped_per_day(api, monkeypatch):
    monkeypatch.setattr(moderation, "MAX_BLOCKS_PER_DAY", 1)
    monkeypatch.setattr(moderation, "_new_blocks", DailyAllowance("blocks"))
    first = publish_new(api)["id"]
    second = publish_new(api, headers=LIN)["id"]
    assert api.post("/api/blocks", json={"experience_id": first}, headers=KAI).status_code == 201
    # Blocking the same author again is not a new block.
    assert api.post("/api/blocks", json={"experience_id": first}, headers=KAI).status_code == 201
    over = api.post("/api/blocks", json={"experience_id": second}, headers=KAI)
    assert over.status_code == 429 and over.json()["detail"]["code"] == "daily_limit_reached"


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


def test_reports_are_capped_per_day(api, monkeypatch):
    monkeypatch.setattr(moderation, "MAX_REPORTS_PER_DAY", 1)
    first = publish_new(api)["id"]
    second = publish_new(api, original_voice="另一則經驗")["id"]
    assert report(api, first, KAI).status_code == 201
    over = report(api, second, KAI)
    assert over.status_code == 429 and over.json()["detail"]["code"] == "daily_limit_reached"


def test_staff_deleting_a_comment_is_logged(api, db):
    eid = publish_new(api)["id"]
    url = f"/api/experiences/{eid}/comments"
    comment = api.post(url, json={"body": "買我的東西"}, headers=KAI).json()
    assert api.delete(f"/api/comments/{comment['id']}", headers=REVIEWER).status_code == 204
    [entry] = db.scalars(select(AdminAction).where(AdminAction.target_type == "comment")).all()
    assert entry.action == "delete" and entry.target_id == comment["id"]


def test_comment_counts_leave_out_blocked_comments(api):
    commented = publish_new(api, headers=LIN)["id"]
    blocked_post = publish_new(api)["id"]
    url = f"/api/experiences/{commented}/comments"
    api.post(url, json={"body": "匿名留言"}, headers=MEI)
    api.post(url, json={"body": "另一則"}, headers=JO)
    api.post("/api/blocks", json={"experience_id": blocked_post}, headers=KAI)

    def count_for(headers) -> int:
        items = api.get("/api/experiences", headers=headers).json()["items"]
        return next(e["comment_count"] for e in items if e["id"] == commented)

    assert count_for(KAI) == 1 == len(api.get(url, headers=KAI).json())
    assert count_for(LIN) == 2
