"""Reports on AI assistant answers (store rule: people can flag AI-generated content).

Conversations live only in server memory, so a report carries its own copy of the question and
the answer. Staff read the queue newest first and mark reports resolved; reports are deleted
with the reporter's account.
"""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.auth import CurrentUser
from app.core.errors import ApiError, not_found
from app.models import AssistantReport
from app.services.common import DailyAllowance, log_admin, now

Reason = Literal["inaccurate", "offensive", "harmful", "other"]
Status = Literal["open", "resolved"]
MAX_REPORTS_PER_DAY = 20  # per reporter
QUEUE_LIMIT = 100
_new_reports = DailyAllowance("assistant-reports")


def _blank_is_none(value: str | None) -> str | None:
    return (value or "").strip() or None


class AssistantReportIn(BaseModel):
    conversation_id: str | None = Field(default=None, max_length=100)
    question: str = Field(min_length=1, max_length=1000)
    answer: str = Field(min_length=1, max_length=4000)
    reason: Reason
    details: str | None = Field(default=None, max_length=1000)

    _details = field_validator("details", "conversation_id")(_blank_is_none)


class AssistantReportCreated(BaseModel):
    id: str


class AssistantReportItem(BaseModel):
    id: str
    conversation_id: str | None
    question: str
    answer: str
    reason: Reason
    details: str | None
    created_at: datetime
    status: Status


class ResolveAssistantReport(BaseModel):
    note: str | None = Field(default=None, max_length=1000)


def report_answer(
    db: Session, user: CurrentUser, body: AssistantReportIn
) -> AssistantReportCreated:
    if not _new_reports.take(user.id, MAX_REPORTS_PER_DAY):
        raise ApiError(429, "daily_limit_reached")
    report = AssistantReport(
        reporter_id=user.id,
        conversation_id=body.conversation_id,
        question=body.question,
        answer=body.answer,
        reason=body.reason,
        details=body.details,
    )
    db.add(report)
    db.commit()
    return AssistantReportCreated(id=report.id)


def queue(db: Session, status: Status) -> list[AssistantReportItem]:
    rows = db.scalars(
        select(AssistantReport)
        .where(AssistantReport.status == status)
        .order_by(AssistantReport.created_at.desc(), AssistantReport.id)
        .limit(QUEUE_LIMIT)
    )
    return [
        AssistantReportItem(
            id=r.id,
            conversation_id=r.conversation_id,
            question=r.question,
            answer=r.answer,
            reason=r.reason,  # type: ignore[arg-type]
            details=r.details,
            created_at=r.created_at,
            status=r.status,  # type: ignore[arg-type]
        )
        for r in rows
    ]


def resolve(db: Session, actor: CurrentUser, report_id: str, body: ResolveAssistantReport) -> None:
    report = db.get(AssistantReport, report_id)
    if report is None:
        raise not_found("report_not_found")
    if report.status != "resolved":
        report.status = "resolved"
        report.resolution_note = (body.note or "").strip() or None
        report.resolved_by = actor.id
        report.resolved_at = now()
        log_admin(db, actor, "resolve", "assistant_report", report.id)
        db.commit()
