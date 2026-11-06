"""Reader reactions (B-14) and experiences saved for later.

Reacting or saving twice (a double tap, a retried request) is not an error: the second request
answers 200 with the current state, never 409.
"""

from sqlalchemy import delete, func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.core.auth import CurrentUser
from app.core.errors import conflict
from app.models import Experience, ExperienceReaction, SavedExperience
from app.services.experiences.queries import (
    _public_items,
    _public_query,
    _require_public,
    get_public,
)
from app.services.experiences.schemas import Locale, PublicExperience

# ---------- reactions (B-14) ----------


def set_reaction(
    db: Session, user: CurrentUser, experience_id: str, kind: str, on: bool
) -> PublicExperience:
    experience = _require_public(db, experience_id)
    if on:
        db.execute(
            insert(ExperienceReaction)
            .values(experience_id=experience.id, user_id=user.id, kind=kind)
            .on_conflict_do_nothing()
        )
    else:
        db.execute(
            delete(ExperienceReaction).where(
                ExperienceReaction.experience_id == experience.id,
                ExperienceReaction.user_id == user.id,
                ExperienceReaction.kind == kind,
            )
        )
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
            db.execute(
                insert(SavedExperience)
                .values(user_id=user.id, experience_id=experience_id)
                .on_conflict_do_nothing()
            )
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
