"""Who a reader has blocked, per persona.

An author can show up in two personas: anonymous posts and comments, and content signed with a
name. A block made from one persona hides only that persona. Otherwise blocking a named author
would make their anonymous posts vanish too, and the blocker could tell which anonymous posts
are theirs (and the other way round). Blocks from before migration 0012 have no persona and
hide both, as they always did.
"""

from typing import Literal

from sqlalchemy import ColumnElement, case, exists, or_, select
from sqlalchemy.orm import Session

from app.models import Experience, ExperienceComment, UserBlock

Persona = Literal["anonymous", "named"]


def experience_persona(author_display: str) -> Persona:
    return "anonymous" if author_display == "anonymous" else "named"


def _experience_persona_sql() -> ColumnElement[str]:
    return case((Experience.author_display == "anonymous", "anonymous"), else_="named")


def _comment_persona_sql(post: Experience) -> ColumnElement[str]:
    # The post author's comments are marked "by the author", so they share the post's persona.
    return case(
        (ExperienceComment.author_id == post.author_id, experience_persona(post.author_display)),
        (ExperienceComment.author_display == "nickname", "named"),
        else_="anonymous",
    )


def _covers(persona: ColumnElement[str] | str) -> ColumnElement[bool]:
    return or_(UserBlock.persona.is_(None), UserBlock.persona == persona)


def find_block(db: Session, blocker_id: str, author_id: str, persona: Persona) -> UserBlock | None:
    """The block that already hides this author's persona, if any."""
    return db.scalar(
        select(UserBlock)
        .where(
            UserBlock.blocker_id == blocker_id,
            UserBlock.blocked_id == author_id,
            _covers(persona),
        )
        .limit(1)
    )


def hides_experience(viewer_id: str) -> ColumnElement[bool]:
    """True for experiences whose author the viewer blocked in the persona the post shows."""
    return exists().where(
        UserBlock.blocker_id == viewer_id,
        UserBlock.blocked_id == Experience.author_id,
        _covers(_experience_persona_sql()),
    )


def hides_comment(viewer_id: str, post: Experience) -> ColumnElement[bool]:
    """True for comments on post whose author the viewer blocked in the persona shown."""
    return exists().where(
        UserBlock.blocker_id == viewer_id,
        UserBlock.blocked_id == ExperienceComment.author_id,
        _covers(_comment_persona_sql(post)),
    )


def blocks_post(db: Session, viewer_id: str, post: Experience) -> bool:
    persona = experience_persona(post.author_display)
    return find_block(db, viewer_id, post.author_id, persona) is not None
