"""Building and querying the semantic index (A-20, A-21, A-22).

Rules:
- Only public content is indexed; hiding, deleting, a report take-down or account deletion
  removes it immediately (synchronously, no AI call needed).
- The index holds no author information. Visibility and blocks are re-checked at query time, so
  a stale row can never surface hidden content.
- Official documents rank before student content, which is always labelled as unverified.
"""

import logging
import re
from datetime import date, datetime
from typing import Any

from sqlalchemy import delete, exists, select
from sqlalchemy import text as sql
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session, sessionmaker

from app.core.auth import CurrentUser
from app.core.config import get_settings
from app.models import (
    ContentEmbedding,
    ExecutionFeedback,
    Experience,
    ExperienceSummary,
    ExperienceTranslation,
    KbChunk,
    KbDocument,
)
from app.rag.embedder import Embedder, EmbeddingUnavailable
from app.services.blocking import hides_experience

logger = logging.getLogger(__name__)

MAX_CHUNK = 800
OVERLAP = 120


# ---------- chunking ----------


def chunk_text(text: str, max_chars: int = MAX_CHUNK, overlap: int = OVERLAP) -> list[str]:
    """Split on paragraphs, then sentences, into pieces of at most max_chars with some overlap."""
    text = re.sub(r"[ \t]+", " ", text).strip()
    if not text:
        return []
    pieces: list[str] = []
    for paragraph in re.split(r"\n\s*\n", text):
        paragraph = paragraph.strip()
        if len(paragraph) <= max_chars:
            pieces.append(paragraph)
            continue
        sentences = re.split(r"(?<=[。！？!?.])\s*", paragraph)
        current = ""
        for sentence in sentences:
            while len(sentence) > max_chars:  # one enormous sentence: hard split
                pieces.append(sentence[:max_chars])
                sentence = sentence[max_chars - overlap :]
            if len(current) + len(sentence) > max_chars and current:
                pieces.append(current)
                current = current[-overlap:]
            current += sentence
        if current.strip():
            pieces.append(current)
    # Merge tiny neighbours so each chunk carries enough context.
    chunks: list[str] = []
    for piece in pieces:
        if chunks and len(chunks[-1]) + len(piece) + 1 <= max_chars // 2:
            chunks[-1] = f"{chunks[-1]}\n{piece}"
        else:
            chunks.append(piece)
    return [c.strip() for c in chunks if c.strip()]


# ---------- user content (A-20) ----------


def remove_content(db: Session, content_type: str, content_ids: list[str]) -> None:
    if content_ids:
        db.execute(
            delete(ContentEmbedding).where(
                ContentEmbedding.content_type == content_type,
                ContentEmbedding.content_id.in_(content_ids),
            )
        )


def _upsert(
    db: Session, content_type: str, content_id: str, text: str, vector, published_at
) -> None:
    stmt = insert(ContentEmbedding).values(
        content_type=content_type,
        content_id=content_id,
        content=text,
        embedding=vector,
        published_at=published_at,
    )
    db.execute(
        stmt.on_conflict_do_update(
            index_elements=["content_type", "content_id"],
            set_={
                "content": stmt.excluded.content,
                "embedding": stmt.excluded.embedding,
                "published_at": stmt.excluded.published_at,
                "indexed_at": datetime.now().astimezone(),
            },
        )
    )


def experience_text(db: Session, experience: Experience) -> str:
    summary = db.get(ExperienceSummary, experience.confirmed_summary_id)
    parts = [experience.title or "", " ".join(experience.tags or []), experience.original_voice]
    if summary:
        parts += [summary.situation, summary.feeling_or_attempt, summary.reminder]
    for t in db.scalars(
        select(ExperienceTranslation).where(
            ExperienceTranslation.experience_id == experience.id,
            ExperienceTranslation.summary_id == experience.confirmed_summary_id,
        )
    ):
        parts += [t.title or "", t.original_voice, t.situation, t.reminder]
    return "\n".join(p for p in parts if p)


def sync_experience(db: Session, embedder: Embedder, experience_id: str) -> bool:
    """Index the experience if it is public, otherwise make sure it is not indexed."""
    experience = db.get(Experience, experience_id)
    if experience is None or experience.status != "published":
        remove_content(db, "experience", [experience_id])
        db.commit()
        return False
    text = experience_text(db, experience)
    db.commit()  # hand the connection back while Gemini embeds the text
    [vector] = embedder.embed_documents([text])
    status = db.scalar(select(Experience.status).where(Experience.id == experience_id))
    if status != "published":  # hidden or deleted meanwhile
        return False
    _upsert(db, "experience", experience.id, text, vector, experience.published_at)
    db.commit()
    return True


BACKFILL_BATCH = 10


def index_missing(db: Session, embedder: Embedder, limit: int = BACKFILL_BATCH) -> int:
    """Index published experiences that have no entry yet (an earlier attempt failed)."""
    missing = db.scalars(
        select(Experience.id)
        .where(
            Experience.status == "published",
            ~exists().where(
                ContentEmbedding.content_type == "experience",
                ContentEmbedding.content_id == Experience.id,
            ),
        )
        .order_by(Experience.published_at.desc())
        .limit(limit)
    ).all()
    indexed = 0
    for experience_id in missing:
        try:
            indexed += sync_experience(db, embedder, experience_id)
        except EmbeddingUnavailable:
            raise  # Gemini is down: the rest would fail too
        except Exception:
            db.rollback()
            logger.exception("Backfill of experience %s failed", experience_id)
    return indexed


