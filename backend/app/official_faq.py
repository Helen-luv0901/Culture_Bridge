"""Load the official NISA Q&A into the database and index it for the assistant.

    uv run python -m app.official_faq                 # app/content/nisa_faq.json
    uv run python -m app.official_faq --dry-run       # only validate the file
    uv run python -m app.official_faq --no-embed      # skip the Gemini embeddings

The questions are government answers published on the MOE NISA site, so they go live as they
are (no review drafts). Running it again updates changed questions, marks questions the file no
longer lists inactive, and embeds only what changed or was never embedded, so it is cheap to
repeat; a failed embedding run is finished by the next run.
"""

import argparse
import hashlib
import json
import sys
from datetime import date
from pathlib import Path

from pydantic import BaseModel, Field, model_validator
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.core.db import get_sessionmaker
from app.models import ContentEmbedding, FaqCategory, FaqIdentity, OfficialFaq
from app.rag.embedder import Embedder, EmbeddingUnavailable, get_embedder
from app.rag.index import _upsert
from app.services.faqs import EMBEDDING_TYPE, forget_cache

DEFAULT_PATH = Path(__file__).with_name("content") / "nisa_faq.json"
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


def load(path: Path) -> FaqFile:
    return FaqFile.model_validate_json(path.read_text(encoding="utf-8"))


def embedding_text(faq: OfficialFaq, category: FaqCategory) -> str:
    """What the assistant's semantic search matches: the question, its category and answer."""
    parts = [
        f"{category.name_zh} / {category.name_en}",
        faq.question_zh,
        faq.question_en,
        faq.answer_zh,
        faq.answer_en,
    ]
    return "\n".join(p for p in parts if p)


def _upsert_labels(db: Session, model, labels: list[LabelIn]) -> None:
    for position, label in enumerate(labels):
        row = db.get(model, label.id) or model(id=label.id)
        row.name_zh, row.name_en, row.position = label.zh, label.en, position
        db.add(row)


def import_faqs(db: Session, data: FaqFile) -> dict[str, int]:
    """Write the file's questions; returns counts of new, updated, unchanged and retired."""
    _upsert_labels(db, FaqCategory, data.categories)
    _upsert_labels(db, FaqIdentity, data.identities)
    db.flush()
    counts = {"new": 0, "updated": 0, "unchanged": 0, "retired": 0}
    listed = set()
    for item in data.faqs:
        listed.add(item.id)
        digest = item.content_hash()
        row = db.get(OfficialFaq, item.id)
        if row is not None and row.content_hash == digest and row.active:
            counts["unchanged"] += 1
            continue
        counts["new" if row is None else "updated"] += 1
        row = row or OfficialFaq(id=item.id)
        values = item.model_dump(exclude={"id", "category"})
        for key, value in values.items():
            setattr(row, key, value)
        row.category_id = item.category
        row.content_hash = digest
        row.active = True
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


def embed_missing(db: Session, embedder: Embedder, batch: int = 50) -> int:
    """Embed active questions that have no embedding yet; returns how many were embedded."""
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
        rows = missing[start : start + batch]
        texts = [embedding_text(faq, category) for faq, category in rows]
        vectors = embedder.embed_documents(texts)
        for (faq, _), text, vector in zip(rows, texts, vectors, strict=True):
            published = None
            _upsert(db, EMBEDDING_TYPE, faq.id, text, vector, published)
        db.commit()  # keep finished batches if a later one fails
        done += len(rows)
    return done


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("path", nargs="?", type=Path, default=DEFAULT_PATH)
    parser.add_argument("--dry-run", action="store_true", help="only validate the file")
    parser.add_argument("--no-embed", action="store_true", help="skip the Gemini embeddings")
    args = parser.parse_args()
    data = load(args.path)
    if args.dry_run:
        print(f"{len(data.faqs)} questions in {len(data.categories)} categories OK")
        return
    with get_sessionmaker()() as db:
        counts = import_faqs(db, data)
        print(", ".join(f"{k} {v}" for k, v in counts.items()))
        if args.no_embed:
            return
        try:
            print(f"embedded {embed_missing(db, get_embedder())}")
        except EmbeddingUnavailable as exc:
            # The questions are live already; the AI finds them by keyword until a rerun embeds.
            print(f"embedding failed, run again later: {exc}", file=sys.stderr)
            sys.exit(1)


if __name__ == "__main__":
    main()
