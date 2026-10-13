from datetime import timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select

from app.core.config import get_settings
from app.main import app
from app.models import ExperienceView, UserActivityDay
from app.seed import seed
from app.services import metrics

MEI = {"Authorization": "Bearer dev:mei"}
KAI = {"Authorization": "Bearer dev:kai"}
REVIEWER = {"Authorization": "Bearer dev:rita:reviewer"}


@pytest.fixture
def api(db):
    metrics._recorded.clear()  # tables are truncated between tests; the cache is not
    seed(db, get_settings().demo_content_path)
    return TestClient(app)


def _views(db) -> int:
    return db.scalar(select(func.count()).select_from(ExperienceView)) or 0


def test_activity_and_views_are_recorded_once_per_day(api, db):
    api.get("/api/me", headers=MEI)
    api.get("/api/me", headers=MEI)
    days = db.scalars(select(UserActivityDay.day).where(UserActivityDay.user_id == "dev-mei"))
    assert list(days) == [metrics.today()]

    experience = api.get("/api/experiences").json()["items"][0]["id"]
    api.get(f"/api/experiences/{experience}")  # guests are not tracked
    assert _views(db) == 0
    api.get(f"/api/experiences/{experience}", headers=KAI)
    api.get(f"/api/experiences/{experience}", headers=KAI)
    assert _views(db) == 1

    mine = api.post(
        "/api/experiences",
        json={
            "topic_id": "life_adaptation",
            "identity_type": "exchange_student",
            "original_voice": "我的故事",
        },
        headers=MEI,
    ).json()["id"]
    api.get(f"/api/experiences/{mine}", headers=MEI)  # drafts 404; authors never count
    assert _views(db) == 1

    # Deleting the account removes its activity and views.
    assert api.delete("/api/me", headers=KAI).status_code == 204
    assert _views(db) == 0
    left = db.scalar(select(func.count()).where(UserActivityDay.user_id == "dev-kai"))
    assert left == 0


def test_stats_for_staff(api, db):
    assert api.get("/api/admin/stats", headers=MEI).status_code == 403

    today = metrics.today()
    # A returned within 7 days of their first day; B did not come back.
    for user, offsets in {"dev-a": (10, 8), "dev-b": (9,)}.items():
        api.get("/api/me", headers={"Authorization": f"Bearer dev:{user[4:]}"})
        db.query(UserActivityDay).filter(UserActivityDay.user_id == user).delete()
        for offset in offsets:
            db.add(UserActivityDay(user_id=user, day=today - timedelta(days=offset)))
    db.commit()
    experience = api.get("/api/experiences").json()["items"][0]["id"]
    api.get(f"/api/experiences/{experience}", headers=KAI)

    stats = api.get("/api/admin/stats?days=30", headers=REVIEWER).json()
    assert stats["return_cohort"] == 2 and stats["returned_within_7_days"] == 1
    assert stats["return_rate"] == 0.5
    assert stats["active_users"] >= 4  # a, b, kai, rita (and the seed's demo author)
    assert stats["experience_readers"] == 1
    assert stats["reader_rate"] == round(1 / stats["active_users"], 3)
    assert stats["executions_started"] == 0 and stats["outcomes"] == {}
    assert stats["summary_confirm_rate"] is None or 0 <= stats["summary_confirm_rate"] <= 1
    assert api.get("/api/admin/stats?days=3", headers=REVIEWER).status_code == 422
