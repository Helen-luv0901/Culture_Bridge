import re

import pytest

from app.assistant.llm import ToolCall
from app.assistant.tools import ToolContext, default_registry

registry = default_registry()


def run(ctx: ToolContext, name: str, **args) -> dict:
    return registry.execute(ToolCall(id="1", name=name, args=args), ctx).result


def test_specs_are_plain_json_schema():
    specs = {s.name: s for s in registry.specs()}
    assert set(specs) == {
        "search_official_faq",
        "get_official_faq",
        "search_procedures",
        "get_procedure",
        "search_experiences",
        "get_experience",
        "open_screen",
        "search_app_help",
        "semantic_search",
    }
    search = specs["search_experiences"].parameters
    assert search["type"] == "object"
    assert search["properties"]["topic"]["enum"] == ["life_adaptation", "culture_communication"]
    assert "anyOf" not in search["properties"]["query"]
    assert specs["get_official_faq"].parameters["required"] == ["faq_id"]


def test_search_official_faq_matches_chinese_question(ctx):
    result = run(ctx, "search_official_faq", query="居留證逾期")
    assert result["results"][0]["faq_id"] == "nisa-934"
    assert result["results"][0]["category"] == "簽證/居留證"


def test_search_official_faq_in_english(ctx):
    ctx.locale = "en"
    first = run(ctx, "search_official_faq", query="health insurance")["results"][0]
    assert first["category"] == "Health and Insurance"
    # The site's English version (it may use typographic quotes, so not "ASCII only").
    assert not re.search(r"[一-鿿]", first["question"])


def test_search_official_faq_no_match_is_empty(ctx):
    assert run(ctx, "search_official_faq", query="寵物貓") == {"count": 0, "results": []}


def test_get_official_faq_returns_the_answer_with_its_source_and_records_card(ctx):
    result = run(ctx, "get_official_faq", faq_id="nisa-934")
    faq = result["faq"]
    assert result["found"] is True
    assert "government agencies" in result["notice"]
    assert faq["answer"] and faq["answering_agency"] and faq["posted_on"]
    assert faq["url"].startswith("https://www.nisa.moe.gov.tw/")
    card = ctx.cards["faq:nisa-934"]
    assert card.question == faq["question"]
    assert card.answering_agency == faq["answering_agency"]


def test_chinese_only_question_tells_the_model_to_translate(ctx):
    ctx.locale = "en"
    faq = run(ctx, "get_official_faq", faq_id="nisa-1076")["faq"]
    assert "Only the Chinese original" in faq["note"]
    assert "居留證" in faq["question"]


def test_get_official_faq_unknown_id(ctx):
    assert run(ctx, "get_official_faq", faq_id="nope") == {"found": False, "faq_id": "nope"}
    assert ctx.cards == {}


def test_experiences_are_labelled_and_anonymous(ctx):
    found = run(ctx, "search_experiences", topic="culture_communication")
    assert found["count"] == 2
    assert all(r["kind"] == "student_experience" for r in found["results"])

    detail = run(ctx, "get_experience", experience_id="professor-see")
    assert "not verified fact" in detail["notice"]
    assert not any("author" in key for key in detail["experience"])
    assert ctx.cards["experience:professor-see"].label == "student_experience"


def test_unknown_tool_and_bad_args_become_error_results(ctx):
    assert "Unknown tool" in run(ctx, "delete_everything")["error"]
    missing = run(ctx, "get_official_faq")
    assert missing["error"] == "Invalid arguments"
    assert run(ctx, "search_official_faq", query="x", sql="drop")["error"] == "Invalid arguments"
    # Procedures are read, never started from the assistant.
    assert "Unknown tool" in run(ctx, "search_actions", query="ARC")["error"]
    assert "Unknown tool" in run(ctx, "propose_start_action", action_id="arc")["error"]


