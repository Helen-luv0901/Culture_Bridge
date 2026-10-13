"""Procedure editing for reviewers and admins (D-1, D-2, D-6).

Published versions are frozen by the database; changing a procedure means creating a new version,
editing that draft and publishing it. "verified" needs a reviewer's verification record against a
source attached to that version (also enforced by a trigger). Every write lands in admin_actions.
"""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, HttpUrl
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.auth import CurrentUser
from app.core.errors import ApiError, conflict, not_found
from app.models import (
    Action,
    ActionStep,
    ActionVersion,
    ActionVersionSource,
    ExecutionFeedback,
    Source,
    VerificationRecord,
)
from app.services.actions import FeedbackCategory, FeedbackKind, VerificationStatus
from app.services.common import Text2, log_admin, now, text2

SLUG = r"^[a-z0-9]+(-[a-z0-9]+)*$"


class StepIn(BaseModel):
    title_zh: str = Field(min_length=1, max_length=200)
    title_en: str = Field(min_length=1, max_length=200)
    notes: str | None = Field(default=None, max_length=2000)


class VersionContent(BaseModel):
    title_zh: str = Field(min_length=1, max_length=200)
    title_en: str = Field(min_length=1, max_length=200)
    description_zh: str = Field(default="", max_length=4000)
    description_en: str = Field(default="", max_length=4000)
    applicable_to: str = Field(min_length=1, max_length=500)
    applicable_to_en: str = Field(default="", max_length=500)
    location: str | None = Field(default=None, max_length=200)
    location_en: str | None = Field(default=None, max_length=200)
    steps: list[StepIn] = Field(default_factory=list, max_length=30)


class NewAction(VersionContent):
    slug: str = Field(pattern=SLUG, max_length=60)


class SourceIn(BaseModel):
    title: str = Field(min_length=1, max_length=300)
    url: HttpUrl
    publisher: str = Field(min_length=1, max_length=200)
    kind: Literal["official", "institution", "partner"]
    accessed_at: datetime


class AttachSource(BaseModel):
    evidence_note: str = Field(min_length=1, max_length=1000)


class VerificationIn(BaseModel):
    source_id: str
    decision: Literal["verified", "needs_review", "outdated"]
    note: str = Field(min_length=1, max_length=2000)


class StatusIn(BaseModel):
    # verified/needs_review/outdated go through a verification record instead.
    status: Literal["unverified", "community_supported"]


class AdminStep(BaseModel):
    id: str
    position: int
    title_zh: str
    title_en: str
    notes: str | None


class AdminSource(BaseModel):
    id: str
    title: str
    url: str
    publisher: str
    kind: str
    accessed_at: datetime
    evidence_note: str | None = None


class AdminVerification(BaseModel):
    id: str
    source_id: str
    reviewer_id: str
    decision: str
    note: str
    checked_at: datetime


class AdminVersion(BaseModel):
    id: str
    action_id: str
    version_number: int
    title_zh: str
    title_en: str
    description_zh: str
    description_en: str
    applicable_to: str
    applicable_to_en: str
    location: str | None
    location_en: str | None
    verification_status: VerificationStatus
    published_at: datetime | None
    created_at: datetime
    steps: list[AdminStep]
    sources: list[AdminSource]
    verifications: list[AdminVerification]


class AdminActionItem(BaseModel):
    id: str
    slug: str
    archived_at: datetime | None
    title: Text2
    latest_version_number: int
    latest_published_version_number: int | None
    has_draft: bool
    verification_status: VerificationStatus


class FeedbackItem(BaseModel):
    id: str
    action_id: str
    action_title: Text2
    version_number: int
    step_id: str | None
    step_title: Text2 | None
    kind: FeedbackKind
    category: FeedbackCategory | None
    original_voice: str | None
    review_state: Literal["pending", "reviewed", "dismissed"]
    created_at: datetime


class FeedbackReview(BaseModel):
    review_state: Literal["reviewed", "dismissed"]


# ---------- helpers ----------


def _version(db: Session, version_id: str) -> ActionVersion:
    v = db.get(ActionVersion, version_id)
    if v is None:
        raise not_found("version_not_found")
    return v


