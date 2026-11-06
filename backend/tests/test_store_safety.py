"""Store review (batch 1): terms acceptance, legal pages, AI answer reports, comment moderation
by post authors, the content filter, suspension, and abuse limits."""

from datetime import UTC, datetime
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.ai.experience_ai import get_experience_ai
from app.core.terms import TERMS_VERSION
from app.main import app
from app.models import CommentLike, ExperienceReaction, SavedExperience, User
from tests.test_experiences import FakeAI

MEI = {"Authorization": "Bearer dev:mei"}
KAI = {"Authorization": "Bearer dev:kai"}
LIN = {"Authorization": "Bearer dev:lin"}
REVIEWER = {"Authorization": "Bearer dev:rita:reviewer"}
ADMIN = {"Authorization": "Bearer dev:ada:admin"}

POST = {
    "title": "租屋押金",
    "original_voice": "房東要兩個月押金，我先問了學長姐。",
    "category": "life",
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


def code(response) -> str:
    return response.json()["detail"]["code"]


def post(api, headers=MEI, **overrides) -> dict:
    response = api.post("/api/posts", json=POST | overrides, headers=headers)
    assert response.status_code == 201, response.text
    return response.json()


def comment(api, eid: str, body: str, headers) -> dict:
    response = api.post(f"/api/experiences/{eid}/comments", json={"body": body}, headers=headers)
    assert response.status_code == 201, response.text
    return response.json()


# ---------- §1 terms of use / AI notice ----------


def test_config_lists_terms_version_legal_pages_and_support_email(api, monkeypatch):
    from app.core.config import get_settings

    config = api.get("/api/config").json()
    assert config["terms_version"] == TERMS_VERSION == 1
    assert config["legal"] == {
        "privacy": "/privacy",
        "terms": "/terms",
        "account_deletion": "/account-deletion",
    }
    assert config["support_email"] is None
    monkeypatch.setenv("SUPPORT_EMAIL", "help@example.org")
    get_settings.cache_clear()
    try:
        assert api.get("/api/config").json()["support_email"] == "help@example.org"
    finally:
        get_settings.cache_clear()


@pytest.mark.real_terms
def test_posting_and_commenting_need_the_current_terms(api):
    assert api.get("/api/me", headers=MEI).json()["terms_version"] is None
    refused = api.post("/api/posts", json=POST, headers=MEI)
    assert refused.status_code == 403 and code(refused) == "terms_not_accepted"

    outdated = api.post("/api/me/terms", json={"version": TERMS_VERSION + 1}, headers=MEI)
    assert outdated.status_code == 422 and code(outdated) == "terms_version_outdated"
    assert api.post("/api/me/terms", json={"version": TERMS_VERSION}).status_code == 401
    accepted = api.post("/api/me/terms", json={"version": TERMS_VERSION}, headers=MEI)
    assert accepted.status_code == 200 and accepted.json()["terms_version"] == TERMS_VERSION
    assert accepted.json()["id"] == "dev-mei"
    item = post(api)

    url = f"/api/experiences/{item['id']}/comments"
    refused = api.post(url, json={"body": "我也是"}, headers=KAI)
    assert refused.status_code == 403 and code(refused) == "terms_not_accepted"
    # Reading, reacting, saving, reporting and blocking are not gated.
    assert api.get(url, headers=KAI).status_code == 200
    assert api.put(f"/api/experiences/{item['id']}/reactions/helpful", headers=KAI).is_success
    assert api.put(f"/api/experiences/{item['id']}/saved", headers=KAI).is_success
    report = {"experience_id": item["id"], "reason": "spam"}
    assert api.post("/api/reports", json=report, headers=KAI).status_code == 201
    api.post("/api/me/terms", json={"version": TERMS_VERSION}, headers=KAI)
    assert api.post(url, json={"body": "我也是"}, headers=KAI).status_code == 201


@pytest.mark.real_terms
def test_terms_from_an_older_version_must_be_accepted_again(api, db, monkeypatch):
    api.post("/api/me/terms", json={"version": TERMS_VERSION}, headers=MEI)
    monkeypatch.setattr("app.core.terms.TERMS_VERSION", TERMS_VERSION + 1)
    refused = api.post("/api/posts", json=POST, headers=MEI)
    assert refused.status_code == 403 and code(refused) == "terms_not_accepted"


# ---------- §2 public pages ----------


@pytest.mark.parametrize("path", ["/privacy", "/terms", "/account-deletion"])
def test_legal_pages_show_the_support_email(api, monkeypatch, path):
    from app.core.config import get_settings

    unset = api.get(path)
    assert unset.status_code == 200 and unset.headers["content-type"].startswith("text/html")
    assert "［客服信箱待設定］" in unset.text and "[support email not set yet]" in unset.text
    assert "{{SUPPORT_EMAIL" not in unset.text
    monkeypatch.setenv("SUPPORT_EMAIL", "help@example.org")
    get_settings.cache_clear()
    try:
        page = api.get(path).text
    finally:
        get_settings.cache_clear()
    assert "help@example.org" in page and "［客服信箱待設定］" not in page


def test_legal_pages_say_what_store_review_needs(api):
    terms = api.get("/terms").text
    for words in (
        "零容忍",
        "24 小時",
        "停權",
        "Gemini",
        "可能有誤",
        "/privacy",
        "/account-deletion",
        "zero tolerance",
        "24 hours",
        "suspend",
        "can be wrong",
        "最近 6 輪",
        "［待確認］",
    ):
        assert words in terms, words
    privacy = api.get("/privacy").text
    for words in (
        "大頭貼",
        "留言",
        "Gemini",
        "/account-deletion",
        "/terms",
        "profile photo",
        "Crash",
    ):
        assert words in privacy
    deletion = api.get("/account-deletion").text
    for words in ("留言", "大頭貼", "收藏", "comments", "profile photo", "saved"):
        assert words in deletion


# ---------- §3 reporting an AI answer ----------

ANSWER_REPORT = {
    "conversation_id": "c1",
    "question": "居留證要帶什麼？",
    "answer": "只要帶護照。",
    "reason": "inaccurate",
    "details": "還要照片",
}


def test_assistant_answers_can_be_reported_and_resolved(api, monkeypatch):
    assert api.post("/api/assistant/reports", json=ANSWER_REPORT).status_code == 401
    bad = api.post("/api/assistant/reports", json=ANSWER_REPORT | {"reason": "meh"}, headers=MEI)
    assert bad.status_code == 422
    too_long = ANSWER_REPORT | {"answer": "x" * 4001}
    assert api.post("/api/assistant/reports", json=too_long, headers=MEI).status_code == 422
    created = api.post("/api/assistant/reports", json=ANSWER_REPORT, headers=MEI)
    assert created.status_code == 201
    report_id = created.json()["id"]
    minimal = ANSWER_REPORT | {"conversation_id": None, "details": None, "reason": "harmful"}
    assert api.post("/api/assistant/reports", json=minimal, headers=KAI).status_code == 201

    assert api.get("/api/admin/assistant-reports", headers=MEI).status_code == 403
    queue = api.get("/api/admin/assistant-reports", headers=REVIEWER).json()
    assert [r["reason"] for r in queue] == ["harmful", "inaccurate"]  # newest first
    assert set(queue[1]) == {
        "id",
        "question",
        "answer",
        "reason",
        "details",
        "created_at",
        "status",
        "conversation_id",
    }
    assert queue[1]["id"] == report_id and queue[1]["status"] == "open"
    assert queue[1]["question"] == "居留證要帶什麼？" and queue[1]["conversation_id"] == "c1"

    resolve = f"/api/admin/assistant-reports/{report_id}/resolve"
    assert api.post(resolve, json={"note": "已更正"}, headers=REVIEWER).status_code == 204
    assert (
        api.post("/api/admin/assistant-reports/nope/resolve", json={}, headers=REVIEWER).status_code
        == 404
    )
    assert len(api.get("/api/admin/assistant-reports?status=open", headers=REVIEWER).json()) == 1
    resolved = api.get("/api/admin/assistant-reports?status=resolved", headers=REVIEWER).json()
    assert [r["id"] for r in resolved] == [report_id] and resolved[0]["status"] == "resolved"


def test_assistant_reports_have_a_daily_cap(api, monkeypatch):
    from app.services import assistant_reports

    monkeypatch.setattr(assistant_reports, "MAX_REPORTS_PER_DAY", 1)
    assert api.post("/api/assistant/reports", json=ANSWER_REPORT, headers=MEI).status_code == 201
    again = api.post("/api/assistant/reports", json=ANSWER_REPORT, headers=MEI)
    assert again.status_code == 429 and code(again) == "daily_limit_reached"


def test_assistant_reports_go_with_the_account(api, db):
    api.post("/api/assistant/reports", json=ANSWER_REPORT, headers=MEI)
    assert api.delete("/api/me", headers=MEI).status_code == 204
    assert api.get("/api/admin/assistant-reports", headers=REVIEWER).json() == []


# ---------- §4 blocking a commenter; post authors removing comments ----------


def test_blocking_a_commenter_hides_their_comments(api):
    item = post(api)
    url = f"/api/experiences/{item['id']}/comments"
    theirs = comment(api, item["id"], "廣告", KAI)
    comment(api, item["id"], "謝謝分享", LIN)
    both = {"experience_id": item["id"], "comment_id": theirs["id"]}
    for body in (both, {}):
        refused = api.post("/api/blocks", json=body, headers=MEI)
        assert refused.status_code == 422 and code(refused) == "invalid_request"
    missing = api.post("/api/blocks", json={"comment_id": "nope"}, headers=MEI)
    assert missing.status_code == 404 and code(missing) == "comment_not_found"
    own = api.post("/api/blocks", json={"comment_id": theirs["id"]}, headers=KAI)
    assert own.status_code == 422 and code(own) == "cannot_block_self"

    block = api.post("/api/blocks", json={"comment_id": theirs["id"]}, headers=MEI)
    assert block.status_code == 201 and set(block.json()) == {"id", "persona", "created_at"}
    assert block.json()["persona"] == "anonymous"
    assert [c["body"] for c in api.get(url, headers=MEI).json()] == ["謝謝分享"]
    # The same block again is the same block; /api/me/blocks works too.
    again = api.post("/api/me/blocks", json={"comment_id": theirs["id"]}, headers=MEI)
    assert again.status_code == 201 and again.json()["id"] == block.json()["id"]
    assert [b["id"] for b in api.get("/api/me/blocks", headers=MEI).json()] == [block.json()["id"]]


def test_post_authors_can_remove_comments_on_their_post(api):
    item = post(api)
    url = f"/api/experiences/{item['id']}/comments"
    theirs = comment(api, item["id"], "不禮貌的留言", KAI)
    flags = {c["id"]: c["removable_by_me"] for c in api.get(url, headers=MEI).json()}
    assert flags == {theirs["id"]: True}  # the post's author
    assert api.get(url, headers=KAI).json()[0]["removable_by_me"] is True  # the commenter
    assert api.get(url, headers=LIN).json()[0]["removable_by_me"] is False
    assert api.get(url).json()[0]["removable_by_me"] is False
    assert api.get(url, headers=REVIEWER).json()[0]["removable_by_me"] is True

    assert api.delete(f"/api/comments/{theirs['id']}", headers=LIN).status_code == 403
    assert api.delete(f"/api/comments/{theirs['id']}", headers=MEI).status_code == 204
    assert api.get(url).json() == []


# ---------- §5 content filter ----------


def test_objectionable_words_are_refused_everywhere(api, db):
    item = post(api)
    for body in (
        {"title": "you are a FUCKING idiot"},
        {"original_voice": "那個人是婊子"},
        {"tags": ["#nigger"]},
    ):
        refused = api.post("/api/posts", json=POST | body, headers=MEI)
        assert refused.status_code == 422 and code(refused) == "content_not_allowed", body
    url = f"/api/experiences/{item['id']}/comments"
    refused = api.post(url, json={"body": "幹你娘"}, headers=KAI)
    assert refused.status_code == 422 and code(refused) == "content_not_allowed"
    for profile in ({"nickname": "slut"}, {"real_name": "臭婊子"}):
        refused = api.patch("/api/me", json=profile, headers=KAI)
        assert refused.status_code == 422 and code(refused) == "content_not_allowed"
    # Nothing was stored.
    assert len(api.get("/api/me/experiences", headers=MEI).json()) == 1
    assert api.get(url).json() == []
    assert db.get(User, "dev-kai").nickname is None


def test_everyday_student_posts_pass_the_filter():
    from app.services.content_filter import contains_blocked_words

    for text in (
        "租屋要先看合約，押金通常是兩個月",
        "居留證 ARC 要先線上預約",
        "逢甲夜市的臭豆腐很好吃",
        "騎機車要戴安全帽，機車駕照考試不難",
        "我不太能吃辣，點餐時要說小辣",
        "他很能幹，幹部會議在週五",
        "Renting near campus: ask the landlord about the deposit",
        "Night markets in Taichung are great; Scunthorpe friends agree",
        "I passed my scooter license and got my ARC renewed",
        "The assessment was hard but the class was fun",
    ):
        assert not contains_blocked_words(text), text


def test_filter_matches_english_whole_words_case_insensitively():
    from app.services.content_filter import contains_blocked_words

    assert contains_blocked_words("What the FuCk")
    assert contains_blocked_words("ｆｕｃｋ this")  # full-width letters
    assert not contains_blocked_words("Scunthorpe")


# ---------- §6 suspension ----------


def test_suspended_accounts_can_read_but_not_write(api, db):
    item = post(api)
    api.get("/api/me", headers=KAI)
    assert api.post("/api/admin/users/dev-kai/suspend", headers=REVIEWER).status_code == 403
    assert api.post("/api/admin/users/nope/suspend", headers=ADMIN).status_code == 404
    assert api.post("/api/admin/users/dev-kai/suspend", headers=ADMIN).status_code == 204

    eid = item["id"]
    writes = [
        ("post", "/api/posts", POST),
        ("post", f"/api/experiences/{eid}/comments", {"body": "hi"}),
        ("put", f"/api/experiences/{eid}/reactions/helpful", None),
        ("put", f"/api/experiences/{eid}/saved", None),
        ("post", "/api/reports", {"experience_id": eid, "reason": "spam"}),
        ("post", "/api/assistant/reports", ANSWER_REPORT),
        ("patch", "/api/me", {"nickname": "k"}),
        ("post", "/api/me/terms", {"version": TERMS_VERSION}),
    ]
    for method, path, body in writes:
        kwargs = {"json": body} if body is not None else {}
        refused = getattr(api, method)(path, headers=KAI, **kwargs)
        assert refused.status_code == 403 and code(refused) == "account_suspended", path
    assert api.get(f"/api/experiences/{eid}", headers=KAI).status_code == 200
    assert api.get("/api/me", headers=KAI).status_code == 200
    translated = api.post(
        f"/api/experiences/{eid}/translations", json={"locale": "en"}, headers=KAI
    )
    assert translated.status_code == 200  # reading a translation is not a write

    assert api.post("/api/admin/users/dev-kai/unsuspend", headers=ADMIN).status_code == 204
    assert api.put(f"/api/experiences/{eid}/saved", headers=KAI).status_code == 200


def test_suspended_accounts_can_still_delete_themselves(api):
    api.get("/api/me", headers=KAI)
    api.post("/api/admin/users/dev-kai/suspend", headers=ADMIN)
    assert api.delete("/api/me", headers=KAI).status_code == 204


def test_staff_are_never_suspended(api, db):
    api.get("/api/me", headers=REVIEWER)
    refused = api.post("/api/admin/users/dev-rita/suspend", headers=ADMIN)
    assert refused.status_code == 422 and code(refused) == "cannot_suspend_staff"
    # Even a suspension set by hand does not stop staff.
    db.get(User, "dev-rita").suspended_at = datetime.now(UTC)
    db.commit()
    assert api.post("/api/me/terms", json={"version": TERMS_VERSION}, headers=REVIEWER).is_success


def test_report_queue_carries_the_author_and_staff_can_suspend_them(api):
    item = post(api, headers=KAI)
    reply = comment(api, item["id"], "垃圾訊息", LIN)
    api.post("/api/reports", json={"experience_id": item["id"], "reason": "spam"}, headers=MEI)
    api.post("/api/reports", json={"comment_id": reply["id"], "reason": "spam"}, headers=MEI)
    queue = api.get("/api/admin/reports", headers=REVIEWER).json()
    refs = {q["target_type"]: q["author_ref"] for q in queue}
    assert refs == {"experience": "dev-kai", "comment": "dev-lin"}

    [entry] = [q for q in queue if q["target_type"] == "comment"]
    url = f"/api/admin/reports/{entry['report_id']}/suspend-author"
    assert api.post(url, headers=REVIEWER).status_code == 403  # admins only
    assert api.post("/api/admin/reports/nope/suspend-author", headers=ADMIN).status_code == 404
    assert api.post(url, headers=ADMIN).status_code == 204
    refused = api.post(f"/api/experiences/{item['id']}/comments", json={"body": "x"}, headers=LIN)
    assert code(refused) == "account_suspended"


# ---------- §7 abuse limits and sign-in hardening ----------


def test_deleting_does_not_give_back_the_daily_post_and_comment_count(api, monkeypatch):
    from app.services import comments as comment_svc
    from app.services.experiences import posts as exp_svc

    monkeypatch.setattr(exp_svc, "MAX_POSTS_PER_DAY", 2)
    monkeypatch.setattr(comment_svc, "MAX_COMMENTS_PER_DAY", 1)
    first = post(api)
    target = post(api, headers=KAI)
    assert api.delete(f"/api/experiences/{first['id']}", headers=MEI).status_code == 204
    post(api)
    refused = api.post("/api/posts", json=POST, headers=MEI)
    assert refused.status_code == 429 and code(refused) == "daily_limit_reached"

    written = comment(api, target["id"], "一", LIN)
    assert api.delete(f"/api/comments/{written['id']}", headers=LIN).status_code == 204
    again = api.post(f"/api/experiences/{target['id']}/comments", json={"body": "二"}, headers=LIN)
    assert again.status_code == 429 and code(again) == "daily_limit_reached"


def test_translations_have_a_daily_cap_and_a_cool_down_after_failures(api, ai, monkeypatch):
    from app.services.experiences import translations

    ai.fail = True  # no background translation
    items = [post(api, title=f"第{n}篇") for n in range(3)]
    ai.fail = False
    monkeypatch.setattr(translations, "TRANSLATIONS_PER_DAY", 2)

    def translate(eid, headers=None):
        return api.post(
            f"/api/experiences/{eid}/translations", json={"locale": "en"}, headers=headers
        )

    assert translate(items[0]["id"]).json()["translation"]["locale"] == "en"
    # Already translated: no AI call, nothing counted.
    assert translate(items[0]["id"]).status_code == 200
    assert translate(items[1]["id"]).status_code == 200
    capped = translate(items[2]["id"])
    assert capped.status_code == 429 and code(capped) == "daily_limit_reached"
    assert ai.translations == 2
    # Signed-in people count on their own allowance.
    monkeypatch.setattr(translations, "TRANSLATIONS_PER_DAY", 1)
    ai.fail = True
    failed = translate(items[2]["id"], KAI)
    assert failed.status_code == 503 and code(failed) == "ai_unavailable"
    ai.fail = False
    cooling = translate(items[2]["id"], LIN)
    assert cooling.status_code == 503 and code(cooling) == "ai_unavailable"
    assert ai.translations == 2

    later = translations._clock() + translations.RETRY_AFTER_FAILURE_SECONDS + 1
    monkeypatch.setattr(translations, "_clock", lambda: later)
    assert translate(items[2]["id"], LIN).json()["translation"]["locale"] == "en"


def _claims(provider: str | None) -> dict:
    claims = {"iss": "https://securetoken.google.com/culture-bridge", "sub": "uid1"}
    if provider is not None:
        claims["firebase"] = {"sign_in_provider": provider}
    return claims


def test_only_google_and_apple_sign_ins_are_accepted(monkeypatch):
    from app.core.auth import FirebaseTokenVerifier
    from app.core.config import get_settings
    from app.core.errors import ApiError

    verifier = FirebaseTokenVerifier("culture-bridge")
    monkeypatch.setattr(verifier, "_get_certs", lambda max_age=None: {"k": "cert"})
    for provider in ("google.com", "apple.com"):
        monkeypatch.setattr("app.core.auth.jwt.decode", lambda *a, p=provider, **k: _claims(p))
        assert verifier.verify("t").subject == "firebase:uid1"
    for provider in ("anonymous", "password", "phone", None):
        monkeypatch.setattr("app.core.auth.jwt.decode", lambda *a, p=provider, **k: _claims(p))
        with pytest.raises(ApiError) as exc:
            verifier.verify("t")
        assert exc.value.status_code == 401 and exc.value.code == "invalid_token"
    monkeypatch.setenv("ALLOWED_SIGN_IN_PROVIDERS", "google.com, password")
    get_settings.cache_clear()
    try:
        monkeypatch.setattr("app.core.auth.jwt.decode", lambda *a, **k: _claims("password"))
        assert verifier.verify("t").subject == "firebase:uid1"
    finally:
        get_settings.cache_clear()


def test_google_key_outages_keep_the_last_good_keys(monkeypatch):
    import requests

    from app.core.auth import FirebaseTokenVerifier
    from app.core.errors import ApiError

    verifier = FirebaseTokenVerifier("culture-bridge")
    clock = [1000.0]
    monkeypatch.setattr("app.core.auth.time.monotonic", lambda: clock[0])
    monkeypatch.setattr("app.core.auth.jwt.decode", lambda *a, **k: _claims("google.com"))
    up = [False]

    def get(url, timeout):
        if not up[0]:
            raise requests.ConnectionError("down")
        return SimpleNamespace(raise_for_status=lambda: None, json=lambda: {"k": "cert"})

    monkeypatch.setattr("app.core.auth.requests.get", get)
    with pytest.raises(ApiError) as exc:
        verifier.verify("t")  # no keys at all yet: the server can't check anyone
    assert exc.value.status_code == 503 and exc.value.code == "auth_unavailable"
    up[0] = True
    # Right after a failure with nothing cached, requests are answered at once (no queue of
    # 10 s timeouts on the lock); Google is asked again after the back-off.
    with pytest.raises(ApiError):
        verifier.verify("t")
    clock[0] += 61
    assert verifier.verify("t").subject == "firebase:uid1"
    up[0] = False
    clock[0] += 10_000  # the cache expired and Google is down: the old keys still work
    assert verifier.verify("t").subject == "firebase:uid1"


def test_reacting_liking_and_saving_twice_is_idempotent(api, db, monkeypatch):
    item = post(api)
    reply = comment(api, item["id"], "同感", KAI)
    react = f"/api/experiences/{item['id']}/reactions/helpful"
    like = f"/api/comments/{reply['id']}/like"
    saved = f"/api/experiences/{item['id']}/saved"
    first = [api.put(url, headers=LIN) for url in (react, like, saved)]
    assert [r.status_code for r in first] == [200, 200, 200]
    # A double tap: the second request runs before it can see the first one's row.
    real_get = Session.get

    def stale_get(self, entity, ident, **kwargs):
        if entity in (ExperienceReaction, CommentLike, SavedExperience):
            return None
        return real_get(self, entity, ident, **kwargs)

    with monkeypatch.context() as patched:
        patched.setattr(Session, "get", stale_get)
        second = [api.put(url, headers=LIN) for url in (react, like, saved)]
    assert [r.status_code for r in second] == [200, 200, 200]
    assert second[0].json()["my_reactions"] == ["helpful"]
    assert second[1].json()["like_count"] == 1 and second[1].json()["liked"] is True
    assert second[2].json()["saved"] is True
    mine = select(ExperienceReaction).where(ExperienceReaction.user_id == "dev-lin")
    assert len(list(db.scalars(mine))) == 1
    assert api.get(f"/api/experiences/{item['id']}/comments").json()[0]["like_count"] == 1


def test_guide_counts_people_and_feedback_has_a_daily_cap(api, db, monkeypatch):
    from app.core.config import get_settings
    from app.seed import seed
    from app.services import actions

    seed(db, get_settings().demo_content_path)
    for _ in range(2):  # the same person finishing twice is one success
        execution = api.post("/api/actions/arc/executions", json={}, headers=MEI).json()
        step = execution["steps"][1]["step_id"]
        for _ in range(2):  # and reporting the same step twice is one stuck person
            stuck = {"kind": "stuck", "step_id": step}
            feedback = api.post(
                f"/api/executions/{execution['id']}/feedback", json=stuck, headers=MEI
            )
            assert feedback.status_code == 201
        api.post(
            f"/api/executions/{execution['id']}/finish", json={"outcome": "success"}, headers=MEI
        )
    guide = api.get("/api/actions/arc").json()
    assert guide["recent_success_count"] == 1
    assert guide["steps"][1]["recent_stuck_count"] == 1
    assert [a for a in api.get("/api/actions").json() if a["slug"] == "arc"][0][
        "recent_success_count"
    ] == 1

    monkeypatch.setattr(actions, "MAX_FEEDBACK_PER_DAY", 4)
    execution = api.post("/api/actions/arc/executions", json={}, headers=MEI).json()
    refused = api.post(
        f"/api/executions/{execution['id']}/feedback", json={"kind": "different"}, headers=MEI
    )
    assert refused.status_code == 429 and code(refused) == "daily_limit_reached"


def test_suspended_accounts_can_still_remove_what_they_published_and_block(api):
    # The terms promise you can always delete your own content; blocking is a safety tool.
    mine = post(api, headers=KAI)
    theirs = post(api)
    remark = comment(api, theirs["id"], "我的留言", KAI)
    other = comment(api, theirs["id"], "別人的留言", LIN)
    api.post("/api/admin/users/dev-kai/suspend", headers=ADMIN)

    assert api.delete(f"/api/comments/{remark['id']}", headers=KAI).status_code == 204
    assert api.delete(f"/api/experiences/{mine['id']}", headers=KAI).status_code == 204
    blocked = api.post("/api/blocks", json={"comment_id": other["id"]}, headers=KAI)
    assert blocked.status_code == 201
    listed = api.get("/api/me/blocks", headers=KAI).json()
    assert api.delete(f"/api/me/blocks/{listed[0]['id']}", headers=KAI).status_code == 204
    # Still no new content.
    refused = api.post("/api/posts", json=POST, headers=KAI)
    assert refused.status_code == 403 and code(refused) == "account_suspended"


@pytest.mark.parametrize(
    "text",
    [
        "f​uck this",  # zero-width space inside the word
        "'fuck'",  # in quotes
        "I’ll kill you",  # curly apostrophe
        "幹 你 娘",  # spaces between Chinese characters
    ],
)
def test_the_filter_is_not_dodged_by_invisible_characters_quotes_or_spaces(text):
    from app.services.content_filter import contains_blocked_words

    assert contains_blocked_words(text), text


@pytest.mark.parametrize(
    "text",
    [
        "如何通報強姦或性侵？學校有專線",
        "援交詐騙要小心，不要點陌生連結",
        "這抹殺了你的努力",
        "Kike",
        "food porn at the night market",
    ],
)
def test_safety_posts_and_names_are_not_mistaken_for_abuse(text):
    from app.services.content_filter import contains_blocked_words

    assert not contains_blocked_words(text), text
