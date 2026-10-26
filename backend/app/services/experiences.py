"""Student experiences (B-8..B-16).

Posts (the redesign): the author writes a title and text, picks a category and tags, and the
post is published exactly as written; the AI only suggests tags. Each post still gets a confirmed
"verbatim" summary (empty parts) so the database's publication gate stays the same.

Older flow (kept for existing drafts): draft -> AI summary -> author confirms -> published.
Either way posts are translated in the background and never carry a verification status. Public
payloads never expose the author's account; they show a name only when the author chose to sign
with their nickname or real name, read live from the account.
"""

import logging
import re
import threading
from datetime import UTC, datetime, timedelta, timezone
from typing import Literal

from pydantic import BaseModel, Field, field_validator
from sqlalchemy import Select, delete, exists, func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.ai.experience_ai import AIUnavailable, ExperienceAI, TranslatedExperience
from app.core.auth import CurrentUser
from app.core.errors import ApiError, conflict, not_found
from app.core.text_search import relevant, search_units
from app.models import (
    Action,
    ActionExperienceLink,
    CommentLike,
    Experience,
    ExperienceComment,
    ExperienceLink,
    ExperienceReaction,
    ExperienceSummary,
    ExperienceTranslation,
    SavedExperience,
    User,
)
from app.rag.index import remove_content
from app.services import avatars
from app.services.blocking import hides_comment_on_its_post, hides_experience
from app.services.common import now

logger = logging.getLogger(__name__)

Locale = Literal["zh-Hant", "en"]
TopicId = Literal["life_adaptation", "culture_communication"]
Category = Literal["life", "food", "housing", "transit", "study", "culture", "difference"]
Sort = Literal["new", "hot"]
IdentityType = Literal["degree_student", "exchange_student", "language_student", "other"]
ReactionKind = Literal["helpful", "experienced_too"]
AuthorDisplay = Literal["anonymous", "nickname", "real_name"]
_TAIPEI = timezone(timedelta(hours=8))
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


# ---------- helpers ----------


def _own(db: Session, user: CurrentUser, experience_id: str) -> Experience:
    experience = db.get(Experience, experience_id)
    if experience is None or experience.author_id != user.id:
        raise not_found("experience_not_found")
    return experience


def _own_draft(db: Session, user: CurrentUser, experience_id: str) -> Experience:
    experience = _own(db, user, experience_id)
    if experience.status != "draft":
        raise conflict("experience_not_draft")
    return experience


def _summary_out(summary: ExperienceSummary, voice: str) -> SummaryOut:
    return SummaryOut(
        id=summary.id,
        version_number=summary.version_number,
        situation=summary.situation,
        feeling_or_attempt=summary.feeling_or_attempt,
        reminder=summary.reminder,
        model_name=summary.model_name,
        confirmed_at=summary.confirmed_at,
        matches_current_voice=summary.source_voice == voice,
    )


def _latest_summary(db: Session, experience_id: str) -> ExperienceSummary | None:
    return db.scalar(
        select(ExperienceSummary)
        .where(ExperienceSummary.experience_id == experience_id)
        .order_by(ExperienceSummary.version_number.desc())
    )


def _next_summary_number(db: Session, experience_id: str) -> int:
    current = db.scalar(
        select(func.max(ExperienceSummary.version_number)).where(
            ExperienceSummary.experience_id == experience_id
        )
    )
    return (current or 0) + 1


def _public_query(viewer: CurrentUser | None) -> Select:
    query = (
        select(Experience, ExperienceSummary)
        .join(
            ExperienceSummary,
            (ExperienceSummary.id == Experience.confirmed_summary_id)
            & (ExperienceSummary.experience_id == Experience.id),
        )
        .where(Experience.status == "published")
    )
    if viewer is not None:
        query = query.where(~hides_experience(viewer.id))
    return query


