"""Favorly Pydantic models — contracts for all API boundaries and VLM outputs."""

from datetime import datetime
from decimal import Decimal
from enum import Enum
from uuid import UUID, uuid4
from typing import Optional, List
from pydantic import BaseModel, Field, field_validator, model_validator, HttpUrl, ConfigDict, field_serializer
from pydantic_settings import BaseSettings


# ============================================================================
# ENUMS
# ============================================================================

class TripStatus(str, Enum):
    OPEN = "open"
    SHOPPING = "shopping"
    SETTLING = "settling"
    DONE = "done"


class RequestStatus(str, Enum):
    PENDING = "pending"
    ACCEPTED = "accepted"
    DECLINED = "declined"


class ItemStatus(str, Enum):
    PENDING = "pending"
    GOT = "got"
    SUBSTITUTED = "substituted"
    SKIPPED = "skipped"


class ParseSource(str, Enum):
    TEXT = "text"
    PHOTO = "photo"
    VOICE = "voice"


class StoreSection(str, Enum):
    PRODUCE = "produce"
    DAIRY = "dairy"
    MEAT = "meat"
    BAKERY = "bakery"
    FROZEN = "frozen"
    PANTRY = "pantry"
    BEVERAGES = "beverages"
    HOUSEHOLD = "household"
    PERSONAL_CARE = "personal_care"
    OTHER = "other"


class LedgerEventType(str, Enum):
    TRIP_RUN = "trip_run"
    FAVOR_RECEIVED = "favor_received"


class SubstitutionDecision(str, Enum):
    CHOOSE = "choose"
    SKIP = "skip"
    TIMEOUT_SKIP = "timeout_skip"


STORE_SECTION_ORDER = [
    StoreSection.PRODUCE,
    StoreSection.BAKERY,
    StoreSection.MEAT,
    StoreSection.DAIRY,
    StoreSection.FROZEN,
    StoreSection.PANTRY,
    StoreSection.BEVERAGES,
    StoreSection.HOUSEHOLD,
    StoreSection.PERSONAL_CARE,
    StoreSection.OTHER,
]


# ============================================================================
# DOMAIN ENTITIES
# ============================================================================

class User(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    id: UUID = Field(default_factory=uuid4)
    circle_id: UUID
    name: str
    venmo_handle: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)


