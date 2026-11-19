"""Settings read from environment variables (local: backend/.env is not committed)."""

import os
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]


# Gemini refuses a request deadline under 10 s ("Manually set deadline 8s is too short",
# 400 INVALID_ARGUMENT, production 2026-11-05), so no timeout setting goes below it.
GEMINI_MIN_DEADLINE_SECONDS = 10.0


@dataclass(frozen=True)
class Settings:
    env: str
    database_url: str
    firebase_project_id: str | None
    # Firebase web app settings handed to the app at startup; public identifiers, not secrets.
    firebase_web: dict[str, str] | None
    web_dir: Path | None
    ai_summaries_per_day: int
    ai_tag_suggestions_per_day: int
    embedding_model: str
    semantic_max_distance: float
    gemini_api_key: str | None
    gemini_model: str
    # Groq (OpenAI-compatible, free tier, ~1 s answers): asked first by the assistant when a key
    # is set, with Gemini as the backup. Empty key = Gemini only.
    groq_api_key: str | None
    groq_model: str
    groq_base_url: str
    groq_reasoning_effort: str
    # Tried in order when GEMINI_MODEL answers 429 (free quota used up) or runs out of time.
    gemini_fallback_models: tuple[str, ...]
    gemini_timeout_seconds: float
    # One assistant model call (at least 10 s, Gemini's minimum). Answers take 1-3 s; a model
    # still silent after this is slow (free tier under load) and the backup is asked instead.
    assistant_model_timeout_seconds: float
    # How much Gemini "thinks" before the assistant and tag suggestions answer:
    # minimal | low | medium | high, or empty for the model's default (slowest).
    gemini_thinking_level: str
    assistant_max_tool_rounds: int
    assistant_memory_exchanges: int
    assistant_allow_guests: bool
    assistant_per_minute: int
    assistant_per_day: int
    assistant_daily_llm_calls: int
    # Every Gemini request (assistant, summaries, translations, tags, embeddings) counts here.
    gemini_daily_calls: int
    demo_content_path: Path
    # Shown on /privacy, /terms and /account-deletion and handed to the app; None until set.
    support_email: str | None
    # Firebase sign-in methods accepted (claim firebase.sign_in_provider): the app offers only
    # Google and Apple, so anonymous or email/password logins made with the public web API key
    # are refused.
    allowed_sign_in_providers: tuple[str, ...]

    @property
    def is_development(self) -> bool:
        return self.env == "development"


def _flag(name: str, default: bool) -> bool:
    value = os.getenv(name)
    return default if value is None else value.strip().lower() in ("1", "true", "yes")


def _firebase_web() -> dict[str, str] | None:
    keys = {
        "apiKey": "FIREBASE_WEB_API_KEY",
        "appId": "FIREBASE_WEB_APP_ID",
        "authDomain": "FIREBASE_AUTH_DOMAIN",
        "messagingSenderId": "FIREBASE_MESSAGING_SENDER_ID",
        "projectId": "FIREBASE_PROJECT_ID",
    }
    values = {name: os.getenv(env, "") for name, env in keys.items()}
    return values if values["apiKey"] and values["projectId"] else None


