"""How every Gemini request is paid for, retried, and moved to a backup model.

Each attempt counts against the daily budget shared by all AI features (app.core.usage), so a
loop or an abuser can't run up the bill. Only failures that may pass on a second try are
retried (server errors, timeouts, an answer that couldn't be read), after a short pause that
grows; a refused or invalid request fails at once.

On the free tier every model has its own per-minute and per-day quota, so a model that answers
429 (quota used up) is rested for a minute and the request goes to the next model in the list
(GEMINI_MODEL, then GEMINI_FALLBACK_MODELS).
"""

import logging
import random
import threading
import time
from collections.abc import Callable, Sequence

from google.genai import errors as genai_errors

from app.core.usage import spend_gemini_call

logger = logging.getLogger(__name__)
_RETRY_STATUS = {500, 502, 503, 504}
_QUOTA_STATUS = 429
REST_SECONDS = 60.0  # long enough for a per-minute quota; a used-up day is tried again then

_resting_until: dict[str, float] = {}
_resting_lock = threading.Lock()


class GeminiBudgetReached(Exception):
    pass


def _out_of_quota(exc: Exception) -> bool:
    return isinstance(exc, genai_errors.APIError) and exc.code == _QUOTA_STATUS


def _worth_retrying(exc: Exception) -> bool:
    if isinstance(exc, genai_errors.APIError):
        return exc.code in _RETRY_STATUS
    return True  # timeouts, dropped connections, unreadable JSON


def _pause(attempt: int) -> float:
    return min(8.0, 1.5 * 2 ** (attempt - 1)) * random.uniform(0.5, 1.0)


def _rest(model: str, now: Callable[[], float]) -> None:
    with _resting_lock:
        _resting_until[model] = now() + REST_SECONDS


def _awake(models: Sequence[str], now: Callable[[], float]) -> list[str]:
    """The models not resting; all of them if every one is (one may have recovered)."""
    with _resting_lock:
        awake = [m for m in models if _resting_until.get(m, 0.0) <= now()]
    return awake or list(models)


def call_gemini[T](
    request: Callable[[str], T],
    models: Sequence[str],
    attempts: int = 1,
    sleep: Callable[[float], None] = time.sleep,
    now: Callable[[], float] = time.monotonic,
) -> tuple[T, str]:
    """Run `request(model)` on the first model that answers, trying each up to `attempts`
    times. Returns the result and the model that gave it; raises the last error, or
    GeminiBudgetReached."""
    last: Exception | None = None
    for model in _awake(models, now):
        for attempt in range(attempts):
            if attempt:
                sleep(_pause(attempt))
            if not spend_gemini_call():
                raise GeminiBudgetReached("daily Gemini budget reached")
            try:
                result = request(model)
            except Exception as exc:  # the SDK raises several error types
                last = exc
                if _out_of_quota(exc):
                    _rest(model, now)
                    if model != models[-1]:
                        logger.warning("Gemini %s is over its quota; trying the next model", model)
                        break
                    # No model left to try (embeddings have only one): wait and try again.
                    logger.warning("Gemini %s is over its quota", model)
                    continue
                if not _worth_retrying(exc):
                    raise
                continue
            if model != models[0]:
                logger.info("Gemini %s answered instead of %s", model, models[0])
            return result, model
    assert last is not None
    raise last
