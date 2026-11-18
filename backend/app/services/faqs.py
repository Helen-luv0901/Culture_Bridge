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
from typing import Literal

from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy import text as sql
from sqlalchemy.orm import Session

from app.core.auth import CurrentUser
from app.core.config import get_settings
from app.core.errors import not_found
from app.core.text_search import relevant
from app.models import (
    ContentEmbedding,
    Experience,
    ExperienceTranslation,
    FaqCategory,
    FaqIdentity,
    OfficialFaq,
)
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


class FaqReview(BaseModel):
    """A warning from the reviewed consistency pass (migration 0017)."""

    kind: Literal["superseded", "conflict", "time_limited"]
    note: Text2
    # The newer question that replaced this answer, when there is one.
    superseded_by: str | None = None


class FaqSummary(BaseModel):
    id: str
    category_id: str
    identities: list[str]
    question: Text2
    excerpt: Text2
    posted_on: date | None
    # False: the English text is the Chinese original (the site has no English version).
    has_english: bool
    # "school": asked by international-office staff about school administration; ranked after
    # student questions and labelled in the app.
    audience: Literal["student", "school"] = "student"
    review: FaqReview | None = None


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
        audience=faq.audience or "student",
        review=FaqReview(
            kind=faq.review_kind,
            note=both(faq.review_note_zh, faq.review_note_en),
            superseded_by=faq.superseded_by,
        )
        if faq.review_kind
        else None,
    )


def demoted(faq: OfficialFaq) -> bool:
    """School administration, or an answer a newer one replaced / a measure that ended."""
    return faq.audience == "school" or faq.review_kind in ("superseded", "time_limited")


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


def demote_last[T](items: list[T], is_demoted) -> list[T]:
    """Keep the order but move school-administration and outdated questions after the rest."""
    return [i for i in items if not is_demoted(i)] + [i for i in items if is_demoted(i)]


def search_faqs(db: Session, q: str, limit: int) -> list[FaqSummary]:
    rows = active_with_categories(db)
    found = relevant([((f, c), *searchable(f, c)) for f, c in rows], q, limit * 2)
    return [summary(f) for f, _ in demote_last(found, lambda fc: demoted(fc[0]))[:limit]]


# ---------- questions and posts recommended for each other ----------
#
# Nearest-by-distance alone failed in production (2026-11-18): short student posts sit "close"
# to almost every long official answer, so 224 of 227 questions showed the same six posts. A
# pair is recommended only when it is mutual: the post is among the question's K_POSTS nearest
# posts AND the question is among the post's K_FAQS nearest questions. A post can then appear
# under a handful of questions at most, and no distance threshold has to be tuned.

#
# Mutual alone still paired unrelated things in production (rescan 2026-11-19): of 17 posts
# most are tests or food chat ("rrq bengek", "Place to Go?"), and each is still some question's
# nearest. A pair must therefore also share words: the question has to be among the keyword
# matches for the post's title (either language). Checked against all 17 production posts, this
# kept 6 pairs that are about the same thing (national insurance within 6 months, an enrollment
# certificate for the ARC, the language barrier) and dropped every unrelated one. Meaning finds
# the candidates, words confirm them; no distance threshold to tune.

RELATED_POSTS = 3
K_POSTS = 10
K_FAQS = 3
KEYWORD_FAQS = 5  # keyword matches per post title that may confirm a pair
TITLE_FALLBACK_CHARS = 80

_POSTS_FOR_FAQ = sql(
    """
    WITH f AS (
      SELECT embedding FROM content_embeddings
      WHERE content_type = 'official_faq' AND content_id = :faq_id
    ), candidate AS (
      SELECT e.content_id, e.embedding, e.embedding <=> f.embedding AS d
      FROM content_embeddings e, f
      WHERE e.content_type = 'experience'
      ORDER BY d
      LIMIT :k_posts
    )
    SELECT c.content_id,
      (SELECT count(*) FROM content_embeddings o
         JOIN official_faqs q ON q.id = o.content_id AND q.active
       WHERE o.content_type = 'official_faq' AND (o.embedding <=> c.embedding) < c.d) AS rank
    FROM candidate c
    WHERE c.d < :max_distance
    ORDER BY c.d
    """
)

