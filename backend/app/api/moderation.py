from fastapi import APIRouter, status
from pydantic import BaseModel, model_validator

from app.core.auth import RequiredUser
from app.core.db import DbSession
from app.services import moderation as svc

router = APIRouter(tags=["moderation"])


@router.post("/reports", status_code=status.HTTP_201_CREATED)
def report(body: svc.ReportIn, user: RequiredUser, db: DbSession) -> svc.ReportAck:
    return svc.report_content(db, user, body)


class BlockIn(BaseModel):
    """Block the author of a post (experience_id) or of a comment (comment_id), not both."""

    experience_id: str | None = None
    comment_id: str | None = None

    @model_validator(mode="after")
    def _one_target(self) -> "BlockIn":
        if (self.experience_id is None) == (self.comment_id is None):
            raise ValueError("give exactly one of experience_id or comment_id")
        return self


@router.post("/blocks", status_code=status.HTTP_201_CREATED)
@router.post("/me/blocks", status_code=status.HTTP_201_CREATED, include_in_schema=False)
def block(body: BlockIn, user: RequiredUser, db: DbSession) -> svc.BlockOut:
    """Block the (anonymous) author of a post or comment; their posts and comments in that
    persona disappear for you."""
    if body.comment_id is not None:
        return svc.block_commenter(db, user, body.comment_id)
    assert body.experience_id is not None
    return svc.block_author(db, user, body.experience_id)
