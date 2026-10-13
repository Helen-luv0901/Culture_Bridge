"""SQLAlchemy mappings of the tables in database/schema_postgres.sql (+ migration 0002).

The database owns the rules (CHECK constraints and triggers); these classes only describe columns.
Change tables through Alembic migrations, never by editing these alone.
"""

import uuid
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, TIMESTAMP
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

Timestamp = TIMESTAMP(timezone=True)


def _utcnow() -> datetime:
    return datetime.now(UTC)


def new_id() -> str:
    return uuid.uuid4().hex


class Base(DeclarativeBase):
    pass


def _created() -> Mapped[datetime]:
    return mapped_column(Timestamp, default=_utcnow, server_default=func.now(), nullable=False)


# ---------- people and places ----------


class User(Base):
    __tablename__ = "users"
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    auth_subject: Mapped[str] = mapped_column(Text, unique=True)
    preferred_locale: Mapped[str] = mapped_column(Text, default="zh-Hant", server_default="zh-Hant")
    role: Mapped[str] = mapped_column(Text, default="student", server_default="student")
    created_at: Mapped[datetime] = _created()


class Institution(Base):
    __tablename__ = "institutions"
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    name_zh: Mapped[str] = mapped_column(Text)
    name_en: Mapped[str] = mapped_column(Text)
    city: Mapped[str | None] = mapped_column(Text)


class Topic(Base):
    __tablename__ = "topics"
    id: Mapped[str] = mapped_column(Text, primary_key=True)
    name_zh: Mapped[str] = mapped_column(Text)
    name_en: Mapped[str] = mapped_column(Text)


# ---------- procedures ----------


class Action(Base):
    __tablename__ = "actions"
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    slug: Mapped[str] = mapped_column(Text, unique=True)
    archived_at: Mapped[datetime | None] = mapped_column(Timestamp)


class ActionVersion(Base):
    __tablename__ = "action_versions"
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    action_id: Mapped[str] = mapped_column(ForeignKey("actions.id"))
    version_number: Mapped[int] = mapped_column(Integer)
    title_zh: Mapped[str] = mapped_column(Text)
    title_en: Mapped[str] = mapped_column(Text)
    description_zh: Mapped[str] = mapped_column(Text, default="", server_default="")
    description_en: Mapped[str] = mapped_column(Text, default="", server_default="")
    institution_id: Mapped[str | None] = mapped_column(ForeignKey("institutions.id"))
    location: Mapped[str | None] = mapped_column(Text)
    applicable_to: Mapped[str] = mapped_column(Text)
    applicable_to_en: Mapped[str] = mapped_column(Text, default="", server_default="")
    location_en: Mapped[str | None] = mapped_column(Text)
    verification_status: Mapped[str] = mapped_column(
        Text, default="unverified", server_default="unverified"
    )
    published_at: Mapped[datetime | None] = mapped_column(Timestamp)
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = _created()


class ActionStep(Base):
    __tablename__ = "action_steps"
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    action_version_id: Mapped[str] = mapped_column(ForeignKey("action_versions.id"))
    position: Mapped[int] = mapped_column(Integer)
    title_zh: Mapped[str] = mapped_column(Text)
    title_en: Mapped[str] = mapped_column(Text)
    notes: Mapped[str | None] = mapped_column(Text)


class Source(Base):
    __tablename__ = "sources"
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    title: Mapped[str] = mapped_column(Text)
    url: Mapped[str] = mapped_column(Text)
    publisher: Mapped[str] = mapped_column(Text)
    kind: Mapped[str] = mapped_column(Text)
    accessed_at: Mapped[datetime] = mapped_column(Timestamp)


class ActionVersionSource(Base):
    __tablename__ = "action_version_sources"
    action_version_id: Mapped[str] = mapped_column(
        ForeignKey("action_versions.id"), primary_key=True
    )
    source_id: Mapped[str] = mapped_column(ForeignKey("sources.id"), primary_key=True)
    evidence_note: Mapped[str] = mapped_column(Text)


class VerificationRecord(Base):
    __tablename__ = "verification_records"
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    action_version_id: Mapped[str] = mapped_column(Text)
    source_id: Mapped[str] = mapped_column(Text)
    reviewer_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    decision: Mapped[str] = mapped_column(Text)
    note: Mapped[str] = mapped_column(Text)
    checked_at: Mapped[datetime] = mapped_column(
        Timestamp, default=_utcnow, server_default=func.now()
    )


class Execution(Base):
    __tablename__ = "executions"
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    action_version_id: Mapped[str] = mapped_column(ForeignKey("action_versions.id"))
    institution_id: Mapped[str | None] = mapped_column(ForeignKey("institutions.id"))
    identity_type: Mapped[str] = mapped_column(Text)
    started_at: Mapped[datetime] = mapped_column(
        Timestamp, default=_utcnow, server_default=func.now()
    )
    finished_at: Mapped[datetime | None] = mapped_column(Timestamp)
    outcome: Mapped[str | None] = mapped_column(Text)


class ExecutionStep(Base):
    __tablename__ = "execution_steps"
    execution_id: Mapped[str] = mapped_column(Text, primary_key=True)
    action_version_id: Mapped[str] = mapped_column(Text)
    step_id: Mapped[str] = mapped_column(Text, primary_key=True)
    state: Mapped[str] = mapped_column(Text, default="pending", server_default="pending")
    updated_at: Mapped[datetime] = mapped_column(
        Timestamp, default=_utcnow, server_default=func.now()
    )


