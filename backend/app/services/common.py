import threading
from datetime import UTC, date, datetime, timedelta, timezone
from typing import Any

from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.auth import CurrentUser
from app.models import AdminAction

RECENT_WINDOW = timedelta(days=30)
_TAIPEI = timezone(timedelta(hours=8))


class DailyAllowance:
    """How many times each person has done something today (Taiwan time), in this process."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._day: date | None = None
        self._used: dict[str, int] = {}

    def take(self, user_id: str, limit: int) -> bool:
        today = datetime.now(_TAIPEI).date()
        with self._lock:
            if self._day != today:
                self._day, self._used = today, {}
            used = self._used.get(user_id, 0)
            if used >= limit:
                return False
            self._used[user_id] = used + 1
            return True


class Text2(BaseModel):
    """A text in both app languages."""

    zh: str
    en: str


def now() -> datetime:
    return datetime.now(UTC)


def start_of_today() -> datetime:
    """Midnight today in Taiwan, as UTC (daily limits reset then)."""
    midnight = datetime.combine(now().astimezone(_TAIPEI).date(), datetime.min.time(), _TAIPEI)
    return midnight.astimezone(UTC)


def text2(zh: str | None, en: str | None) -> Text2:
    zh = zh or ""
    return Text2(zh=zh, en=en or zh)


def log_admin(
    db: Session,
    actor: CurrentUser,
    action: str,
    target_type: str,
    target_id: str,
    **detail: Any,
) -> None:
    """Record a reviewer/admin write (D-6, B-2). Committed together with the change itself."""
    db.add(
        AdminAction(
            actor_id=actor.id,
            action=action,
            target_type=target_type,
            target_id=target_id,
            detail=detail,
        )
    )
