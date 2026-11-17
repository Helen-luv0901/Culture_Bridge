"""Official Q&A from the Ministry of Education NISA site (migration 0016).

The questions were written and answered by government agencies, so they are shown as published
official content with their source, answering agency and date; nobody edits them in the app.
The importer (app.official_faq) keeps them in step with app/content/nisa_faq.json.

Some questions exist only in Chinese and two only in English: each text falls back to the
other language, and `has_english` tells the app whether the English is the official one.
"""

import threading
import time
from datetime import date

from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.auth import CurrentUser
from app.core.errors import not_found
from app.core.text_search import relevant
from app.models import ContentEmbedding, Experience, FaqCategory, FaqIdentity, OfficialFaq
from app.services.common import Text2
from app.services.experiences.queries import _public_items, _public_query
from app.services.experiences.schemas import Locale, PublicExperience

PUBLISHER = Text2(zh="教育部 NISA 計畫辦公室", en="Ministry of Education NISA Office")
EXCERPT_CHARS = 90
EMBEDDING_TYPE = "official_faq"


class FaqLabel(BaseModel):
    id: str
    name: Text2


class FaqCategoryOut(FaqLabel):
    count: int


class FaqSummary(BaseModel):
    id: str
    category_id: str
    identities: list[str]
    question: Text2
    excerpt: Text2
    posted_on: date | None
    # False: the English text is the Chinese original (the site has no English version).
    has_english: bool


class FaqDetail(FaqSummary):
    category: Text2
    answer: Text2
    source: Text2
    agency: Text2
    publisher: Text2 = PUBLISHER
    url: str


class FaqIndex(BaseModel):
    categories: list[FaqCategoryOut]
    identities: list[FaqLabel]
    items: list[FaqSummary]


def both(zh: str, en: str) -> Text2:
    """Either language may be missing; show the other one rather than nothing."""
    return Text2(zh=zh or en, en=en or zh)


def _excerpt(text: str) -> str:
    text = " ".join(text.split())
    return text if len(text) <= EXCERPT_CHARS else text[:EXCERPT_CHARS].rstrip() + "…"


def summary(faq: OfficialFaq) -> FaqSummary:
    return FaqSummary(
        id=faq.id,
        category_id=faq.category_id,
        identities=list(faq.identities or []),
        question=both(faq.question_zh, faq.question_en),
        excerpt=both(_excerpt(faq.answer_zh), _excerpt(faq.answer_en)),
        posted_on=faq.posted_on,
        has_english=bool(faq.question_en and faq.answer_en),
    )


def detail(faq: OfficialFaq, category: FaqCategory) -> FaqDetail:
    return FaqDetail(
        **summary(faq).model_dump(),
        category=Text2(zh=category.name_zh, en=category.name_en),
        answer=both(faq.answer_zh, faq.answer_en),
        source=both(faq.source_zh, faq.source_en),
        agency=both(faq.agency_zh, faq.agency_en),
        url=faq.url,
    )


def _active(db: Session) -> list[OfficialFaq]:
    return list(
        db.scalars(
            select(OfficialFaq)
            .where(OfficialFaq.active.is_(True))
            .order_by(OfficialFaq.posted_on.desc().nulls_last(), OfficialFaq.id.desc())
        )
    )


def list_faqs(db: Session) -> FaqIndex:
    items = _active(db)
    counts: dict[str, int] = {}
    for faq in items:
        counts[faq.category_id] = counts.get(faq.category_id, 0) + 1
    categories = db.scalars(select(FaqCategory).order_by(FaqCategory.position))
    identities = db.scalars(select(FaqIdentity).order_by(FaqIdentity.position))
    return FaqIndex(
        categories=[
            FaqCategoryOut(id=c.id, name=Text2(zh=c.name_zh, en=c.name_en), count=counts[c.id])
            for c in categories
            if counts.get(c.id)
        ],
        identities=[FaqLabel(id=i.id, name=Text2(zh=i.name_zh, en=i.name_en)) for i in identities],
        items=[summary(f) for f in items],
    )


