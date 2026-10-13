"""App how-to knowledge base (work-assignment A-14).

A small, versioned JSON file the assistant searches to explain how Culture Bridge works. It never
holds procedure facts: those come from the data tools so they stay current and traceable.
"""

import json
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Literal

from app.assistant.data import Locale, Localized, rank

GUIDE_PATH = Path(__file__).with_name("app_guide.json")

EntryKind = Literal["feature", "navigation", "faq", "glossary"]


@dataclass(frozen=True)
class KnowledgeEntry:
    id: str
    kind: EntryKind
    title: Localized
    body: Localized
    keywords: tuple[str, ...]

    def heading_text(self) -> str:
        return " ".join([self.title.zh, self.title.en, *self.keywords]).lower()

    def body_text(self) -> str:
        return f"{self.body.zh} {self.body.en}".lower()


@dataclass(frozen=True)
class KnowledgeBase:
    version: str
    entries: tuple[KnowledgeEntry, ...]

    @classmethod
    def from_file(cls, path: Path) -> "KnowledgeBase":
        raw = json.loads(path.read_text(encoding="utf-8"))
        entries = tuple(
            KnowledgeEntry(
                id=item["id"],
                kind=item["kind"],
                title=Localized(zh=item["title"]["zh-Hant"], en=item["title"]["en"]),
                body=Localized(zh=item["body"]["zh-Hant"], en=item["body"]["en"]),
                keywords=tuple(item.get("keywords", [])),
            )
            for item in raw["entries"]
        )
        return cls(version=raw["version"], entries=entries)

    def search(self, query: str, limit: int) -> list[KnowledgeEntry]:
        return rank([(e, e.heading_text(), e.body_text()) for e in self.entries], query, limit)

    def as_result(self, entry: KnowledgeEntry, locale: Locale) -> dict[str, str]:
        return {
            "id": entry.id,
            "kind": entry.kind,
            "title": entry.title.get(locale),
            "body": entry.body.get(locale),
        }


@lru_cache
def default_knowledge_base() -> KnowledgeBase:
    return KnowledgeBase.from_file(GUIDE_PATH)
