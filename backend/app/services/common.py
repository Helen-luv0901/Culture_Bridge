from datetime import UTC, datetime, timedelta
from typing import Any

from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.auth import CurrentUser
from app.core.usage import DailyCounter, DatabaseCounter
from app.models import AdminAction

RECENT_WINDOW = timedelta(days=30)


class DailyAllowance:
    """How many times each person has done something today (Taiwan time), counted in the
    database so restarts and extra instances don't reset it (app.core.usage)."""

    def __init__(self, name: str, counter: DailyCounter | None = None) -> None:
        self._name = name
        self._counter = counter or DatabaseCounter()

    def take(self, user_id: str, limit: int) -> bool:
        return self._counter.take(f"{self._name}:{user_id}", limit)


class Text2(BaseModel):
    """A text in both app languages."""

    zh: str
    en: str


def now() -> datetime:
    return datetime.now(UTC)


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
