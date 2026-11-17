"""Load the official NISA Q&A into the database and index it for the assistant.

    uv run python -m app.official_faq                 # app/content/nisa_faq.json
    uv run python -m app.official_faq --dry-run       # only validate the file
    uv run python -m app.official_faq --no-embed      # skip the Gemini embeddings

Reviewed labels live apart from the scraped text, in app/content/nisa_faq_review.json: who each
question is for (student or school administration) and warnings for answers that a newer one
replaced, that conflict, or that described a temporary measure. Re-scraping the site never
touches them; changing them never re-embeds anything.

The questions are government answers published on the MOE NISA site, so they go live as they
are (no review drafts). Running it again updates changed questions, marks questions the file no
longer lists inactive, and embeds only what changed or was never embedded, so it is cheap to
repeat; a failed embedding run is finished by the next run.
"""

import argparse
import hashlib
import json
import sys
import time
from datetime import date
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, Field, model_validator
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.core.db import get_sessionmaker
from app.models import ContentEmbedding, FaqCategory, FaqIdentity, OfficialFaq
from app.rag.embedder import Embedder, EmbeddingUnavailable, get_embedder
from app.rag.index import _upsert
from app.services.faqs import EMBEDDING_TYPE, forget_cache

DEFAULT_PATH = Path(__file__).with_name("content") / "nisa_faq.json"
REVIEW_PATH = DEFAULT_PATH.with_name("nisa_faq_review.json")
_SLUG = r"^[a-z0-9-]{1,64}$"


class LabelIn(BaseModel):
    id: str = Field(pattern=_SLUG)
    zh: str = Field(min_length=1, max_length=100)
    en: str = Field(min_length=1, max_length=100)


class FaqIn(BaseModel):
    id: str = Field(pattern=_SLUG)
    category: str
    identities: list[str]
    question_zh: str = ""
    question_en: str = ""
    answer_zh: str = ""
    answer_en: str = ""
    source_zh: str = ""
    source_en: str = ""
    agency_zh: str = ""
    agency_en: str = ""
    posted_on: date | None = None
    url: str = Field(pattern=r"^https://")

    @model_validator(mode="after")
    def _has_text(self) -> "FaqIn":
        if not (self.question_zh or self.question_en) or not (self.answer_zh or self.answer_en):
            raise ValueError(f"{self.id}: needs a question and an answer in some language")
        return self

    def content_hash(self) -> str:
        raw = json.dumps(self.model_dump(mode="json"), ensure_ascii=False, sort_keys=True)
        return hashlib.sha256(raw.encode()).hexdigest()


class FaqFile(BaseModel):
    categories: list[LabelIn]
    identities: list[LabelIn]
    faqs: list[FaqIn]

    @model_validator(mode="after")
    def _known_labels(self) -> "FaqFile":
        categories = {c.id for c in self.categories}
        identities = {i.id for i in self.identities}
        ids = [f.id for f in self.faqs]
        if len(ids) != len(set(ids)):
            raise ValueError("duplicate faq ids")
        for faq in self.faqs:
            if faq.category not in categories:
                raise ValueError(f"{faq.id}: unknown category {faq.category}")
            if unknown := set(faq.identities) - identities:
                raise ValueError(f"{faq.id}: unknown identities {sorted(unknown)}")
        return self


class ReviewIn(BaseModel):
    id: str = Field(pattern=_SLUG)
    kind: Literal["superseded", "conflict", "time_limited"]
    superseded_by: str | None = Field(default=None, pattern=_SLUG)
    related: list[str] = []
    note_zh: str = Field(min_length=1, max_length=300)
    note_en: str = Field(default="", max_length=600)


class ReviewFile(BaseModel):
    """Reviewed labels: audience per question, and warnings (see the module docstring)."""

    audience: dict[str, Literal["student", "school"]] = {}
    reviews: list[ReviewIn] = []

    def check(self, faqs: FaqFile) -> None:
        ids = {f.id for f in faqs.faqs}
        named = set(self.audience) | {r.id for r in self.reviews}
        named |= {r.superseded_by for r in self.reviews if r.superseded_by}
        if unknown := named - ids:
            raise ValueError(f"review file names unknown questions: {sorted(unknown)}")
        if len({r.id for r in self.reviews}) != len(self.reviews):
            raise ValueError("review file lists a question twice")


def load(path: Path) -> FaqFile:
    return FaqFile.model_validate_json(path.read_text(encoding="utf-8"))


def load_review(path: Path = REVIEW_PATH) -> ReviewFile:
    if not path.is_file():
        return ReviewFile()
    return ReviewFile.model_validate_json(path.read_text(encoding="utf-8"))


def embedding_text(faq: OfficialFaq, category: FaqCategory) -> str:
    """What the assistant's semantic search matches: the question, its category and answer."""
    parts = [
        f"{category.name_zh} / {category.name_en}",
        faq.question_zh,
        faq.question_en,
        _clip(faq.answer_zh),
        _clip(faq.answer_en),
    ]
    return "\n".join(p for p in parts if p)


# The opening of an answer says what it is about; whole answers (some run to thousands of
# characters in two languages) only cost tokens against the free tier's per-minute limit.
EMBED_ANSWER_CHARS = 600


def _clip(text: str) -> str:
    return text[:EMBED_ANSWER_CHARS]


def _upsert_labels(db: Session, model, labels: list[LabelIn]) -> None:
    for position, label in enumerate(labels):
        row = db.get(model, label.id) or model(id=label.id)
        row.name_zh, row.name_en, row.position = label.zh, label.en, position
        db.add(row)


