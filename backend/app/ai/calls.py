"""How every Gemini request is paid for, retried, and moved to a backup model.

Each attempt counts against the daily budget shared by all AI features (app.core.usage), so a
loop or an abuser can't run up the bill. A refused or invalid request fails at once.

The free tier is often busy: a model answers 503 ("high demand") within a second or so, and
answers again a few seconds later (2026-10-27, gemini-3.1-flash-lite: 6 of 10 requests got
through within four tries). So a busy model is asked again twice, a second or two apart, before
the request moves on. Every model also has its own per-minute and per-day quota: one that
answers 429 is rested for a minute and the request goes straight to the next model in the list
(GEMINI_MODEL, then GEMINI_FALLBACK_MODELS).

Free-tier requests are the first Google slows down ("sheddable" on aistudio.google.com/status):
on 2026-11-04 gemini-3.5-flash-lite took 20-30 s per answer, then 504, instead of 1-3 s. A model
that runs out of time (504 or our own timeout) is not asked again: it rests for a minute like a
429 and the next model is asked at once. Only a lone model (embeddings) retries a timeout, and
unreadable answers are retried, `attempts` times. No new attempt starts after `budget` seconds,
so one request takes at most the budget plus one request's timeout.
"""

import logging
import random
import threading
import time
from collections.abc import Callable, Sequence
from concurrent.futures import FIRST_COMPLETED, Future, ThreadPoolExecutor, wait

import httpx
from google.genai import errors as genai_errors

from app.core.usage import spend_gemini_call

logger = logging.getLogger(__name__)
_BUSY_STATUS = {500, 502, 503}
_QUOTA_STATUS = 429
_DEADLINE_STATUS = 504
BUSY_RETRIES = 2  # per model, after a 5xx; these answers come back fast
BUDGET_SECONDS = 45.0  # one request: every model and retry together
REST_SECONDS = 60.0  # long enough for a per-minute quota; a used-up day is tried again then
# A slow model stays slow for a while (all of 2026-11-04): skip it for ten minutes, then one
# request finds out whether it has recovered.
SLOW_REST_SECONDS = 600.0
# A person is waiting (the assistant): normal answers take 1-3 s, so a model silent after 2 s
# gets company from the next one, and the first answer wins (call_gemini_hedged).
HEDGE_AFTER_SECONDS = 2.0

_resting_until: dict[str, float] = {}
_resting_lock = threading.Lock()


class GeminiBudgetReached(Exception):
    pass


def _out_of_quota(exc: Exception) -> bool:
    return isinstance(exc, genai_errors.APIError) and exc.code == _QUOTA_STATUS


def _busy(exc: Exception) -> bool:
    return isinstance(exc, genai_errors.APIError) and exc.code in _BUSY_STATUS


def _too_slow(exc: Exception) -> bool:
    """No answer in time: Google's deadline (504) or our own timeout."""
    if isinstance(exc, genai_errors.APIError):
        return exc.code == _DEADLINE_STATUS
    return isinstance(exc, httpx.TimeoutException)


def _worth_retrying(exc: Exception) -> bool:
    # Timeouts, dropped connections, unreadable JSON; any other API error is the request's fault.
    return not isinstance(exc, genai_errors.APIError)


def _pause(retry: int) -> float:
    return min(8.0, 1.5 * 2 ** (retry - 1)) * random.uniform(0.5, 1.0)


def _rest(model: str, now: Callable[[], float], seconds: float = REST_SECONDS) -> None:
    with _resting_lock:
        _resting_until[model] = max(_resting_until.get(model, 0.0), now() + seconds)


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
                if _out_of_quota(exc) or _too_slow(exc):
                    _rest(model, now, SLOW_REST_SECONDS if _too_slow(exc) else REST_SECONDS)
                    if model != models[-1]:
                        logger.warning(
                            "Gemini %s is %s; trying the next model",
                            model,
                            "over its quota" if _out_of_quota(exc) else "too slow",
                        )
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
                    logger.warning("Gemini %s failed: %s", model, exc)
                    break
                sleep(pause)
                continue
            if model != models[0]:
                logger.info("Gemini %s answered instead of %s", model, models[0])
            return result, model
    assert last is not None
    raise last


