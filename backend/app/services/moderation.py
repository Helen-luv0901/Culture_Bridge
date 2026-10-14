"""Reports, blocks, moderation and account deletion (B-17..B-19, Google Play UGC policy).

Authors are anonymous, so people block "the author of this experience" and see opaque block ids;
nothing here lets anyone link experiences to an account.
"""

import hashlib
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field
from sqlalchemy import delete, func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.auth import CurrentUser
from app.core.errors import ApiError, conflict, forbidden, not_found
from app.models import (
    ActionVersion,
    AssistantOperation,
    Execution,
    ExecutionFeedback,
    ExecutionStep,
    Experience,
    ExperienceReaction,
    ExperienceSummary,
    Report,
    SavedExperience,
    User,
    UserBlock,
    VerificationRecord,
)
from app.rag.index import remove_content
from app.services.common import log_admin, now
from app.services.experiences import delete_experiences
from app.services.metrics import forget_activity

ReportReason = Literal[
    "spam", "harassment", "hate", "sexual", "personal_info", "misinformation", "other"
]
AUTO_HIDE_REPORTS = 3  # distinct reporters before an experience is hidden pending review
DELETED_STAFF = "deleted-staff"


class ReportIn(BaseModel):
    experience_id: str
    reason: ReportReason
    note: str | None = Field(default=None, max_length=1000)


class ReportAck(BaseModel):
    id: str
    status: Literal["pending", "actioned", "dismissed"]


class BlockOut(BaseModel):
    id: str
    created_at: datetime


class ReportedItem(BaseModel):
    report_id: str  # newest pending report; resolving it resolves all reports on the target
    target_type: Literal["experience"]
    target_id: str
    target_status: Literal["draft", "published", "hidden"] | None
    original_voice: str | None
    reasons: dict[str, int]
    notes: list[str]
    report_count: int
    first_reported_at: datetime


class ResolveIn(BaseModel):
    # hide: take the experience down; dismiss: reports were unfounded (restores if auto-hidden)
    action: Literal["hide", "dismiss"]


class RoleIn(BaseModel):
    role: Literal["student", "reviewer", "admin"]


class StaffMember(BaseModel):
    id: str
    role: Literal["reviewer", "admin"]
    created_at: datetime


# ---------- reports ----------


def report_experience(db: Session, user: CurrentUser, body: ReportIn) -> ReportAck:
    experience = db.get(Experience, body.experience_id)
    if experience is None or experience.status == "draft":
        raise not_found("experience_not_found")
    if experience.author_id == user.id:
        raise ApiError(422, "cannot_report_own")
    report = Report(
        reporter_id=user.id,
        target_type="experience",
        target_id=experience.id,
        reason=body.reason,
        note=(body.note or "").strip() or None,
    )
    db.add(report)
    try:
        db.flush()
    except IntegrityError as exc:
        db.rollback()
        raise conflict("already_reported") from exc
    pending = db.scalar(
        select(func.count()).where(
            Report.target_type == "experience",
            Report.target_id == experience.id,
            Report.status == "pending",
        )
    )
    if experience.status == "published" and (pending or 0) >= AUTO_HIDE_REPORTS:
        experience.status = "hidden"
        remove_content(db, "experience", [experience.id])
    db.commit()
    return ReportAck(id=report.id, status="pending")


def report_queue(db: Session, status: str) -> list[ReportedItem]:
    reports = list(
        db.scalars(
            select(Report)
            .where(Report.status == status, Report.target_type == "experience")
            .order_by(Report.created_at)
        )
    )
    grouped: dict[str, list[Report]] = {}
    for r in reports:
        grouped.setdefault(r.target_id, []).append(r)
    items = []
    for target_id, group in grouped.items():
        experience = db.get(Experience, target_id)
        reasons: dict[str, int] = {}
        for r in group:
            reasons[r.reason] = reasons.get(r.reason, 0) + 1
        items.append(
            ReportedItem(
                report_id=group[-1].id,
                target_type="experience",
                target_id=target_id,
                target_status=experience.status if experience else None,  # type: ignore[arg-type]
                original_voice=experience.original_voice if experience else None,
                reasons=reasons,
                notes=[r.note for r in group if r.note],
                report_count=len(group),
                first_reported_at=group[0].created_at,
            )
        )
    return items


def resolve_report(db: Session, actor: CurrentUser, report_id: str, body: ResolveIn) -> str:
    report = db.get(Report, report_id)
    if report is None:
        raise not_found("report_not_found")
    experience = db.get(Experience, report.target_id)
    if experience is not None:
        if body.action == "hide":
            experience.status = "hidden"
            remove_content(db, "experience", [experience.id])
        elif experience.status == "hidden":
            experience.status = "published"
    db.execute(
        update(Report)
        .where(
            Report.target_type == report.target_type,
            Report.target_id == report.target_id,
            Report.status == "pending",
        )
        .values(
            status="actioned" if body.action == "hide" else "dismissed",
            resolved_by=actor.id,
            resolved_at=now(),
        )
    )
    log_admin(db, actor, f"report_{body.action}", report.target_type, report.target_id)
    db.commit()
    return report.target_id