def sync_feedback(db: Session, embedder: Embedder, feedback_id: str) -> bool:
    """Students' own words from execution reports, once a reviewer has accepted the report."""
    feedback = db.get(ExecutionFeedback, feedback_id)
    if feedback is None or feedback.review_state != "reviewed" or not feedback.original_voice:
        remove_content(db, "execution_feedback", [feedback_id])
        db.commit()
        return False
    [vector] = embedder.embed_documents([feedback.original_voice])
    _upsert(
        db, "execution_feedback", feedback.id, feedback.original_voice, vector, feedback.created_at
    )
    db.commit()
    return True


def sync_in_background(
    session_factory: sessionmaker[Session], embedder: Embedder, content_type: str, content_id: str
) -> None:
    with session_factory() as db:
        try:
            if content_type == "experience":
                sync_experience(db, embedder, content_id)
            else:
                sync_feedback(db, embedder, content_id)
            # Each new item also picks up a few that failed before, so nothing stays unindexed.
            if healed := index_missing(db, embedder):
                logger.info("Indexed %s experiences that were missing", healed)
        except EmbeddingUnavailable as exc:
            # Removal never needs embeddings, so this only delays new content being searchable;
            # the next item's backfill retries it.
            logger.warning("Indexing %s %s failed: %s", content_type, content_id, exc)
        except Exception:
            logger.exception("Indexing %s %s failed", content_type, content_id)


# ---------- official documents (A-21) ----------


def add_document(
    db: Session,
    embedder: Embedder,
    *,
    title: str,
    url: str,
    publisher: str,
    document_date: date | None,
    action_id: str | None,
    text: str,
    created_by: str | None,
) -> KbDocument:
    chunks = chunk_text(text)
    if not chunks:
        raise ValueError("document has no text")
    vectors = embedder.embed_documents(chunks)
    document = KbDocument(
        title=title,
        url=url,
        publisher=publisher,
        document_date=document_date,
        action_id=action_id,
        created_by=created_by,
    )
    db.add(document)
    db.flush()
    for position, (content, vector) in enumerate(zip(chunks, vectors, strict=True), 1):
        db.add(
            KbChunk(document_id=document.id, position=position, content=content, embedding=vector)
        )
    db.commit()
    return document


# ---------- search (A-22) ----------


def semantic_search(
    db: Session,
    embedder: Embedder,
    query: str,
    viewer: CurrentUser | None,
    limit: int = 4,
    max_distance: float | None = None,
    vector: list[float] | None = None,
) -> dict[str, Any]:
    """Nearest official passages and student content; matches beyond max_distance are noise.
    `vector` is the query already embedded (the assistant starts that early)."""
    cutoff = max_distance if max_distance is not None else get_settings().semantic_max_distance
    if vector is None:
        vector = embedder.embed_query(query)
    official_distance = KbChunk.embedding.cosine_distance(vector)
    official = db.execute(
        select(KbChunk, KbDocument, official_distance.label("d"))
        .join(KbDocument, KbDocument.id == KbChunk.document_id)
        .where(KbDocument.active.is_(True), official_distance < cutoff)
        .order_by(official_distance)
        .limit(limit)
    ).all()

    # The HNSW index returns its ef_search nearest rows before the visibility and distance
    # filters below; the default (40) can leave too few once hidden or blocked rows drop out.
    db.execute(sql("SET LOCAL hnsw.ef_search = 100"))
    content_distance = ContentEmbedding.embedding.cosine_distance(vector)
    # Re-check visibility here: only published experiences and reviewed feedback, never blocked.
    visible_experience = exists().where(
        Experience.id == ContentEmbedding.content_id, Experience.status == "published"
    )
    if viewer is not None:
        visible_experience = visible_experience.where(~hides_experience(viewer.id))
    visible_feedback = exists().where(
        ExecutionFeedback.id == ContentEmbedding.content_id,
        ExecutionFeedback.review_state == "reviewed",
    )
    students = db.execute(
        select(ContentEmbedding, content_distance.label("d"))
        .where(
            content_distance < cutoff,
            ((ContentEmbedding.content_type == "experience") & visible_experience)
            | ((ContentEmbedding.content_type == "execution_feedback") & visible_feedback),
        )
        .order_by(content_distance)
        .limit(limit)
    ).all()

    return {
        "official_passages": [
            {
                "document_title": doc.title,
                "publisher": doc.publisher,
                "url": doc.url,
                "document_date": doc.document_date.isoformat() if doc.document_date else None,
                "passage": chunk.position,
                "text": chunk.content,
                "related_action_id": doc.action_id,
            }
            for chunk, doc, _ in official
        ],
        "student_content": [
            {
                "label": "student_shared_unverified",
                "content_type": row.content_type,
                "content_id": row.content_id,
                "shared_on": row.published_at.date().isoformat() if row.published_at else None,
                "text": row.content,
                # Cosine distance to the question: lower is closer.
                "distance": round(float(d), 4),
            }
            for row, d in students
        ],
    }
