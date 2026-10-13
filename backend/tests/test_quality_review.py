from app.ai.experience_ai import AIUnavailable, SummaryDraft
from app.core.config import get_settings
from app.quality import assistant_review, summary_review
from app.seed import seed
from tests.conftest import ScriptedLLM, answer, call


def test_assistant_review_sheet(db, monkeypatch, make_assistant):
    seed(db, get_settings().demo_content_path)
    llm = ScriptedLLM(call("get_action", action_id="work-permit"), answer("請看工作證流程卡。"))
    services = type("S", (), {"assistant": make_assistant(llm)})()
    monkeypatch.setattr(assistant_review, "get_services", lambda: services)

    reply = assistant_review.ask("工作證要準備哪些文件？", "zh-Hant")
    sheet = assistant_review.render(
        [{"question": "工作證要準備哪些文件？", "expect": "x"}], [reply]
    )
    assert "## 1. 工作證要準備哪些文件？" in sheet
    assert "> 請看工作證流程卡。" in sheet
    assert "流程卡 申請工作證（verified" in sheet and "get_action" in sheet
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
