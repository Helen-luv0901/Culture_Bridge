import pytest
from fastapi.testclient import TestClient

from app.ai.experience_ai import (
    AIUnavailable,
    SummaryDraft,
    TranslatedExperience,
    get_experience_ai,
)
from app.core.config import get_settings
from app.main import app
from app.seed import seed

MEI = {"Authorization": "Bearer dev:mei"}
KAI = {"Authorization": "Bearer dev:kai"}
LIN = {"Authorization": "Bearer dev:lin"}


class FakeAI:
    def __init__(self) -> None:
        self.fail = False
        self.summaries = 0
        self.translations = 0

    def summarize(self, original_voice, locale):
        if self.fail:
            raise AIUnavailable("down")
        self.summaries += 1
        return SummaryDraft(
            situation=f"情境：{original_voice[:10]}",
            feeling_or_attempt="感到不安",
            reminder="可以先問學長姐",
            model_name="fake-model",
        )

    def suggest_tags(self, title, text, locale):
        if self.fail:
            raise AIUnavailable("down")
        return ["#測試"]

    def translate(self, fields, source, target):
        if self.fail:
            raise AIUnavailable("down")
        self.translations += 1
        return TranslatedExperience(**{k: f"[{target}] {v}" for k, v in fields.__dict__.items()})


@pytest.fixture
def ai():
    fake = FakeAI()
    app.dependency_overrides[get_experience_ai] = lambda: fake
    yield fake
    app.dependency_overrides.pop(get_experience_ai, None)


@pytest.fixture
def api(ai) -> TestClient:
    return TestClient(app)


DRAFT = {
    "topic_id": "life_adaptation",
    "identity_type": "exchange_student",
    "original_voice": "  第一次去健保卡櫃台，不知道要帶什麼。  ",
}


def publish_new(api, headers=MEI, **overrides) -> dict:
    draft = api.post("/api/experiences", json=DRAFT | overrides, headers=headers).json()
    summary = api.post(f"/api/experiences/{draft['id']}/summaries", headers=headers).json()
    published = api.post(
        f"/api/experiences/{draft['id']}/publish",
        json={"summary_id": summary["id"]},
        headers=headers,
    )
    assert published.status_code == 200, published.text
    return published.json()


def test_draft_summary_publish_translate(api, ai):
    assert api.post("/api/experiences", json=DRAFT).status_code == 401
    blank = api.post("/api/experiences", json=DRAFT | {"original_voice": "   "}, headers=MEI)
    assert blank.status_code == 422
    too_long = api.post(
        "/api/experiences", json=DRAFT | {"original_voice": "字" * 2001}, headers=MEI
    )
    assert too_long.status_code == 422

    draft = api.post("/api/experiences", json=DRAFT, headers=MEI).json()
    assert draft["status"] == "draft" and draft["original_voice"] == DRAFT["original_voice"].strip()
    eid = draft["id"]
    # Not public, and nobody else can touch it.
    assert api.get(f"/api/experiences/{eid}").status_code == 404
    assert api.post(f"/api/experiences/{eid}/summaries", headers=KAI).status_code == 404

    summary = api.post(f"/api/experiences/{eid}/summaries", headers=MEI).json()
    assert summary["model_name"] == "fake-model" and summary["matches_current_voice"]

    # Changing the words makes that summary unusable for publishing (B-10).
    api.patch(f"/api/experiences/{eid}", json={"original_voice": "改過的原話"}, headers=MEI)
    stale = api.post(
        f"/api/experiences/{eid}/publish", json={"summary_id": summary["id"]}, headers=MEI
    )
    assert stale.status_code == 409 and stale.json()["detail"]["code"] == "summary_outdated"

    fresh = api.post(f"/api/experiences/{eid}/summaries", headers=MEI).json()
    published = api.post(
        f"/api/experiences/{eid}/publish",
        json={"summary_id": fresh["id"], "reminder": "作者改過的提醒"},
        headers=MEI,
    ).json()
    assert published["status"] == "published"
    assert published["latest_summary"]["model_name"] == "fake-model+author-edit"
    assert published["latest_summary"]["confirmed_at"]

    public = api.get(f"/api/experiences/{eid}").json()
    assert public["reminder"] == "作者改過的提醒"
    # The account never leaks; a name appears only when the author signs with one.
    assert "author_id" not in public and "dev-mei" not in str(public)
    assert public["author_name"] is None
    # Translated in the background after publishing.
    assert ai.translations == 1
    assert public["translation"]["locale"] == "en" and public["translation"]["method"] == "ai"
    assert public["translation"]["original_voice"] == "[en] 改過的原話"
    assert (
        api.patch(
            f"/api/experiences/{eid}", json={"topic_id": "life_adaptation"}, headers=MEI
        ).status_code
        == 409
    )


