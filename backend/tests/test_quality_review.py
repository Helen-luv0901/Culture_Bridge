from app.ai.experience_ai import AIUnavailable, SummaryDraft
from app.core.config import get_settings
from app.quality import assistant_review, summary_review
from app.seed import seed
from tests.conftest import ScriptedLLM, answer, call


def test_assistant_review_sheet(db, monkeypatch, make_assistant):
    seed(db, get_settings().demo_content_path)
    llm = ScriptedLLM(call("get_official_faq", faq_id="nisa-934"), answer("請看移民署的回覆。"))
    services = type("S", (), {"assistant": make_assistant(llm)})()
    monkeypatch.setattr(assistant_review, "get_services", lambda: services)

    reply = assistant_review.ask("居留證過期怎麼辦？", "zh-Hant")
    sheet = assistant_review.render([{"question": "居留證過期怎麼辦？", "expect": "x"}], [reply])
    assert "## 1. 居留證過期怎麼辦？" in sheet
    assert "> 請看移民署的回覆。" in sheet
    assert "官方問答 nisa-934 居留證逾期" in sheet and "get_official_faq" in sheet
    assert "- [ ] 答案正確" in sheet


def test_summary_review_sheet():
    class FakeAI:
        def summarize(self, text, locale):
            if text == "bad":
                raise AIUnavailable("down")
            return SummaryDraft("情境", "", "提醒", "gemini-test")

    sheet = summary_review.review(FakeAI(), [{"text": "原話"}, {"text": "bad"}])
    assert "> 原話" in sheet and "- 情境：情境" in sheet and "- 感受或嘗試：—" in sheet
    assert "⚠️ AI 無法產生摘要" in sheet