def _category(experience: Experience) -> str:
    return experience.category or (
        "culture" if experience.topic_id == "culture_communication" else "life"
    )


def _visible_comments(
    db: Session, ids: list[str], viewer: CurrentUser | None = None
) -> dict[str, int]:
    """Comments on each post as `viewer` sees them: without the ones they blocked, or the
    count would tell them a blocked author commented there."""
    if not ids:
        return {}
    query = (
        select(ExperienceComment.experience_id, func.count())
        .join(Experience, Experience.id == ExperienceComment.experience_id)
        .where(
            ExperienceComment.experience_id.in_(ids),
            ExperienceComment.status == "visible",
        )
        .group_by(ExperienceComment.experience_id)
    )
    if viewer is not None:
        query = query.where(~hides_comment_on_its_post(viewer.id))
    return dict(db.execute(query).all())  # type: ignore[arg-type]


def _counts(db: Session, ids: list[str]) -> dict[str, dict[str, int]]:
    counts: dict[str, dict[str, int]] = {i: {} for i in ids}
    if not ids:
        return counts
    for experience_id, kind, n in db.execute(
        select(ExperienceReaction.experience_id, ExperienceReaction.kind, func.count())
        .where(ExperienceReaction.experience_id.in_(ids))
        .group_by(ExperienceReaction.experience_id, ExperienceReaction.kind)
    ):
        counts[experience_id][kind] = n
    other = Experience.__table__.alias("other")
    for experience_id, n in db.execute(
        select(ExperienceLink.from_experience_id, func.count())
        .join(other, other.c.id == ExperienceLink.to_experience_id)
        .where(
            ExperienceLink.from_experience_id.in_(ids),
            ExperienceLink.kind == "different",
            other.c.status == "published",
        )
        .group_by(ExperienceLink.from_experience_id)
    ):
        counts[experience_id]["different"] = n
    return counts


def _public_items(
    db: Session, rows: list, viewer: CurrentUser | None, locale: Locale | None
) -> list[PublicExperience]:
    ids = [e.id for e, _ in rows]
    counts = _counts(db, ids)
    mine: dict[str, list[str]] = {}
    if viewer is not None and ids:
        for experience_id, kind in db.execute(
            select(ExperienceReaction.experience_id, ExperienceReaction.kind).where(
                ExperienceReaction.experience_id.in_(ids), ExperienceReaction.user_id == viewer.id
            )
        ):
            mine.setdefault(experience_id, []).append(kind)
    saved: set[str] = set()
    if viewer is not None and ids:
        saved = set(
            db.scalars(
                select(SavedExperience.experience_id).where(
                    SavedExperience.experience_id.in_(ids), SavedExperience.user_id == viewer.id
                )
            )
        )
    names: dict[str, str | None] = {}
    signed = {e.author_id for e, _ in rows if e.author_display != "anonymous"}
    if signed:
        authors = {u.id: u for u in db.scalars(select(User).where(User.id.in_(signed)))}
        for experience, _ in rows:
            author = authors.get(experience.author_id)
            if author is not None and experience.author_display == "nickname":
                names[experience.id] = author.nickname
            elif author is not None and experience.author_display == "real_name":
                names[experience.id] = author.real_name
    photos = avatars.urls_for(db, signed)
    comments = _visible_comments(db, ids, viewer)
    guides: dict[str, str] = {}
    if ids:
        for action_id, experience_id in db.execute(
            select(ActionExperienceLink.action_id, ActionExperienceLink.experience_id).where(
                ActionExperienceLink.experience_id.in_(ids)
            )
        ):
            guides.setdefault(experience_id, action_id)
    translations: dict[str, ExperienceTranslation] = {}
    if ids:
        for t in db.scalars(
            select(ExperienceTranslation).where(ExperienceTranslation.experience_id.in_(ids))
        ):
            translations[(t.experience_id, t.summary_id, t.locale)] = t  # type: ignore[index]
    items = []
    for experience, summary in rows:
        target = locale or ("en" if experience.source_locale == "zh-Hant" else "zh-Hant")
        t = None
        if target != experience.source_locale:
            t = translations.get((experience.id, summary.id, target))  # type: ignore[call-overload]
        c = counts[experience.id]
        items.append(
            PublicExperience(
                id=experience.id,
                topic_id=experience.topic_id,  # type: ignore[arg-type]
                identity_type=experience.identity_type,  # type: ignore[arg-type]
                source_locale=experience.source_locale,  # type: ignore[arg-type]
                original_voice=experience.original_voice,
                situation=summary.situation,
                feeling_or_attempt=summary.feeling_or_attempt,
                reminder=summary.reminder,
                translation=TranslationOut(
                    locale=t.locale,  # type: ignore[arg-type]
                    title=t.title,
                    original_voice=t.original_voice,
                    situation=t.situation,
                    feeling_or_attempt=t.feeling_or_attempt,
                    reminder=t.reminder,
                    method=t.method,  # type: ignore[arg-type]
                )
                if t
                else None,
                published_at=experience.published_at,  # type: ignore[arg-type]
                helpful_count=c.get("helpful", 0),
                experienced_too_count=c.get("experienced_too", 0),
                different_count=c.get("different", 0),
                my_reactions=sorted(mine.get(experience.id, [])),  # type: ignore[arg-type]
                saved=experience.id in saved,
                author_name=names.get(experience.id),
                author_avatar_url=photos.get(experience.author_id)
                if names.get(experience.id)
                else None,
                title=experience.title,
                category=_category(experience),  # type: ignore[arg-type]
                tags=list(experience.tags or []),
                comment_count=comments.get(experience.id, 0),
                mine=viewer is not None and experience.author_id == viewer.id,
                action_id=guides.get(experience.id),
            )
        )
    return items


