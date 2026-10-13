"""Run the assistant on a fixed question list and write a review sheet (D-17).

    uv run python -m app.quality.assistant_review                   # default 20 questions
    uv run python -m app.quality.assistant_review questions.json -o review.md

Uses the same database (DATABASE_URL) and model (GEMINI_API_KEY) as the server, asking as a
guest, so nothing is written. Each question starts a new conversation. The sheet lists the answer,
the cards with their verification status, the tools used and whether it was a fallback, with
boxes for the reviewer to tick; send the problems to A.
"""

import argparse
import json
from datetime import datetime
from pathlib import Path

from app.api.assistant import get_services
from app.assistant.db_operations import DbOperationService
from app.assistant.pg_data import PostgresAssistantData
from app.assistant.schemas import AssistantMessageRequest, AssistantReply
from app.core.config import get_settings
from app.core.db import get_sessionmaker

DEFAULT_QUESTIONS = Path(__file__).with_name("assistant_questions.json")
CHECKS = (
    "- [ ] 答案正確　- [ ] 有附依據　- [ ] 驗證狀態正確　- [ ] 經驗標成學生經驗　- [ ] 沒有推測"
)


def ask(question: str, locale: str) -> AssistantReply:
    assistant = get_services().assistant
    with get_sessionmaker()() as db:
        return assistant.reply(
            AssistantMessageRequest(message=question, locale=locale),  # type: ignore[arg-type]
            None,
            data=PostgresAssistantData(db, None),
            operations=DbOperationService(db),
        )


def _cards(reply: AssistantReply) -> list[str]:
    lines = []
    for card in reply.cards:
        if card.type == "action":
            lines.append(
                f"流程卡 {card.title}（{card.verification_status}，"
                f"最後驗證 {card.last_verified_at or '—'}，來源 {len(card.sources)}）"
            )
        else:
            lines.append(f"學生經驗 {card.experience_id}：{card.reminder}")
    return lines


def render(cases: list[dict], replies: list[AssistantReply]) -> str:
    settings = get_settings()
    out = [
        "# 助理品質檢查（D-17）",
        "",
        f"產生時間 {datetime.now():%Y-%m-%d %H:%M}，模型 {settings.gemini_model}"
        + ("" if settings.gemini_api_key else "（沒有 GEMINI_API_KEY：全部是備用回覆）"),
        "",
    ]
    for i, (case, reply) in enumerate(zip(cases, replies, strict=True), 1):
        out += [f"## {i}. {case['question']}", ""]
        if case.get("expect"):
            out += [f"預期：{case['expect']}", ""]
        out += ["> " + line for line in reply.text.splitlines() or [""]]
        out.append("")
        out += [f"- {line}" for line in _cards(reply)]
        if reply.pending_operations:
            out.append(f"- 待確認操作：{', '.join(op.summary for op in reply.pending_operations)}")
        out.append(f"- 工具：{', '.join(reply.tools_used) or '—'}")
        if reply.fallback:
            out.append("- ⚠️ 備用回覆（模型失敗或超過上限）")
        out += ["", CHECKS, "", "問題說明：", ""]
    return "\n".join(out)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("questions", nargs="?", type=Path, default=DEFAULT_QUESTIONS)
    parser.add_argument("-o", "--output", type=Path, default=Path("assistant-review.md"))
    args = parser.parse_args()
    cases = json.loads(args.questions.read_text(encoding="utf-8"))
    replies = []
    for case in cases:
        replies.append(ask(case["question"], case.get("locale", "zh-Hant")))
        print(f"{len(replies)}/{len(cases)} {case['question']}")
    args.output.write_text(render(cases, replies), encoding="utf-8")
    print(f"已寫入 {args.output}")


if __name__ == "__main__":
    main()
