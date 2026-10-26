"""Daily caps kept in the database, Gemini retries and budget, and the indexing backfill."""

from datetime import date

import pytest
from fastapi.testclient import TestClient
from google.genai import errors as genai_errors
from sqlalchemy import func, select

from app.ai import calls
from app.ai.calls import GeminiBudgetReached, call_gemini
from app.ai.experience_ai import get_experience_ai
from app.assistant.limits import RateLimited, UsageLimiter
from app.core.config import get_settings
from app.core.usage import DatabaseCounter
from app.main import app
from app.models import ContentEmbedding
from app.rag.embedder import EmbeddingUnavailable, HashingEmbedder
from tests.test_experiences import FakeAI, publish_new


def test_daily_counts_are_shared_between_instances_and_reset_each_day():
    day = [date(2026, 10, 27)]
    first, second = DatabaseCounter(lambda: day[0]), DatabaseCounter(lambda: day[0])
    assert first.take("k", 2) and second.take("k", 2)  # one count, whichever instance asks
    assert not first.take("k", 2)
    assert second.take("other", 2)
    day[0] = date(2026, 10, 28)
    assert first.take("k", 2)


def test_the_assistant_daily_cap_survives_a_restart():
    limiter = UsageLimiter(per_minute=100, per_day=2, counter=DatabaseCounter())
    limiter.check("user:a")
    limiter.check("user:a")
    restarted = UsageLimiter(per_minute=100, per_day=2, counter=DatabaseCounter())
    with pytest.raises(RateLimited, match="daily_limit_reached"):
        restarted.check("user:a")
    restarted.check("user:b")


def _api_error(code: int) -> genai_errors.APIError:
    return genai_errors.APIError(code, {"error": {"code": code, "message": "x"}})


MODELS = ("main-model", "backup-model")


def test_gemini_retries_only_what_may_pass_on_a_second_try(monkeypatch):
    monkeypatch.setattr(calls, "spend_gemini_call", lambda: True)
    monkeypatch.setattr(calls, "_resting_until", {})
    tries: list[str] = []

    def busy_then_fine(model: str) -> str:
        tries.append(model)
        if len(tries) == 1:
            raise _api_error(503)
        return "ok"

    assert call_gemini(busy_then_fine, MODELS, attempts=2, sleep=lambda _: None) == (
        "ok",
        "main-model",
    )

    refused: list[str] = []

    def invalid(model: str) -> str:
        refused.append(model)
        raise _api_error(400)

    with pytest.raises(genai_errors.APIError):
        call_gemini(invalid, MODELS, attempts=3, sleep=lambda _: None)
    assert refused == ["main-model"]  # an invalid request fails the same on any model


def test_a_model_out_of_quota_hands_over_to_the_backup(monkeypatch):
    monkeypatch.setattr(calls, "spend_gemini_call", lambda: True)
    monkeypatch.setattr(calls, "_resting_until", {})
    clock = [100.0]
    asked: list[str] = []

    def answer(model: str) -> str:
        asked.append(model)
        if model == "main-model":
            raise _api_error(429)
        return f"answer from {model}"

    assert call_gemini(answer, MODELS, now=lambda: clock[0]) == (
        "answer from backup-model",
        "backup-model",
    )
    # The main model rests for a minute: the next requests go straight to the backup.
    asked.clear()
    call_gemini(answer, MODELS, now=lambda: clock[0])
    assert asked == ["backup-model"]
    clock[0] += calls.REST_SECONDS + 1
    asked.clear()
    call_gemini(answer, MODELS, now=lambda: clock[0])
    assert asked == ["main-model", "backup-model"]


def test_when_every_model_is_out_of_quota_the_error_comes_back(monkeypatch):
    monkeypatch.setattr(calls, "spend_gemini_call", lambda: True)
    monkeypatch.setattr(calls, "_resting_until", {})

    def busy(model: str) -> str:
        raise _api_error(429)

    with pytest.raises(genai_errors.APIError):
        call_gemini(busy, MODELS)
    # Both resting: the next request still tries them rather than failing without asking.
    with pytest.raises(genai_errors.APIError):
        call_gemini(busy, MODELS)