def _word_matches(word: str):
    """The word appears in the title, tags, original, summary or a translation."""
    pattern = f"%{word.replace('%', '').replace('_', '')}%"
    translated = exists().where(
        ExperienceTranslation.experience_id == Experience.id,
        or_(
            ExperienceTranslation.title.ilike(pattern),
            ExperienceTranslation.original_voice.ilike(pattern),
            ExperienceTranslation.situation.ilike(pattern),
            ExperienceTranslation.reminder.ilike(pattern),
        ),
    )
    return or_(
        Experience.title.ilike(pattern),
        func.array_to_string(Experience.tags, " ").ilike(pattern),
        Experience.original_voice.ilike(pattern),
        ExperienceSummary.situation.ilike(pattern),
        ExperienceSummary.feeling_or_attempt.ilike(pattern),
        ExperienceSummary.reminder.ilike(pattern),
        translated,
    )


def _keyword_filter(query: Select, q: str) -> Select:
    """Match every word of q (B-16)."""
    for word in q.split()[:8]:
        query = query.where(_word_matches(word))
    return query


# Newest posts sharing any word with the query that get ranked; the rest are too weak to show.
SEARCH_CANDIDATES = 200


def search(
    db: Session, viewer: CurrentUser | None, q: str, locale: Locale | None, limit: int
) -> list[PublicExperience]:
    """The Explore search: posts about the query first, whole questions allowed."""
    units = search_units(q)
    if not units:
        return []
    rows = db.execute(
        _public_query(viewer)
        .where(or_(*(_word_matches(unit) for unit in units)))
        .order_by(Experience.published_at.desc(), Experience.id)
        .limit(SEARCH_CANDIDATES)
    ).all()
    # A translated title is still a title: 「在學證明」 should rank an English post about it.
    titles: dict[str, list[str]] = {}
    bodies: dict[str, list[str]] = {}
    for t in db.scalars(
        select(ExperienceTranslation).where(
            ExperienceTranslation.experience_id.in_([e.id for e, _ in rows])
        )
    ):
        titles.setdefault(t.experience_id, []).append(t.title or "")
        bodies.setdefault(t.experience_id, []).extend([t.original_voice, t.situation, t.reminder])
    items = [
        (
            (experience, summary),
            " ".join(
                [experience.title or "", *(experience.tags or []), *titles.get(experience.id, [])]
            ).lower(),
            " ".join(
                [
                    experience.original_voice,
                    summary.situation,
                    summary.feeling_or_attempt,
                    summary.reminder,
                    *bodies.get(experience.id, []),
                ]
            ).lower(),
        )
        for experience, summary in rows
    ]
    return _public_items(db, relevant(items, q, limit), viewer, locale)