_FAQS_FOR_POST = sql(
    """
    WITH p AS (
      SELECT embedding FROM content_embeddings
      WHERE content_type = 'experience' AND content_id = :post_id
    ), candidate AS (
      SELECT o.content_id, o.embedding, o.embedding <=> p.embedding AS d
      FROM content_embeddings o
        JOIN official_faqs q ON q.id = o.content_id AND q.active, p
      WHERE o.content_type = 'official_faq'
      ORDER BY d
      LIMIT :k_faqs
    )
    SELECT c.content_id,
      (SELECT count(*) FROM content_embeddings e
       WHERE e.content_type = 'experience' AND (e.embedding <=> c.embedding) < c.d) AS rank
    FROM candidate c
    WHERE c.d < :max_distance
    ORDER BY c.d
    """
)


def _active_faq(db: Session, faq_id: str) -> OfficialFaq:
    faq = db.get(OfficialFaq, faq_id)
    if faq is None or not faq.active:
        raise not_found("faq_not_found")
    return faq


def _indexed(db: Session, content_type: str, content_id: str) -> bool:
    return (
        db.scalar(
            select(ContentEmbedding.content_id).where(
                ContentEmbedding.content_type == content_type,
                ContentEmbedding.content_id == content_id,
            )
        )
        is not None
    )


def related_posts(
    db: Session,
    viewer: CurrentUser | None,
    faq_id: str,
    locale: Locale | None,
    limit: int = RELATED_POSTS,
) -> list[PublicExperience]:
    """Published posts that are about the same thing as this question (mutual nearest
    neighbours of the stored embeddings, so no AI call per request). Blocks and visibility are
    applied as everywhere else; none is better than an unrelated one."""
    faq = _active_faq(db, faq_id)
    if not _indexed(db, EMBEDDING_TYPE, faq_id):  # not embedded yet: the question's words
        from app.services.experiences import search

        return search(db, viewer, faq.question_zh or faq.question_en, locale, limit)
    found = db.execute(
        _POSTS_FOR_FAQ,
        {
            "faq_id": faq_id,
            "k_posts": K_POSTS,
            "max_distance": get_settings().semantic_max_distance,
        },
    ).all()
    ids = [
        post_id for post_id, rank in found if rank < K_FAQS and faq_id in _keyword_faqs(db, post_id)
    ]
    if not ids:
        return []
    rows = db.execute(_public_query(viewer).where(Experience.id.in_(ids))).all()
    order = {experience_id: i for i, experience_id in enumerate(ids)}
    rows.sort(key=lambda row: order[row[0].id])
    return _public_items(db, rows[:limit], viewer, locale)


RELATED_FAQS = 3


def _keyword_faqs(db: Session, experience_id: str) -> set[str]:
    """Questions the post's title finds by keywords, in its own language or its translation."""
    experience = db.get(Experience, experience_id)
    if experience is None:
        return set()
    # A post may have no title (older ones): its opening words say what it is about.
    titles = [experience.title or (experience.original_voice or "")[:TITLE_FALLBACK_CHARS]]
    for title, voice in db.execute(
        select(ExperienceTranslation.title, ExperienceTranslation.original_voice).where(
            ExperienceTranslation.experience_id == experience_id,
            ExperienceTranslation.summary_id == experience.confirmed_summary_id,
        )
    ):
        titles.append(title or (voice or "")[:TITLE_FALLBACK_CHARS])
    docs = [(f.id, *searchable(f, c)) for f, c in active_with_categories(db)]
    found: set[str] = set()
    for title in titles:
        if title:
            found.update(relevant(docs, title, KEYWORD_FAQS))
    return found


def related_faqs(
    db: Session,
    viewer: CurrentUser | None,
    experience_id: str,
    limit: int = RELATED_FAQS,
) -> list[FaqSummary]:
    """Official questions about what this post describes, by the same mutual rule; school
    administration and outdated answers are left out (a student reading a post wants rules)."""
    from app.services.experiences import get_public

    get_public(db, viewer, experience_id, None)  # 404 when hidden, deleted or blocked
    if not _indexed(db, "experience", experience_id):
        return []
    found = db.execute(
        _FAQS_FOR_POST,
        {
            "post_id": experience_id,
            "k_faqs": K_FAQS,
            "max_distance": get_settings().semantic_max_distance,
        },
    ).all()
    words = _keyword_faqs(db, experience_id)
    ids = [faq_id for faq_id, rank in found if rank < K_POSTS and faq_id in words]
    by_id = {f.id: f for f, _ in active_with_categories(db)}
    faqs = [by_id[i] for i in ids if i in by_id and not demoted(by_id[i])]
    return [summary(f) for f in faqs[:limit]]
