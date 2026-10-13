"""Request and response bodies for /assistant."""

from datetime import datetime
from typing import Annotated, Any, Literal

from pydantic import BaseModel, Field

from app.assistant.data import Locale, TopicId, VerificationStatus

ScreenActionType = Literal[
    "open_action", "open_experience", "open_explore", "open_share", "open_progress"
]


class ScreenContext(BaseModel):
    """What the user is looking at when they open the floating assistant."""

    route: str | None = Field(default=None, max_length=200)
    action_id: str | None = Field(default=None, max_length=100)
    experience_id: str | None = Field(default=None, max_length=100)


class AssistantMessageRequest(BaseModel):
    message: str = Field(min_length=1, max_length=1000)
    conversation_id: str | None = Field(default=None, max_length=100)
    locale: Locale = "zh-Hant"
    screen: ScreenContext | None = None


class ScreenAction(BaseModel):
    """A navigation the app may perform; the app executes only these whitelisted types."""

    type: ScreenActionType
    target_id: str | None = None
    topic: TopicId | None = None


class ActionCard(BaseModel):
    type: Literal["action"] = "action"
    action_id: str
    title: str
    verification_status: VerificationStatus
    last_verified_at: str | None
    recent_success_count: int
    sources: list[str]


class ExperienceCard(BaseModel):
    type: Literal["experience"] = "experience"
    experience_id: str
    label: Literal["student_experience"] = "student_experience"
    reminder: str


Card = Annotated[ActionCard | ExperienceCard, Field(discriminator="type")]


class PendingOperationOut(BaseModel):
    """A write the user must confirm in the app (POST /assistant/operations/{id}/confirm)."""

    id: str
    type: Literal["start_action"]
    target_id: str
    summary: str
    status: Literal["pending", "confirmed", "cancelled", "expired", "failed"]
    expires_at: datetime
    result: dict[str, Any] | None = None


class AssistantReply(BaseModel):
    conversation_id: str
    text: str
    cards: list[Card] = []
    screen_actions: list[ScreenAction] = []
    pending_operations: list[PendingOperationOut] = []
    tools_used: list[str] = []
    fallback: bool = False
