"""Profile photos (migration 0009).

An upload is checked and rebuilt here before it is stored: it must be a JPEG, PNG, WebP or
GIF image of reasonable size; it is turned upright, cropped to the centre square, resized to
256px and saved as a fresh JPEG, which drops EXIF data such as where the photo was taken.

Photos are only ever shown next to posts and comments signed with a name, so they never
unmask an anonymous post.
"""

import io
import logging
import threading

from PIL import Image, ImageOps, UnidentifiedImageError
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.core.auth import CurrentUser
from app.core.errors import ApiError
from app.models import UserAvatar
from app.services.common import DailyAllowance

logger = logging.getLogger(__name__)

SIZE = 256
QUALITY = 85
MAX_UPLOAD_BYTES = 6_000_000
# Refuse "decompression bombs" before decoding them. The app already shrinks a picked photo to
# 1024px; 24 MP leaves room for other clients while keeping a full-size decode under ~100 MB.
MAX_PIXELS = 24_000_000
UPLOADS_PER_DAY = 20
_FORMATS = {"JPEG", "PNG", "WEBP", "GIF", "MPO"}  # MPO: JPEGs from some phone cameras

_uploads = DailyAllowance("avatar")
# One photo at a time per process: a decoded photo and its copies take tens of MB, and a few at
# once could run a 512 MiB instance out of memory. Each takes well under a second.
_decoding = threading.BoundedSemaphore(1)


def url(avatar_id: str) -> str:
    return f"/api/avatars/{avatar_id}"


def to_square_jpeg(raw: bytes) -> bytes:
    """The upload as a 256px square JPEG without metadata; raises ApiError if it isn't a photo."""
    if not raw or len(raw) > MAX_UPLOAD_BYTES:
        raise ApiError(413, "avatar_too_large")
    try:
        with _decoding, Image.open(io.BytesIO(raw)) as img:
            if img.format not in _FORMATS or img.width * img.height > MAX_PIXELS:
                raise ApiError(422, "avatar_invalid")
            # A large JPEG is decoded at up to 1/8 scale, still at least twice the output size:
            # a 12 MP photo then takes about 2 MB instead of 36. Other formats ignore this.
            img.draft("RGB", (SIZE * 2, SIZE * 2))
            img.load()
            square = ImageOps.fit(ImageOps.exif_transpose(img), (SIZE, SIZE), Image.LANCZOS)
    except (UnidentifiedImageError, Image.DecompressionBombError, OSError, ValueError) as exc:
        raise ApiError(422, "avatar_invalid") from exc
    if square.mode in ("RGBA", "LA", "P"):
        square = square.convert("RGBA")
        background = Image.new("RGB", square.size, (255, 255, 255))
        background.paste(square, mask=square.getchannel("A"))
        square = background
    out = io.BytesIO()
    square.convert("RGB").save(out, "JPEG", quality=QUALITY, optimize=True)
    return out.getvalue()


def save(db: Session, user: CurrentUser, raw: bytes) -> str:
    """Replace the person's photo; returns its new URL."""
    if not _uploads.take(user.id, UPLOADS_PER_DAY):
        raise ApiError(429, "avatar_daily_limit")
    image = to_square_jpeg(raw)
    db.execute(delete(UserAvatar).where(UserAvatar.user_id == user.id))
    avatar = UserAvatar(user_id=user.id, image=image)
    db.add(avatar)
    db.commit()
    return url(avatar.id)


def remove(db: Session, user: CurrentUser) -> None:
    db.execute(delete(UserAvatar).where(UserAvatar.user_id == user.id))
    db.commit()


def url_for(db: Session, user_id: str) -> str | None:
    return urls_for(db, {user_id}).get(user_id)


def urls_for(db: Session, user_ids: set[str]) -> dict[str, str]:
    """Photo URLs by account, for the accounts that have one."""
    if not user_ids:
        return {}
    rows = db.execute(
        select(UserAvatar.user_id, UserAvatar.id).where(UserAvatar.user_id.in_(user_ids))
    )
    return {user_id: url(avatar_id) for user_id, avatar_id in rows}


def image(db: Session, avatar_id: str) -> bytes | None:
    return db.scalar(select(UserAvatar.image).where(UserAvatar.id == avatar_id))