def test_ai_failures_and_daily_limit(api, ai, monkeypatch):
    draft = api.post("/api/experiences", json=DRAFT, headers=MEI).json()
    ai.fail = True
    res = api.post(f"/api/experiences/{draft['id']}/summaries", headers=MEI)
    assert res.status_code == 503 and res.json()["detail"]["code"] == "ai_unavailable"

    ai.fail = False
    monkeypatch.setenv("AI_SUMMARIES_PER_DAY", "2")
    get_settings.cache_clear()
    try:
        for _ in range(2):
            assert (
                api.post(f"/api/experiences/{draft['id']}/summaries", headers=MEI).status_code
                == 201
            )
        limited = api.post(f"/api/experiences/{draft['id']}/summaries", headers=MEI)
        assert limited.status_code == 429
    finally:
        get_settings.cache_clear()


def test_publish_survives_translation_failure(api, ai):
    draft = api.post("/api/experiences", json=DRAFT, headers=MEI).json()
    summary = api.post(f"/api/experiences/{draft['id']}/summaries", headers=MEI).json()
    ai.fail = True
    published = api.post(
        f"/api/experiences/{draft['id']}/publish", json={"summary_id": summary["id"]}, headers=MEI
    )
    assert published.status_code == 200
    assert api.get(f"/api/experiences/{draft['id']}").json()["translation"] is None
    ai.fail = False
    later = api.post(f"/api/experiences/{draft['id']}/translations", json={"locale": "en"}).json()
    assert later["translation"]["locale"] == "en"


def test_explore_filters_search_and_paging(api, db):
    seed(db, get_settings().demo_content_path)
    page = api.get("/api/experiences?topic=culture_communication").json()
    assert {e["id"] for e in page["items"]} == {"professor-see", "class-invitation"}
    assert page["next_offset"] is None
    assert [
        e["id"] for e in api.get("/api/experiences?identity_type=exchange_student").json()["items"]
    ] == ["first-rental"]

    first = api.get("/api/experiences?limit=2").json()
    assert len(first["items"]) == 2 and first["next_offset"] == 2
    rest = api.get("/api/experiences?limit=2&offset=2").json()
    assert len(rest["items"]) == 1 and rest["next_offset"] is None

    assert [e["id"] for e in api.get("/api/experiences", params={"q": "教授"}).json()["items"]] == [
        "professor-see"
    ]
    # English words match the stored translation.
    assert [
        e["id"] for e in api.get("/api/experiences", params={"q": "professor"}).json()["items"]
    ] == ["professor-see"]
    demo = api.get("/api/experiences/professor-see?locale=en").json()
    assert demo["translation"]["method"] == "human"

    results = api.get("/api/search", params={"q": "工作證"}).json()
    assert [a["id"] for a in results["actions"]] == ["work-permit"]
    assert (
        api.get("/api/search", params={"q": "ARC", "kind": "actions"}).json()["experiences"] == []
    )


def test_reactions_and_impact(api, ai):
    mine = publish_new(api)
    eid = mine["id"]
    for headers in (KAI, LIN):
        api.put(f"/api/experiences/{eid}/reactions/helpful", headers=headers)
    api.put(f"/api/experiences/{eid}/reactions/helpful", headers=KAI)  # once per person
    reacted = api.put(f"/api/experiences/{eid}/reactions/experienced_too", headers=KAI).json()
    assert reacted["helpful_count"] == 2 and reacted["experienced_too_count"] == 1
    assert reacted["my_reactions"] == ["experienced_too", "helpful"]
    assert api.put(f"/api/experiences/{eid}/reactions/like", headers=KAI).status_code == 422

    undone = api.delete(f"/api/experiences/{eid}/reactions/helpful", headers=LIN).json()
    assert undone["helpful_count"] == 1 and undone["my_reactions"] == []

    impact = api.get("/api/me/experiences", headers=MEI).json()[0]["impact"]
    assert impact == {
        "helpful_count": 1,
        "experienced_too_count": 1,
        "different_count": 0,
        "people_reached": 1,
    }


def test_different_experience_links_back(api, ai):
    original = publish_new(api)
    draft = api.post(
        "/api/experiences",
        json=DRAFT | {"different_from_id": original["id"], "original_voice": "我的經驗不一樣"},
        headers=KAI,
    ).json()
    # Drafts don't count yet.
    assert api.get(f"/api/experiences/{original['id']}").json()["different_count"] == 0
    summary = api.post(f"/api/experiences/{draft['id']}/summaries", headers=KAI).json()
    api.post(
        f"/api/experiences/{draft['id']}/publish", json={"summary_id": summary["id"]}, headers=KAI
    )

    detail = api.get(f"/api/experiences/{original['id']}").json()
    assert detail["different_count"] == 1
    assert [d["id"] for d in detail["different_experiences"]] == [draft["id"]]
    assert api.get(f"/api/experiences/{draft['id']}").json()["responds_to_id"] == original["id"]

    missing = api.post("/api/experiences", json=DRAFT | {"different_from_id": "nope"}, headers=KAI)
    assert missing.status_code == 404


def test_author_can_delete(api, ai):
    published = publish_new(api)
    api.put(f"/api/experiences/{published['id']}/reactions/helpful", headers=KAI)
    assert api.delete(f"/api/experiences/{published['id']}", headers=KAI).status_code == 404
    assert api.delete(f"/api/experiences/{published['id']}", headers=MEI).status_code == 204
    assert api.get(f"/api/experiences/{published['id']}").status_code == 404
    assert api.get("/api/me/experiences", headers=MEI).json() == []
