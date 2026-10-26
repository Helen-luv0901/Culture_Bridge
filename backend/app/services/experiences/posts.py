"""Authoring: drafts and AI summaries (older flow), posts published as written, deletion, and
the author's own view of their experiences."""

from datetime import UTC, datetime, timedelta, timezone

from sqlalchemy import delete, func, or_, select
from sqlalchemy.orm import Session

from app.ai.experience_ai import AIUnavailable, ExperienceAI
from app.core.auth import CurrentUser
from app.core.errors import ApiError, conflict, not_found
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
from app.services.common import now
from app.services.experiences.queries import (
    _category,
    _counts,
    _require_public,
    _visible_comments,
    get_public,
)
from app.services.experiences.schemas import (
    VERBATIM,
    DraftIn,
    DraftUpdate,
    Impact,
    MyExperience,
    PostIn,
    PublicExperience,
    PublishIn,
    SummaryOut,
    topic_for,
)

_TAIPEI = timezone(timedelta(hours=8))

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