# ---------- public reads ----------


def _heat():
    """ "Me too" taps plus twice the visible comments (a comment takes more effort)."""
    same = (
        select(func.count())
        .where(
            ExperienceReaction.experience_id == Experience.id,
            ExperienceReaction.kind == "experienced_too",
        )
        .correlate(Experience)
        .scalar_subquery()
    )
    comments = (
        select(func.count())
        .where(
            ExperienceComment.experience_id == Experience.id,
            ExperienceComment.status == "visible",
        )
        .correlate(Experience)
        .scalar_subquery()
    )
    return same + 2 * comments


def explore(
    db: Session,
    viewer: CurrentUser | None,
    topic_id: str | None,
    identity_type: str | None,
    q: str | None,
    locale: Locale | None,
    limit: int,
    offset: int,
    category: str | None = None,
    action_id: str | None = None,
    sort: Sort = "new",
) -> ExperiencePage:
    query = _public_query(viewer)
    if topic_id:
        query = query.where(Experience.topic_id == topic_id)
    if category in ("life", "culture"):
        # Posts from before categories only have a topic: life or culture.
        query = query.where(
            or_(
                Experience.category == category,
                Experience.category.is_(None) & (Experience.topic_id == topic_for(category)),
            )
        )
    elif category:
        query = query.where(Experience.category == category)
    if identity_type:
        query = query.where(Experience.identity_type == identity_type)
    if action_id:
        query = query.where(
            exists().where(
                ActionExperienceLink.experience_id == Experience.id,
                ActionExperienceLink.action_id == action_id,
            )
        )
    if q and q.strip():
        query = _keyword_filter(query, q.strip())
    order = (
        (_heat().desc(), Experience.published_at.desc(), Experience.id)
        if sort == "hot"
        else (Experience.published_at.desc(), Experience.id)
    )
    rows = db.execute(query.order_by(*order).limit(limit + 1).offset(offset)).all()
    has_more = len(rows) > limit
    return ExperiencePage(
        items=_public_items(db, rows[:limit], viewer, locale),
        next_offset=offset + limit if has_more else None,
    )


def get_public(
    db: Session, viewer: CurrentUser | None, experience_id: str, locale: Locale | None
) -> ExperienceDetail:
    row = db.execute(_public_query(viewer).where(Experience.id == experience_id)).first()
    if row is None:
        raise not_found("experience_not_found")
    [item] = _public_items(db, [row], viewer, locale)
    different = db.execute(
        _public_query(viewer)
        .join(ExperienceLink, ExperienceLink.to_experience_id == Experience.id)
        .where(
            ExperienceLink.from_experience_id == experience_id, ExperienceLink.kind == "different"
        )
        .order_by(Experience.published_at.desc())
    ).all()
    responds_to = db.scalar(
        select(ExperienceLink.from_experience_id).where(
            ExperienceLink.to_experience_id == experience_id, ExperienceLink.kind == "different"
        )
    )
    return ExperienceDetail(
        **item.model_dump(),
        different_experiences=_public_items(db, different, viewer, locale),
        responds_to_id=responds_to,
    )


def _require_public(db: Session, experience_id: str) -> Experience:
    experience = db.get(Experience, experience_id)
    if experience is None or experience.status != "published":
        raise not_found("experience_not_found")
    return experience


