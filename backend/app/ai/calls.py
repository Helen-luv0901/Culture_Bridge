"""How every Gemini request is paid for and retried.

Each attempt counts against the daily budget shared by all AI features (app.core.usage), so a
loop or an abuser can't run up the bill. Only failures that may pass on a second try are
retried (rate limits, server errors, timeouts, an answer that couldn't be read), after a short
pause that grows; a refused or invalid request fails at once.
"""

import random
import time
from collections.abc import Callable

from google.genai import errors as genai_errors

from app.core.usage import spend_gemini_call

_RETRY_STATUS = {429, 500, 502, 503, 504}


class GeminiBudgetReached(Exception):
    pass


def _worth_retrying(exc: Exception) -> bool:
    if isinstance(exc, genai_errors.APIError):
        return exc.code in _RETRY_STATUS
    return True  # timeouts, dropped connections, unreadable JSON


def _pause(attempt: int) -> float:
    return min(8.0, 1.5 * 2 ** (attempt - 1)) * random.uniform(0.5, 1.0)


def call_gemini[T](
    request: Callable[[], T], attempts: int = 1, sleep: Callable[[float], None] = time.sleep
) -> T:
    """Run `request` up to `attempts` times; raises its last error, or GeminiBudgetReached."""
    last: Exception | None = None
    for attempt in range(attempts):
        if attempt:
            sleep(_pause(attempt))
        if not spend_gemini_call():
            raise GeminiBudgetReached("daily Gemini budget reached")
        try:
            return request()
        except Exception as exc:  # the SDK raises several error types
            last = exc
            if not _worth_retrying(exc):
                break
    assert last is not None
    raise last
