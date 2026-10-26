"""Daily counters for caps (Gemini spend, assistant messages, tag suggestions, uploads, blocks).

They live in the database (usage_counters, migration 0013), so a cap holds across restarts and
across Cloud Run instances; counting in process memory reset on every cold start and doubled
with two instances. Each count is its own short transaction, outside the request's session.
A day is a Taiwan calendar day.
"""

import logging
import threading
from collections.abc import Callable
from datetime import UTC, date, datetime, timedelta, timezone
from functools import lru_cache
from typing import Protocol

from sqlalchemy import Engine, create_engine, delete
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.exc import SQLAlchemyError

from app.core.config import get_settings
from app.models import UsageCounter

logger = logging.getLogger(__name__)
_TAIPEI = timezone(timedelta(hours=8))
KEEP_DAYS = 30


def taipei_today() -> date:
    return datetime.now(UTC).astimezone(_TAIPEI).date()


@lru_cache
def _engine() -> Engine:
    """Counting has its own small pool: a request that already holds a connection from the
    main pool must never wait on that same pool to count (that can stall every request)."""
    return create_engine(
        get_settings().database_url,
        pool_pre_ping=True,
        pool_size=1,
        max_overflow=1,
        pool_timeout=5,
        connect_args={"connect_timeout": 10},
    )


class DailyCounter(Protocol):
    def take(self, key: str, limit: int) -> bool:
        """Count one use of `key` today and return True, or False (counting nothing) at `limit`."""
        ...


class DatabaseCounter:
    def __init__(self, today: Callable[[], date] = taipei_today) -> None:
        self._today = today

    def take(self, key: str, limit: int) -> bool:
        if limit <= 0:
            return False
        day = self._today()
        stmt = (
            insert(UsageCounter)
            .values(day=day, key=key, count=1)
            .on_conflict_do_update(
                index_elements=[UsageCounter.day, UsageCounter.key],
                set_={"count": UsageCounter.count + 1},
                where=UsageCounter.count < limit,
            )
            .returning(UsageCounter.count)
        )
        try:
            with _engine().begin() as conn:
                count = conn.execute(stmt).scalar()
                if count == 1:  # first use of this key today: drop old days while we're here
                    conn.execute(
                        delete(UsageCounter).where(
                            UsageCounter.day < day - timedelta(days=KEEP_DAYS)
                        )
                    )
        except SQLAlchemyError:
            # No count possible: refuse, like a reached cap; every caller has a fallback.
            logger.exception("Usage counter %s unavailable", key)
            return False
        return count is not None


class MemoryCounter:
    """Counts in this process only: unit tests without a database, and cheap pre-checks."""

    def __init__(self, today: Callable[[], date] = taipei_today) -> None:
        self._today = today
        self._lock = threading.Lock()
        self._day: date | None = None
        self._used: dict[str, int] = {}

    def take(self, key: str, limit: int) -> bool:
        with self._lock:
            today = self._today()
            if self._day != today:
                self._day, self._used = today, {}
            used = self._used.get(key, 0)
            if used >= limit:
                return False
            self._used[key] = used + 1
            return True


def spend_gemini_call() -> bool:
    """Count one Gemini request against the daily cap shared by every feature (assistant,
    summaries, translations, tags, embeddings). False: today's budget is used up."""
    allowed = DatabaseCounter().take("gemini", get_settings().gemini_daily_calls)
    if not allowed:
        logger.warning("Daily Gemini budget reached; AI features fall back until midnight")
    return allowed
