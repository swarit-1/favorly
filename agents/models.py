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


class FavorReviewIn(BaseModel):
    """How a finished favor went. Rating is required, the comment is not."""

    reviewer_id: str
    rating: int = Field(ge=1, le=5)
    comment: str | None = None


class Requester(BaseModel):
    id: str
    display_name: str


class MatchEvidence(BaseModel):
    """The graph facts `reason` was written from, kept structured so a client
    can draw them instead of parsing them back out of a sentence.

    Nothing here is model-written: the model only ever phrases `reason`.
    `give_balance` is absent and stays absent -- see edges.py.
    """

    # Sent rather than left for the client to hardcode, so retuning the
    # scoring doesn't leave a UI explaining arithmetic that no longer runs.
    weights: dict[str, float] = Field(default_factory=dict)
    mutual_names: list[str] = Field(default_factory=list)
    favor_count: int = 0            # favors they did FOR the helper -- direction matters
    trip_reason: str | None = None
    fit_reason: str | None = None
    affinity_reason: str | None = None
    graph_reason: str | None = None  # the sentence the deterministic ranking would have written


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
    why: MatchEvidence = Field(default_factory=MatchEvidence)
    posted: str


class RecommendationsOut(BaseModel):
    person_id: str
    # Which path produced these: the model, or the deterministic graph ranking
    # (used when MOCK_LLM is on, the API is unavailable, or validation failed).
    decided_by: str
    favors: list[FavorSuggestion]


class SeedIn(BaseModel):
    scenario: str = "warm"  # warm | cold