# ---------- authoring ----------


def create_draft(db: Session, user: CurrentUser, body: DraftIn) -> MyExperience:
    if body.different_from_id:
        _require_public(db, body.different_from_id)
    experience = Experience(
        author_id=user.id,
        topic_id=body.topic_id,
        identity_type=body.identity_type,
        original_voice=body.original_voice,
        source_locale=body.source_locale,
    )
    db.add(experience)
    db.flush()
    if body.different_from_id:
        # Counted as a "different experience" only once this one is published.
        db.add(
            ExperienceLink(
                from_experience_id=body.different_from_id,
                to_experience_id=experience.id,
                kind="different",
            )
        )
    db.commit()
    return my_experience(db, experience)


def update_draft(
    db: Session, user: CurrentUser, experience_id: str, body: DraftUpdate
) -> MyExperience:
    experience = _own_draft(db, user, experience_id)
    for field in ("topic_id", "identity_type", "original_voice", "source_locale"):
        value = getattr(body, field)
        if value is not None:
            setattr(experience, field, value)
    db.commit()
    return my_experience(db, experience)


def _summaries_today(db: Session, user: CurrentUser) -> int:
    local_midnight = datetime.combine(
        now().astimezone(_TAIPEI).date(), datetime.min.time(), _TAIPEI
    )
    return (
        db.scalar(
            select(func.count())
            .select_from(ExperienceSummary)
            .join(Experience, Experience.id == ExperienceSummary.experience_id)
            .where(
                Experience.author_id == user.id,
                ExperienceSummary.created_at >= local_midnight.astimezone(UTC),
                # Author edits are not AI calls.
                ExperienceSummary.model_name.not_like("%+author-edit"),
                # Posts published as written are not AI calls either.
                ExperienceSummary.model_name != VERBATIM,
            )
        )
        or 0
    )


def generate_summary(
    db: Session, user: CurrentUser, experience_id: str, ai: ExperienceAI, daily_limit: int
) -> SummaryOut:
    experience = _own_draft(db, user, experience_id)
    if _summaries_today(db, user) >= daily_limit:
        raise ApiError(429, "ai_daily_limit_reached")
    db.commit()  # hand the connection back while the AI works (up to a minute)
    try:
        draft = ai.summarize(experience.original_voice, experience.source_locale)  # type: ignore[arg-type]
    except AIUnavailable as exc:
        raise ApiError(
            503, "ai_unavailable", "AI summary is not available; try again later"
        ) from exc
    summary = ExperienceSummary(
        experience_id=experience.id,
        version_number=_next_summary_number(db, experience.id),
        source_voice=experience.original_voice,
        situation=draft.situation,
        feeling_or_attempt=draft.feeling_or_attempt,
        reminder=draft.reminder,
        model_name=draft.model_name,
    )
    db.add(summary)
    db.commit()
    return _summary_out(summary, experience.original_voice)


def publish(db: Session, user: CurrentUser, experience_id: str, body: PublishIn) -> MyExperience:
    """The author confirms a summary of their current words; only then is it public (B-10)."""
    experience = _own_draft(db, user, experience_id)
    summary = db.get(ExperienceSummary, body.summary_id)
    if summary is None or summary.experience_id != experience.id:
        raise not_found("summary_not_found")
    if summary.source_voice != experience.original_voice:
        raise conflict("summary_outdated", "The words changed; generate a new summary first")
    edits = {
        k: v.strip()
        for k in ("situation", "feeling_or_attempt", "reminder")
        if (v := getattr(body, k)) is not None and v.strip() != getattr(summary, k)
    }
    if edits.get("situation") == "" or edits.get("reminder") == "":
        raise ApiError(422, "summary_fields_required")
    if edits:
        summary = ExperienceSummary(
            experience_id=experience.id,
            version_number=_next_summary_number(db, experience.id),
            source_voice=experience.original_voice,
            situation=edits.get("situation", summary.situation),
            feeling_or_attempt=edits.get("feeling_or_attempt", summary.feeling_or_attempt),
            reminder=edits.get("reminder", summary.reminder),
            model_name=f"{summary.model_name}+author-edit",
        )
        db.add(summary)
        db.flush()
    if body.author_display != "anonymous":
        account = db.get(User, user.id)
        if account is None or not getattr(account, body.author_display):
            raise ApiError(422, f"{body.author_display}_missing")
    experience.author_display = body.author_display
    summary.confirmed_by = user.id
    summary.confirmed_at = now()
    db.flush()
    experience.status = "published"
    experience.confirmed_summary_id = summary.id
    experience.published_at = now()
    db.commit()
    return my_experience(db, experience)


