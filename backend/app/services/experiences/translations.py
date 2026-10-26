"""AI translations of published experiences (B-11), stored once and made in the background."""

import logging
import threading

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.ai.experience_ai import AIUnavailable, ExperienceAI, TranslatedExperience
from app.models import Experience, ExperienceSummary, ExperienceTranslation
from app.services.experiences.schemas import Locale

# Logged under the package name, as before the module was split.
logger = logging.getLogger(__package__)

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