def _hands_over(exc: Exception) -> bool:
    """Whether another model may answer where this one failed (not an invalid request)."""
    return _out_of_quota(exc) or _too_slow(exc) or _busy(exc) or _worth_retrying(exc)


def call_gemini_hedged[T](
    request: Callable[[str], T],
    models: Sequence[str],
    hedge_after: float = HEDGE_AFTER_SECONDS,
    budget: float = BUDGET_SECONDS,
) -> tuple[T, str]:
    """For a person waiting: ask the first awake model; when it has not answered after
    `hedge_after` seconds, or fails, ask the next one too, and take the first answer.

    A model overtaken by one asked after it, or silent until the budget runs out, rests for
    SLOW_REST_SECONDS so the next messages go straight to the quicker model; a model asked
    later that loses only by being late is not rested. A busy (5xx) model is asked again
    after a short pause, BUSY_RETRIES times. When the daily budget refuses an extra model,
    the calls already running are still awaited. Calls left running finish in the background
    and are ignored. Raises the last error, GeminiBudgetReached, or TimeoutError."""
    now = time.monotonic
    candidates = _awake(models, now)
    start = now()
    pool = ThreadPoolExecutor(max_workers=len(candidates) * (1 + BUSY_RETRIES))
    finished = threading.Event()  # tells retries still pausing not to call any more
    pending: dict[Future[T], str] = {}
    position: dict[str, int] = {}  # the order models were first asked in
    busy: dict[str, int] = {}
    last: Exception | None = None
    refused = False

    def submit(model: str, pause: float = 0.0) -> bool:
        if not spend_gemini_call():
            return False

        def run() -> T:
            if pause:
                time.sleep(pause)
                if finished.is_set():
                    raise TimeoutError("answered by another model")
            return request(model)

        pending[pool.submit(run)] = model
        return True

    def ask_next() -> None:
        nonlocal refused
        if refused or len(position) >= len(candidates):
            return
        model = candidates[len(position)]
        if submit(model):
            position[model] = len(position)
        else:
            refused = True

    def more_to_ask() -> bool:
        return not refused and len(position) < len(candidates)

    try:
        ask_next()
        while pending:
            remaining = budget - (now() - start)
            if remaining <= 0:
                for silent in set(pending.values()):
                    _rest(silent, now, SLOW_REST_SECONDS)
                break
            more = more_to_ask()
            done, _ = wait(
                pending,
                timeout=min(hedge_after, remaining) if more else remaining,
                return_when=FIRST_COMPLETED,
            )
            if not done:
                if more:
                    logger.warning(
                        "Gemini %s has not answered in %.0f s; asking %s too",
                        ", ".join(sorted(set(pending.values()))),
                        now() - start,
                        candidates[len(position)],
                    )
                    ask_next()
                continue
            results = [(pending.pop(future), future) for future in done]
            winner = next(((m, f) for m, f in results if f.exception() is None), None)
            for model, future in results:
                exc = future.exception()
                if exc is None:
                    continue
                last = exc
                if not _hands_over(exc):
                    if winner is None:
                        raise exc  # an invalid request fails the same on any model
                    continue
                logger.warning("Gemini %s failed: %s", model, exc)
                if _out_of_quota(exc) or _too_slow(exc):
                    _rest(model, now, SLOW_REST_SECONDS if _too_slow(exc) else REST_SECONDS)
                elif winner is None and _busy(exc) and busy.get(model, 0) < BUSY_RETRIES:
                    busy[model] = busy.get(model, 0) + 1
                    pause = _pause(busy[model])
                    if now() - start + pause < budget and not submit(model, pause):
                        refused = True
            if winner is not None:
                model, future = winner
                for slower in set(pending.values()):
                    if position.get(slower, len(candidates)) < position[model]:
                        _rest(slower, now, SLOW_REST_SECONDS)
                        logger.warning("Gemini %s is too slow; resting it", slower)
                if model != models[0]:
                    logger.info("Gemini %s answered instead of %s", model, models[0])
                return future.result(), model
            ask_next()  # something failed: the next model need not wait for the hedge
    finally:
        finished.set()
        pool.shutdown(wait=False, cancel_futures=True)
    if last is not None:
        raise last
    if refused and not position:
        raise GeminiBudgetReached("daily Gemini budget reached")
    raise TimeoutError("no Gemini answer within the budget")