MAX_POSTS_PER_DAY = 20


def _posts_today(db: Session, user: CurrentUser) -> int:
    local_midnight = datetime.combine(
        now().astimezone(_TAIPEI).date(), datetime.min.time(), _TAIPEI
    )
    return (
        db.scalar(
            select(func.count())
            .select_from(Experience)
            .where(
                Experience.author_id == user.id,
                Experience.created_at >= local_midnight.astimezone(UTC),
            )
        )
        or 0
    )


def create_post(db: Session, user: CurrentUser, body: PostIn) -> PublicExperience:
    """Publish a post exactly as written; the author confirms their own words."""
    # Each post is translated and indexed by the AI in the background, so cap them.
    if _posts_today(db, user) >= MAX_POSTS_PER_DAY:
        raise ApiError(429, "daily_limit_reached")
    if body.different_from_id:
        _require_public(db, body.different_from_id)
    if body.action_id:
        action = db.get(Action, body.action_id)
        if action is None or action.archived_at is not None:
            raise not_found("action_not_found")
    if body.author_display != "anonymous":
        account = db.get(User, user.id)
        if account is None or not getattr(account, body.author_display):
            raise ApiError(422, f"{body.author_display}_missing")
    experience = Experience(
        author_id=user.id,
        topic_id=topic_for(body.category),
        identity_type="other",
        original_voice=body.original_voice,
        source_locale=body.source_locale,
        title=body.title,
        category=body.category,
        tags=body.tags,
        author_display=body.author_display,
    )
    db.add(experience)
    db.flush()
    summary = ExperienceSummary(
        experience_id=experience.id,
        version_number=1,
        source_voice=experience.original_voice,
        situation="",
        feeling_or_attempt="",
        reminder="",
        model_name=VERBATIM,
        confirmed_by=user.id,
        confirmed_at=now(),
    )
    db.add(summary)
    db.flush()
    experience.status = "published"
    experience.confirmed_summary_id = summary.id
    experience.published_at = now()
    if body.different_from_id:
        db.add(
            ExperienceLink(
                from_experience_id=body.different_from_id,
                to_experience_id=experience.id,
                kind="different",
            )
        )
    if body.action_id:
        db.add(ActionExperienceLink(action_id=body.action_id, experience_id=experience.id))
    db.commit()
    return get_public(db, user, experience.id, None)


def popular_tags(db: Session, limit: int) -> list[str]:
    """The most used tags on public posts."""
    tag = func.unnest(Experience.tags).label("tag")
    used = select(tag).where(Experience.status == "published").subquery()
    return list(
        db.scalars(
            select(used.c.tag)
            .group_by(used.c.tag)
            .order_by(func.count().desc(), used.c.tag)
            .limit(limit)
        )
    )


def delete_experience(db: Session, user: CurrentUser, experience_id: str) -> None:
    experience = _own(db, user, experience_id)
    delete_experiences(db, [experience.id])
    db.commit()