def test_procedure_tools_find_and_read_a_card(ctx):
    found = run(ctx, "search_procedures", query="ARC")
    assert found["count"] >= 1 and found["results"][0]["procedure_id"] == "arc"
    assert set(found["results"][0]) == {"procedure_id", "title"}
    detail = run(ctx, "get_procedure", procedure_id="arc")
    assert detail["found"] is True and detail["procedure"]["steps"]
    assert "辦理證件" in detail["notice"]
    assert run(ctx, "get_procedure", procedure_id="nope") == {
        "found": False,
        "procedure_id": "nope",
    }
    # Reading a card does not show it: the model names the cards it recommends.
    assert ctx.cards == {}


def test_open_screen_whitelist_and_target_checks(ctx):
    assert "error" in run(ctx, "open_screen", screen="open_admin")
    assert "error" in run(ctx, "open_screen", screen="open_faq", target_id="nope")
    assert "error" in run(ctx, "open_screen", screen="open_faq")
    assert "error" in run(ctx, "open_screen", screen="open_action", target_id="nope")
    assert "error" in run(ctx, "open_screen", screen="open_progress", target_id="arc")
    assert run(ctx, "open_screen", screen="open_action", target_id="arc")["ok"] is True
    ctx.screen_actions.clear()

    assert run(ctx, "open_screen", screen="open_faq", target_id="nisa-934")["ok"] is True
    run(ctx, "open_screen", screen="open_faq", target_id="nisa-934")
    run(ctx, "open_screen", screen="open_explore", topic="life_adaptation", target_id="ignored")
    assert [a.model_dump() for a in ctx.screen_actions] == [
        {"type": "open_faq", "target_id": "nisa-934", "topic": None},
        {"type": "open_explore", "target_id": None, "topic": "life_adaptation"},
    ]


def test_tool_crash_is_contained(ctx, monkeypatch):
    def boom(*_):
        raise RuntimeError("db down")

    monkeypatch.setattr(ctx.data, "search_faqs", boom)
    assert "unavailable" in run(ctx, "search_official_faq", query="arc")["error"]


def test_app_help_answers_how_to_questions(ctx):
    result = run(ctx, "search_app_help", query="官方問答是誰寫的")
    assert result["guide_version"]
    assert result["results"][0]["id"] == "official-faq"

    ctx.locale = "en"
    share = run(ctx, "search_app_help", query="how do I share anonymously")
    assert share["results"][0]["id"] in {"share", "privacy"}
    assert share["results"][0]["body"].isascii() or "Share" in share["results"][0]["body"]


@pytest.mark.parametrize(
    ("locale", "query", "expected"),
    [
        ("zh-Hant", "怎麼刪除帳號", "delete-account"),
        ("zh-Hant", "要怎麼檢舉", "report-block"),
        ("zh-Hant", "需要登入嗎", "sign-in"),
        ("en", "how do I block someone", "report-block"),
        ("en", "how do I delete my account", "delete-account"),
        ("zh-Hant", "怎麼收藏想再看的經驗", "saved"),
        ("en", "how do I bookmark an experience", "saved"),
        ("zh-Hant", "可以用暱稱發文嗎", "names"),
        ("en", "can I post with my real name", "names"),
    ],
)
def test_app_help_covers_account_and_safety(ctx, locale, query, expected):
    ctx.locale = locale
    assert run(ctx, "search_app_help", query=query)["results"][0]["id"] == expected


def test_app_guide_is_complete_in_both_languages():
    from app.assistant.knowledge import default_knowledge_base

    kb = default_knowledge_base()
    ids = [e.id for e in kb.entries]
    assert len(ids) == len(set(ids))
    for entry in kb.entries:
        assert entry.title.zh and entry.title.en and entry.body.zh and entry.body.en
        assert entry.title.zh != entry.title.en


def test_search_prefers_questions_and_ignores_question_words(ctx):
    assert run(ctx, "search_official_faq", query="駕照")["results"][0]["faq_id"] == "nisa-923"
    ctx.locale = "en"
    found = run(ctx, "search_official_faq", query="how do I renew my driving license")["results"]
    assert found[0]["faq_id"] == "nisa-923"
