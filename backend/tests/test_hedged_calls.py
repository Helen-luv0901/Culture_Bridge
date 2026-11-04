"""The assistant asks a second model when the first is slow, and takes whichever answers first.

Real threads and short waits: the slow model blocks on an event the test releases at the end.
"""

import threading
import time

import pytest
from google.genai import errors as genai_errors

from app.ai import calls
from app.ai.calls import GeminiBudgetReached, call_gemini_hedged

MODELS = ("main-model", "backup-model", "last-model")
HEDGE = 0.5  # seconds before the next model is asked too; roomy for slow CI runners


def _api_error(code: int) -> genai_errors.APIError:
    return genai_errors.APIError(code, {"error": {"code": code, "message": "x"}})


@pytest.fixture(autouse=True)
def _fresh(monkeypatch):
    monkeypatch.setattr(calls, "spend_gemini_call", lambda: True)
    monkeypatch.setattr(calls, "_resting_until", {})
    monkeypatch.setattr(calls, "_pause", lambda retry: 0.01)


@pytest.fixture
def release():
    gate = threading.Event()
    yield gate
    gate.set()  # let the abandoned slow calls finish


def test_a_quick_first_model_is_the_only_one_asked():
    asked: list[str] = []

    def answer(model: str) -> str:
        asked.append(model)
        return f"from {model}"

    assert call_gemini_hedged(answer, MODELS, hedge_after=HEDGE) == (
        "from main-model",
        "main-model",
    )
    time.sleep(HEDGE * 3)
    assert asked == ["main-model"]


def test_a_slow_first_model_is_overtaken_by_the_backup_and_rests(release):
    asked: list[str] = []

    def answer(model: str) -> str:
        asked.append(model)
        if model == "main-model":
            release.wait(5)
        return f"from {model}"

    started = time.monotonic()
    result = call_gemini_hedged(answer, MODELS, hedge_after=HEDGE)
    assert result == ("from backup-model", "backup-model")
    assert time.monotonic() - started < 3  # not held up by the slow model
    assert asked == ["main-model", "backup-model"]
    # The slow model rests: the next message goes straight to the backup.
    asked.clear()
    assert call_gemini_hedged(answer, MODELS, hedge_after=HEDGE)[1] == "backup-model"
    assert asked == ["backup-model"]
    assert calls._resting_until["main-model"] - time.monotonic() > calls.REST_SECONDS


@pytest.mark.parametrize("code", [429, 503, 504])
def test_a_failing_model_hands_over_without_waiting(code):
    asked: list[str] = []

    def answer(model: str) -> str:
        asked.append(model)
        if model == "main-model":
            raise _api_error(code)
        return f"from {model}"

    started = time.monotonic()
    assert call_gemini_hedged(answer, MODELS, hedge_after=5) == (
        "from backup-model",
        "backup-model",
    )
    assert time.monotonic() - started < 3  # the 5 s hedge wait was not needed
    assert asked == ["main-model", "backup-model"]


def test_an_invalid_request_is_not_sent_to_other_models():
    asked: list[str] = []

    def invalid(model: str) -> str:
        asked.append(model)
        raise _api_error(400)

    with pytest.raises(genai_errors.APIError):
        call_gemini_hedged(invalid, MODELS, hedge_after=HEDGE)
    assert asked == ["main-model"]


def test_when_every_model_fails_the_last_error_comes_back():
    def busy(model: str) -> str:
        raise _api_error(503)

    with pytest.raises(genai_errors.APIError):
        call_gemini_hedged(busy, MODELS, hedge_after=HEDGE)


def test_the_daily_budget_still_applies(monkeypatch):
    monkeypatch.setattr(calls, "spend_gemini_call", lambda: False)
    with pytest.raises(GeminiBudgetReached):
        call_gemini_hedged(lambda model: "x", MODELS, hedge_after=HEDGE)


def test_hedging_starts_early_enough_for_three_to_five_seconds():
    # Normal answers take 1-3 s; the backup answered in about 3 s on 2026-11-05. Asking it
    # after 2 s keeps even a slow first model's message near 5 s.
    assert calls.HEDGE_AFTER_SECONDS <= 2
    assert calls.SLOW_REST_SECONDS >= 600


def test_a_backup_asked_late_is_not_rested_when_the_first_model_wins(release):
    # The first model answers just after the hedge: the backup lost nothing, so it stays
    # available for the next slow spell.
    def answer(model: str) -> str:
        if model == "main-model":
            time.sleep(0.3)
            return "from main-model"
        release.wait(5)
        return f"from {model}"

    assert call_gemini_hedged(answer, MODELS, hedge_after=0.2)[1] == "main-model"
    assert calls._resting_until == {}


def test_a_busy_model_is_asked_again(release):
    # 503s pass on a second try (2026-10-27); every model busy once still gets an answer.
    tries: dict[str, int] = {}

    def busy_once(model: str) -> str:
        tries[model] = tries.get(model, 0) + 1
        if tries[model] == 1:
            raise _api_error(503)
        return f"from {model}"

    assert call_gemini_hedged(busy_once, MODELS, hedge_after=HEDGE)[0].startswith("from ")
    assert calls._resting_until == {}  # busy is not slow


def test_a_refused_hedge_keeps_waiting_for_the_first_model(monkeypatch):
    spent = iter([True, False, False])
    monkeypatch.setattr(calls, "spend_gemini_call", lambda: next(spent))

    def answer(model: str) -> str:
        time.sleep(0.4)
        return f"from {model}"

    assert call_gemini_hedged(answer, MODELS, hedge_after=0.1) == (
        "from main-model",
        "main-model",
    )


def test_running_out_of_budget_rests_the_silent_model(release):
    def silent(model: str) -> str:
        release.wait(5)
        return "late"

    with pytest.raises(TimeoutError):
        call_gemini_hedged(silent, ("only-model",), hedge_after=HEDGE, budget=0.3)
    assert calls._resting_until["only-model"] - time.monotonic() > calls.REST_SECONDS
