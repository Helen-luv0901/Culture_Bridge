"""Import researched procedure cards as drafts for reviewers (D-8).

    uv run python -m app.official_content                 # app/content/official_procedures.json
    uv run python -m app.official_content cards.json --dry-run

Each card becomes an unpublished draft version with its official sources attached, exactly as if
a reviewer had typed it into the admin console. Nothing is published or marked verified: a
reviewer reads the sources, corrects the draft, publishes it and records the verification
(D-2). Running it again refreshes drafts nobody else has touched yet, skips drafts a reviewer
has started on, and opens a new draft version for procedures that were already published.
"""

import argparse
import json
import re
from datetime import datetime
from pathlib import Path

from pydantic import HttpUrl
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.auth import CurrentUser
from app.core.db import get_sessionmaker
from app.models import Action, ActionVersion, AdminAction, Source, User
from app.services import admin_actions as svc
from app.services.publishers import publisher_en

DEFAULT_PATH = Path(__file__).with_name("content") / "official_procedures.json"
IMPORTER = CurrentUser(id="content-import", role="reviewer")  # type: ignore[arg-type]
_MARKERS = re.compile(r"(?:\[\d+\])+")


def _importer(db: Session) -> CurrentUser:
    if db.get(User, IMPORTER.id) is None:
        db.add(User(id=IMPORTER.id, auth_subject=f"system:{IMPORTER.id}", role="reviewer"))
        db.commit()
    return IMPORTER


def _cite(text: str | None, publishers: list[str]) -> str | None:
    """Turn [n] markers into the publisher's name; the public card lists sources by title."""
    if not text:
        return text

    def names(match: re.Match[str]) -> str:
        found = [int(n) - 1 for n in re.findall(r"\d+", match.group(0))]
        unique = dict.fromkeys(publishers[i] for i in found if 0 <= i < len(publishers))
        return f"（{'、'.join(unique)}）" if unique else ""

    return _MARKERS.sub(names, text)


def _cite_en(text: str | None, publishers: list[str]) -> str | None:
    """Like _cite, with English source names and English parentheses."""
    if not text:
        return text

    def names(match: re.Match[str]) -> str:
        found = [int(n) - 1 for n in re.findall(r"\d+", match.group(0))]
        unique = dict.fromkeys(
            publisher_en(publishers[i]) for i in found if 0 <= i < len(publishers)
        )
        return f" ({'; '.join(unique)})" if unique else ""

    return _MARKERS.sub(names, text)


def _content(card: dict) -> svc.NewAction:
    publishers = [s["publisher"] for s in card["sources"]]
    return svc.NewAction(
        slug=card["slug"],
        title_zh=card["title_zh"],
        title_en=card["title_en"],
        description_zh=_cite(card.get("description_zh"), publishers) or "",
        description_en=card.get("description_en") or "",
        applicable_to=card["applicable_to"],
        applicable_to_en=card.get("applicable_to_en") or "",
        location=card.get("location"),
        location_en=card.get("location_en"),
        steps=[
            svc.StepIn(
                title_zh=s["title_zh"],
                title_en=s["title_en"],
                notes=_cite(s.get("notes"), publishers),
                notes_en=_cite_en(s.get("notes_en"), publishers),
            )
            for s in card["steps"]
        ],
    )


def _source_id(db: Session, source: dict, accessed_at: datetime) -> str:
    url = str(HttpUrl(source["url"]))  # stored the way the admin API stores it
    existing = db.scalar(select(Source.id).where(Source.url == url))
    if existing:
        return existing
    created = svc.create_source(
        db,
        IMPORTER,
        svc.SourceIn(
            title=source["title"],
            url=source["url"],
            publisher=source["publisher"],
            kind=source.get("kind", "official"),
            accessed_at=accessed_at,
        ),
    )
    return created.id


def _touched_by_people(db: Session, version_id: str) -> bool:
    """Whether anyone but the importer has changed this draft (edits, sources, verification)."""
    return (
        db.scalar(
            select(AdminAction.id).where(
                AdminAction.target_id == version_id,
                AdminAction.actor_id.is_distinct_from(IMPORTER.id),
            )
        )
        is not None
    )


def import_card(db: Session, card: dict, accessed_at: datetime) -> str:
    content = _content(card)
    slug = content.slug
    if db.get(Action, slug) is None:
        version = svc.create_action(db, IMPORTER, content)
        result = "new draft"
    else:
        latest = db.scalar(
            select(ActionVersion)
            .where(ActionVersion.action_id == slug)
            .order_by(ActionVersion.version_number.desc())
        )
        body = svc.VersionContent(**content.model_dump(exclude={"slug"}))
        if latest is not None and latest.published_at is None:
            if _touched_by_people(db, latest.id):
                return "skipped (a reviewer is editing the draft)"
            version = svc.update_draft(db, IMPORTER, latest.id, body)
            result = "refreshed draft"
        else:
            version = svc.create_version(db, IMPORTER, slug)
            version = svc.update_draft(db, IMPORTER, version.id, body)
            result = f"new draft v{version.version_number}"
    listed = set()
    for source in card["sources"]:
        source_id = _source_id(db, source, accessed_at)
        listed.add(source_id)
        note = source.get("evidence_note") or "見來源"
        version = svc.attach_source(
            db, IMPORTER, version.id, source_id, svc.AttachSource(evidence_note=note)
        )
    # A new version starts with the old one's sources; drop those the card no longer lists
    # (dead or superseded links), so the guide shows exactly the file's sources.
    for source in version.sources:
        if source.id not in listed:
            svc.detach_source(db, IMPORTER, version.id, source.id)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("path", nargs="?", type=Path, default=DEFAULT_PATH)
    parser.add_argument("--dry-run", action="store_true", help="only validate the file")
    args = parser.parse_args()
    data = json.loads(args.path.read_text(encoding="utf-8"))
    accessed_at = datetime.fromisoformat(data["accessed_at"])
    for card in data["cards"]:
        _content(card)  # validate every card before writing anything
        for source in card["sources"]:
            svc.SourceIn(**{**source, "accessed_at": accessed_at})
    if args.dry_run:
        print(f"{len(data['cards'])} cards OK")
        return
    with get_sessionmaker()() as db:
        _importer(db)
        for card in data["cards"]:
            print(f"{card['slug']}: {import_card(db, card, accessed_at)}")


if __name__ == "__main__":
    main()
