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
    demo_content_path: Path

    @property
    def is_development(self) -> bool:
        return self.env == "development"


@lru_cache
def get_settings() -> Settings:
    return Settings(
        env=os.getenv("APP_ENV", "development"),
        gemini_api_key=os.getenv("GEMINI_API_KEY") or None,
        gemini_model=os.getenv("GEMINI_MODEL", "gemini-2.5-flash"),
        gemini_timeout_seconds=float(os.getenv("GEMINI_TIMEOUT_SECONDS", "30")),
        assistant_max_tool_rounds=int(os.getenv("ASSISTANT_MAX_TOOL_ROUNDS", "5")),
        assistant_memory_exchanges=int(os.getenv("ASSISTANT_MEMORY_EXCHANGES", "6")),
        demo_content_path=Path(
            os.getenv(
                "DEMO_CONTENT_PATH",
                str(REPO_ROOT / "flutter_app" / "assets" / "data" / "content.json"),
            )
        ),
    )
