"""Fixes from the code review of 2026-11-19: the prefetch block stays valid JSON, semantic
search passes review warnings on, and the model cannot get more than two listed cards."""

import json

from app.assistant.prefetch import _HEADER, MAX_CHARS, prefetch
from app.assistant.related import Related, related_cards
from app.assistant.tools import ToolContext, faq_card
from app.core.auth import CurrentUser
from tests.test_tools import run


def test_a_long_english_prefetch_stays_valid_json_and_keeps_the_posts(data):
    ctx = ToolContext(data=data, locale="en", user=CurrentUser(id="u1"))
    block = prefetch("exchange student residence permit expires research assistant", ctx).block
    body = json.loads(block[len(_HEADER) + 1 :])  # once cut mid-string at 9,000 characters
    assert len(block) <= MAX_CHARS + len(_HEADER) + 1
    assert "student_experiences" in body
    assert body["official_faq"]["results"]


def test_prefetched_warnings_come_before_the_answer(data):
    ctx = ToolContext(data=data, locale="en", user=CurrentUser(id="u1"))
    found = prefetch("quarantine hotel accommodation compensation", ctx)
    for detail in json.loads(found.block[len(_HEADER) + 1 :])["official_faq"]["results"]:
        if "warning" in detail:
            assert list(detail).index("warning") < list(detail).index("answer")


class _Semantic:
    """The demo source with a semantic search that finds an outdated answer first."""

    def __init__(self, data):
        self._data = data

    def __getattr__(self, name):
        return getattr(self._data, name)

    def semantic_search(self, query, limit, faq_limit=None):
        return {
            "official_faqs": [
                {"faq_id": "nisa-852", "question": "old", "answer": "old answer"},
                {"faq_id": "nisa-1076", "question": "new", "answer": "new answer"},
                {"faq_id": "nisa-910", "question": "school", "answer": "hidden"},
            ],
            "official_passages": [],
        }


def test_semantic_search_passes_review_warnings_and_ranks_outdated_last(data):
    ctx = ToolContext(data=_Semantic(data), locale="zh-Hant", user=CurrentUser(id="u1"))
    found = run(ctx, "semantic_search", query="居留證逾期")
    ids = [f["faq_id"] for f in found["official_faqs"]]
    assert ids == ["nisa-1076", "nisa-852"]  # school question gone, superseded one last
    assert found["official_faqs"][1]["warning"]["superseded_by"] == "nisa-1076"


def test_at_most_two_listed_question_cards(ctx):
    for faq_id in ("nisa-934", "nisa-1076", "nisa-1077"):
        ctx.cards[f"faq:{faq_id}"] = faq_card(ctx.data.get_faq(faq_id), ctx.locale)
    related_cards(
        Related(text="see these", listed=True, faqs=("nisa-934", "nisa-1076", "nisa-1077")), ctx
    )
    assert [k for k in ctx.cards if k.startswith("faq:")] == ["faq:nisa-934", "faq:nisa-1076"]


def test_english_replies_show_no_card_for_a_question_with_only_a_chinese_answer(data):
    """2026-11-19: English mode shows no Chinese; Chinese-only questions appear in Chinese only."""
    zh_only = next(f for f in data.faqs.values() if not f.has_english)
    bilingual = next(f for f in data.faqs.values() if f.has_english)
    en = ToolContext(data=data, locale="en", user=CurrentUser(id="u1"))
    run(en, "get_official_faq", faq_id=zh_only.id)
    run(en, "get_official_faq", faq_id=bilingual.id)
    assert list(en.cards) == [f"faq:{bilingual.id}"]
    zh = ToolContext(data=data, locale="zh-Hant", user=CurrentUser(id="u1"))
    run(zh, "get_official_faq", faq_id=zh_only.id)
    assert list(zh.cards) == [f"faq:{zh_only.id}"]
