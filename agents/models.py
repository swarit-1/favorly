"""Request/response models for the API surface."""

from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field


class EventIn(BaseModel):
    person_id: str
    kind: str = Field(default="message")  # message | favor_logged | system
    body: str
    source_key: Optional[str] = None
    occurred_at: Optional[datetime] = None


class FavorIn(BaseModel):
    giver_id: str
    receiver_id: str
    description: str


class NeedIn(BaseModel):
    person_id: str
    body: str


class NeedClaimIn(BaseModel):
    person_id: str


class Requester(BaseModel):
    id: str
    display_name: str


class FavorSuggestion(BaseModel):
    """One favor the frontend can render as a card and act on."""

    need_id: str
    title: str                      # short card header, e.g. "Grab oat milk for Bob"
    action: str                     # what you'd actually do
    requested_by: Requester
    original_request: str           # verbatim, so the UI can show the real ask
    reason: str                     # why this person, in one sentence
    effort: str = "medium"          # low | medium | high
    score: float
    signals: dict[str, float]       # what the graph contributed, for transparency
    posted: str


class RecommendationsOut(BaseModel):
    person_id: str
    # Which path produced these: the model, or the deterministic graph ranking
    # (used when MOCK_LLM is on, the API is unavailable, or validation failed).
    decided_by: str
    favors: list[FavorSuggestion]


class SeedIn(BaseModel):
    scenario: str = "warm"  # warm | cold


class TickIn(BaseModel):
    steps: int = 1
