"""Settings read from environment variables (local: backend/.env is not committed)."""

import os
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]


@dataclass(frozen=True)
class Settings:
    env: str
    gemini_api_key: str | None
    gemini_model: str
    gemini_timeout_seconds: float
    assistant_max_tool_rounds: int
    assistant_memory_exchanges: int
    assistant_allow_guests: bool
    assistant_per_minute: int
    assistant_per_day: int
    assistant_daily_llm_calls: int
    demo_content_path: Path

    @property
    def is_development(self) -> bool:
        return self.env == "development"


def _flag(name: str, default: bool) -> bool:
    value = os.getenv(name)
    return default if value is None else value.strip().lower() in ("1", "true", "yes")


@lru_cache
def get_settings() -> Settings:
    env = os.getenv("APP_ENV", "development")
    return Settings(
        env=env,
        gemini_api_key=os.getenv("GEMINI_API_KEY") or None,
        gemini_model=os.getenv("GEMINI_MODEL", "gemini-2.5-flash"),
        gemini_timeout_seconds=float(os.getenv("GEMINI_TIMEOUT_SECONDS", "30")),
        assistant_max_tool_rounds=int(os.getenv("ASSISTANT_MAX_TOOL_ROUNDS", "5")),
        assistant_memory_exchanges=int(os.getenv("ASSISTANT_MEMORY_EXCHANGES", "6")),
        # Whether guests may chat is still undecided (tech-architecture §9.6): off outside dev.
        assistant_allow_guests=_flag("ASSISTANT_ALLOW_GUESTS", env == "development"),
        assistant_per_minute=int(os.getenv("ASSISTANT_PER_MINUTE", "10")),
        assistant_per_day=int(os.getenv("ASSISTANT_PER_DAY", "100")),
        assistant_daily_llm_calls=int(os.getenv("ASSISTANT_DAILY_LLM_CALLS", "3000")),
        demo_content_path=Path(
            os.getenv(
                "DEMO_CONTENT_PATH",
                str(REPO_ROOT / "flutter_app" / "assets" / "data" / "content.json"),
            )
        ),
    )