@lru_cache
def get_settings() -> Settings:
    # Cloud Run sets K_SERVICE (services) or CLOUD_RUN_JOB (jobs): a deployment that lost its
    # APP_ENV must not fall back to development, which accepts dev:<name> logins.
    on_cloud_run = bool(os.getenv("K_SERVICE") or os.getenv("CLOUD_RUN_JOB"))
    env = os.getenv("APP_ENV") or ("production" if on_cloud_run else "development")
    return Settings(
        env=env,
        database_url=os.getenv(
            "DATABASE_URL", "postgresql+psycopg://postgres@localhost:5432/culturebridge"
        ),
        firebase_project_id=os.getenv("FIREBASE_PROJECT_ID") or None,
        firebase_web=_firebase_web(),
        # Built Flutter web app (flutter build web); served at / when present.
        web_dir=Path(os.environ["WEB_DIR"]) if os.getenv("WEB_DIR") else None,
        ai_summaries_per_day=int(os.getenv("AI_SUMMARIES_PER_DAY", "10")),
        # Past this, suggestions come from keyword rules instead of the model.
        ai_tag_suggestions_per_day=int(os.getenv("AI_TAG_SUGGESTIONS_PER_DAY", "15")),
        embedding_model=os.getenv("EMBEDDING_MODEL", "gemini-embedding-001"),
        # Cosine distance cut-off; tune with `python -m app.rag.evaluate` on real embeddings.
        semantic_max_distance=float(os.getenv("SEMANTIC_MAX_DISTANCE", "0.6")),
        gemini_api_key=os.getenv("GEMINI_API_KEY") or None,
        gemini_model=os.getenv("GEMINI_MODEL", "gemini-3.8-flash"),
        groq_api_key=os.getenv("GROQ_API_KEY") or None,
        groq_model=os.getenv("GROQ_MODEL", "openai/gpt-oss-120b"),
        groq_base_url=os.getenv("GROQ_BASE_URL", "https://api.groq.com/openai/v1"),
        groq_reasoning_effort=os.getenv("GROQ_REASONING_EFFORT", "low").strip().lower(),
        gemini_fallback_models=tuple(
            m.strip()
            for m in os.getenv(
                # gemini-2.5-flash-lite was retired for new users on 2026-11-19 (404). The last
                # backup is another family: that night both Flash Lite models timed out together.
                "GEMINI_FALLBACK_MODELS",
                "gemini-3.1-flash-lite,gemini-3.8-flash",
            ).split(",")
            if m.strip()
        ),
        gemini_timeout_seconds=max(
            GEMINI_MIN_DEADLINE_SECONDS, float(os.getenv("GEMINI_TIMEOUT_SECONDS", "30"))
        ),
        assistant_model_timeout_seconds=max(
            GEMINI_MIN_DEADLINE_SECONDS,
            # 2026-11-19 the free tier took 10-20 s per answer for a whole evening; at 10 s every
            # model was cut off (504) and nobody got an answer. Two backups x 20 s still fit the
            # 45 s round budget, and the app waits 120 s.
            float(os.getenv("ASSISTANT_MODEL_TIMEOUT_SECONDS", "20")),
        ),
        gemini_thinking_level=os.getenv("GEMINI_THINKING_LEVEL", "low").strip().lower(),
        assistant_max_tool_rounds=int(os.getenv("ASSISTANT_MAX_TOOL_ROUNDS", "5")),
        assistant_memory_exchanges=int(os.getenv("ASSISTANT_MEMORY_EXCHANGES", "6")),
        # Whether guests may chat is still undecided (tech-architecture §9.6): off outside dev.
        assistant_allow_guests=_flag("ASSISTANT_ALLOW_GUESTS", env == "development"),
        assistant_per_minute=int(os.getenv("ASSISTANT_PER_MINUTE", "5")),
        assistant_per_day=int(os.getenv("ASSISTANT_PER_DAY", "20")),
        # Sized for the free tier (AI Studio, 2026-10-27): GEMINI_MODEL and one backup with 500
        # text requests a day each, embeddings 1,000. The assistant gets 700 of the text
        # requests, leaving room for translations, tags and summaries; nobody can use up the day
        # alone (20 messages, at most 6 model calls each). Raise these on a paid plan.
        assistant_daily_llm_calls=int(os.getenv("ASSISTANT_DAILY_LLM_CALLS", "700")),
        gemini_daily_calls=int(os.getenv("GEMINI_DAILY_CALLS", "2000")),
        demo_content_path=Path(
            os.getenv(
                "DEMO_CONTENT_PATH",
                str(REPO_ROOT / "flutter_app" / "assets" / "data" / "content.json"),
            )
        ),
        support_email=os.getenv("SUPPORT_EMAIL", "").strip() or None,
        allowed_sign_in_providers=tuple(
            p.strip()
            for p in os.getenv("ALLOWED_SIGN_IN_PROVIDERS", "google.com,apple.com").split(",")
            if p.strip()
        ),
    )
