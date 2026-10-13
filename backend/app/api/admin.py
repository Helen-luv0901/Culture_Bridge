"""Reviewer/admin endpoints (D-6). Everything here requires a reviewer or admin role."""

from datetime import date
from typing import Annotated, Literal

from fastapi import APIRouter, BackgroundTasks, Depends, Query, Response, status
from pydantic import BaseModel, Field, HttpUrl
from sqlalchemy import func, select

from app.ai.experience_ai import AIUnavailable
from app.ai.feedback_ai import FeedbackAI, get_feedback_ai
from app.core.auth import AdminUser, StaffUser
from app.core.db import DbSession, get_sessionmaker
from app.core.errors import ApiError, not_found
from app.models import KbChunk, KbDocument
from app.rag.embedder import EmbeddingUnavailable, get_embedder
from app.rag.index import add_document, sync_in_background
from app.services import admin_actions as svc
from app.services import metrics, moderation

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


@router.post("/actions/{action_id}/feedback-summary")
def feedback_summary(
    action_id: str,
    body: svc.FeedbackSummaryIn,
    user: StaffUser,
    db: DbSession,
    ai: Annotated[FeedbackAI, Depends(get_feedback_ai)],
) -> svc.FeedbackSummaryOut:
    """AI overview of students' reports for one procedure (D-7). Advice only: nothing changes."""
    try:
        return svc.summarize_feedback(db, user, ai, action_id, body)
    except AIUnavailable as exc:
        raise ApiError(503, "ai_unavailable") from exc


@router.post("/feedback/{feedback_id}", status_code=status.HTTP_204_NO_CONTENT)
def review_feedback(
    feedback_id: str,
    body: svc.FeedbackReview,
    user: StaffUser,
    db: DbSession,
    background: BackgroundTasks,
) -> Response:
    svc.review_feedback(db, user, feedback_id, body)
    if body.review_state == "reviewed":
        background.add_task(
            sync_in_background,
            get_sessionmaker(),
            get_embedder(),
            "execution_feedback",
            feedback_id,
        )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/reports")
def report_queue(
    _: StaffUser,
    db: DbSession,
    status: Literal["pending", "actioned", "dismissed"] = "pending",
) -> list[moderation.ReportedItem]:
    return moderation.report_queue(db, status)


def _reindex(background: BackgroundTasks, experience_id: str) -> None:
    background.add_task(
        sync_in_background, get_sessionmaker(), get_embedder(), "experience", experience_id
    )


@router.post("/reports/{report_id}/resolve", status_code=204)
def resolve_report(
    report_id: str,
    body: moderation.ResolveIn,
    user: StaffUser,
    db: DbSession,
    background: BackgroundTasks,
) -> Response:
    target = moderation.resolve_report(db, user, report_id, body)
    if body.action == "dismiss":
        _reindex(background, target)
    return Response(status_code=204)


@router.post("/experiences/{experience_id}/hide", status_code=204)
def hide_experience(experience_id: str, user: StaffUser, db: DbSession) -> Response:
    moderation.set_experience_visibility(db, user, experience_id, hidden=True)
    return Response(status_code=204)


@router.post("/experiences/{experience_id}/restore", status_code=204)
def restore_experience(
    experience_id: str, user: StaffUser, db: DbSession, background: BackgroundTasks
) -> Response:
    moderation.set_experience_visibility(db, user, experience_id, hidden=False)
    _reindex(background, experience_id)
    return Response(status_code=204)


@router.get("/stats")
def stats(
    _: StaffUser, db: DbSession, days: int = Query(default=30, ge=7, le=365)
) -> metrics.UsageStats:
    """Numbers for the MVP success signals (D-19)."""
    return metrics.usage_stats(db, days)


@router.get("/users")
def list_staff(_: AdminUser, db: DbSession) -> list[moderation.StaffMember]:
    """Reviewers and admins (account ids only), so an admin can see who has access."""
    return moderation.list_staff(db)


@router.put("/users/{user_id}/role", status_code=204)
def set_role(user_id: str, body: moderation.RoleIn, user: AdminUser, db: DbSession) -> Response:
    moderation.set_role(db, user, user_id, body)
    return Response(status_code=204)


# ---------- official documents for semantic search (A-21) ----------


class KbDocumentIn(BaseModel):
    title: str = Field(min_length=1, max_length=300)
    url: HttpUrl
    publisher: str = Field(min_length=1, max_length=200)
    document_date: date | None = None
    action_id: str | None = None
    text: str = Field(min_length=1, max_length=200_000)


class KbDocumentOut(BaseModel):
    id: str
    title: str
    url: str
    publisher: str
    document_date: date | None
    action_id: str | None
    active: bool
    chunk_count: int


def _kb_out(db, doc: KbDocument) -> KbDocumentOut:
    count = db.scalar(select(func.count()).where(KbChunk.document_id == doc.id)) or 0
    return KbDocumentOut(
        id=doc.id,
        title=doc.title,
        url=doc.url,
        publisher=doc.publisher,
        document_date=doc.document_date,
        action_id=doc.action_id,
        active=doc.active,
        chunk_count=count,
    )


@router.get("/kb/documents")
def list_documents(_: StaffUser, db: DbSession) -> list[KbDocumentOut]:
    docs = db.scalars(select(KbDocument).order_by(KbDocument.created_at.desc()))
    return [_kb_out(db, d) for d in docs]


@router.post("/kb/documents", status_code=201)
def create_document(body: KbDocumentIn, user: StaffUser, db: DbSession) -> KbDocumentOut:
    """Add an official document's text: it is chunked and embedded for the assistant."""
    try:
        doc = add_document(
            db,
            get_embedder(),
            title=body.title,
            url=str(body.url),
            publisher=body.publisher,
            document_date=body.document_date,
            action_id=body.action_id,
            text=body.text,
            created_by=user.id,
        )
    except EmbeddingUnavailable as exc:
        raise ApiError(503, "embeddings_unavailable") from exc
    except ValueError as exc:
        raise ApiError(422, "document_empty") from exc
    svc.log_admin(db, user, "add_kb_document", "kb_document", doc.id, url=doc.url)
    db.commit()
    return _kb_out(db, doc)


@router.post("/kb/documents/{document_id}/active", status_code=204)
def set_document_active(
    document_id: str, user: StaffUser, db: DbSession, active: bool = False
) -> Response:
    """Retire an outdated document (or bring it back); retired documents are never searched."""
    doc = db.get(KbDocument, document_id)
    if doc is None:
        raise not_found("document_not_found")
    doc.active = active
    svc.log_admin(db, user, "kb_document_active", "kb_document", doc.id, active=active)
    db.commit()
    return Response(status_code=204)
