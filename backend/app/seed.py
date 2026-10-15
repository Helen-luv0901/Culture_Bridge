"""Load the Flutter demo content into the database (B-3).

    uv run python -m app.seed            # development databases only
    uv run python -m app.seed --force    # any APP_ENV (e.g. a staging database)

Demo procedures carry no real source URLs, so every seeded source and verification record says it
is demo data; D-8 replaces them with reviewed official sources before launch. Running it twice is
safe: anything already present is skipped.
"""

import argparse
import json
import sys
from pathlib import Path

from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.db import get_sessionmaker
from app.models import (
    Action,
    ActionStep,
    ActionVersion,
    ActionVersionSource,
    Experience,
    ExperienceSummary,
    ExperienceTranslation,
    Source,
    User,
    VerificationRecord,
)
from app.services.common import now

DEMO_NOTE = "示範資料：正式上線前須由 reviewer 依官方來源重新審查（D-8）。Demo data, not reviewed."
SEED_ADMIN = "seed-admin"
_STATUS = {
    "Recently Verified": "verified",
    "Needs Review": "needs_review",
    "Community Supported": "community_supported",
}
_TOPIC = {"lifeAdaptation": "life_adaptation", "cultureCommunication": "culture_communication"}
_IDENTITY = {
    "degreeStudent": "degree_student",
    "exchangeStudent": "exchange_student",
    "languageStudent": "language_student",
}


def _user(db: Session, user_id: str, role: str) -> None:
    if db.get(User, user_id) is None:
        db.add(User(id=user_id, auth_subject=f"seed:{user_id}", role=role))
        db.flush()


def seed_action(db: Session, card: dict) -> bool:
    if db.get(Action, card["id"]) is not None:
        return False
    en = card.get("translations", {}).get("en", {})
    action = Action(id=card["id"], slug=card["id"])
    db.add(action)
    db.flush()
    v = ActionVersion(
        action_id=action.id,
        version_number=1,
        title_zh=card["title"],
        title_en=en.get("title", card["title"]),
        description_zh=card.get("description", ""),
        description_en=en.get("description", ""),
        applicable_to=card["applicableTo"],
        applicable_to_en=en.get("applicableTo", ""),
        location=card.get("location"),
        location_en=en.get("location"),
        created_by=SEED_ADMIN,
    )
    db.add(v)
    db.flush()
    en_steps = en.get("steps", [])
    for i, title in enumerate(card["steps"]):
        db.add(
            ActionStep(
                action_version_id=v.id,
                position=i + 1,
                title_zh=title,
                title_en=en_steps[i] if i < len(en_steps) else title,
            )
        )
    sources = []
    for title in card.get("sources", []):
        source = Source(title=title, url="", publisher=title, kind="official", accessed_at=now())
        db.add(source)
        db.flush()
        db.add(
            ActionVersionSource(
                action_version_id=v.id, source_id=source.id, evidence_note=DEMO_NOTE
            )
        )
        sources.append(source)
    db.flush()
    v.published_at = now()
    db.flush()
    status = _STATUS.get(card.get("status", ""), "unverified")
    if status in ("verified", "needs_review") and sources:
        db.add(
            VerificationRecord(
                action_version_id=v.id,
                source_id=sources[0].id,
                reviewer_id=SEED_ADMIN,
                decision=status,
                note=DEMO_NOTE,
            )
        )
        db.flush()
    v.verification_status = status if (sources or status != "verified") else "unverified"
    db.flush()
    return True


def seed_experience(db: Session, item: dict) -> bool:
    if db.get(Experience, item["id"]) is not None:
        return False
    author = f"seed-author-{item['id']}"
    _user(db, author, "student")
    voice = item["originalVoice"]
    experience = Experience(
        id=item["id"],
        author_id=author,
        topic_id=_TOPIC[item["topicKey"]],
        category="culture" if item["topicKey"] == "cultureCommunication" else "life",
        identity_type=_IDENTITY.get(item["identityTypeKey"], "other"),
        original_voice=voice,
        source_locale="en" if item.get("sourceLanguage") == "en" else "zh-Hant",
    )
    db.add(experience)
    db.flush()
    summary = ExperienceSummary(
        experience_id=experience.id,
        version_number=1,
        source_voice=voice,
        situation=item["summary"],
        feeling_or_attempt="",
        reminder=item["reminder"],
        model_name="demo-content",
        confirmed_by=author,
        confirmed_at=now(),
    )
    db.add(summary)
    db.flush()
    experience.status = "published"
    experience.confirmed_summary_id = summary.id
    experience.published_at = now()
    db.flush()
    en = item.get("translations", {}).get("en")
    if en and experience.source_locale != "en":
        db.add(
            ExperienceTranslation(
                experience_id=experience.id,
                summary_id=summary.id,
                locale="en",
                original_voice=en["originalVoice"],
                situation=en["summary"],
                feeling_or_attempt="",
                reminder=en["reminder"],
                method="human",
            )
        )
    return True


def seed(db: Session, content_path: Path) -> dict[str, int]:
    raw = json.loads(content_path.read_text(encoding="utf-8-sig"))
    _user(db, SEED_ADMIN, "admin")
    actions = sum(seed_action(db, card) for card in raw["actionCards"])
    experiences = sum(seed_experience(db, item) for item in raw["experiences"])
    db.commit()
    return {"actions": actions, "experiences": experiences}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--force", action="store_true", help="allow outside APP_ENV=development")
    args = parser.parse_args()
    settings = get_settings()
    if not settings.is_development and not args.force:
        sys.exit("Refusing to seed demo data outside development (use --force).")
    with get_sessionmaker()() as db:
        print(seed(db, settings.demo_content_path))


if __name__ == "__main__":
    main()
