"""Public reads: the feed, search and one post, and the payloads readers see.

Readers never see a post they blocked the author of, and comment counts leave out comments they
blocked for the same reason.
"""

from sqlalchemy import Select, exists, func, or_, select
from sqlalchemy.orm import Session

from app.core.auth import CurrentUser
from app.core.errors import not_found
from app.core.text_search import relevant, search_units
from app.models import (
    ActionExperienceLink,
    Experience,
    ExperienceComment,
    ExperienceLink,
    ExperienceReaction,
    ExperienceSummary,
    ExperienceTranslation,
    SavedExperience,
    User,
)
from app.services import avatars
from app.services.blocking import hides_comment_on_its_post, hides_experience
from app.services.experiences.schemas import (
    ExperienceDetail,
    ExperiencePage,
    Locale,
    PublicExperience,
    Sort,
    TranslationOut,
    topic_for,
)

# ---------- helpers ----------


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
