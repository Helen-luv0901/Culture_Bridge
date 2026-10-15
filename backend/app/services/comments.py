"""Comments under student posts, with one level of replies and "same here" likes.

Comments are anonymous unless the commenter signs with their nickname; public payloads never
expose accounts. Comments by authors the reader blocked are left out, hidden comments are only
seen by moderators, and a reply to a reply attaches to the top-level comment.
"""

from datetime import UTC, datetime, timedelta, timezone
from typing import Literal

from pydantic import BaseModel, Field, field_validator
from sqlalchemy import delete, exists, func, select
from sqlalchemy.orm import Session

from app.core.auth import CurrentUser
from app.core.errors import ApiError, forbidden, not_found
from app.models import CommentLike, Experience, ExperienceComment, User, UserBlock

MAX_BODY = 1000
MAX_COMMENTS = 500  # per post, newest kept visible
MAX_COMMENTS_PER_DAY = 100  # per commenter
_TAIPEI = timezone(timedelta(hours=8))


class CommentIn(BaseModel):
    body: str = Field(max_length=MAX_BODY)
    reply_to_id: str | None = None
    author_display: Literal["anonymous", "nickname"] = "anonymous"

    @field_validator("body")
    @classmethod
    def _body(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("body must not be blank")
        return value


class CommentOut(BaseModel):
    id: str
    reply_to_id: str | None
    body: str
    created_at: datetime
    # The nickname when the commenter chose to sign; None means anonymous.
    author_name: str | None
    like_count: int
    liked: bool
    by_post_author: bool
    mine: bool


def _public_post(db: Session, experience_id: str, viewer: CurrentUser | None = None) -> Experience:
    experience = db.get(Experience, experience_id)
    if experience is None or experience.status != "published":
        raise not_found("experience_not_found")
    # A post by an author the reader blocked is gone for them, comments included.
    if viewer is not None and db.get(UserBlock, (viewer.id, experience.author_id)):
        raise not_found("experience_not_found")
    return experience


def _hides_author(post: Experience, comment: ExperienceComment) -> bool:
    """The author of an anonymous post never shows a name on it, or it would unmask them."""
    return comment.author_id == post.author_id and post.author_display == "anonymous"


def _out(
    db: Session, comments: list[ExperienceComment], post: Experience, viewer: CurrentUser | None
) -> list[CommentOut]:
    ids = [c.id for c in comments]
    likes: dict[str, int] = {}
    liked: set[str] = set()
    names: dict[str, str | None] = {}
    if ids:
        likes = dict(
            db.execute(  # type: ignore[arg-type]
                select(CommentLike.comment_id, func.count())
                .where(CommentLike.comment_id.in_(ids))
                .group_by(CommentLike.comment_id)
            ).all()
        )
        if viewer is not None:
            liked = set(
                db.scalars(
                    select(CommentLike.comment_id).where(
                        CommentLike.comment_id.in_(ids), CommentLike.user_id == viewer.id
                    )
                )
            )
        signed = {c.author_id for c in comments if c.author_display == "nickname"}
        if signed:
            names = {u.id: u.nickname for u in db.scalars(select(User).where(User.id.in_(signed)))}
    return [
        CommentOut(
            id=c.id,
            reply_to_id=c.reply_to_id,
            body=c.body,
            created_at=c.created_at,
            author_name=names.get(c.author_id)
            if c.author_display == "nickname" and not _hides_author(post, c)
            else None,
            like_count=likes.get(c.id, 0),
            liked=c.id in liked,
            by_post_author=c.author_id == post.author_id,
            mine=viewer is not None and c.author_id == viewer.id,
        )
        for c in comments
    ]


def list_comments(db: Session, viewer: CurrentUser | None, experience_id: str) -> list[CommentOut]:
    post = _public_post(db, experience_id, viewer)
    query = select(ExperienceComment).where(
        ExperienceComment.experience_id == post.id, ExperienceComment.status == "visible"
    )
    if viewer is not None:
        query = query.where(
            ~exists().where(
                UserBlock.blocker_id == viewer.id,
                UserBlock.blocked_id == ExperienceComment.author_id,
            )
        )
    newest = db.scalars(
        query.order_by(ExperienceComment.created_at.desc(), ExperienceComment.id.desc()).limit(
            MAX_COMMENTS
        )
    )
    return _out(db, list(newest)[::-1], post, viewer)


def add_comment(db: Session, user: CurrentUser, experience_id: str, body: CommentIn) -> CommentOut:
    post = _public_post(db, experience_id, user)
    local_midnight = datetime.combine(datetime.now(_TAIPEI).date(), datetime.min.time(), _TAIPEI)
    written_today = db.scalar(
        select(func.count())
        .select_from(ExperienceComment)
        .where(
            ExperienceComment.author_id == user.id,
            ExperienceComment.created_at >= local_midnight.astimezone(UTC),
        )
    )
    if (written_today or 0) >= MAX_COMMENTS_PER_DAY:
        raise ApiError(429, "daily_limit_reached")
    reply_to = None
    if body.reply_to_id:
        target = db.get(ExperienceComment, body.reply_to_id)
        if target is None or target.experience_id != post.id or target.status != "visible":
            raise not_found("comment_not_found")
        # One level of replies: answering a reply answers its thread.
        reply_to = target.reply_to_id or target.id
    if body.author_display == "nickname" and post.author_id == user.id:
        if post.author_display == "anonymous":
            raise ApiError(422, "anonymous_post_author")
    if body.author_display == "nickname":
        account = db.get(User, user.id)
        if account is None or not account.nickname:
            raise ApiError(422, "nickname_missing")
    comment = ExperienceComment(
        experience_id=post.id,
        author_id=user.id,
        reply_to_id=reply_to,
        body=body.body,
        author_display=body.author_display,
    )
    db.add(comment)
    db.commit()
    return _out(db, [comment], post, user)[0]


def _visible(db: Session, comment_id: str) -> ExperienceComment:
    comment = db.get(ExperienceComment, comment_id)
    if comment is None or comment.status != "visible":
        raise not_found("comment_not_found")
    _public_post(db, comment.experience_id)
    return comment


def set_like(db: Session, user: CurrentUser, comment_id: str, on: bool) -> CommentOut:
    comment = _visible(db, comment_id)
    existing = db.get(CommentLike, (comment.id, user.id))
    if on and existing is None:
        db.add(CommentLike(comment_id=comment.id, user_id=user.id))
    elif not on and existing is not None:
        db.delete(existing)
    db.commit()
    post = db.get(Experience, comment.experience_id)
    assert post is not None
    return _out(db, [comment], post, user)[0]


def delete_comment(db: Session, user: CurrentUser, comment_id: str) -> None:
    """The commenter (or staff) deletes a comment; its replies go with it."""
    comment = db.get(ExperienceComment, comment_id)
    if comment is None:
        raise not_found("comment_not_found")
    if comment.author_id != user.id and not user.is_staff:
        raise forbidden("not_comment_author")
    thread = select(ExperienceComment.id).where(
        (ExperienceComment.id == comment.id) | (ExperienceComment.reply_to_id == comment.id)
    )
    db.execute(delete(CommentLike).where(CommentLike.comment_id.in_(thread)))
    db.execute(delete(ExperienceComment).where(ExperienceComment.reply_to_id == comment.id))
    db.execute(delete(ExperienceComment).where(ExperienceComment.id == comment.id))
    db.commit()