def _draft(db: Session, version_id: str) -> ActionVersion:
    v = _version(db, version_id)
    if v.published_at is not None:
        raise conflict("version_published", "Published versions are frozen; create a new version")
    return v


def _apply_content(v: ActionVersion, body: VersionContent) -> None:
    for field in (
        "title_zh",
        "title_en",
        "description_zh",
        "description_en",
        "applicable_to",
        "applicable_to_en",
        "location",
        "location_en",
    ):
        setattr(v, field, getattr(body, field))


def _replace_steps(db: Session, v: ActionVersion, steps: list[StepIn]) -> None:
    for old in db.scalars(select(ActionStep).where(ActionStep.action_version_id == v.id)):
        db.delete(old)
    db.flush()
    for position, step in enumerate(steps, 1):
        db.add(
            ActionStep(
                action_version_id=v.id,
                position=position,
                title_zh=step.title_zh,
                title_en=step.title_en,
                notes=step.notes,
            )
        )


def version_out(db: Session, v: ActionVersion) -> AdminVersion:
    steps = db.scalars(
        select(ActionStep).where(ActionStep.action_version_id == v.id).order_by(ActionStep.position)
    )
    sources = db.execute(
        select(Source, ActionVersionSource.evidence_note)
        .join(ActionVersionSource, ActionVersionSource.source_id == Source.id)
        .where(ActionVersionSource.action_version_id == v.id)
    )
    records = db.scalars(
        select(VerificationRecord)
        .where(VerificationRecord.action_version_id == v.id)
        .order_by(VerificationRecord.checked_at.desc())
    )
    return AdminVersion(
        id=v.id,
        action_id=v.action_id,
        version_number=v.version_number,
        title_zh=v.title_zh,
        title_en=v.title_en,
        description_zh=v.description_zh,
        description_en=v.description_en,
        applicable_to=v.applicable_to,
        applicable_to_en=v.applicable_to_en,
        location=v.location,
        location_en=v.location_en,
        verification_status=v.verification_status,  # type: ignore[arg-type]
        published_at=v.published_at,
        created_at=v.created_at,
        steps=[
            AdminStep(
                id=s.id,
                position=s.position,
                title_zh=s.title_zh,
                title_en=s.title_en,
                notes=s.notes,
            )
            for s in steps
        ],
        sources=[
            AdminSource(
                id=s.id,
                title=s.title,
                url=s.url,
                publisher=s.publisher,
                kind=s.kind,
                accessed_at=s.accessed_at,
                evidence_note=note,
            )
            for s, note in sources
        ],
        verifications=[
            AdminVerification(
                id=r.id,
                source_id=r.source_id,
                reviewer_id=r.reviewer_id,
                decision=r.decision,
                note=r.note,
                checked_at=r.checked_at,
            )
            for r in records
        ],
    )


# ---------- actions and versions ----------


def list_admin_actions(db: Session) -> list[AdminActionItem]:
    items = []
    for action in db.scalars(select(Action).order_by(Action.slug)):
        versions = list(
            db.scalars(
                select(ActionVersion)
                .where(ActionVersion.action_id == action.id)
                .order_by(ActionVersion.version_number.desc())
            )
        )
        if not versions:
            continue
        latest = versions[0]
        published = next((v for v in versions if v.published_at is not None), None)
        shown = published or latest
        items.append(
            AdminActionItem(
                id=action.id,
                slug=action.slug,
                archived_at=action.archived_at,
                title=text2(shown.title_zh, shown.title_en),
                latest_version_number=latest.version_number,
                latest_published_version_number=published.version_number if published else None,
                has_draft=latest.published_at is None,
                verification_status=shown.verification_status,  # type: ignore[arg-type]
            )
        )
    return items


def list_versions(db: Session, action_id: str) -> list[AdminVersion]:
    if db.get(Action, action_id) is None:
        raise not_found("action_not_found")
    versions = db.scalars(
        select(ActionVersion)
        .where(ActionVersion.action_id == action_id)
        .order_by(ActionVersion.version_number.desc())
    )
    return [version_out(db, v) for v in versions]


