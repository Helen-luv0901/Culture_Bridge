"""AI translations of published experiences (B-11), stored once and made in the background."""

import logging
import threading
import time
from collections.abc import Callable

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.ai.experience_ai import AIUnavailable, ExperienceAI, TranslatedExperience
from app.core.errors import ApiError
from app.models import Experience, ExperienceSummary, ExperienceTranslation
from app.services.common import DailyAllowance
from app.services.experiences.schemas import Locale

# Logged under the package name, as before the module was split.
logger = logging.getLogger(__package__)

# ---------- translations (B-11) ----------


def translate(
    db: Session,
    ai: ExperienceAI,
    experience_id: str,
    target: Locale,
    before_ai: Callable[[], None] | None = None,
) -> bool:
    """Store an AI translation of the confirmed summary, if there is none yet.

    before_ai runs only when the AI is about to be asked, and may raise to stop it."""
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
        db.commit()  # that check took a connection again; not held for the AI call
        if before_ai is not None:
            before_ai()
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


# ---------- on request (POST /experiences/{id}/translations, open to guests) ----------

TRANSLATIONS_PER_DAY = 60  # AI translations per person (or IP address for guests) a day
RETRY_AFTER_FAILURE_SECONDS = 600
_requested = DailyAllowance("translations")
# (experience id, locale) -> when a requested translation last failed, in this process.
_failed_at: dict[tuple[str, str], float] = {}
_failed_guard = threading.Lock()


def _clock() -> float:
    return time.monotonic()


class _CoolingDown(AIUnavailable):
    pass


def translate_on_request(
    db: Session, ai: ExperienceAI, experience_id: str, target: Locale, caller: str
) -> bool:
    """translate() for a reader who asked: counted against the caller's daily allowance (only
    when the AI is really asked), and not retried for 10 minutes after it failed, so nobody can
    make the server call Gemini again and again for one post. Raises AIUnavailable (503) or
    ApiError 429 daily_limit_reached."""
    key = (experience_id, target)

    def before_ai() -> None:
        with _failed_guard:
            failed = _failed_at.get(key)
        if failed is not None and _clock() - failed < RETRY_AFTER_FAILURE_SECONDS:
            raise _CoolingDown("translation failed recently")
        if not _requested.take(caller, TRANSLATIONS_PER_DAY):
            raise ApiError(429, "daily_limit_reached")

    try:
        return translate(db, ai, experience_id, target, before_ai)
    except _CoolingDown:
        raise
    except AIUnavailable:
        with _failed_guard:
            now = _clock()
            for old in [k for k, t in _failed_at.items() if now - t >= RETRY_AFTER_FAILURE_SECONDS]:
                del _failed_at[old]
            _failed_at[key] = now
        raise


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
