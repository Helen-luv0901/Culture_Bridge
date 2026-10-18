import base64
import binascii
from typing import Literal

from fastapi import APIRouter, Response, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy.orm import Session

from app.core.auth import RequiredUser
from app.core.db import DbSession
from app.core.errors import ApiError
from app.models import User
from app.services import avatars, moderation

router = APIRouter(prefix="/me", tags=["me"])


class Profile(BaseModel):
    id: str
    role: Literal["student", "reviewer", "admin"]
    preferred_locale: Literal["zh-Hant", "en"]
    # Optional; shown only on experiences the person chose to sign with them.
    nickname: str | None
    real_name: str | None
    avatar_url: str | None = None


class AvatarUpload(BaseModel):
    # Base64 of a JPEG, PNG, WebP or GIF; the server crops and shrinks it.
    image: str = Field(min_length=1, max_length=8_100_000)


class AvatarOut(BaseModel):
    avatar_url: str | None


class ProfileUpdate(BaseModel):
    """Only the fields sent are changed; send null or "" to clear a name."""

    preferred_locale: Literal["zh-Hant", "en"] | None = None
    nickname: str | None = Field(default=None, max_length=30)
    real_name: str | None = Field(default=None, max_length=50)

    @field_validator("nickname", "real_name")
    @classmethod
    def _blank_is_none(cls, value: str | None) -> str | None:
        value = " ".join(value.split()) if value else None
        return value or None


def _profile(row: User, db: Session) -> Profile:
    return Profile(
        id=row.id,
        role=row.role,  # type: ignore[arg-type]
        preferred_locale=row.preferred_locale,  # type: ignore[arg-type]
        nickname=row.nickname,
        real_name=row.real_name,
        avatar_url=avatars.url_for(db, row.id),
    )


@router.get("")
def get_me(user: RequiredUser, db: DbSession) -> Profile:
    row = db.get(User, user.id)
    assert row is not None
    return _profile(row, db)


@router.patch("")
def update_me(body: ProfileUpdate, user: RequiredUser, db: DbSession) -> Profile:
    row = db.get(User, user.id)
    assert row is not None
    for field in body.model_fields_set:
        value = getattr(body, field)
        if field == "preferred_locale" and value is None:
            continue
        setattr(row, field, value)
    db.commit()
    return _profile(row, db)


@router.put("/avatar")
def upload_avatar(body: AvatarUpload, user: RequiredUser, db: DbSession) -> AvatarOut:
    """Replace the profile photo; it is cropped to a square and its metadata dropped."""
    try:
        raw = base64.b64decode(body.image, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise ApiError(422, "avatar_invalid") from exc
    return AvatarOut(avatar_url=avatars.save(db, user, raw))


@router.delete("/avatar", status_code=status.HTTP_204_NO_CONTENT)
def delete_avatar(user: RequiredUser, db: DbSession) -> Response:
    avatars.remove(db, user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


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
