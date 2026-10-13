"""Assistant access control and cost limits (work-assignment A-18).

- Per caller: a requests-per-minute window and a daily message cap (Asia/Taipei day).
- Global: a daily budget of Gemini calls; past it the assistant answers with the fallback.

Counters live in process memory, so with several Cloud Run instances each enforces its own share.
"""

import threading
import time
from collections import defaultdict, deque
from collections.abc import Callable
from datetime import UTC, date, datetime, timedelta, timezone

from app.assistant.llm import LLM, LLMError, ModelTurn, ToolSpec, Turn

_TAIPEI = timezone(timedelta(hours=8))


def _taipei_today() -> date:
    return datetime.now(UTC).astimezone(_TAIPEI).date()


class RateLimited(Exception):
    def __init__(self, code: str, retry_after_seconds: int) -> None:
        super().__init__(code)
        self.code = code
        self.retry_after_seconds = retry_after_seconds


class UsageLimiter:
    def __init__(
        self,
        per_minute: int,
        per_day: int,
        monotonic: Callable[[], float] = time.monotonic,
        today: Callable[[], date] = _taipei_today,
    ) -> None:
        self._per_minute = per_minute
        self._per_day = per_day
        self._monotonic = monotonic
        self._today = today
        self._recent: dict[str, deque[float]] = defaultdict(deque)
        self._daily: dict[str, int] = defaultdict(int)
        self._day = today()
        self._lock = threading.Lock()

    def check(self, key: str) -> None:
        """Count one message for `key`, or raise RateLimited without counting it."""
        with self._lock:
            self._roll_day()
            now = self._monotonic()
            recent = self._recent[key]
            while recent and now - recent[0] >= 60:
                recent.popleft()
            if len(recent) >= self._per_minute:
                raise RateLimited("rate_limited", max(1, int(60 - (now - recent[0])) + 1))
            if self._daily[key] >= self._per_day:
                raise RateLimited("daily_limit_reached", _seconds_until_taipei_midnight())
            recent.append(now)
            self._daily[key] += 1

    def _roll_day(self) -> None:
        today = self._today()
        if today != self._day:
            self._day = today
            self._daily.clear()
            self._recent.clear()


class DailyBudget:
    """Counts Gemini calls across all users and stops at the daily cap."""

    def __init__(self, max_calls: int, today: Callable[[], date] = _taipei_today) -> None:
        self._max_calls = max_calls
        self._today = today
        self._day = today()
        self._used = 0
        self._lock = threading.Lock()

    def take(self) -> bool:
        with self._lock:
            if self._today() != self._day:
                self._day = self._today()
                self._used = 0
            if self._used >= self._max_calls:
                return False
            self._used += 1
            return True


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
