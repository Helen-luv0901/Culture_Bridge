"""The redesign: posts published as written, AI-suggested tags, comments and guide documents."""

import pytest
from fastapi.testclient import TestClient

from app.ai.experience_ai import AIUnavailable, get_experience_ai
from app.core.config import get_settings
from app.main import app
from app.seed import seed
from app.services import tags as tag_svc
from tests.test_experiences import FakeAI

MEI = {"Authorization": "Bearer dev:mei"}
KAI = {"Authorization": "Bearer dev:kai"}
LIN = {"Authorization": "Bearer dev:lin"}
JO = {"Authorization": "Bearer dev:jo"}
REVIEWER = {"Authorization": "Bearer dev:rita:reviewer"}

POST = {
    "title": "  居留證要先  線上預約 ",
    "original_voice": "  我以為可以直接去服務站，結果要先線上預約。 ",
    "category": "life",
    "tags": ["#居留證", "線上 預約", "#居留證", "", "#太長的標籤一二三四五六七八九十"],
}


@pytest.fixture
def ai():
    fake = FakeAI()
    app.dependency_overrides[get_experience_ai] = lambda: fake
    yield fake
    app.dependency_overrides.pop(get_experience_ai, None)


@pytest.fixture
def api(ai) -> TestClient:
    return TestClient(app)


def post(api, headers=MEI, **overrides) -> dict:
    response = api.post("/api/posts", json=POST | overrides, headers=headers)
    assert response.status_code == 201, response.text
    return response.json()


def test_post_is_published_exactly_as_written(api, ai):
    assert api.post("/api/posts", json=POST).status_code == 401
    for bad in ({"title": "   "}, {"original_voice": " "}, {"category": "official"}):
        assert api.post("/api/posts", json=POST | bad, headers=MEI).status_code == 422

    item = post(api)
    assert item["title"] == "居留證要先 線上預約"
    assert item["original_voice"] == "我以為可以直接去服務站，結果要先線上預約。"
    assert item["category"] == "life" and item["topic_id"] == "life_adaptation"
    assert item["tags"] == ["#居留證", "#線上預約"]
    # The AI never rewrote it: no summary, and the author sees it as theirs.
    assert (item["situation"], item["reminder"]) == ("", "")
    assert item["mine"] is True and item["comment_count"] == 0
    assert ai.summaries == 0

    public = api.get(f"/api/experiences/{item['id']}").json()
    assert public["mine"] is False and public["title"] == item["title"]
    # Translated in the background, title included.
    assert ai.translations == 1
    english = api.get(f"/api/experiences/{item['id']}?locale=en").json()["translation"]
    assert english["title"].startswith("[en]")

    mine = api.get("/api/me/experiences", headers=MEI).json()
    assert mine[0]["title"] == item["title"] and mine[0]["tags"] == item["tags"]


def test_signing_needs_the_name_set(api):
    unsigned = api.post("/api/posts", json=POST | {"author_display": "nickname"}, headers=MEI)
    assert unsigned.json()["detail"]["code"] == "nickname_missing"
    api.patch("/api/me", json={"nickname": "小美"}, headers=MEI)
    item = post(api, author_display="nickname")
    assert item["author_name"] == "小美"


def test_cultural_differences_is_its_own_category(api):
    item = post(api, category="difference", title="說「下次一起吃飯」不一定是邀請")
    assert item["category"] == "difference" and item["topic_id"] == "culture_communication"
    ids = [e["id"] for e in api.get("/api/experiences?category=difference").json()["items"]]
    assert ids == [item["id"]]
    culture = api.get("/api/experiences?category=culture").json()["items"]
    assert item["id"] not in [e["id"] for e in culture]


def test_categories_hot_sort_search_and_popular_tags(api, db):
    seed(db, get_settings().demo_content_path)
    food = post(api, category="food", title="夜市點餐", tags=["#夜市"])
    life = post(api, category="life", title="公車要舉手", tags=["#公車"])
    other_life = post(api, category="life", title="宿舍", tags=["#夜市"])

    def ids(response) -> list[str]:
        return [e["id"] for e in response.json()["items"]]

    assert ids(api.get("/api/experiences?category=food")) == [food["id"]]
    life_ids = ids(api.get("/api/experiences?category=life"))
    assert life_ids[:2] == [other_life["id"], life["id"]]
    # Seeded posts from before categories are filed under life or culture by topic.
    assert len(life_ids) > 2
    assert ids(api.get("/api/experiences?category=culture"))

    api.put(f"/api/experiences/{life['id']}/reactions/experienced_too", headers=KAI)
    api.post(f"/api/experiences/{food['id']}/comments", json={"body": "我也是"}, headers=KAI)
    hot = ids(api.get("/api/experiences?sort=hot"))
    assert hot[:2] == [food["id"], life["id"]]  # a comment counts twice a "me too"

    assert ids(api.get("/api/experiences", params={"q": "#公車"})) == [life["id"]]
    found = api.get("/api/search", params={"q": "夜市點餐"}).json()
    assert [e["id"] for e in found["experiences"]] == [food["id"]]
    assert api.get("/api/tags/popular").json()[0] == "#夜市"