def test_a_busy_model_is_asked_again_before_moving_on(monkeypatch):
    monkeypatch.setattr(calls, "spend_gemini_call", lambda: True)
    monkeypatch.setattr(calls, "_resting_until", {})
    asked: list[str] = []

    def busy_twice(model: str) -> str:
        asked.append(model)
        if asked.count("main-model") <= 2 and model == "main-model":
            raise _api_error(503)
        return model

    assert call_gemini(busy_twice, MODELS, sleep=lambda _: None) == ("main-model", "main-model")
    assert asked == ["main-model"] * 3

    asked.clear()

    def always_busy_main(model: str) -> str:
        asked.append(model)
        if model == "main-model":
            raise _api_error(503)
        return model

    assert call_gemini(always_busy_main, MODELS, sleep=lambda _: None)[1] == "backup-model"
    assert asked == ["main-model"] * 3 + ["backup-model"]


def test_one_request_never_waits_past_the_budget(monkeypatch):
    monkeypatch.setattr(calls, "spend_gemini_call", lambda: True)
    monkeypatch.setattr(calls, "_resting_until", {})
    clock = [0.0]

    def busy(model: str) -> str:
        clock[0] += 9  # a slow 503
        raise _api_error(503)

    with pytest.raises(genai_errors.APIError):
        call_gemini(
            busy,
            ("a", "b", "c"),
            sleep=lambda s: clock.__setitem__(0, clock[0] + s),
            now=lambda: clock[0],
            budget=20,
        )
    assert clock[0] <= 20 + 9 + 8  # stops after the attempt that crossed the budget


def test_a_lone_model_out_of_quota_is_tried_again(monkeypatch):
    # Embeddings have no backup model: a 429 waits and retries instead of failing at once.
    monkeypatch.setattr(calls, "spend_gemini_call", lambda: True)
    monkeypatch.setattr(calls, "_resting_until", {})
    tries: list[str] = []

    def busy_once(model: str) -> str:
        tries.append(model)
        if len(tries) == 1:
            raise _api_error(429)
        return "vector"

    assert call_gemini(busy_once, ("embedder",), attempts=2, sleep=lambda _: None) == (
        "vector",
        "embedder",
    )


def test_gemini_stops_at_the_daily_budget(monkeypatch):
    monkeypatch.setenv("GEMINI_DAILY_CALLS", "1")
    monkeypatch.setattr(calls, "_resting_until", {})
    get_settings.cache_clear()
    try:
        assert call_gemini(lambda model: "a", MODELS) == ("a", "main-model")
        with pytest.raises(GeminiBudgetReached):
            call_gemini(lambda model: "b", MODELS)
    finally:
        get_settings.cache_clear()


def test_free_tier_limits_and_backup_model_by_default(monkeypatch):
    for name in ("GEMINI_FALLBACK_MODELS", "ASSISTANT_PER_DAY", "ASSISTANT_DAILY_LLM_CALLS"):
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setenv("GEMINI_FALLBACK_MODELS", " gemini-3.1-flash-lite , other ")
    get_settings.cache_clear()
    try:
        settings = get_settings()
        assert settings.gemini_fallback_models == ("gemini-3.1-flash-lite", "other")
        monkeypatch.delenv("GEMINI_FALLBACK_MODELS")
        get_settings.cache_clear()
        assert get_settings().gemini_fallback_models == (
            "gemini-3.1-flash-lite",
            "gemini-2.5-flash-lite",
        )
        # One person's day (20 messages, at most 6 model calls each) fits many times over.
        assert settings.assistant_per_day * 6 < settings.assistant_daily_llm_calls <= 1000
    finally:
        get_settings.cache_clear()


class FlakyEmbedder(HashingEmbedder):
    down = True

    def embed_documents(self, texts: list[str]) -> list[list[float]]:
        if self.down:
            raise EmbeddingUnavailable("Gemini is down")
        return super().embed_documents(texts)


def test_posts_missed_by_indexing_are_indexed_with_the_next_one(db, monkeypatch):
    embedder = FlakyEmbedder()
    monkeypatch.setattr("app.api.experiences.get_embedder", lambda: embedder)
    app.dependency_overrides[get_experience_ai] = FakeAI
    try:
        api = TestClient(app)
        publish_new(api)  # Gemini is down: not indexed
        indexed = select(func.count()).select_from(ContentEmbedding)
        assert db.scalar(indexed) == 0
        embedder.down = False
        publish_new(api, original_voice="另一則經驗")
        assert db.scalar(indexed) == 2  # the new post and the one that failed before
    finally:
        app.dependency_overrides.pop(get_experience_ai, None)


def test_cloud_run_without_app_env_runs_as_production(monkeypatch):
    monkeypatch.delenv("APP_ENV", raising=False)
    monkeypatch.setenv("K_SERVICE", "culture-bridge")
    get_settings.cache_clear()
    try:
        assert get_settings().env == "production"
    finally:
        get_settings.cache_clear()
