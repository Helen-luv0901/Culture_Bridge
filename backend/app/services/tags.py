"""Tag suggestions for a post being written (「AI 推薦標籤」).

The AI only suggests tags; it never rewrites the post. When the model is unavailable, or the
author has used today's allowance, keyword rules suggest tags instead, so the share page keeps
working. Suggestions are never stored: the author picks which ones go out with the post.
"""

import logging
import re
from datetime import timedelta, timezone

from pydantic import BaseModel, Field

from app.ai.experience_ai import AIUnavailable, ExperienceAI
from app.core.auth import CurrentUser
from app.services.common import DailyAllowance
from app.services.experiences import clean_tags

logger = logging.getLogger(__name__)

MAX_SUGGESTIONS = 6
_TAIPEI = timezone(timedelta(hours=8))

# Keyword -> tag, for when the model cannot be used. Chinese first, then English.
KEYWORD_TAGS: tuple[tuple[str, str], ...] = (
    ("預約", "#線上預約"),
    ("移民署", "#移民署"),
    ("服務站", "#移民署"),
    ("居留", "#居留證"),
    ("arc", "#居留證"),
    ("在學證明", "#在學證明"),
    ("退件", "#退件"),
    ("健保", "#健保"),
    ("nhi", "#健保"),
    ("看病", "#看病"),
    ("醫院", "#看病"),
    ("銀行", "#開戶"),
    ("開戶", "#開戶"),
    ("bank", "#開戶"),
    ("租", "#租屋"),
    ("房東", "#租屋"),
    ("rent", "#租屋"),
    ("電費", "#電費"),
    ("垃圾", "#垃圾分類"),
    ("教授", "#教授"),
    ("老師", "#教授"),
    ("professor", "#教授"),
    ("同學", "#人際關係"),
    ("朋友", "#人際關係"),
    ("吃飯", "#邀約"),
    ("客氣", "#客套話"),
    ("打工", "#打工"),
    ("工作證", "#工作證"),
    ("work permit", "#工作證"),
    ("照片", "#證件照"),
    ("機場", "#交通"),
    ("捷運", "#交通"),
    ("公車", "#公車"),
    ("bus", "#公車"),
    ("夜市", "#夜市"),
    ("點餐", "#點餐"),
    ("宿舍", "#宿舍"),
    ("dorm", "#宿舍"),
    ("中文", "#語言"),
    ("聽不懂", "#語言"),
    ("排隊", "#等很久"),
    ("文件", "#要帶的文件"),
    ("護照", "#要帶的文件"),
    ("passport", "#要帶的文件"),
)


class TagRequest(BaseModel):
    title: str = Field(default="", max_length=200)
    text: str = Field(default="", max_length=2000)
    category: str | None = Field(default=None, max_length=20)


class TagSuggestions(BaseModel):
    tags: list[str]
    # "ai" or "keywords": where the suggestions came from.
    source: str


def keyword_tags(text: str) -> list[str]:
    lower = text.lower()
    found = [tag for word, tag in KEYWORD_TAGS if word in lower]
    return clean_tags(found)[:MAX_SUGGESTIONS]


# How many model calls each author has made today.
_allowance = DailyAllowance("tags")


def _locale(text: str) -> str:
    return "zh-Hant" if re.search(r"[㐀-鿿]", text) else "en"


def suggest(
    user: CurrentUser, body: TagRequest, ai: ExperienceAI, daily_limit: int
) -> TagSuggestions:
    text = f"{body.title}\n{body.text}".strip()
    if not text:
        return TagSuggestions(tags=[], source="keywords")
    if _allowance.take(user.id, daily_limit):
        try:
            raw = ai.suggest_tags(body.title, body.text, _locale(text))  # type: ignore[arg-type]
            tags = clean_tags(raw)[:MAX_SUGGESTIONS]
            if tags:
                return TagSuggestions(tags=tags, source="ai")
        except AIUnavailable as exc:
            logger.info("Tag suggestions fall back to keywords: %s", exc)
    return TagSuggestions(tags=keyword_tags(text), source="keywords")
