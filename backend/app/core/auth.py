"""Temporary caller identity.

Placeholder until B wires up the real login-token verification (work-assignment B-6/B-7).
In development, `X-Dev-User-Id` impersonates a student; everywhere else every caller is a guest.
"""

from dataclasses import dataclass
from typing import Annotated, Literal

from fastapi import Depends, Header

from app.core.config import Settings, get_settings

Role = Literal["student", "reviewer", "admin"]


@dataclass(frozen=True)
class CurrentUser:
    id: str
    role: Role = "student"


def get_optional_user(
    settings: Annotated[Settings, Depends(get_settings)],
    x_dev_user_id: Annotated[str | None, Header()] = None,
) -> CurrentUser | None:
    if settings.is_development and x_dev_user_id:
        return CurrentUser(id=x_dev_user_id)
    return None
