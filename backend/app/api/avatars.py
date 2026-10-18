from fastapi import APIRouter, Response

from app.core.db import DbSession
from app.core.errors import not_found
from app.services import avatars

router = APIRouter(prefix="/avatars", tags=["avatars"])


@router.get("/{avatar_id}")
def get_avatar(avatar_id: str, db: DbSession) -> Response:
    """A profile photo. Each upload gets a new id, so it can be cached for good."""
    image = avatars.image(db, avatar_id[:64])
    if image is None:
        raise not_found("avatar_not_found")
    return Response(
        content=image,
        media_type="image/jpeg",
        headers={"Cache-Control": "public, max-age=31536000, immutable"},
    )
