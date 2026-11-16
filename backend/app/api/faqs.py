from fastapi import APIRouter, Query

from app.core.auth import OptionalUser
from app.core.db import DbSession
from app.services import faqs as svc
from app.services.experiences.schemas import Locale, PublicExperience

router = APIRouter(tags=["official-faq"])


@router.get("/faqs")
def list_faqs(db: DbSession) -> svc.FaqIndex:
    """Every official question with its category and identities; the app filters locally."""
    return svc.list_faqs(db)


@router.get("/faqs/{faq_id}")
def get_faq(faq_id: str, db: DbSession) -> svc.FaqDetail:
    return svc.get_faq(db, faq_id)


@router.get("/faqs/{faq_id}/related-posts")
def related_posts(
    faq_id: str,
    db: DbSession,
    viewer: OptionalUser,
    locale: Locale | None = None,
    limit: int = Query(default=svc.RELATED_POSTS, ge=1, le=6),
) -> list[PublicExperience]:
    """Student posts closest in meaning to the question (unverified personal experience)."""
    return svc.related_posts(db, viewer, faq_id, locale, limit)