def create_action(db: Session, actor: CurrentUser, body: NewAction) -> AdminVersion:
    action = Action(id=body.slug, slug=body.slug)
    db.add(action)
    try:
        db.flush()
    except IntegrityError as exc:
        db.rollback()
        raise conflict("slug_taken") from exc
    v = ActionVersion(action_id=action.id, version_number=1, created_by=actor.id, applicable_to="")
    _apply_content(v, body)
    db.add(v)
    db.flush()
    _replace_steps(db, v, body.steps)
    log_admin(db, actor, "create_action", "action", action.id, slug=body.slug)
    db.commit()
    return version_out(db, v)


def create_version(db: Session, actor: CurrentUser, action_id: str) -> AdminVersion:
    """Start a new draft copied from the newest version (content, steps and sources)."""
    if db.get(Action, action_id) is None:
        raise not_found("action_not_found")
    base = db.scalar(
        select(ActionVersion)
        .where(ActionVersion.action_id == action_id)
        .order_by(ActionVersion.version_number.desc())
    )
    assert base is not None
    if base.published_at is None:
        raise conflict("draft_exists", f"Version {base.version_number} is still a draft")
    v = ActionVersion(
        action_id=action_id,
        version_number=base.version_number + 1,
        created_by=actor.id,
        title_zh=base.title_zh,
        title_en=base.title_en,
        description_zh=base.description_zh,
        description_en=base.description_en,
        applicable_to=base.applicable_to,
        applicable_to_en=base.applicable_to_en,
        institution_id=base.institution_id,
        location=base.location,
        location_en=base.location_en,
    )
    db.add(v)
    db.flush()
    for step in db.scalars(
        select(ActionStep)
        .where(ActionStep.action_version_id == base.id)
        .order_by(ActionStep.position)
    ):
        db.add(
            ActionStep(
                action_version_id=v.id,
                position=step.position,
                title_zh=step.title_zh,
                title_en=step.title_en,
                notes=step.notes,
            )
        )
    for link in db.scalars(
        select(ActionVersionSource).where(ActionVersionSource.action_version_id == base.id)
    ):
        db.add(
            ActionVersionSource(
                action_version_id=v.id, source_id=link.source_id, evidence_note=link.evidence_note
            )
        )
    log_admin(db, actor, "create_version", "action_version", v.id, based_on=base.id)
    db.commit()
    return version_out(db, v)


def update_draft(
    db: Session, actor: CurrentUser, version_id: str, body: VersionContent
) -> AdminVersion:
    v = _draft(db, version_id)
    _apply_content(v, body)
    _replace_steps(db, v, body.steps)
    log_admin(db, actor, "update_draft", "action_version", v.id)
    db.commit()
    return version_out(db, v)


def publish_version(db: Session, actor: CurrentUser, version_id: str) -> AdminVersion:
    v = _draft(db, version_id)
    if not db.scalar(select(func.count()).where(ActionStep.action_version_id == v.id)):
        raise ApiError(422, "steps_required")
    if not v.applicable_to.strip():
        raise ApiError(422, "applicable_to_required")
    v.published_at = now()
    log_admin(db, actor, "publish_version", "action_version", v.id)
    db.commit()
    return version_out(db, v)


def archive_action(db: Session, actor: CurrentUser, action_id: str, archived: bool) -> None:
    action = db.get(Action, action_id)
    if action is None:
        raise not_found("action_not_found")
    action.archived_at = now() if archived else None
    log_admin(db, actor, "archive" if archived else "unarchive", "action", action_id)
    db.commit()


# ---------- sources and verification ----------


def list_sources(db: Session) -> list[AdminSource]:
    return [
        AdminSource(
            id=s.id,
            title=s.title,
            url=s.url,
            publisher=s.publisher,
            kind=s.kind,
            accessed_at=s.accessed_at,
        )
        for s in db.scalars(select(Source).order_by(Source.title))
    ]


