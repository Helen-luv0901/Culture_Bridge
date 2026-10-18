"""AssistantDataSource over the real services, as seen by one viewer (blocks apply)."""

from dataclasses import dataclass, field

from sqlalchemy.orm import Session

from app.assistant.data import (
    ActionRecord,
    ExperienceRecord,
    Localized,
    ProgressRecord,
    ProgressStep,
    Source,
    rank,
)
from app.core.auth import CurrentUser
from app.core.errors import ApiError
from app.rag.embedder import Embedder, EmbeddingUnavailable, get_embedder
from app.rag.index import semantic_search
from app.services import actions, experiences
from app.services.common import Text2

# The assistant ranks candidates itself (bigram/stem matching handles natural questions better
# than SQL AND-matching), so it looks at a bounded recent window of experiences.
_EXPERIENCE_WINDOW = 200


def _loc(text: Text2) -> Localized:
    return Localized(zh=text.zh, en=text.en)


def _action_record(detail: actions.ActionDetail) -> ActionRecord:
    return ActionRecord(
        id=detail.id,
        title=_loc(detail.title),
        description=_loc(detail.description),
        applicable_to=_loc(detail.applicable_to),
        location=_loc(detail.location) if detail.location else Localized("", ""),
        verification_status=detail.verification_status,
        last_verified_at=detail.last_verified_at.date().isoformat()
        if detail.last_verified_at
        else None,
        recent_success_count=detail.recent_success_count,
        steps=tuple(_loc(s.title) for s in detail.steps),
        sources=tuple(
            Source(
                title=Localized(s.title, s.title),
                url=s.url or None,
                publisher=s.publisher,
                kind=s.kind,
            )
            for s in detail.sources
        ),
    )


def _experience_record(item: experiences.PublicExperience) -> ExperienceRecord:
    t = item.translation
    zh_first = item.source_locale == "zh-Hant"

    def pair(original: str, translated: str | None) -> Localized:
        other = translated if translated is not None else original
        return Localized(zh=original, en=other) if zh_first else Localized(zh=other, en=original)

    # Posts published as written have no AI summary; their title stands in for it.
    summary = " ".join(p for p in (item.situation, item.feeling_or_attempt) if p) or (
        item.title or ""
    )
    t_summary = (
        " ".join(p for p in (t.situation, t.feeling_or_attempt) if p) or (t.title or "")
        if t
        else None
    )
    return ExperienceRecord(
        id=item.id,
        topic_id=item.topic_id,
        identity_type=item.identity_type,
        source_locale=item.source_locale,
        original_voice=pair(item.original_voice, t.original_voice if t else None),
        summary=pair(summary, t_summary),
        reminder=pair(item.reminder, t.reminder if t else None),
        helpful_count=item.helpful_count,
        different_count=item.different_count,
        title=pair(item.title or "", t.title if t else None),
        category=item.category,
    )


def _searchable(e: ExperienceRecord) -> str:
    parts = [e.original_voice, e.summary, e.reminder]
    return " ".join(f"{p.zh} {p.en}" for p in parts).lower()


@dataclass
class PostgresAssistantData:
    db: Session
    viewer: CurrentUser | None
    embedder: Embedder = field(default_factory=get_embedder)
    _actions: dict[str, ActionRecord] | None = field(default=None, init=False)

    def _all_actions(self) -> dict[str, ActionRecord]:
        if self._actions is None:
            self._actions = {
                a.id: _action_record(actions.get_action(self.db, a.id))
                for a in actions.list_actions(self.db)
            }
        return self._actions

    def search_actions(self, query: str, limit: int) -> list[ActionRecord]:
        items = [
            (a, f"{a.title.zh} {a.title.en}".lower(), _action_text(a))
            for a in self._all_actions().values()
        ]
        return rank(items, query, limit)

    def get_action(self, action_id: str) -> ActionRecord | None:
        return self._all_actions().get(action_id)

    def search_experiences(self, query, topic_id, identity_type, limit) -> list[ExperienceRecord]:
        page = experiences.explore(
            self.db, self.viewer, topic_id, identity_type, None, None, _EXPERIENCE_WINDOW, 0
        )
        records = [_experience_record(item) for item in page.items]
        return rank([(e, "", _searchable(e)) for e in records], query or "", limit)

    def get_experience(self, experience_id: str) -> ExperienceRecord | None:
        try:
            return _experience_record(
                experiences.get_public(self.db, self.viewer, experience_id, None)
            )
        except ApiError:
            return None

    def get_in_progress(self, user_id: str) -> list[ProgressRecord]:
        return [
            ProgressRecord(
                execution_id=e.id,
                action_id=e.action_id,
                action_title=_loc(e.title),
                started_at=e.started_at.isoformat(),
                steps=tuple(ProgressStep(s.position, _loc(s.title), s.state) for s in e.steps),
            )
            for e in actions.my_executions(self.db, CurrentUser(id=user_id), False)
        ]

    def semantic_search(self, query: str, limit: int) -> dict | None:
        try:
            return semantic_search(self.db, self.embedder, query, self.viewer, limit)
        except EmbeddingUnavailable:
            return None


def _action_text(a: ActionRecord) -> str:
    parts = [a.title, a.description, a.applicable_to, *a.steps]
    return " ".join(f"{p.zh} {p.en}" for p in parts).lower()