class Circle(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    id: UUID = Field(default_factory=uuid4)
    name: str
    invite_code: str = Field(min_length=6, max_length=6)
    created_at: datetime = Field(default_factory=datetime.utcnow)


class TripCaps(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    max_requesters: int = Field(default=6, ge=1)
    max_dollars_per_person: float = Field(default=40.00, ge=0)
    max_items_per_person: int = Field(default=8, ge=1)


class Trip(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    id: UUID = Field(default_factory=uuid4)
    shopper_id: UUID
    circle_id: UUID
    store: str
    depart_at: datetime
    caps: TripCaps = Field(default_factory=TripCaps)
    status: TripStatus = TripStatus.OPEN
    created_at: datetime = Field(default_factory=datetime.utcnow)


class Item(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    id: UUID = Field(default_factory=uuid4)
    request_id: UUID
    trip_id: UUID
    name: str
    qty: int = Field(default=1, ge=1)
    unit: Optional[str] = None
    note: Optional[str] = None
    max_price: Optional[float] = None
    section: StoreSection = StoreSection.OTHER
    status: ItemStatus = ItemStatus.PENDING
    substitute_of: Optional[UUID] = None
    actual_price: Optional[float] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)


class Request(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    id: UUID = Field(default_factory=uuid4)
    trip_id: UUID
    requester_id: UUID
    status: RequestStatus = RequestStatus.PENDING
    items: List[Item] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=datetime.utcnow)


class Parse(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    id: UUID = Field(default_factory=uuid4)
    user_id: UUID
    source: ParseSource
    raw_ref: str
    transcript: Optional[str] = None
    parsed: Optional[dict] = None
    confirmed: bool = False
    confirmed_items: Optional[List[dict]] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)


class Receipt(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    id: UUID = Field(default_factory=uuid4)
    trip_id: UUID
    image_ref: str
    split: Optional[dict] = None
    assignments: Optional[List[dict]] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)


class Settlement(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    id: UUID = Field(default_factory=uuid4)
    trip_id: UUID
    requester_id: UUID
    lines: List[dict] = Field(default_factory=list)
    subtotal: float
    tax_share: float
    total: float
    venmo_link: Optional[str] = None
    marked_paid: bool = False
    created_at: datetime = Field(default_factory=datetime.utcnow)


class LedgerEvent(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    id: UUID = Field(default_factory=uuid4)
    circle_id: UUID
    user_id: UUID
    type: LedgerEventType
    value: float
    trip_id: Optional[UUID] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)


class LedgerRow(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    user: User
    trips_run: int
    favors_received: int
    dollars_carried: float


# ============================================================================
# VLM OUTPUT MODELS (AI Surfaces #1–#3)
# ============================================================================

class ItemDraft(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    name: str = Field(min_length=1, max_length=80)
    qty: int = Field(default=1, ge=1)
    unit: Optional[str] = None
    note: Optional[str] = None
    max_price: Optional[float] = None
    confidence: float = Field(ge=0, le=1)
    needs_confirmation: bool
    raw_span: Optional[str] = None


class ParsedList(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    source: ParseSource
    items: List[ItemDraft] = Field(max_length=30)
    unparsed_fragments: List[str] = Field(default_factory=list)
    language: str = "en"


class ShelfCandidate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    name: str
    brand: Optional[str] = None
    size: Optional[str] = None
    price: Optional[float] = None
    confidence: float = Field(ge=0, le=1)
    reason: str = Field(max_length=120)


class ShelfCandidates(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    item_id: UUID
    original_item_name: str
    candidates: List[ShelfCandidate] = Field(max_length=4)
    shelf_summary: Optional[str] = None


class ReceiptLine(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    line_no: int
    description: str
    normalized_name: str
    qty: float = Field(default=1.0)
    unit_price: Optional[float] = None
    line_total: float
    confidence: float = Field(ge=0, le=1)


class ReceiptSplit(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    store: Optional[str] = None
    purchased_at: Optional[datetime] = None
    lines: List[ReceiptLine]
    subtotal: float
    tax: float
    total: float

    @model_validator(mode="after")
    def totals_reconcile(self):
        lines_sum = sum(line.line_total for line in self.lines)
        if abs(lines_sum - self.subtotal) > 0.05:
            raise ValueError(f"lines sum ({lines_sum}) != subtotal ({self.subtotal})")
        if abs(self.subtotal + self.tax - self.total) > 0.02:
            raise ValueError(f"subtotal+tax ({self.subtotal + self.tax}) != total ({self.total})")
        return self


# ============================================================================
# MATCHING / SETTLEMENT MODELS
# ============================================================================

class LineAssignment(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    line_no: int
    item_id: Optional[UUID] = None
    requester_id: Optional[UUID] = None
    score: float = Field(ge=0, le=1)
    ambiguous: bool = False
    alternatives: List[UUID] = Field(default_factory=list)


class SettlementLine(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    item_id: UUID
    description: str
    amount: float


class MergedListRow(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    item: Item
    requester: User
    running_total: float
    cap: float
    over_cap: bool = False


class MergedList(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    trip_id: UUID
    sections: dict[StoreSection, List[MergedListRow]] = Field(default_factory=dict)
    totals_by_requester: dict[UUID, float] = Field(default_factory=dict)


class SubstitutionPrompt(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    id: UUID = Field(default_factory=uuid4)
    item_id: UUID
    requester_id: UUID
    candidates: ShelfCandidates
    expires_at: datetime
    decision: Optional[SubstitutionDecision] = None
    chosen_index: Optional[int] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)
