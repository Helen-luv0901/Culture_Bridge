"""Import researched procedure cards as drafts for reviewers (D-8).

    uv run python -m app.official_content                 # app/content/official_procedures.json
    uv run python -m app.official_content cards.json --dry-run

Each card becomes an unpublished draft version with its official sources attached, exactly as if
a reviewer had typed it into the admin console. Nothing is published or marked verified: a
reviewer reads the sources, corrects the draft, publishes it and records the verification
(D-2). Running it again skips procedures that already have an open draft.
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
from app.models import Action, ActionVersion, Source, User
from app.services import admin_actions as svc

DEFAULT_PATH = Path(__file__).with_name("content") / "official_procedures.json"
IMPORTER = CurrentUser(id="content-import", role="reviewer")  # type: ignore[arg-type]
_MARKER = re.compile(r"\[(\d+)\]")


def _importer(db: Session) -> CurrentUser:
    if db.get(User, IMPORTER.id) is None:
        db.add(User(id=IMPORTER.id, auth_subject=f"system:{IMPORTER.id}", role="reviewer"))
        db.commit()
    return IMPORTER


def _cite(text: str | None, publishers: list[str]) -> str | None:
    """Turn [n] markers into the publisher's name; the public card lists sources by title."""
    if not text:
        return text

    def name(match: re.Match[str]) -> str:
        i = int(match.group(1)) - 1
        return f"（{publishers[i]}）" if 0 <= i < len(publishers) else ""

    return _MARKER.sub(name, text).replace("）（", "、")


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
        if latest is not None and latest.published_at is None:
            return "skipped (a draft is already open)"
        version = svc.create_version(db, IMPORTER, slug)
        body = svc.VersionContent(**content.model_dump(exclude={"slug"}))
        version = svc.update_draft(db, IMPORTER, version.id, body)
        result = f"new draft v{version.version_number}"
    for source in card["sources"]:
        source_id = _source_id(db, source, accessed_at)
        note = source.get("evidence_note") or "見來源"
        svc.attach_source(db, IMPORTER, version.id, source_id, svc.AttachSource(evidence_note=note))
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
