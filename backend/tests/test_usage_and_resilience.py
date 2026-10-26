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


def test_gemini_retries_only_what_may_pass_on_a_second_try(monkeypatch):
    monkeypatch.setattr(calls, "spend_gemini_call", lambda: True)
    tries: list[int] = []

    def busy_then_fine() -> str:
        tries.append(1)
        if len(tries) == 1:
            raise _api_error(503)
        return "ok"

    assert call_gemini(busy_then_fine, attempts=2, sleep=lambda _: None) == "ok"

    refused: list[int] = []

    def invalid() -> str:
        refused.append(1)
        raise _api_error(400)

    with pytest.raises(genai_errors.APIError):
        call_gemini(invalid, attempts=3, sleep=lambda _: None)
    assert len(refused) == 1


def test_gemini_stops_at_the_daily_budget(monkeypatch):
    monkeypatch.setenv("GEMINI_DAILY_CALLS", "1")
    get_settings.cache_clear()
    try:
        assert call_gemini(lambda: "a") == "a"
        with pytest.raises(GeminiBudgetReached):
            call_gemini(lambda: "b")
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
