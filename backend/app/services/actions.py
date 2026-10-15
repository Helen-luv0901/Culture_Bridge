"""Procedures for students (D-1..5): latest published versions, executions, progress, feedback."""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field
from sqlalchemy import and_, exists, func, or_, select
from sqlalchemy.orm import Session

from app.core.auth import CurrentUser
from app.core.errors import ApiError, conflict, not_found
from app.models import (
    Action,
    ActionStep,
    ActionVersion,
    ActionVersionSource,
    Execution,
    ExecutionFeedback,
    ExecutionStep,
    Source,
    VerificationRecord,
)
from app.services.common import RECENT_WINDOW, Text2, now, text2

VerificationStatus = Literal[
    "unverified", "community_supported", "needs_review", "verified", "outdated"
]
IdentityType = Literal["degree_student", "exchange_student", "language_student", "other"]
StepState = Literal["pending", "done", "stuck"]
Outcome = Literal["success", "failed", "different", "abandoned"]
FeedbackKind = Literal["stuck", "different", "possibly_outdated"]
FeedbackCategory = Literal[
    "documents", "fee", "location", "process", "eligibility", "website", "other"
]


# ---------- response models ----------


class ActionSummary(BaseModel):
    id: str
    slug: str
    version_id: str
    version_number: int
    title: Text2
    description: Text2
    applicable_to: Text2
    location: Text2 | None
    verification_status: VerificationStatus
    last_verified_at: datetime | None
    published_at: datetime
    recent_success_count: int


class StepOut(BaseModel):
    id: str
    position: int
    title: Text2
    notes: str | None
    recent_stuck_count: int


class SourceOut(BaseModel):
    id: str
    title: str
    url: str
    publisher: str
    kind: Literal["official", "institution", "partner"]
    evidence_note: str
    accessed_at: datetime


class ActionDetail(ActionSummary):
    steps: list[StepOut]
    sources: list[SourceOut]
    # "What to bring", ticked off by the student before going.
    documents: list[Text2] = []


class ExecutionStepOut(BaseModel):
    step_id: str
    position: int
    title: Text2
    state: StepState


class ExecutionOut(BaseModel):
    id: str
    action_id: str
    action_version_id: str
    version_number: int
    title: Text2
    identity_type: IdentityType
    started_at: datetime
    finished_at: datetime | None
    outcome: Outcome | None
    steps: list[ExecutionStepOut]
    # True when a newer version was published after this attempt started.
    newer_version_available: bool


class StartExecution(BaseModel):
    identity_type: IdentityType = "other"


class StepUpdate(BaseModel):
    state: StepState


class FinishExecution(BaseModel):
    outcome: Outcome


class FeedbackIn(BaseModel):
    kind: FeedbackKind
    step_id: str | None = None
    category: FeedbackCategory | None = None
    original_voice: str | None = Field(default=None, max_length=2000)


class FeedbackOut(BaseModel):
    id: str
    kind: FeedbackKind
    step_id: str | None
    category: FeedbackCategory | None
    review_state: Literal["pending", "reviewed", "dismissed"]
    created_at: datetime


# ---------- queries ----------


def _latest_published(db: Session):
    """(Action, ActionVersion) rows for the latest published version of each live action."""
    newest = (
        select(ActionVersion.action_id, func.max(ActionVersion.version_number).label("n"))
        .where(ActionVersion.published_at.is_not(None))
        .group_by(ActionVersion.action_id)
        .subquery()
    )
    return (
        select(Action, ActionVersion)
        .join(ActionVersion, ActionVersion.action_id == Action.id)
        .join(
            newest,
            and_(
                newest.c.action_id == ActionVersion.action_id,
                newest.c.n == ActionVersion.version_number,
            ),
        )
        .where(Action.archived_at.is_(None))
    )


def _recent_successes(db: Session, action_ids: list[str]) -> dict[str, int]:
    if not action_ids:
        return {}
    rows = db.execute(
        select(ActionVersion.action_id, func.count(Execution.id))
        .join(Execution, Execution.action_version_id == ActionVersion.id)
        .where(
            ActionVersion.action_id.in_(action_ids),
            Execution.outcome == "success",
            Execution.finished_at >= now() - RECENT_WINDOW,
        )
        .group_by(ActionVersion.action_id)
    )
    return dict(rows.all())


def _last_verified(db: Session, version_ids: list[str]) -> dict[str, datetime]:
    if not version_ids:
        return {}
    rows = db.execute(
        select(VerificationRecord.action_version_id, func.max(VerificationRecord.checked_at))
        .where(
            VerificationRecord.action_version_id.in_(version_ids),
            VerificationRecord.decision == "verified",
        )
        .group_by(VerificationRecord.action_version_id)
    )
    return dict(rows.all())