def delete_experiences(db: Session, ids: list[str]) -> None:
    """Remove experiences and everything hanging off them (also used by account deletion)."""
    if not ids:
        return
    comment_ids = select(ExperienceComment.id).where(ExperienceComment.experience_id.in_(ids))
    db.execute(delete(CommentLike).where(CommentLike.comment_id.in_(comment_ids)))
    # Replies first: they point at the top-level comments.
    db.execute(
        delete(ExperienceComment).where(
            ExperienceComment.experience_id.in_(ids), ExperienceComment.reply_to_id.is_not(None)
        )
    )
    db.execute(delete(ExperienceComment).where(ExperienceComment.experience_id.in_(ids)))
    db.execute(delete(ExperienceReaction).where(ExperienceReaction.experience_id.in_(ids)))
    db.execute(delete(SavedExperience).where(SavedExperience.experience_id.in_(ids)))
    db.execute(
        delete(ExperienceLink).where(
            or_(
                ExperienceLink.from_experience_id.in_(ids),
                ExperienceLink.to_experience_id.in_(ids),
            )
        )
    )
    db.execute(delete(ActionExperienceLink).where(ActionExperienceLink.experience_id.in_(ids)))
    db.execute(delete(ExperienceTranslation).where(ExperienceTranslation.experience_id.in_(ids)))
    # The confirmed summary is referenced by the experience (deferred FK), so drop both together.
    db.execute(delete(ExperienceSummary).where(ExperienceSummary.experience_id.in_(ids)))
    db.execute(delete(Experience).where(Experience.id.in_(ids)))
    remove_content(db, "experience", ids)


def my_experience(db: Session, experience: Experience) -> MyExperience:
    summary = _latest_summary(db, experience.id)
    c = _counts(db, [experience.id])[experience.id]
    people = db.scalar(
        select(func.count(func.distinct(ExperienceReaction.user_id))).where(
            ExperienceReaction.experience_id == experience.id
        )
    )
    return MyExperience(
        id=experience.id,
        status=experience.status,  # type: ignore[arg-type]
        topic_id=experience.topic_id,  # type: ignore[arg-type]
        identity_type=experience.identity_type,  # type: ignore[arg-type]
        source_locale=experience.source_locale,  # type: ignore[arg-type]
        original_voice=experience.original_voice,
        created_at=experience.created_at,
        published_at=experience.published_at,
        latest_summary=_summary_out(summary, experience.original_voice) if summary else None,
        author_display=experience.author_display,  # type: ignore[arg-type]
        title=experience.title,
        category=_category(experience),  # type: ignore[arg-type]
        tags=list(experience.tags or []),
        comment_count=_visible_comments(db, [experience.id]).get(experience.id, 0),
        impact=Impact(
            helpful_count=c.get("helpful", 0),
            experienced_too_count=c.get("experienced_too", 0),
            different_count=c.get("different", 0),
            people_reached=people or 0,
        ),
    )


def my_experiences(db: Session, user: CurrentUser) -> list[MyExperience]:
    rows = db.scalars(
        select(Experience)
        .where(Experience.author_id == user.id)
        .order_by(Experience.created_at.desc())
    )
    return [my_experience(db, e) for e in rows]


def get_mine(db: Session, user: CurrentUser, experience_id: str) -> MyExperience:
    return my_experience(db, _own(db, user, experience_id))


# ---------- reactions (B-14) ----------


def set_reaction(
    db: Session, user: CurrentUser, experience_id: str, kind: str, on: bool
) -> PublicExperience:
    experience = _require_public(db, experience_id)
    existing = db.get(ExperienceReaction, (experience.id, user.id, kind))
    if on and existing is None:
        db.add(ExperienceReaction(experience_id=experience.id, user_id=user.id, kind=kind))
    elif not on and existing is not None:
        db.delete(existing)
    db.commit()
    return get_public(db, user, experience_id, None)


# ---------- saved for later ----------

MAX_SAVED = 200


