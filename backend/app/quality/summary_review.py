"""Run the AI experience summary on real shares and write a review sheet (B-22).

    uv run python -m app.quality.summary_review shares.json -o summary-review.md

shares.json is a list of {"text": "...", "locale": "zh-Hant" | "en"}: about 20 real shares
collected with the students' consent. Keep that file out of the repo. The sheet shows each
original next to its summary with boxes for: faithful to the original, no experience written
as a rule, nothing identifying.
"""

import argparse
import json
from datetime import datetime
from pathlib import Path

from app.ai.experience_ai import AIUnavailable, ExperienceAI, get_experience_ai

CHECKS = (
    "- [ ] 忠於原文（沒有新增事實）　- [ ] 沒有把經驗寫成規定"
    "　- [ ] 沒有可辨識個人的資訊　- [ ] 提醒有幫助"
)


def review(ai: ExperienceAI, shares: list[dict]) -> str:
    out = ["# AI 摘要品質檢查（B-22）", "", f"產生時間 {datetime.now():%Y-%m-%d %H:%M}", ""]
    for i, share in enumerate(shares, 1):
        out += [f"## {i}", "", "原文：", ""]
        out += ["> " + line for line in share["text"].splitlines() or [""]]
        out.append("")
        try:
            draft = ai.summarize(share["text"], share.get("locale", "zh-Hant"))
            out += [
                f"- 情境：{draft.situation}",
                f"- 感受或嘗試：{draft.feeling_or_attempt or '—'}",
                f"- 給下一位的提醒：{draft.reminder}",
                f"- 模型：{draft.model_name}",
            ]
        except AIUnavailable as exc:
            out.append(f"- ⚠️ AI 無法產生摘要：{exc}")
        out += ["", CHECKS, "", "問題說明：", ""]
    return "\n".join(out)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("shares", type=Path)
    parser.add_argument("-o", "--output", type=Path, default=Path("summary-review.md"))
    args = parser.parse_args()
    shares = json.loads(args.shares.read_text(encoding="utf-8"))
    args.output.write_text(review(get_experience_ai(), shares), encoding="utf-8")
    print(f"已寫入 {args.output}（{len(shares)} 則）")


if __name__ == "__main__":
    main()
