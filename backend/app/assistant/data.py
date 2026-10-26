"""Read-only data the assistant tools are allowed to see.

`AssistantDataSource` is the seam between the assistant and storage. `DemoDataSource` serves
flutter_app/assets/data/content.json so the assistant runs before the Cloud SQL services exist;
a PostgreSQL implementation (latest_published_actions / public_experiences views, B's keyword
search for B-16) replaces it without touching the tools.
"""

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal, Protocol

from app.core.text_search import rank

Locale = Literal["zh-Hant", "en"]
VerificationStatus = Literal[
    "unverified", "community_supported", "needs_review", "verified", "outdated"
]
TopicId = Literal["life_adaptation", "culture_communication"]
IdentityType = Literal["degree_student", "exchange_student", "language_student", "other"]
StepState = Literal["pending", "done", "stuck"]


@dataclass(frozen=True)
class Localized:
    zh: str
    en: str

    def get(self, locale: Locale) -> str:
        return self.en if locale == "en" else self.zh


@dataclass(frozen=True)
class Source:
    title: Localized
    url: str | None = None
    publisher: str | None = None
    kind: Literal["official", "institution", "partner"] | None = None


@dataclass(frozen=True)
class ActionRecord:
    """Latest published version of a procedure (latest_published_actions)."""

    id: str
    title: Localized
    description: Localized
    applicable_to: Localized
    location: Localized
    verification_status: VerificationStatus
    last_verified_at: str | None
    recent_success_count: int
    steps: tuple[Localized, ...]
    sources: tuple[Source, ...]


@dataclass(frozen=True)
class ExperienceRecord:
    """Public projection of a published experience (public_experiences): no author fields."""

    id: str
    topic_id: TopicId
    identity_type: IdentityType
    source_locale: Locale
    original_voice: Localized
    summary: Localized
    reminder: Localized
    helpful_count: int
    different_count: int
    # The author's title (empty for older posts) and category, for post cards.
    title: Localized = Localized("", "")
    category: str | None = None


@dataclass(frozen=True)
class ProgressStep:
    position: int
    title: Localized
    state: StepState


@dataclass(frozen=True)
class ProgressRecord:
    execution_id: str
    action_id: str
    action_title: Localized
    started_at: str
    steps: tuple[ProgressStep, ...]


class AssistantDataSource(Protocol):
    def search_actions(self, query: str, limit: int) -> list[ActionRecord]: ...

    def get_action(self, action_id: str) -> ActionRecord | None: ...

    def search_experiences(
        self,
        query: str | None,
        topic_id: TopicId | None,
        identity_type: IdentityType | None,
        limit: int,
    ) -> list[ExperienceRecord]: ...

    def get_experience(self, experience_id: str) -> ExperienceRecord | None: ...

    def get_in_progress(self, user_id: str) -> list[ProgressRecord]: ...

    def semantic_search(self, query: str, limit: int) -> dict | None:
        """Official passages and student content by meaning; None when unavailable."""
        ...


# Demo JSON uses UI labels and camelCase keys; map them onto the schema vocabulary.
_DEMO_STATUS: dict[str, VerificationStatus] = {
    "Recently Verified": "verified",
    "Needs Review": "needs_review",
    "Community Supported": "community_supported",
    "Outdated": "outdated",
}
_DEMO_TOPIC: dict[str, TopicId] = {
    "lifeAdaptation": "life_adaptation",
    "cultureCommunication": "culture_communication",
}
_DEMO_IDENTITY: dict[str, IdentityType] = {
    "degreeStudent": "degree_student",
    "exchangeStudent": "exchange_student",
    "languageStudent": "language_student",
}


@dataclass
class DemoDataSource:
    actions: dict[str, ActionRecord]
    experiences: dict[str, ExperienceRecord]
    progress: dict[str, list[ProgressRecord]] = field(default_factory=dict)

    @classmethod
    def from_file(cls, path: Path) -> "DemoDataSource":
        raw = json.loads(path.read_text(encoding="utf-8-sig"))
        actions = {card["id"]: _demo_action(card) for card in raw["actionCards"]}
        experiences = {item["id"]: _demo_experience(item) for item in raw["experiences"]}
        return cls(actions=actions, experiences=experiences)

    def search_actions(self, query: str, limit: int) -> list[ActionRecord]:
        return rank(
            [(a, _both(a.title).lower(), _action_text(a)) for a in self.actions.values()],
            query,
            limit,
        )

    def get_action(self, action_id: str) -> ActionRecord | None:
        return self.actions.get(action_id)

    def search_experiences(
        self,
        query: str | None,
        topic_id: TopicId | None,
        identity_type: IdentityType | None,
        limit: int,
    ) -> list[ExperienceRecord]:
        pool = [
            e
            for e in self.experiences.values()
            if (topic_id is None or e.topic_id == topic_id)
            and (identity_type is None or e.identity_type == identity_type)
        ]
        return rank([(e, "", _experience_text(e)) for e in pool], query or "", limit)

    def get_experience(self, experience_id: str) -> ExperienceRecord | None:
        return self.experiences.get(experience_id)

    def get_in_progress(self, user_id: str) -> list[ProgressRecord]:
        return list(self.progress.get(user_id, []))

    def semantic_search(self, query: str, limit: int) -> dict | None:
        return None


def _localized(zh: str, en: str | None) -> Localized:
    return Localized(zh=zh, en=en or zh)


def _demo_action(card: dict) -> ActionRecord:
    en = card.get("translations", {}).get("en", {})
    en_sources = en.get("sources", [])
    en_steps = en.get("steps", [])
    return ActionRecord(
        id=card["id"],
        title=_localized(card["title"], en.get("title")),
        description=_localized(card["description"], en.get("description")),
        applicable_to=_localized(card["applicableTo"], en.get("applicableTo")),
        location=_localized(card["location"], en.get("location")),
        verification_status=_DEMO_STATUS.get(card["status"], "unverified"),
        last_verified_at=card.get("verifiedAt"),
        recent_success_count=card.get("recentCompletions", 0),
        steps=tuple(
            _localized(step, en_steps[i] if i < len(en_steps) else None)
            for i, step in enumerate(card["steps"])
        ),
        sources=tuple(
            Source(title=_localized(title, en_sources[i] if i < len(en_sources) else None))
            for i, title in enumerate(card["sources"])
        ),
    )


def _demo_experience(item: dict) -> ExperienceRecord:
    en = item.get("translations", {}).get("en", {})
    return ExperienceRecord(
        id=item["id"],
        topic_id=_DEMO_TOPIC[item["topicKey"]],
        identity_type=_DEMO_IDENTITY.get(item["identityTypeKey"], "other"),
        source_locale="en" if item.get("sourceLanguage") == "en" else "zh-Hant",
        original_voice=_localized(item["originalVoice"], en.get("originalVoice")),
        summary=_localized(item["summary"], en.get("summary")),
        reminder=_localized(item["reminder"], en.get("reminder")),
        helpful_count=item.get("helpfulCount", 0),
        different_count=0,
    )


def _both(value: Localized) -> str:
    return f"{value.zh} {value.en}"


def _action_text(action: ActionRecord) -> str:
    parts = [action.title, action.description, action.applicable_to, *action.steps]
    return " ".join(_both(p) for p in parts).lower()


def _experience_text(experience: ExperienceRecord) -> str:
    parts = [experience.original_voice, experience.summary, experience.reminder]
    return " ".join(_both(p) for p in parts).lower()