def test_posts_shared_under_a_guide(api, db):
    seed(db, get_settings().demo_content_path)
    missing = api.post("/api/posts", json=POST | {"action_id": "nope"}, headers=MEI)
    assert missing.status_code == 404
    item = post(api, action_id="arc")
    assert item["action_id"] == "arc"
    listed = api.get("/api/experiences?action_id=arc").json()["items"]
    assert [e["id"] for e in listed] == [item["id"]]

    answer = post(api, headers=KAI, different_from_id=item["id"], title="我的不一樣")
    detail = api.get(f"/api/experiences/{item['id']}").json()
    assert [e["id"] for e in detail["different_experiences"]] == [answer["id"]]


def test_tag_suggestions_use_ai_then_fall_back_to_keywords(api, ai, monkeypatch):
    monkeypatch.setattr(tag_svc, "_allowance", tag_svc.DailyAllowance())
    body = {"title": "居留證", "text": "要先線上預約才能去服務站"}
    url = "/api/experiences/tag-suggestions"
    assert api.post(url, json=body).status_code == 401

    ai.suggest_tags = lambda title, text, locale: [
        "#居留證",
        "#服務站",
        "#居留證",
        "太長的標籤一二三四五六七八九十",
    ]
    first = api.post(url, json=body, headers=MEI).json()
    assert first == {"tags": ["#居留證", "#服務站"], "source": "ai"}

    def down(title, text, locale):
        raise AIUnavailable("quota")

    ai.suggest_tags = down
    fallback = api.post(url, json=body, headers=MEI).json()
    assert fallback["source"] == "keywords"
    assert {"#居留證", "#線上預約", "#移民署"} <= set(fallback["tags"])

    # Past the daily allowance the model is not called at all.
    calls = []
    ai.suggest_tags = lambda title, text, locale: calls.append(1) or ["#x"]
    limit = get_settings().ai_tag_suggestions_per_day
    for _ in range(limit + 2):
        api.post(url, json=body, headers=KAI)
    assert len(calls) == limit
    empty = api.post(url, json={}, headers=LIN).json()
    assert empty == {"tags": [], "source": "keywords"}


def test_comments_replies_likes_and_deletion(api):
    item = post(api)
    url = f"/api/experiences/{item['id']}/comments"
    assert api.post(url, json={"body": "hi"}).status_code == 401
    assert api.post(url, json={"body": "  "}, headers=KAI).status_code == 422
    unsigned = api.post(url, json={"body": "x", "author_display": "nickname"}, headers=KAI)
    assert unsigned.json()["detail"]["code"] == "nickname_missing"

    first = api.post(url, json={"body": " 我也遇過 "}, headers=KAI).json()
    assert first["body"] == "我也遇過" and first["author_name"] is None and first["mine"] is True
    reply = api.post(url, json={"body": "謝謝", "reply_to_id": first["id"]}, headers=MEI).json()
    assert reply["reply_to_id"] == first["id"] and reply["by_post_author"] is True
    # Answering a reply answers its thread.
    deeper = api.post(url, json={"body": "+1", "reply_to_id": reply["id"]}, headers=LIN).json()
    assert deeper["reply_to_id"] == first["id"]

    liked = api.put(f"/api/comments/{first['id']}/like", headers=MEI).json()
    assert liked["like_count"] == 1 and liked["liked"] is True
    api.put(f"/api/comments/{first['id']}/like", headers=MEI)  # idempotent
    listed = api.get(url).json()
    assert [c["id"] for c in listed] == [first["id"], reply["id"], deeper["id"]]
    assert listed[0]["like_count"] == 1 and listed[0]["liked"] is False
    assert listed[0]["mine"] is False
    assert api.get(f"/api/experiences/{item['id']}").json()["comment_count"] == 3

    assert api.delete(f"/api/comments/{first['id']}", headers=MEI).status_code == 403
    assert api.delete(f"/api/comments/{first['id']}", headers=KAI).status_code == 204
    assert api.get(url).json() == []  # its replies went with it

    again = api.post(url, json={"body": "再一次"}, headers=KAI).json()
    assert api.delete(f"/api/experiences/{item['id']}", headers=MEI).status_code == 204
    assert api.get(url).status_code == 404
    assert api.put(f"/api/comments/{again['id']}/like", headers=MEI).status_code == 404


def test_anonymous_post_authors_cannot_sign_their_comments(api):
    api.patch("/api/me", json={"nickname": "小美"}, headers=MEI)
    item = post(api)
    url = f"/api/experiences/{item['id']}/comments"
    signed = api.post(url, json={"body": "我", "author_display": "nickname"}, headers=MEI)
    assert signed.json()["detail"]["code"] == "anonymous_post_author"


