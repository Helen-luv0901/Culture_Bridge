from typing import Literal

from fastapi import APIRouter
from pydantic import BaseModel

from app.core.auth import RequiredUser
from app.core.db import DbSession
from app.models import User

router = APIRouter(prefix="/me", tags=["me"])


class Profile(BaseModel):
    id: str
    role: Literal["student", "reviewer", "admin"]
    preferred_locale: Literal["zh-Hant", "en"]


class ProfileUpdate(BaseModel):
    preferred_locale: Literal["zh-Hant", "en"]


@router.get("")
def get_me(user: RequiredUser) -> Profile:
    return Profile(id=user.id, role=user.role, preferred_locale=user.preferred_locale)


@router.patch("")
def update_me(body: ProfileUpdate, user: RequiredUser, db: DbSession) -> Profile:
    row = db.get(User, user.id)
    assert row is not None
    row.preferred_locale = body.preferred_locale
    db.commit()
    return Profile(id=row.id, role=row.role, preferred_locale=row.preferred_locale)