def get_faq(db: Session, faq_id: str) -> FaqDetail:
    faq = db.get(OfficialFaq, faq_id)
    if faq is None or not faq.active:
        raise not_found("faq_not_found")
    return detail(faq, db.get(FaqCategory, faq.category_id))


# ---------- keyword search (Explore and the assistant) ----------

# Every assistant message searches the Q&A; reading 200-odd rows each time is wasteful, and the
# content changes only when the importer runs, so it is kept for a minute.
_TTL_SECONDS = 60.0
_cache: tuple[float, list[tuple[OfficialFaq, FaqCategory]]] | None = None
_lock = threading.Lock()


def active_with_categories(db: Session) -> list[tuple[OfficialFaq, FaqCategory]]:
    global _cache
    with _lock:
        cached = _cache
    if cached is not None and time.monotonic() - cached[0] < _TTL_SECONDS:
        return cached[1]
    # Detached copies: the cache outlives this session and is shared between requests.
    categories = {c.id: _copy(c) for c in db.scalars(select(FaqCategory))}
    rows = [(_copy(f), categories[f.category_id]) for f in _active(db)]
    with _lock:
        _cache = (time.monotonic(), rows)
    return rows


def _copy[T](row: T) -> T:
    columns = row.__table__.columns  # type: ignore[attr-defined]
    return type(row)(**{c.key: getattr(row, c.key) for c in columns})


def forget_cache() -> None:
    global _cache
    with _lock:
        _cache = None


def searchable(faq: OfficialFaq, category: FaqCategory) -> tuple[str, str]:
    """(heading, body) for keyword ranking, both languages."""
    heading = f"{faq.question_zh} {faq.question_en} {category.name_zh} {category.name_en}"
    return heading.lower(), f"{faq.answer_zh} {faq.answer_en}".lower()


def search_faqs(db: Session, q: str, limit: int) -> list[FaqSummary]:
    rows = active_with_categories(db)
    found = relevant([((f, c), *searchable(f, c)) for f, c in rows], q, limit)
    return [summary(f) for f, _ in found]


# ---------- student posts close to a question ----------

RELATED_POSTS = 3
# Cosine distance; farther posts only share a few words with the question.
RELATED_MAX_DISTANCE = 0.45


def related_posts(
    db: Session,
    viewer: CurrentUser | None,
    faq_id: str,
    locale: Locale | None,
    limit: int = RELATED_POSTS,
) -> list[PublicExperience]:
    """Published posts nearest in meaning to this question (its stored embedding, so no AI
    call per request). Blocks and visibility are applied as everywhere else."""
    faq = db.get(OfficialFaq, faq_id)
    if faq is None or not faq.active:
        raise not_found("faq_not_found")
    vector = db.scalar(
        select(ContentEmbedding.embedding).where(
            ContentEmbedding.content_type == EMBEDDING_TYPE, ContentEmbedding.content_id == faq_id
        )
    )
    if vector is None:  # not indexed yet: fall back to the question's words
        from app.services.experiences import search

        return search(db, viewer, faq.question_zh or faq.question_en, locale, limit)
    distance = ContentEmbedding.embedding.cosine_distance(vector)
    ids = list(
        db.scalars(
            select(ContentEmbedding.content_id)
            .where(ContentEmbedding.content_type == "experience", distance < RELATED_MAX_DISTANCE)
            .order_by(distance)
            .limit(limit * 3)  # some may be hidden from this viewer
        )
    )
    if not ids:
        return []
    rows = db.execute(_public_query(viewer).where(Experience.id.in_(ids))).all()
    order = {experience_id: i for i, experience_id in enumerate(ids)}
    rows.sort(key=lambda row: order[row[0].id])
    return _public_items(db, rows[:limit], viewer, locale)
