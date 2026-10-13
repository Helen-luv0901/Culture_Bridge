"""Usage numbers for the MVP success signals (D-19, experience-led-mvp "MVP Success Signals").

Recording is deliberately small: one row per account per active day, and one row per reader per
experience per day (signed-in readers only, never the author). Days are Taiwan dates. Rates are
None when there is nothing to divide by, so a tiny pilot never shows a misleading percentage.
"""

from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from pydantic import BaseModel
from sqlalchemy import and_, distinct, func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session, aliased

from app.models import (
    ActionStep,
    ActionVersion,
    Execution,
    ExecutionFeedback,
    Experience,
    ExperienceLink,
    ExperienceSummary,
    ExperienceView,
    UserActivityDay,
)
from app.services.common import Text2, text2

TAIPEI = ZoneInfo("Asia/Taipei")

# (user_id, day) already written by this process; saves a write on every request.
_recorded: set[tuple[str, date]] = set()


def today() -> date:
    return datetime.now(TAIPEI).date()


def record_activity(db: Session, user_id: str) -> None:
    day = today()
    if (user_id, day) in _recorded:
        return
    db.execute(insert(UserActivityDay).values(user_id=user_id, day=day).on_conflict_do_nothing())
    db.commit()
    if len(_recorded) > 50_000:
        _recorded.clear()
    _recorded.add((user_id, day))


def forget_activity(user_id: str) -> None:
    """After account deletion, a new account with the same id must be recorded again."""
    for key in [k for k in _recorded if k[0] == user_id]:
        _recorded.discard(key)


def record_view(db: Session, viewer_id: str, experience_id: str) -> None:
    author = db.scalar(select(Experience.author_id).where(Experience.id == experience_id))
    if author is None or author == viewer_id:
        return
    db.execute(
        insert(ExperienceView)
        .values(experience_id=experience_id, viewer_id=viewer_id, day=today())
        .on_conflict_do_nothing()
    )
    db.commit()


class StuckStep(BaseModel):
    action_title: Text2
    step_title: Text2 | None
    count: int


class UsageStats(BaseModel):
    days: int
    since: date
    active_users: int
    # 7-day return: people whose first day falls in the window (and is at least 7 days ago)
    return_cohort: int
    returned_within_7_days: int
    return_rate: float | None
    experience_readers: int
    reader_rate: float | None
    experiences_published: int
    sharing_authors: int
    share_rate: float | None
    drafts_with_ai_summary: int
    published_after_summary: int
    summary_confirm_rate: float | None
    confirmed_with_author_edits: int
    different_responses: int
    executions_started: int
    outcomes: dict[str, int]
    top_stuck_steps: list[StuckStep]


def _rate(part: int, whole: int) -> float | None:
    return round(part / whole, 3) if whole else None


def _day_start(day: date) -> datetime:
    return datetime(day.year, day.month, day.day, tzinfo=TAIPEI)


def usage_stats(db: Session, days: int) -> UsageStats:
    end = today()
    since = end - timedelta(days=days - 1)
    since_ts = _day_start(since)

    active = (
        db.scalar(
            select(func.count(distinct(UserActivityDay.user_id))).where(
                UserActivityDay.day >= since
            )
        )
        or 0
    )

    first_days = (
        select(UserActivityDay.user_id, func.min(UserActivityDay.day).label("first"))
        .group_by(UserActivityDay.user_id)
        .subquery()
    )
    cohort_filter = and_(first_days.c.first >= since, first_days.c.first <= end - timedelta(days=7))
    cohort = db.scalar(select(func.count()).select_from(first_days).where(cohort_filter)) or 0
    later = aliased(UserActivityDay)
    returned = (
        db.scalar(
            select(func.count(distinct(first_days.c.user_id)))
            .select_from(first_days)
            .join(later, later.user_id == first_days.c.user_id)
            .where(
                cohort_filter,
                later.day > first_days.c.first,
                later.day <= first_days.c.first + 7,
            )
        )
        or 0
    )

    readers = (
        db.scalar(
            select(func.count(distinct(ExperienceView.viewer_id))).where(
                ExperienceView.day >= since
            )
        )
        or 0
    )

    published_filter = and_(Experience.status == "published", Experience.published_at >= since_ts)
    published = db.scalar(select(func.count()).where(published_filter)) or 0
    authors = (
        db.scalar(select(func.count(distinct(Experience.author_id))).where(published_filter)) or 0
    )

    summarized = (
        select(ExperienceSummary.experience_id)
        .where(ExperienceSummary.created_at >= since_ts)
        .distinct()
    )
    with_summary = db.scalar(select(func.count()).select_from(summarized.subquery())) or 0
    published_after = (
        db.scalar(
            select(func.count()).where(
                Experience.id.in_(summarized), Experience.status == "published"
            )
        )
        or 0
    )
    author_edits = (
        db.scalar(
            select(func.count()).where(
                ExperienceSummary.confirmed_at >= since_ts,
                ExperienceSummary.model_name.contains("+author-edit"),
            )
        )
        or 0
    )

    different = (
        db.scalar(
            select(func.count()).where(
                ExperienceLink.kind == "different", ExperienceLink.created_at >= since_ts
            )
        )
        or 0
    )

    started = db.scalar(select(func.count()).where(Execution.started_at >= since_ts)) or 0
    outcomes = {
        outcome: count
        for outcome, count in db.execute(
            select(Execution.outcome, func.count())
            .where(Execution.finished_at >= since_ts, Execution.outcome.is_not(None))
            .group_by(Execution.outcome)
        )
    }

    stuck = db.execute(
        select(ActionVersion, ActionStep, func.count())
        .select_from(ExecutionFeedback)
        .join(ActionVersion, ActionVersion.id == ExecutionFeedback.action_version_id)
        .outerjoin(ActionStep, ActionStep.id == ExecutionFeedback.step_id)
        .where(ExecutionFeedback.kind == "stuck", ExecutionFeedback.created_at >= since_ts)
        .group_by(ActionVersion.id, ActionStep.id)
        .order_by(func.count().desc())
        .limit(5)
    )

    return UsageStats(
        days=days,
        since=since,
        active_users=active,
        return_cohort=cohort,
        returned_within_7_days=returned,
        return_rate=_rate(returned, cohort),
        experience_readers=readers,
        reader_rate=_rate(readers, active),
        experiences_published=published,
        sharing_authors=authors,
        share_rate=_rate(authors, active),
        drafts_with_ai_summary=with_summary,
        published_after_summary=published_after,
        summary_confirm_rate=_rate(published_after, with_summary),
        confirmed_with_author_edits=author_edits,
        different_responses=different,
        executions_started=started,
        outcomes=outcomes,
        top_stuck_steps=[
            StuckStep(
                action_title=text2(v.title_zh, v.title_en),
                step_title=text2(s.title_zh, s.title_en) if s else None,
                count=n,
            )
            for v, s, n in stuck
        ],
    )
