"""Read-only data the assistant tools are allowed to see.

`AssistantDataSource` is the seam between the assistant and storage. `DemoDataSource` serves
flutter_app/assets/data/content.json so the assistant runs before the Cloud SQL services exist;
a PostgreSQL implementation (latest_published_actions / public_experiences views, B's keyword
search for B-16) replaces it without touching the tools.
"""

import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal, Protocol

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
_CJK = re.compile(r"[㐀-鿿豈-﫿]")


# Question words carry no topic, so they must not make every document "match".
_STOPWORDS = frozenset(
    "a an and are can do does for how i in is it me mean my of on the to what where why you".split()
)
_CJK_FILLER = set("的了嗎呢吧什麼怎哪我你他她是要")


def search_units(query: str) -> list[str]:
    """Query -> match units. CJK runs become bigrams so 「工作證怎麼辦」 still matches 「工作證」;
    Latin words are cut to a stem so "sharing" matches "share" and "anonymously" "anonymous"."""
    units: list[str] = []
    for token in re.findall(r"[a-z0-9]+|[^\sa-z0-9]+", query.lower()):
        if _CJK.search(token):
            if len(token) <= 2:
                units.append(token)
                continue
            bigrams = (token[i : i + 2] for i in range(len(token) - 1))
            units.extend(b for b in bigrams if not _CJK_FILLER.intersection(b))
        elif token not in _STOPWORDS:
            units.append(token if len(token) <= 4 else token[: max(4, len(token) - 3)])
    return units


def _matches(unit: str, haystack: str) -> bool:
    if _CJK.search(unit):
        return unit in haystack
    return re.search(rf"\b{re.escape(unit)}", haystack) is not None


def score(units: list[str], haystack: str) -> float:
    if not units:
        return 1.0
    return sum(1 for unit in units if _matches(unit, haystack)) / len(units)


def rank[T](items: list[tuple[T, str, str]], query: str, limit: int) -> list[T]:
    """Rank (item, heading, body) triples; heading hits count double, so the document *about*
    a topic beats ones that only mention it."""
    units = search_units(query)
    scored = [(item, 2 * score(units, head) + score(units, body)) for item, head, body in items]
    scored = [pair for pair in scored if pair[1] > 0]
    scored.sort(key=lambda pair: pair[1], reverse=True)
    return [item for item, _ in scored[:limit]]


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
