"""Reviewer/admin endpoints (D-6). Everything here requires a reviewer or admin role."""

from typing import Literal

from fastapi import APIRouter, Query, Response, status

from app.core.auth import AdminUser, StaffUser
from app.core.db import DbSession
from app.services import admin_actions as svc
from app.services import moderation

router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/actions")
def list_actions(_: StaffUser, db: DbSession) -> list[svc.AdminActionItem]:
    return svc.list_admin_actions(db)


@router.post("/actions", status_code=status.HTTP_201_CREATED)
def create_action(body: svc.NewAction, user: StaffUser, db: DbSession) -> svc.AdminVersion:
    return svc.create_action(db, user, body)


@router.get("/actions/{action_id}/versions")
def list_versions(action_id: str, _: StaffUser, db: DbSession) -> list[svc.AdminVersion]:
    return svc.list_versions(db, action_id)


@router.post("/actions/{action_id}/versions", status_code=status.HTTP_201_CREATED)
def create_version(action_id: str, user: StaffUser, db: DbSession) -> svc.AdminVersion:
    return svc.create_version(db, user, action_id)


@router.post("/actions/{action_id}/archive", status_code=status.HTTP_204_NO_CONTENT)
def archive(action_id: str, user: StaffUser, db: DbSession, archived: bool = True) -> Response:
    svc.archive_action(db, user, action_id, archived)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.put("/versions/{version_id}")
def update_draft(
    version_id: str, body: svc.VersionContent, user: StaffUser, db: DbSession
) -> svc.AdminVersion:
    return svc.update_draft(db, user, version_id, body)


@router.post("/versions/{version_id}/publish")
def publish(version_id: str, user: StaffUser, db: DbSession) -> svc.AdminVersion:
    return svc.publish_version(db, user, version_id)


@router.put("/versions/{version_id}/sources/{source_id}")
def attach_source(
    version_id: str, source_id: str, body: svc.AttachSource, user: StaffUser, db: DbSession
) -> svc.AdminVersion:
    return svc.attach_source(db, user, version_id, source_id, body)


@router.delete("/versions/{version_id}/sources/{source_id}")
def detach_source(
    version_id: str, source_id: str, user: StaffUser, db: DbSession
) -> svc.AdminVersion:
    return svc.detach_source(db, user, version_id, source_id)


@router.post("/versions/{version_id}/verifications")
def verify(
    version_id: str, body: svc.VerificationIn, user: StaffUser, db: DbSession
) -> svc.AdminVersion:
    return svc.record_verification(db, user, version_id, body)


@router.put("/versions/{version_id}/status")
def set_status(
    version_id: str, body: svc.StatusIn, user: StaffUser, db: DbSession
) -> svc.AdminVersion:
    return svc.set_status(db, user, version_id, body)


@router.get("/sources")
def list_sources(_: StaffUser, db: DbSession) -> list[svc.AdminSource]:
    return svc.list_sources(db)


@router.post("/sources", status_code=status.HTTP_201_CREATED)
def create_source(body: svc.SourceIn, user: StaffUser, db: DbSession) -> svc.AdminSource:
    return svc.create_source(db, user, body)


@router.get("/feedback")
def list_feedback(
    _: StaffUser,
    db: DbSession,
    state: Literal["pending", "reviewed", "dismissed"] = "pending",
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> list[svc.FeedbackItem]:
    return svc.list_feedback(db, state, limit, offset)


@router.post("/feedback/{feedback_id}", status_code=status.HTTP_204_NO_CONTENT)
def review_feedback(
    feedback_id: str, body: svc.FeedbackReview, user: StaffUser, db: DbSession
) -> Response:
    svc.review_feedback(db, user, feedback_id, body)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/reports")
def report_queue(
    _: StaffUser,
    db: DbSession,
    status: Literal["pending", "actioned", "dismissed"] = "pending",
) -> list[moderation.ReportedItem]:
    return moderation.report_queue(db, status)


@router.post("/reports/{report_id}/resolve", status_code=204)
def resolve_report(
    report_id: str, body: moderation.ResolveIn, user: StaffUser, db: DbSession
) -> Response:
    moderation.resolve_report(db, user, report_id, body)
    return Response(status_code=204)


@router.post("/experiences/{experience_id}/hide", status_code=204)
def hide_experience(experience_id: str, user: StaffUser, db: DbSession) -> Response:
    moderation.set_experience_visibility(db, user, experience_id, hidden=True)
    return Response(status_code=204)


@router.post("/experiences/{experience_id}/restore", status_code=204)
def restore_experience(experience_id: str, user: StaffUser, db: DbSession) -> Response:
    moderation.set_experience_visibility(db, user, experience_id, hidden=False)
    return Response(status_code=204)


@router.put("/users/{user_id}/role", status_code=204)
def set_role(user_id: str, body: moderation.RoleIn, user: AdminUser, db: DbSession) -> Response:
    moderation.set_role(db, user, user_id, body)
    return Response(status_code=204)
