"""How every Gemini request is paid for, retried, and moved to a backup model.

Each attempt counts against the daily budget shared by all AI features (app.core.usage), so a
loop or an abuser can't run up the bill. A refused or invalid request fails at once.

The free tier is often busy: a model answers 503 ("high demand") within a second or so, and
answers again a few seconds later (2026-10-27, gemini-3.1-flash-lite: 6 of 10 requests got
through within four tries). So a busy model is asked again twice, a second or two apart, before
the request moves on. Every model also has its own per-minute and per-day quota: one that
answers 429 is rested for a minute and the request goes straight to the next model in the list
(GEMINI_MODEL, then GEMINI_FALLBACK_MODELS). Timeouts and unreadable answers are retried
`attempts` times. One request never keeps the reader waiting past BUDGET_SECONDS.
"""

import logging
import random
import threading
import time
from collections.abc import Callable, Sequence

from google.genai import errors as genai_errors

from app.core.usage import spend_gemini_call

logger = logging.getLogger(__name__)
_BUSY_STATUS = {500, 502, 503, 504}
_QUOTA_STATUS = 429
BUSY_RETRIES = 2  # per model, after a 5xx; these answers come back fast
BUDGET_SECONDS = 45.0  # one request: every model and retry together
REST_SECONDS = 60.0  # long enough for a per-minute quota; a used-up day is tried again then

_resting_until: dict[str, float] = {}
_resting_lock = threading.Lock()


class GeminiBudgetReached(Exception):
    pass


def _out_of_quota(exc: Exception) -> bool:
    return isinstance(exc, genai_errors.APIError) and exc.code == _QUOTA_STATUS


def _busy(exc: Exception) -> bool:
    return isinstance(exc, genai_errors.APIError) and exc.code in _BUSY_STATUS


def _worth_retrying(exc: Exception) -> bool:
    # Timeouts, dropped connections, unreadable JSON; any other API error is the request's fault.
    return not isinstance(exc, genai_errors.APIError)


def _pause(retry: int) -> float:
    return min(8.0, 1.5 * 2 ** (retry - 1)) * random.uniform(0.5, 1.0)


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
    budget: float = BUDGET_SECONDS,
) -> tuple[T, str]:
    """Run `request(model)` on the first model that answers. Returns the result and the model
    that gave it; raises the last error, or GeminiBudgetReached."""
    start = now()
    last: Exception | None = None
    for model in _awake(models, now):
        failures = busy = 0
        while True:
            if last is not None and now() - start > budget:
                raise last
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
                    failures += 1
                    retry = failures < attempts
                elif _busy(exc):
                    busy += 1
                    retry = busy <= BUSY_RETRIES
                elif _worth_retrying(exc):
                    failures += 1
                    retry = failures < attempts
                else:
                    raise
                pause = _pause(failures + busy)
                if not retry or now() - start + pause > budget:
                    logger.warning("Gemini %s failed (%s); trying the next model", model, exc)
                    break
                sleep(pause)
                continue
            if model != models[0]:
                logger.info("Gemini %s answered instead of %s", model, models[0])
            return result, model
    assert last is not None
    raise last