def set_saved(
    db: Session, user: CurrentUser, experience_id: str, on: bool
) -> PublicExperience | None:
    """Save or unsave. Unsaving works even after the experience was hidden or deleted."""
    existing = db.get(SavedExperience, (user.id, experience_id))
    if on:
        _require_public(db, experience_id)
        if existing is None:
            count = db.scalar(
                select(func.count())
                .select_from(SavedExperience)
                .where(SavedExperience.user_id == user.id)
            )
            if (count or 0) >= MAX_SAVED:
                raise conflict("too_many_saved")
            db.add(SavedExperience(user_id=user.id, experience_id=experience_id))
    elif existing is not None:
        db.delete(existing)
    db.commit()
    if db.execute(_public_query(user).where(Experience.id == experience_id)).first() is None:
        return None
    return get_public(db, user, experience_id, None)


def saved_experiences(
    db: Session, user: CurrentUser, locale: Locale | None
) -> list[PublicExperience]:
    """Newest saves first; hidden, deleted and blocked authors' experiences drop out."""
    rows = db.execute(
        _public_query(user)
        .join(
            SavedExperience,
            (SavedExperience.experience_id == Experience.id) & (SavedExperience.user_id == user.id),
        )
        .order_by(SavedExperience.created_at.desc(), Experience.id)
        .limit(MAX_SAVED)
    ).all()
    return _public_items(db, rows, user, locale)


# ---------- translations (B-11) ----------


def translate(db: Session, ai: ExperienceAI, experience_id: str, target: Locale) -> bool:
    """Store an AI translation of the confirmed summary, if there is none yet."""
    experience = db.get(Experience, experience_id)
    if experience is None or experience.status != "published":
        return False
    if target == experience.source_locale:
        return False
    summary = db.get(ExperienceSummary, experience.confirmed_summary_id)
    assert summary is not None
    key = (experience.id, summary.id, target)
    if db.get(ExperienceTranslation, key) is not None:
        return False
    fields = TranslatedExperience(
        original_voice=experience.original_voice,
        situation=summary.situation,
        feeling_or_attempt=summary.feeling_or_attempt,
        reminder=summary.reminder,
        title=experience.title or "",
    )
    source: Locale = experience.source_locale  # type: ignore[assignment]
    db.commit()  # hand the connection back while the AI works
    # Readers opening the same new post at once would each pay for the same translation;
    # while one request is translating it, the others show the original instead of waiting.
    lock = _translation_lock(key)
    if not lock.acquire(blocking=False):
        return False
    try:
        if db.get(ExperienceTranslation, key) is not None:  # finished just before
            return False
        translated = ai.translate(fields, source, target)
        db.add(
            ExperienceTranslation(
                experience_id=key[0],
                summary_id=key[1],
                locale=target,
                method="ai",
                original_voice=translated.original_voice,
                situation=translated.situation,
                feeling_or_attempt=translated.feeling_or_attempt,
                reminder=translated.reminder,
                title=translated.title or None,
            )
        )
        try:
            db.commit()
        except IntegrityError:  # another server instance stored it first
            db.rollback()
            return False
    finally:
        lock.release()
    return True


_translation_locks: dict[tuple[str, str, str], threading.Lock] = {}
_translation_locks_guard = threading.Lock()


def _translation_lock(key: tuple[str, str, str]) -> threading.Lock:
    with _translation_locks_guard:
        return _translation_locks.setdefault(key, threading.Lock())


def translate_in_background(session_factory, ai: ExperienceAI, experience_id: str) -> None:
    """Runs after the publish response; a failure only means the reader sees the original."""
    with session_factory() as db:
        experience = db.get(Experience, experience_id)
        if experience is None:
            return
        target: Locale = "en" if experience.source_locale == "zh-Hant" else "zh-Hant"
        try:
            translate(db, ai, experience_id, target)
        except AIUnavailable as exc:
            logger.warning("Translation of %s failed: %s", experience_id, exc)