def import_faqs(db: Session, data: FaqFile, review: ReviewFile | None = None) -> dict[str, int]:
    """Write the file's questions and their reviewed labels; returns counts of new, updated,
    unchanged and retired questions (by text) and of labels that changed."""
    # Labels for questions the file no longer has are ignored here (a re-scrape may drop one);
    # --dry-run reports them so the review file can be tidied.
    review = review if review is not None else load_review()
    notes = {r.id: r for r in review.reviews}
    _upsert_labels(db, FaqCategory, data.categories)
    _upsert_labels(db, FaqIdentity, data.identities)
    db.flush()
    counts = {"new": 0, "updated": 0, "unchanged": 0, "retired": 0, "relabelled": 0}
    listed = set()
    for item in data.faqs:
        listed.add(item.id)
        digest = item.content_hash()
        row = db.get(OfficialFaq, item.id)
        if row is not None and row.content_hash == digest and row.active:
            counts["unchanged"] += 1
            counts["relabelled"] += _label(row, review.audience.get(item.id), notes.get(item.id))
            continue
        counts["new" if row is None else "updated"] += 1
        row = row or OfficialFaq(id=item.id)
        values = item.model_dump(exclude={"id", "category"})
        for key, value in values.items():
            setattr(row, key, value)
        row.category_id = item.category
        row.content_hash = digest
        row.active = True
        _label(row, review.audience.get(item.id), notes.get(item.id))
        db.add(row)
        # The text changed: its old embedding no longer describes it.
        db.execute(
            delete(ContentEmbedding).where(
                ContentEmbedding.content_type == EMBEDDING_TYPE,
                ContentEmbedding.content_id == item.id,
            )
        )
    for row in db.scalars(select(OfficialFaq).where(OfficialFaq.active.is_(True))):
        if row.id not in listed:
            row.active = False
            counts["retired"] += 1
    db.execute(
        delete(ContentEmbedding).where(
            ContentEmbedding.content_type == EMBEDDING_TYPE,
            ContentEmbedding.content_id.not_in(listed),
        )
    )
    db.commit()
    forget_cache()
    return counts


def _label(row: OfficialFaq, audience: str | None, note: ReviewIn | None) -> bool:
    """Apply the reviewed labels; True when something changed."""
    values = {
        "audience": audience or "student",
        "review_kind": note.kind if note else None,
        "review_note_zh": note.note_zh if note else "",
        "review_note_en": note.note_en if note else "",
        "superseded_by": note.superseded_by if note else None,
    }
    changed = any(getattr(row, k, None) != v for k, v in values.items())
    for key, value in values.items():
        setattr(row, key, value)
    return changed


def embed_missing(
    db: Session,
    embedder: Embedder,
    batch: int = 50,
    pause: float = 0.0,
    retries: int = 0,
    sleep=time.sleep,
) -> int:
    """Embed active questions that have no embedding yet; returns how many were embedded.

    The import job paces itself (`pause` seconds between batches) and, when Gemini refuses a
    batch (a per-minute quota, a timeout), waits a minute and tries it again up to `retries`
    times: on 2026-11-18 the first production run sent 50 long texts at once and failed."""
    missing = db.execute(
        select(OfficialFaq, FaqCategory)
        .join(FaqCategory, FaqCategory.id == OfficialFaq.category_id)
        .where(
            OfficialFaq.active.is_(True),
            ~select(ContentEmbedding.content_id)
            .where(
                ContentEmbedding.content_type == EMBEDDING_TYPE,
                ContentEmbedding.content_id == OfficialFaq.id,
            )
            .exists(),
        )
        .order_by(OfficialFaq.id)
    ).all()
    done = 0
    for start in range(0, len(missing), batch):
        if start and pause:
            sleep(pause)
        rows = missing[start : start + batch]
        texts = [embedding_text(faq, category) for faq, category in rows]
        db.commit()  # hand the connection back while Gemini works
        for attempt in range(retries + 1):
            try:
                vectors = embedder.embed_documents(texts)
                break
            except EmbeddingUnavailable as exc:
                if attempt == retries:
                    raise
                print(f"batch at {start} refused ({exc}); trying again in a minute", flush=True)
                sleep(RETRY_SECONDS)
        for (faq, _), text, vector in zip(rows, texts, vectors, strict=True):
            _upsert(db, EMBEDDING_TYPE, faq.id, text, vector, None)
        db.commit()  # keep finished batches if a later one fails
        done += len(rows)
        print(f"embedded {done}/{len(missing)}", flush=True)
    return done


RETRY_SECONDS = 65.0  # past a per-minute quota window
# For the import job: about 10 texts of ~1,500 characters per batch, 15 s apart, stays well under
# the free tier's tokens per minute; 227 questions take about six minutes.
JOB_BATCH = 10
JOB_PAUSE_SECONDS = 15.0
JOB_RETRIES = 4


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("path", nargs="?", type=Path, default=DEFAULT_PATH)
    parser.add_argument("--dry-run", action="store_true", help="only validate the file")
    parser.add_argument("--no-embed", action="store_true", help="skip the Gemini embeddings")
    args = parser.parse_args()
    data = load(args.path)
    load_review().check(data)
    if args.dry_run:
        print(f"{len(data.faqs)} questions in {len(data.categories)} categories OK")
        return
    with get_sessionmaker()() as db:
        counts = import_faqs(db, data)
        print(", ".join(f"{k} {v}" for k, v in counts.items()))
        if args.no_embed:
            return
        try:
            embedded = embed_missing(
                db,
                get_embedder(),
                batch=JOB_BATCH,
                pause=JOB_PAUSE_SECONDS,
                retries=JOB_RETRIES,
            )
            print(f"embedded {embedded}")
        except EmbeddingUnavailable as exc:
            # The questions are live already; the AI finds them by keyword until a rerun embeds.
            print(f"embedding failed, run again later: {exc}", file=sys.stderr)
            sys.exit(1)


if __name__ == "__main__":
    main()
