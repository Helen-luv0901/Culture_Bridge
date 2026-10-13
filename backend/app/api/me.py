from typing import Literal

from fastapi import APIRouter, Response, status
from pydantic import BaseModel

from app.core.auth import RequiredUser
from app.core.db import DbSession
from app.models import User
from app.services import moderation

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


@router.delete("", status_code=status.HTTP_204_NO_CONTENT)
def delete_me(user: RequiredUser, db: DbSession) -> Response:
    """Delete the account and all its data (B-17). The app then deletes the Firebase login."""
    from app.api.assistant import get_services

    moderation.delete_account(db, user)
    get_services().assistant.forget_user(user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/blocks")
def my_blocks(user: RequiredUser, db: DbSession) -> list[moderation.BlockOut]:
    return moderation.my_blocks(db, user)


@router.delete("/blocks/{block_id}", status_code=status.HTTP_204_NO_CONTENT)
def unblock(block_id: str, user: RequiredUser, db: DbSession) -> Response:
    moderation.unblock(db, user, block_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
