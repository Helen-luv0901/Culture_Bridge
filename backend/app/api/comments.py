from fastapi import APIRouter, Response, status

from app.core.auth import OptionalUser, RequiredUser
from app.core.db import DbSession
from app.services import comments as svc

router = APIRouter(tags=["comments"])


@router.get("/experiences/{experience_id}/comments")
def list_comments(experience_id: str, db: DbSession, viewer: OptionalUser) -> list[svc.CommentOut]:
    return svc.list_comments(db, viewer, experience_id)


@router.post("/experiences/{experience_id}/comments", status_code=status.HTTP_201_CREATED)
def add_comment(
    experience_id: str, body: svc.CommentIn, user: RequiredUser, db: DbSession
) -> svc.CommentOut:
    return svc.add_comment(db, user, experience_id, body)


@router.put("/comments/{comment_id}/like")
def like(comment_id: str, user: RequiredUser, db: DbSession) -> svc.CommentOut:
    return svc.set_like(db, user, comment_id, True)


@router.delete("/comments/{comment_id}/like")
def unlike(comment_id: str, user: RequiredUser, db: DbSession) -> svc.CommentOut:
    return svc.set_like(db, user, comment_id, False)


@router.delete("/comments/{comment_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_comment(comment_id: str, user: RequiredUser, db: DbSession) -> Response:
    svc.delete_comment(db, user, comment_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