def create_source(db: Session, actor: CurrentUser, body: SourceIn) -> AdminSource:
    source = Source(
        title=body.title,
        url=str(body.url),
        publisher=body.publisher,
        kind=body.kind,
        accessed_at=body.accessed_at,
    )
    db.add(source)
    db.flush()
    log_admin(db, actor, "create_source", "source", source.id, url=source.url)
    db.commit()
    return AdminSource(
        id=source.id,
        title=source.title,
        url=source.url,
        publisher=source.publisher,
        kind=source.kind,
        accessed_at=source.accessed_at,
    )


def attach_source(
    db: Session, actor: CurrentUser, version_id: str, source_id: str, body: AttachSource
) -> AdminVersion:
    v = _draft(db, version_id)
    if db.get(Source, source_id) is None:
        raise not_found("source_not_found")
    link = db.get(ActionVersionSource, (v.id, source_id))
    if link:
        link.evidence_note = body.evidence_note
    else:
        db.add(
            ActionVersionSource(
                action_version_id=v.id, source_id=source_id, evidence_note=body.evidence_note
            )
        )
    log_admin(db, actor, "attach_source", "action_version", v.id, source_id=source_id)
    db.commit()
    return version_out(db, v)


def detach_source(db: Session, actor: CurrentUser, version_id: str, source_id: str) -> AdminVersion:
    v = _draft(db, version_id)
    link = db.get(ActionVersionSource, (v.id, source_id))
    if link is None:
        raise not_found("source_not_attached")
    db.delete(link)
    log_admin(db, actor, "detach_source", "action_version", v.id, source_id=source_id)
    db.commit()
    return version_out(db, v)


def record_verification(
    db: Session, actor: CurrentUser, version_id: str, body: VerificationIn
) -> AdminVersion:
    """A reviewer checks a version against one of its sources; the status follows the decision."""
    v = _version(db, version_id)
    if db.get(ActionVersionSource, (v.id, body.source_id)) is None:
        raise ApiError(422, "source_not_attached")
    db.add(
        VerificationRecord(
            action_version_id=v.id,
            source_id=body.source_id,
            reviewer_id=actor.id,
            decision=body.decision,
            note=body.note,
        )
    )
    db.flush()
    v.verification_status = body.decision
    log_admin(
        db,
        actor,
        "verify",
        "action_version",
        v.id,
        decision=body.decision,
        source_id=body.source_id,
    )
    db.commit()
    return version_out(db, v)


def set_status(db: Session, actor: CurrentUser, version_id: str, body: StatusIn) -> AdminVersion:
    v = _version(db, version_id)
    v.verification_status = body.status
    log_admin(db, actor, "set_status", "action_version", v.id, status=body.status)
    db.commit()
    return version_out(db, v)


# ---------- feedback review queue (D-6, C-15) ----------


def list_feedback(db: Session, state: str, limit: int, offset: int) -> list[FeedbackItem]:
    rows = db.execute(
        select(ExecutionFeedback, ActionVersion, ActionStep)
        .join(ActionVersion, ActionVersion.id == ExecutionFeedback.action_version_id)
        .outerjoin(ActionStep, ActionStep.id == ExecutionFeedback.step_id)
        .where(ExecutionFeedback.review_state == state)
        .order_by(ExecutionFeedback.created_at.desc())
        .limit(limit)
        .offset(offset)
    )
    return [
        FeedbackItem(
            id=f.id,
            action_id=v.action_id,
            action_title=text2(v.title_zh, v.title_en),
            version_number=v.version_number,
            step_id=f.step_id,
            step_title=text2(s.title_zh, s.title_en) if s else None,
            kind=f.kind,  # type: ignore[arg-type]
            category=f.category,  # type: ignore[arg-type]
            original_voice=f.original_voice,
            review_state=f.review_state,  # type: ignore[arg-type]
            created_at=f.created_at,
        )
        for f, v, s in rows
    ]


def review_feedback(
    db: Session, actor: CurrentUser, feedback_id: str, body: FeedbackReview
) -> None:
    feedback = db.get(ExecutionFeedback, feedback_id)
    if feedback is None:
        raise not_found("feedback_not_found")
    feedback.review_state = body.review_state
    log_admin(
        db, actor, "review_feedback", "execution_feedback", feedback_id, state=body.review_state
    )
    db.commit()