class ExecutionFeedback(Base):
    __tablename__ = "execution_feedback"
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    execution_id: Mapped[str] = mapped_column(Text)
    action_version_id: Mapped[str] = mapped_column(Text)
    step_id: Mapped[str | None] = mapped_column(Text)
    kind: Mapped[str] = mapped_column(Text)
    category: Mapped[str | None] = mapped_column(Text)
    original_voice: Mapped[str | None] = mapped_column(Text)
    review_state: Mapped[str] = mapped_column(Text, default="pending", server_default="pending")
    created_at: Mapped[datetime] = _created()


# ---------- experiences ----------


class Experience(Base):
    __tablename__ = "experiences"
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    author_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    topic_id: Mapped[str] = mapped_column(ForeignKey("topics.id"))
    identity_type: Mapped[str] = mapped_column(Text)
    original_voice: Mapped[str] = mapped_column(Text)
    source_locale: Mapped[str] = mapped_column(Text, default="zh-Hant", server_default="zh-Hant")
    institution_id: Mapped[str | None] = mapped_column(ForeignKey("institutions.id"))
    location: Mapped[str | None] = mapped_column(Text)
    status: Mapped[str] = mapped_column(Text, default="draft", server_default="draft")
    confirmed_summary_id: Mapped[str | None] = mapped_column(Text)
    published_at: Mapped[datetime | None] = mapped_column(Timestamp)
    created_at: Mapped[datetime] = _created()


class ExperienceSummary(Base):
    __tablename__ = "experience_summaries"
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    experience_id: Mapped[str] = mapped_column(ForeignKey("experiences.id"))
    version_number: Mapped[int] = mapped_column(Integer)
    source_voice: Mapped[str] = mapped_column(Text)
    situation: Mapped[str] = mapped_column(Text)
    feeling_or_attempt: Mapped[str] = mapped_column(Text)
    reminder: Mapped[str] = mapped_column(Text)
    model_name: Mapped[str] = mapped_column(Text)
    confirmed_by: Mapped[str | None] = mapped_column(ForeignKey("users.id"))
    confirmed_at: Mapped[datetime | None] = mapped_column(Timestamp)
    created_at: Mapped[datetime] = _created()


class ExperienceTranslation(Base):
    __tablename__ = "experience_translations"
    experience_id: Mapped[str] = mapped_column(ForeignKey("experiences.id"), primary_key=True)
    summary_id: Mapped[str] = mapped_column(Text, primary_key=True)
    locale: Mapped[str] = mapped_column(Text, primary_key=True)
    original_voice: Mapped[str] = mapped_column(Text)
    situation: Mapped[str] = mapped_column(Text)
    feeling_or_attempt: Mapped[str] = mapped_column(Text)
    reminder: Mapped[str] = mapped_column(Text)
    method: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = _created()


class ExperienceReaction(Base):
    __tablename__ = "experience_reactions"
    experience_id: Mapped[str] = mapped_column(ForeignKey("experiences.id"), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    kind: Mapped[str] = mapped_column(Text, primary_key=True)
    created_at: Mapped[datetime] = _created()


class ExperienceLink(Base):
    __tablename__ = "experience_links"
    from_experience_id: Mapped[str] = mapped_column(ForeignKey("experiences.id"), primary_key=True)
    to_experience_id: Mapped[str] = mapped_column(ForeignKey("experiences.id"), primary_key=True)
    kind: Mapped[str] = mapped_column(Text, primary_key=True)
    created_at: Mapped[datetime] = _created()


class ActionExperienceLink(Base):
    __tablename__ = "action_experience_links"
    action_id: Mapped[str] = mapped_column(ForeignKey("actions.id"), primary_key=True)
    experience_id: Mapped[str] = mapped_column(ForeignKey("experiences.id"), primary_key=True)


# ---------- moderation, audit and assistant (migration 0002) ----------


class Report(Base):
    __tablename__ = "reports"
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    reporter_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    target_type: Mapped[str] = mapped_column(Text)
    target_id: Mapped[str] = mapped_column(Text)
    reason: Mapped[str] = mapped_column(Text)
    note: Mapped[str | None] = mapped_column(Text)
    status: Mapped[str] = mapped_column(Text, default="pending", server_default="pending")
    resolved_by: Mapped[str | None] = mapped_column(ForeignKey("users.id"))
    resolved_at: Mapped[datetime | None] = mapped_column(Timestamp)
    created_at: Mapped[datetime] = _created()


class UserBlock(Base):
    __tablename__ = "user_blocks"
    blocker_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    blocked_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    created_at: Mapped[datetime] = _created()


class AdminAction(Base):
    __tablename__ = "admin_actions"
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    actor_id: Mapped[str | None] = mapped_column(ForeignKey("users.id"))
    action: Mapped[str] = mapped_column(Text)
    target_type: Mapped[str] = mapped_column(Text)
    target_id: Mapped[str] = mapped_column(Text)
    detail: Mapped[dict[str, Any]] = mapped_column(JSONB, default=dict, server_default="{}")
    created_at: Mapped[datetime] = _created()


class AssistantOperation(Base):
    __tablename__ = "assistant_operations"
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    type: Mapped[str] = mapped_column(String(40))
    target_id: Mapped[str] = mapped_column(Text)
    summary: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(Text, default="pending", server_default="pending")
    result: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    created_at: Mapped[datetime] = _created()
    expires_at: Mapped[datetime] = mapped_column(Timestamp)
    resolved_at: Mapped[datetime | None] = mapped_column(Timestamp)
