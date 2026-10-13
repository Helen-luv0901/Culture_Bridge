from fastapi import APIRouter, status
from pydantic import BaseModel

from app.core.auth import RequiredUser
from app.core.db import DbSession
from app.services import moderation as svc

router = APIRouter(tags=["moderation"])


@router.post("/reports", status_code=status.HTTP_201_CREATED)
def report(body: svc.ReportIn, user: RequiredUser, db: DbSession) -> svc.ReportAck:
    return svc.report_experience(db, user, body)


class BlockIn(BaseModel):
    experience_id: str


@router.post("/blocks", status_code=status.HTTP_201_CREATED)
def block(body: BlockIn, user: RequiredUser, db: DbSession) -> svc.BlockOut:
    """Block the (anonymous) author of an experience; their posts disappear for you."""
    return svc.block_author(db, user, body.experience_id)