def set_experience_visibility(
    db: Session, actor: CurrentUser, experience_id: str, hidden: bool
) -> None:
    experience = db.get(Experience, experience_id)
    if experience is None or experience.status == "draft":
        raise not_found("experience_not_found")
    experience.status = "hidden" if hidden else "published"
    if hidden:
        remove_content(db, "experience", [experience.id])
    log_admin(db, actor, "hide" if hidden else "restore", "experience", experience_id)
    db.commit()


# ---------- blocks ----------


def _block_id(blocker_id: str, blocked_id: str) -> str:
    return hashlib.sha256(f"{blocker_id}:{blocked_id}".encode()).hexdigest()[:20]


def block_author(db: Session, user: CurrentUser, experience_id: str) -> BlockOut:
    experience = db.get(Experience, experience_id)
    if experience is None or experience.status == "draft":
        raise not_found("experience_not_found")
    if experience.author_id == user.id:
        raise ApiError(422, "cannot_block_self")
    block = db.get(UserBlock, (user.id, experience.author_id))
    if block is None:
        block = UserBlock(blocker_id=user.id, blocked_id=experience.author_id)
        db.add(block)
        db.commit()
    return BlockOut(id=_block_id(user.id, experience.author_id), created_at=block.created_at)


def my_blocks(db: Session, user: CurrentUser) -> list[BlockOut]:
    return [
        BlockOut(id=_block_id(b.blocker_id, b.blocked_id), created_at=b.created_at)
        for b in db.scalars(
            select(UserBlock)
            .where(UserBlock.blocker_id == user.id)
            .order_by(UserBlock.created_at.desc())
        )
    ]


def unblock(db: Session, user: CurrentUser, block_id: str) -> None:
    for b in db.scalars(select(UserBlock).where(UserBlock.blocker_id == user.id)):
        if _block_id(b.blocker_id, b.blocked_id) == block_id:
            db.delete(b)
            db.commit()
            return
    raise not_found("block_not_found")


# ---------- roles ----------


def list_staff(db: Session) -> list[StaffMember]:
    rows = db.scalars(
        select(User).where(User.role.in_(["reviewer", "admin"])).order_by(User.created_at)
    )
    return [StaffMember(id=u.id, role=u.role, created_at=u.created_at) for u in rows]  # type: ignore[arg-type]


def set_role(db: Session, actor: CurrentUser, user_id: str, body: RoleIn) -> None:
    if user_id == actor.id and body.role != "admin":
        raise forbidden("cannot_demote_self")
    target = db.get(User, user_id)
    if target is None:
        raise not_found("user_not_found")
    target.role = body.role
    log_admin(db, actor, "set_role", "user", user_id, role=body.role)
    db.commit()


# ---------- account deletion (B-17) ----------


def _deleted_staff(db: Session) -> str:
    if db.get(User, DELETED_STAFF) is None:
        db.add(User(id=DELETED_STAFF, auth_subject=f"system:{DELETED_STAFF}", role="student"))
        db.flush()
    return DELETED_STAFF


def delete_account(db: Session, user: CurrentUser) -> None:
    """Delete the account and everything the person wrote or did.

    Reviewer evidence (verification records, versions they created) must survive for the
    published procedures to stay verifiable, so it is reassigned to a placeholder account.
    """
    uid = user.id
    delete_experiences(
        db, list(db.scalars(select(Experience.id).where(Experience.author_id == uid)))
    )
    db.execute(delete(ExperienceReaction).where(ExperienceReaction.user_id == uid))
    db.execute(delete(SavedExperience).where(SavedExperience.user_id == uid))
    # Summaries they confirmed belong to their own experiences, already removed above.
    db.execute(delete(ExperienceSummary).where(ExperienceSummary.confirmed_by == uid))
    executions = list(db.scalars(select(Execution.id).where(Execution.user_id == uid)))
    if executions:
        feedback_ids = list(
            db.scalars(
                select(ExecutionFeedback.id).where(ExecutionFeedback.execution_id.in_(executions))
            )
        )
        remove_content(db, "execution_feedback", feedback_ids)
        db.execute(delete(ExecutionFeedback).where(ExecutionFeedback.execution_id.in_(executions)))
        db.execute(delete(ExecutionStep).where(ExecutionStep.execution_id.in_(executions)))
        db.execute(delete(Execution).where(Execution.id.in_(executions)))
    staff_rows = db.scalar(
        select(func.count())
        .select_from(VerificationRecord)
        .where(VerificationRecord.reviewer_id == uid)
    ) or db.scalar(
        select(func.count()).select_from(ActionVersion).where(ActionVersion.created_by == uid)
    )
    if staff_rows:
        placeholder = _deleted_staff(db)
        db.execute(
            update(VerificationRecord)
            .where(VerificationRecord.reviewer_id == uid)
            .values(reviewer_id=placeholder)
        )
        db.execute(
            update(ActionVersion)
            .where(ActionVersion.created_by == uid)
            .values(created_by=placeholder)
        )
    # reports, blocks and assistant operations cascade; admin_actions keep a NULL actor.
    db.execute(delete(AssistantOperation).where(AssistantOperation.user_id == uid))
    db.execute(delete(User).where(User.id == uid))
    db.commit()
    forget_activity(uid)
