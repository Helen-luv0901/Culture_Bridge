from app.assistant.data import Localized, ProgressRecord, ProgressStep
from app.assistant.llm import ToolCall
from app.assistant.tools import ToolContext, default_registry

registry = default_registry()


def run(ctx: ToolContext, name: str, **args) -> dict:
    return registry.execute(ToolCall(id="1", name=name, args=args), ctx).result


def test_specs_are_plain_json_schema():
    specs = {s.name: s for s in registry.specs()}
    assert set(specs) == {
        "search_actions",
        "get_action",
        "search_experiences",
        "get_experience",
        "get_my_progress",
        "open_screen",
        "search_app_help",
        "propose_start_action",
        "semantic_search",
    }
    search = specs["search_experiences"].parameters
    assert search["type"] == "object"
    assert search["properties"]["topic"]["enum"] == ["life_adaptation", "culture_communication"]
    assert "anyOf" not in search["properties"]["query"]
    assert specs["get_action"].parameters["required"] == ["action_id"]


def test_search_actions_matches_chinese_question(ctx):
    result = run(ctx, "search_actions", query="工作證怎麼辦")
    assert result["results"][0]["action_id"] == "work-permit"
    assert result["results"][0]["verification_status"] == "verified"


def test_search_actions_in_english(ctx):
    ctx.locale = "en"
    result = run(ctx, "search_actions", query="bank account")
    assert result["results"][0] == {
        "action_id": "bank",
        "title": "Open a Bank Account",
        "verification_status": "verified",
        "last_verified_at": "2026-08-12",
        "recent_success_count": 9,
    }


def test_search_actions_no_match_is_empty(ctx):
    assert run(ctx, "search_actions", query="駕照") == {"count": 0, "results": []}


def test_get_action_returns_evidence_and_records_card(ctx):
    result = run(ctx, "get_action", action_id="insurance")
    action = result["action"]
    assert result["found"] is True
    assert action["verification_status"] == "needs_review"
    assert action["steps"][0]["position"] == 1
    assert action["sources"]
    card = ctx.cards["action:insurance"]
    assert card.verification_status == "needs_review"
    assert card.last_verified_at == "2026-07-29"


def test_get_action_unknown_id(ctx):
    assert run(ctx, "get_action", action_id="nope") == {"found": False, "action_id": "nope"}
    assert ctx.cards == {}


def test_experiences_are_labelled_and_anonymous(ctx):
    found = run(ctx, "search_experiences", topic="culture_communication")
    assert found["count"] == 2
    assert all(r["kind"] == "student_experience" for r in found["results"])

    detail = run(ctx, "get_experience", experience_id="professor-see")
    assert "not verified fact" in detail["notice"]
    assert not any("author" in key for key in detail["experience"])
    assert ctx.cards["experience:professor-see"].label == "student_experience"


def test_get_my_progress_requires_login(ctx):
    ctx.user = None
    assert run(ctx, "get_my_progress") == {"requires_login": True, "results": []}


def test_get_my_progress_only_returns_own_records(ctx, data):
    data.progress["u1"] = [
        ProgressRecord(
            execution_id="e1",
            action_id="arc",
            action_title=Localized("申請或更新 ARC", "Apply for or Renew Your ARC"),
            started_at="2026-10-01T02:00:00Z",
            steps=(ProgressStep(1, Localized("準備文件", "Prepare documents"), "done"),),
        )
    ]
    data.progress["u2"] = []
    assert run(ctx, "get_my_progress")["results"][0]["steps"][0]["state"] == "done"
    ctx.user = ctx.user.__class__(id="u2")
    assert run(ctx, "get_my_progress")["count"] == 0


def test_unknown_tool_and_bad_args_become_error_results(ctx):
    assert "Unknown tool" in run(ctx, "delete_everything")["error"]
    missing = run(ctx, "get_action")
    assert missing["error"] == "Invalid arguments"
    assert run(ctx, "search_actions", query="x", sql="drop")["error"] == "Invalid arguments"


def test_open_screen_whitelist_and_target_checks(ctx):
    assert "error" in run(ctx, "open_screen", screen="open_admin")
    assert "error" in run(ctx, "open_screen", screen="open_action", target_id="nope")
    assert "error" in run(ctx, "open_screen", screen="open_action")

    assert run(ctx, "open_screen", screen="open_action", target_id="arc")["ok"] is True
    run(ctx, "open_screen", screen="open_action", target_id="arc")
    run(ctx, "open_screen", screen="open_explore", topic="life_adaptation", target_id="ignored")
    assert [a.model_dump() for a in ctx.screen_actions] == [
        {"type": "open_action", "target_id": "arc", "topic": None},
        {"type": "open_explore", "target_id": None, "topic": "life_adaptation"},
    ]


def test_tool_crash_is_contained(ctx, monkeypatch):
    def boom(*_):
        raise RuntimeError("db down")

    monkeypatch.setattr(ctx.data, "search_actions", boom)
    assert "unavailable" in run(ctx, "search_actions", query="arc")["error"]


def test_app_help_answers_how_to_questions(ctx):
    result = run(ctx, "search_app_help", query="驗證狀態代表什麼")
    assert result["guide_version"]
    assert result["results"][0]["id"] == "verification-status"

    ctx.locale = "en"
    share = run(ctx, "search_app_help", query="how do I share anonymously")
    assert share["results"][0]["id"] in {"share", "privacy"}
    assert share["results"][0]["body"].isascii() or "Share" in share["results"][0]["body"]


def test_app_guide_is_complete_in_both_languages():
    from app.assistant.knowledge import default_knowledge_base

    kb = default_knowledge_base()
    ids = [e.id for e in kb.entries]
    assert len(ids) == len(set(ids))
    for entry in kb.entries:
        assert entry.title.zh and entry.title.en and entry.body.zh and entry.body.en
        assert entry.title.zh != entry.title.en


def test_search_prefers_titles_and_ignores_question_words(ctx):
    assert run(ctx, "search_actions", query="ARC")["results"][0]["action_id"] == "arc"
    ctx.locale = "en"
    found = run(ctx, "search_actions", query="how do I get health insurance")["results"]
    assert found[0]["action_id"] == "insurance"
