from typing import Annotated, Literal

from fastapi import APIRouter, BackgroundTasks, Depends, Query, Response, status
from pydantic import BaseModel

from app.ai.experience_ai import AIUnavailable, ExperienceAI, get_experience_ai
from app.core.auth import OptionalUser, RequiredUser
from app.core.config import get_settings
from app.core.db import DbSession, get_sessionmaker
from app.core.errors import ApiError
from app.rag.embedder import get_embedder
from app.rag.index import sync_in_background
from app.services import actions as action_svc
from app.services import experiences as svc
from app.services import metrics

router = APIRouter(tags=["experiences"])
AI = Annotated[ExperienceAI, Depends(get_experience_ai)]


@router.get("/experiences")
def explore(
    db: DbSession,
    viewer: OptionalUser,
    topic: svc.TopicId | None = None,
    identity_type: svc.IdentityType | None = None,
    q: str | None = Query(default=None, max_length=200),
    locale: svc.Locale | None = None,
    limit: int = Query(default=20, ge=1, le=50),
    offset: int = Query(default=0, ge=0),
) -> svc.ExperiencePage:
    return svc.explore(db, viewer, topic, identity_type, q, locale, limit, offset)


@router.get("/experiences/{experience_id}")
def get_experience(
    experience_id: str, db: DbSession, viewer: OptionalUser, locale: svc.Locale | None = None
) -> svc.ExperienceDetail:
    detail = svc.get_public(db, viewer, experience_id, locale)
    if viewer is not None:
        metrics.record_view(db, viewer.id, experience_id)
    return detail


@router.post("/experiences", status_code=status.HTTP_201_CREATED)
def create_draft(body: svc.DraftIn, user: RequiredUser, db: DbSession) -> svc.MyExperience:
    return svc.create_draft(db, user, body)


@router.patch("/experiences/{experience_id}")
def update_draft(
    experience_id: str, body: svc.DraftUpdate, user: RequiredUser, db: DbSession
) -> svc.MyExperience:
    return svc.update_draft(db, user, experience_id, body)


@router.delete("/experiences/{experience_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_experience(experience_id: str, user: RequiredUser, db: DbSession) -> Response:
    svc.delete_experience(db, user, experience_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/experiences/{experience_id}/summaries", status_code=status.HTTP_201_CREATED)
def generate_summary(
    experience_id: str, user: RequiredUser, db: DbSession, ai: AI
) -> svc.SummaryOut:
    limit = get_settings().ai_summaries_per_day
    return svc.generate_summary(db, user, experience_id, ai, limit)


@router.post("/experiences/{experience_id}/publish")
def publish(
    experience_id: str,
    body: svc.PublishIn,
    user: RequiredUser,
    db: DbSession,
    ai: AI,
    background: BackgroundTasks,
) -> svc.MyExperience:
    result = svc.publish(db, user, experience_id, body)
    # Translate first so the index includes both languages.
    background.add_task(svc.translate_in_background, get_sessionmaker(), ai, experience_id)
    background.add_task(
        sync_in_background, get_sessionmaker(), get_embedder(), "experience", experience_id
    )
    return result


class TranslationRequest(BaseModel):
    locale: svc.Locale


@router.post("/experiences/{experience_id}/translations")
def request_translation(
    experience_id: str, body: TranslationRequest, db: DbSession, viewer: OptionalUser, ai: AI
) -> svc.ExperienceDetail:
    """Translate now if no translation exists yet (e.g. the background job failed)."""
    try:
        svc.translate(db, ai, experience_id, body.locale)
    except AIUnavailable as exc:
        raise ApiError(503, "ai_unavailable") from exc
    return svc.get_public(db, viewer, experience_id, body.locale)


@router.put("/experiences/{experience_id}/reactions/{kind}")
def add_reaction(
    experience_id: str, kind: svc.ReactionKind, user: RequiredUser, db: DbSession
) -> svc.PublicExperience:
    return svc.set_reaction(db, user, experience_id, kind, True)


@router.delete("/experiences/{experience_id}/reactions/{kind}")
def remove_reaction(
    experience_id: str, kind: svc.ReactionKind, user: RequiredUser, db: DbSession
) -> svc.PublicExperience:
    return svc.set_reaction(db, user, experience_id, kind, False)


@router.get("/me/experiences")
def my_experiences(user: RequiredUser, db: DbSession) -> list[svc.MyExperience]:
    return svc.my_experiences(db, user)


@router.get("/me/experiences/{experience_id}")
def my_experience(experience_id: str, user: RequiredUser, db: DbSession) -> svc.MyExperience:
    return svc.get_mine(db, user, experience_id)


class SearchResults(BaseModel):
    actions: list[action_svc.ActionSummary]
    experiences: list[svc.PublicExperience]


@router.get("/search")
def search(
    db: DbSession,
    viewer: OptionalUser,
    q: str = Query(min_length=1, max_length=200),
    locale: svc.Locale | None = None,
    kind: Literal["all", "actions", "experiences"] = "all",
) -> SearchResults:
    """Keyword search over procedures and experiences (B-16); the assistant uses it too."""
    return SearchResults(
        actions=action_svc.search_actions(db, q, 10) if kind != "experiences" else [],
        experiences=(
            svc.explore(db, viewer, None, None, q, locale, 10, 0).items if kind != "actions" else []
        ),
    )
