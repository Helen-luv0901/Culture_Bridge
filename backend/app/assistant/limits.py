"""Assistant access control and cost limits (work-assignment A-18).

- Per caller: a requests-per-minute window and a daily message cap (Asia/Taipei day).
- Global: a daily budget of Gemini calls; past it the assistant answers with the fallback.

The daily counts go through a DailyCounter: the database in production (app.core.usage), so
they hold across restarts and instances; memory in unit tests. The per-minute window stays in
memory (a burst only needs to be slowed down, and it resets within a minute anyway).
"""

import threading
import time
from collections import defaultdict, deque
from collections.abc import Callable
from datetime import UTC, date, datetime, timedelta, timezone

from app.assistant.llm import LLM, LLMError, ModelTurn, ToolSpec, Turn
from app.core.usage import DailyCounter, MemoryCounter

_TAIPEI = timezone(timedelta(hours=8))


def _taipei_today() -> date:
    return datetime.now(UTC).astimezone(_TAIPEI).date()


class RateLimited(Exception):
    def __init__(self, code: str, retry_after_seconds: int) -> None:
        super().__init__(code)
        self.code = code
        self.retry_after_seconds = retry_after_seconds


_MAX_TRACKED = 5000  # callers kept in the per-minute window before idle ones are dropped


class UsageLimiter:
    def __init__(
        self,
        per_minute: int,
        per_day: int,
        monotonic: Callable[[], float] = time.monotonic,
        today: Callable[[], date] = _taipei_today,
        counter: DailyCounter | None = None,
    ) -> None:
        self._per_minute = per_minute
        self._per_day = per_day
        self._monotonic = monotonic
        self._daily = counter or MemoryCounter(today)
        self._recent: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def check(self, key: str) -> None:
        """Count one message for `key`, or raise RateLimited without counting it."""
        with self._lock:
            now = self._monotonic()
            if len(self._recent) > _MAX_TRACKED:
                self._forget_idle(now)
            recent = self._recent[key]
            while recent and now - recent[0] >= 60:
                recent.popleft()
            if len(recent) >= self._per_minute:
                raise RateLimited("rate_limited", max(1, int(60 - (now - recent[0])) + 1))
            recent.append(now)
        # Outside the lock: the daily count is a database round trip.
        if not self._daily.take(f"assistant:{key}", self._per_day):
            with self._lock:
                if now in self._recent[key]:
                    self._recent[key].remove(now)
            raise RateLimited("daily_limit_reached", _seconds_until_taipei_midnight())

    def _forget_idle(self, now: float) -> None:
        idle = [k for k, times in self._recent.items() if not times or now - times[-1] >= 60]
        for k in idle:
            del self._recent[k]


class DailyBudget:
    """Counts Gemini calls across all users and stops at the daily cap."""

    def __init__(
        self,
        max_calls: int,
        today: Callable[[], date] = _taipei_today,
        counter: DailyCounter | None = None,
    ) -> None:
        self._max_calls = max_calls
        self._counter = counter or MemoryCounter(today)

    def take(self) -> bool:
        return self._counter.take("gemini:assistant", self._max_calls)


class BudgetedLLM:
    def __init__(self, llm: LLM, budget: DailyBudget) -> None:
        self._llm = llm
        self._budget = budget

    def generate(self, system: str, history: list[Turn], tools: list[ToolSpec]) -> ModelTurn:
        if not self._budget.take():
            raise LLMError("daily Gemini call budget reached")
        return self._llm.generate(system, history, tools)


def _seconds_until_taipei_midnight() -> int:
    now = datetime.now(UTC).astimezone(_TAIPEI)
    midnight = datetime.combine(now.date() + timedelta(days=1), datetime.min.time(), _TAIPEI)
    return int((midnight - now).total_seconds()) + 1
