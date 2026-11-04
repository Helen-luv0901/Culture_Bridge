"""The app shows answers as plain text, so Markdown the model writes anyway is taken out."""

from app.assistant.plain_text import plain_text
from tests.conftest import ScriptedLLM, answer
from tests.test_agent import USER, ask


def test_bold_and_headings_lose_their_markers():
    # 2026-11-05: the backup model wrote "1. **首次申請外僑居留證**:" and the app showed the stars.
    assert plain_text("1. **首次申請外僑居留證**：\n- 請**務必**在 30 天內申請") == (
        "1. 首次申請外僑居留證：\n- 請務必在 30 天內申請"
    )
    assert plain_text("***重要***") == "重要"
    assert plain_text("## 準備文件\n### Steps\n護照") == "準備文件\nSteps\n護照"


def test_ordinary_text_and_lists_stay_as_written():
    text = "1. 帶護照\n- 照片 2 張\n費用 1,000 元 * 2 份\nsnake_case_name 與 #hashtag"
    assert plain_text(text) == text
    for text in ("`__init__.py` 與 __name__", "2**3 + 4**2", "a__b__c"):
        assert plain_text(text) == text


def test_bold_never_pairs_across_lines():
    # An unclosed ** must not swallow the next line and move the stars elsewhere.
    assert plain_text("**A：xx\n- **B**：yy") == "**A：xx\n- B：yy"


def test_the_assistant_never_shows_markdown(make_assistant):
    llm = ScriptedLLM(
        answer("## 居留證\n1. **首次申請**：入境後 30 天內。\n**RELATED:** action:arc")
    )
    reply = make_assistant(llm).reply(ask("居留證要準備什麼？"), USER)
    assert reply.text == "居留證\n1. 首次申請：入境後 30 天內。"
    assert [c.type for c in reply.cards] == ["action"]  # a bolded RELATED line still counts