def _summary(
    action: Action, v: ActionVersion, successes: dict[str, int], verified: dict[str, datetime]
) -> ActionSummary:
    assert v.published_at is not None
    return ActionSummary(
        id=action.id,
        slug=action.slug,
        version_id=v.id,
        version_number=v.version_number,
        title=text2(v.title_zh, v.title_en),
        description=text2(v.description_zh, v.description_en),
        applicable_to=text2(v.applicable_to, v.applicable_to_en),
        location=text2(v.location, v.location_en) if v.location else None,
        verification_status=v.verification_status,  # type: ignore[arg-type]
        # A verified date only means something while the status still says verified.
        last_verified_at=verified.get(v.id) if v.verification_status == "verified" else None,
        published_at=v.published_at,
        recent_success_count=successes.get(action.id, 0),
    )


def list_actions(db: Session) -> list[ActionSummary]:
    rows = db.execute(_latest_published(db).order_by(ActionVersion.title_zh)).all()
    successes = _recent_successes(db, [a.id for a, _ in rows])
    verified = _last_verified(db, [v.id for _, v in rows])
    return [_summary(a, v, successes, verified) for a, v in rows]


def search_actions(db: Session, q: str, limit: int) -> list[ActionSummary]:
    """Keyword search over the latest published versions, both languages and step titles."""
    query = _latest_published(db)
    for word in q.split()[:8]:
        pattern = f"%{word.replace('%', '').replace('_', '')}%"
        in_steps = exists().where(
            ActionStep.action_version_id == ActionVersion.id,
            or_(ActionStep.title_zh.ilike(pattern), ActionStep.title_en.ilike(pattern)),
        )
        query = query.where(
            or_(
                ActionVersion.title_zh.ilike(pattern),
                ActionVersion.title_en.ilike(pattern),
                ActionVersion.description_zh.ilike(pattern),
                ActionVersion.description_en.ilike(pattern),
                Action.slug.ilike(pattern),
                in_steps,
            )
        )
    rows = db.execute(query.order_by(ActionVersion.title_zh).limit(limit)).all()
    successes = _recent_successes(db, [a.id for a, _ in rows])
    verified = _last_verified(db, [v.id for _, v in rows])
    return [_summary(a, v, successes, verified) for a, v in rows]


def latest_version(db: Session, action_id: str) -> tuple[Action, ActionVersion]:
    row = db.execute(_latest_published(db).where(Action.id == action_id)).first()
    if row is None:
        raise not_found("action_not_found")
    return row


def _steps(db: Session, version_id: str) -> list[ActionStep]:
    return list(
        db.scalars(
            select(ActionStep)
            .where(ActionStep.action_version_id == version_id)
            .order_by(ActionStep.position)
        )
    )


def get_action(db: Session, action_id: str) -> ActionDetail:
    action, v = latest_version(db, action_id)
    summary = _summary(action, v, _recent_successes(db, [action.id]), _last_verified(db, [v.id]))
    stuck = dict(
        db.execute(
            select(ExecutionFeedback.step_id, func.count())
            .where(
                ExecutionFeedback.action_version_id == v.id,
                ExecutionFeedback.kind == "stuck",
                ExecutionFeedback.created_at >= now() - RECENT_WINDOW,
            )
            .group_by(ExecutionFeedback.step_id)
        ).all()
    )
    sources = db.execute(
        select(Source, ActionVersionSource.evidence_note)
        .join(ActionVersionSource, ActionVersionSource.source_id == Source.id)
        .where(ActionVersionSource.action_version_id == v.id)
        .order_by(Source.title)
    )
    return ActionDetail(
        **summary.model_dump(),
        steps=[
            StepOut(
                id=s.id,
                position=s.position,
                title=text2(s.title_zh, s.title_en),
                notes=s.notes,
                recent_stuck_count=stuck.get(s.id, 0),
            )
            for s in _steps(db, v.id)
        ],
        sources=[
            SourceOut(
                id=s.id,
                title=s.title,
                url=s.url,
                publisher=s.publisher,
                kind=s.kind,  # type: ignore[arg-type]
                evidence_note=note,
                accessed_at=s.accessed_at,
            )
            for s, note in sources
        ],
        documents=[text2(d.get("zh"), d.get("en")) for d in v.documents or []],
    )


# ---------- executions ----------


def _own_execution(db: Session, user: CurrentUser, execution_id: str) -> Execution:
    execution = db.get(Execution, execution_id)
    if execution is None or execution.user_id != user.id:
        raise not_found("execution_not_found")
    return execution


