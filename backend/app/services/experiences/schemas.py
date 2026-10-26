"""Request and response shapes for experiences, plus the limits and tag rules they enforce."""

import re
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator

Locale = Literal["zh-Hant", "en"]
TopicId = Literal["life_adaptation", "culture_communication"]
Category = Literal["life", "food", "housing", "transit", "study", "culture", "difference"]
Sort = Literal["new", "hot"]
IdentityType = Literal["degree_student", "exchange_student", "language_student", "other"]
ReactionKind = Literal["helpful", "experienced_too"]
AuthorDisplay = Literal["anonymous", "nickname", "real_name"]
MAX_VOICE = 2000
MAX_TITLE = 80
MAX_TAGS = 8
MAX_TAG_LENGTH = 12
VERBATIM = "author-verbatim"  # model_name of the summary a post publishes with


def topic_for(category: str) -> str:
    """The older two-topic field still exists (the assistant filters by it)."""
    return "culture_communication" if category in ("culture", "difference") else "life_adaptation"


def clean_tags(tags: list[str]) -> list[str]:
    """'#tag' strings: no spaces, at most 12 characters, no repeats, at most 8."""
    out: list[str] = []
    for raw in tags:
        word = re.sub(r"\s+", "", raw.strip().lstrip("#"))
        if not word or len(word) > MAX_TAG_LENGTH:
            continue
        tag = f"#{word}"
        if tag not in out:
            out.append(tag)
    return out[:MAX_TAGS]


def _clean_voice(value: str) -> str:
    value = value.strip()
    if not value:
        raise ValueError("original_voice must not be blank")
    return value


class DraftIn(BaseModel):
    topic_id: TopicId
    identity_type: IdentityType
    original_voice: str = Field(max_length=MAX_VOICE)
    source_locale: Locale = "zh-Hant"
    different_from_id: str | None = None

    _voice = field_validator("original_voice")(_clean_voice)


class DraftUpdate(BaseModel):
    topic_id: TopicId | None = None
    identity_type: IdentityType | None = None
    original_voice: str | None = Field(default=None, max_length=MAX_VOICE)
    source_locale: Locale | None = None

    @field_validator("original_voice")
    @classmethod
    def _voice(cls, value: str | None) -> str | None:
        return None if value is None else _clean_voice(value)


class PostIn(BaseModel):
    """A post published as written."""

    title: str = Field(max_length=MAX_TITLE)
    original_voice: str = Field(max_length=MAX_VOICE)
    category: Category
    tags: list[str] = Field(default_factory=list, max_length=20)
    source_locale: Locale = "zh-Hant"
    author_display: Literal["anonymous", "nickname", "real_name"] = "anonymous"
    different_from_id: str | None = None
    # Shown under this official guide as well.
    action_id: str | None = None

    _voice = field_validator("original_voice")(_clean_voice)

    @field_validator("title")
    @classmethod
    def _title(cls, value: str) -> str:
        value = " ".join(value.split())
        if not value:
            raise ValueError("title must not be blank")
        return value

    @field_validator("tags")
    @classmethod
    def _tags(cls, value: list[str]) -> list[str]:
        return clean_tags(value)


class SummaryOut(BaseModel):
    id: str
    version_number: int
    situation: str
    feeling_or_attempt: str
    reminder: str
    model_name: str
    confirmed_at: datetime | None
    # False once the author has changed their words since this summary was made.
    matches_current_voice: bool


class PublishIn(BaseModel):
    summary_id: str
    # The author may adjust the AI wording before confirming.
    situation: str | None = Field(default=None, max_length=1000)
    feeling_or_attempt: str | None = Field(default=None, max_length=1000)
    reminder: str | None = Field(default=None, max_length=1000)
    author_display: AuthorDisplay = "anonymous"


class TranslationOut(BaseModel):
    locale: Locale
    title: str | None = None
    original_voice: str
    situation: str
    feeling_or_attempt: str
    reminder: str
    method: Literal["human", "ai"]


class PublicExperience(BaseModel):
    id: str
    topic_id: TopicId
    identity_type: IdentityType
    source_locale: Locale
    original_voice: str
    situation: str
    feeling_or_attempt: str
    reminder: str
    translation: TranslationOut | None
    published_at: datetime
    helpful_count: int
    experienced_too_count: int
    different_count: int
    my_reactions: list[ReactionKind]
    saved: bool = False
    # The name the author chose to sign with; None means anonymous.
    author_name: str | None = None
    # The author's photo, only on signed posts.
    author_avatar_url: str | None = None
    title: str | None = None
    category: Category = "life"
    tags: list[str] = Field(default_factory=list)
    comment_count: int = 0
    # Written by the signed-in reader (they may delete it).
    mine: bool = False
    # The official guide this post was shared under.
    action_id: str | None = None


class ExperienceDetail(PublicExperience):
    different_experiences: list[PublicExperience]
    responds_to_id: str | None


class Impact(BaseModel):
    helpful_count: int
    experienced_too_count: int
    different_count: int
    # People are counted once however many ways they reacted.
    people_reached: int


class MyExperience(BaseModel):
    id: str
    status: Literal["draft", "published", "hidden"]
    topic_id: TopicId
    identity_type: IdentityType
    source_locale: Locale
    original_voice: str
    created_at: datetime
    published_at: datetime | None
    latest_summary: SummaryOut | None
    impact: Impact
    author_display: AuthorDisplay = "anonymous"
    title: str | None = None
    category: Category = "life"
    tags: list[str] = Field(default_factory=list)
    comment_count: int = 0


class ExperiencePage(BaseModel):
    items: list[PublicExperience]
    next_offset: int | None