def test_posts_and_comments_have_daily_caps(api, monkeypatch):
    from app.services import comments as comment_svc
    from app.services import experiences as exp_svc

    monkeypatch.setattr(exp_svc, "MAX_POSTS_PER_DAY", 2)
    monkeypatch.setattr(comment_svc, "MAX_COMMENTS_PER_DAY", 1)
    item = post(api)
    post(api)
    assert api.post("/api/posts", json=POST, headers=MEI).status_code == 429
    url = f"/api/experiences/{item['id']}/comments"
    assert api.post(url, json={"body": "一"}, headers=KAI).status_code == 201
    assert api.post(url, json={"body": "二"}, headers=KAI).status_code == 429


def test_blocked_authors_comments_are_left_out(api):
    item = post(api)
    url = f"/api/experiences/{item['id']}/comments"
    other = post(api, headers=KAI, title="kai 的分享")
    api.post(url, json={"body": "kai 說的"}, headers=KAI)
    api.post("/api/blocks", json={"experience_id": other["id"]}, headers=LIN)
    assert api.get(url, headers=LIN).json() == []
    assert len(api.get(url, headers=MEI).json()) == 1
    # Blocking a post's author hides the post's comments too.
    api.post("/api/blocks", json={"experience_id": item["id"]}, headers=JO)
    assert api.get(url, headers=JO).status_code == 404
    assert api.post(url, json={"body": "x"}, headers=JO).status_code == 404


def test_comment_reports_hide_and_are_reviewed(api):
    item = post(api)
    url = f"/api/experiences/{item['id']}/comments"
    comment = api.post(url, json={"body": "廣告"}, headers=KAI).json()
    report = {"comment_id": comment["id"], "reason": "spam"}
    both = report | {"experience_id": item["id"]}
    assert api.post("/api/reports", json=both, headers=MEI).status_code == 422
    assert api.post("/api/reports", json={"reason": "spam"}, headers=MEI).status_code == 422
    assert api.post("/api/reports", json=report, headers=KAI).status_code == 422  # own comment
    for headers in (MEI, LIN):
        assert api.post("/api/reports", json=report, headers=headers).status_code == 201
    assert api.post("/api/reports", json=report, headers=MEI).status_code == 409
    assert len(api.get(url).json()) == 1
    api.post("/api/reports", json=report, headers=JO)
    assert api.get(url).json() == []  # hidden after three reports

    queue = api.get("/api/admin/reports", headers=REVIEWER).json()
    [entry] = [q for q in queue if q["target_type"] == "comment"]
    assert entry["original_voice"] == "廣告" and entry["target_status"] == "hidden"
    resolve = f"/api/admin/reports/{entry['report_id']}/resolve"
    assert api.post(resolve, json={"action": "dismiss"}, headers=REVIEWER).status_code == 204
    assert len(api.get(url).json()) == 1


def test_account_deletion_removes_comments_and_likes(api):
    item = post(api)
    url = f"/api/experiences/{item['id']}/comments"
    comment = api.post(url, json={"body": "我的留言"}, headers=KAI).json()
    api.put(f"/api/comments/{comment['id']}/like", headers=KAI)
    mine = api.post(url, json={"body": "作者回覆"}, headers=MEI).json()
    api.put(f"/api/comments/{mine['id']}/like", headers=KAI)
    assert api.delete("/api/me", headers=KAI).status_code == 204
    listed = api.get(url).json()
    assert [c["id"] for c in listed] == [mine["id"]] and listed[0]["like_count"] == 0


DOCS_ACTION = {
    "slug": "docs-check",
    "title_zh": "測試指南",
    "title_en": "Test guide",
    "applicable_to": "所有學生",
    "steps": [{"title_zh": "送件", "title_en": "Apply"}],
    "documents": [{"zh": "護照正本", "en": "Passport"}, {"zh": "在學證明"}],
}


def test_guides_carry_a_documents_checklist(api, db):
    seed(db, get_settings().demo_content_path)
    draft = api.post("/api/admin/actions", json=DOCS_ACTION, headers=REVIEWER).json()
    assert draft["documents"] == [
        {"zh": "護照正本", "en": "Passport"},
        {"zh": "在學證明", "en": "在學證明"},
    ]
    api.post(f"/api/admin/versions/{draft['id']}/publish", headers=REVIEWER)
    public = api.get("/api/actions/docs-check").json()
    assert [d["zh"] for d in public["documents"]] == ["護照正本", "在學證明"]
    # Published content is frozen; a new version starts from the same checklist.
    frozen = api.put(
        f"/api/admin/versions/{draft['id']}",
        json=DOCS_ACTION | {"documents": []},
        headers=REVIEWER,
    )
    assert frozen.status_code == 409
    v2 = api.post("/api/admin/actions/docs-check/versions", headers=REVIEWER).json()
    assert len(v2["documents"]) == 2
    assert api.get("/api/actions/arc").json()["documents"] == []