def _execution_out(db: Session, execution: Execution) -> ExecutionOut:
    v = db.get(ActionVersion, execution.action_version_id)
    assert v is not None
    states = dict(
        db.execute(
            select(ExecutionStep.step_id, ExecutionStep.state).where(
                ExecutionStep.execution_id == execution.id
            )
        ).all()
    )
    newest = db.scalar(
        select(func.max(ActionVersion.version_number)).where(
            ActionVersion.action_id == v.action_id, ActionVersion.published_at.is_not(None)
        )
    )
    return ExecutionOut(
        id=execution.id,
        action_id=v.action_id,
        action_version_id=v.id,
        version_number=v.version_number,
        title=text2(v.title_zh, v.title_en),
        identity_type=execution.identity_type,  # type: ignore[arg-type]
        started_at=execution.started_at,
        finished_at=execution.finished_at,
        outcome=execution.outcome,  # type: ignore[arg-type]
        steps=[
            ExecutionStepOut(
                step_id=s.id,
                position=s.position,
                title=text2(s.title_zh, s.title_en),
                state=states.get(s.id, "pending"),  # type: ignore[arg-type]
            )
            for s in _steps(db, v.id)
        ],
        newer_version_available=(newest or 0) > v.version_number,
    )


def open_execution(db: Session, user_id: str, action_id: str) -> Execution | None:
    return db.scalar(
        select(Execution)
        .join(ActionVersion, ActionVersion.id == Execution.action_version_id)
        .where(
            Execution.user_id == user_id,
            ActionVersion.action_id == action_id,
            Execution.finished_at.is_(None),
        )
        .order_by(Execution.started_at.desc())
    )


def start_execution(
    db: Session, user: CurrentUser, action_id: str, identity_type: str = "other"
) -> tuple[ExecutionOut, bool]:
    """Start the latest published version, or return the attempt already in progress."""
    existing = open_execution(db, user.id, action_id)
    if existing:
        return _execution_out(db, existing), False
    _, v = latest_version(db, action_id)
    execution = Execution(user_id=user.id, action_version_id=v.id, identity_type=identity_type)
    db.add(execution)
    db.flush()
    for step in _steps(db, v.id):
        db.add(ExecutionStep(execution_id=execution.id, action_version_id=v.id, step_id=step.id))
    db.commit()
    return _execution_out(db, execution), True


def my_executions(db: Session, user: CurrentUser, include_finished: bool) -> list[ExecutionOut]:
    query = select(Execution).where(Execution.user_id == user.id)
    if not include_finished:
        query = query.where(Execution.finished_at.is_(None))
    executions = db.scalars(query.order_by(Execution.started_at.desc()))
    return [_execution_out(db, e) for e in executions]


def get_execution(db: Session, user: CurrentUser, execution_id: str) -> ExecutionOut:
    return _execution_out(db, _own_execution(db, user, execution_id))


def _open(db: Session, user: CurrentUser, execution_id: str) -> Execution:
    execution = _own_execution(db, user, execution_id)
    if execution.finished_at is not None:
        raise conflict("execution_finished")
    return execution


def set_step(
    db: Session, user: CurrentUser, execution_id: str, step_id: str, state: str
) -> ExecutionOut:
    execution = _open(db, user, execution_id)
    step = db.get(ExecutionStep, (execution.id, step_id))
    if step is None:
        raise not_found("step_not_found")
    step.state = state
    step.updated_at = now()
    db.commit()
    return _execution_out(db, execution)


def finish_execution(
    db: Session, user: CurrentUser, execution_id: str, outcome: str
) -> ExecutionOut:
    execution = _open(db, user, execution_id)
    execution.outcome = outcome
    execution.finished_at = now()
    db.commit()
    return _execution_out(db, execution)


def add_feedback(
    db: Session, user: CurrentUser, execution_id: str, body: FeedbackIn
) -> FeedbackOut:
    execution = _own_execution(db, user, execution_id)
    if body.kind == "stuck" and not body.step_id:
        raise ApiError(422, "step_required")
    if body.step_id:
        step = db.get(ActionStep, body.step_id)
        if step is None or step.action_version_id != execution.action_version_id:
            raise not_found("step_not_found")
    voice = (body.original_voice or "").strip() or None
    feedback = ExecutionFeedback(
        execution_id=execution.id,
        action_version_id=execution.action_version_id,
        step_id=body.step_id,
        kind=body.kind,
        category=body.category,
        original_voice=voice,
    )
    db.add(feedback)
    if body.kind == "stuck" and execution.finished_at is None:
        row = db.get(ExecutionStep, (execution.id, body.step_id))
        if row is not None:
            row.state = "stuck"
            row.updated_at = now()
    db.commit()
    return FeedbackOut(
        id=feedback.id,
        kind=feedback.kind,  # type: ignore[arg-type]
        step_id=feedback.step_id,
        category=feedback.category,  # type: ignore[arg-type]
        review_state=feedback.review_state,  # type: ignore[arg-type]
        created_at=feedback.created_at,
    )
