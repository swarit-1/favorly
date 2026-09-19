"""Favorly Pydantic models — contracts for all API boundaries and VLM outputs."""

from datetime import datetime
from decimal import Decimal
from enum import Enum
from uuid import UUID, uuid4
from typing import Optional, List
from pydantic import BaseModel, Field, field_validator, model_validator, HttpUrl
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


# Store section order for aisle sorting
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

def condecimal(ge: float = 0, decimal_places: int = 2):
    """Helper for Decimal fields: quantized to cents, non-negative."""
    return Decimal(f"0.{'0' * decimal_places}")


class User(BaseModel):
    model_config = dict(extra="forbid", str_strip_whitespace=True)

    id: UUID = Field(default_factory=uuid4)
    circle_id: UUID
    name: str
    venmo_handle: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)


class Circle(BaseModel):
    model_config = dict(extra="forbid", str_strip_whitespace=True)

    id: UUID = Field(default_factory=uuid4)
    name: str
    invite_code: str = Field(min_length=6, max_length=6)  # "ABC123"
    created_at: datetime = Field(default_factory=datetime.utcnow)


class TripCaps(BaseModel):
    model_config = dict(extra="forbid", str_strip_whitespace=True)

    max_requesters: int = Field(default=6, ge=1)
    max_dollars_per_person: Decimal = Field(default=Decimal("40.00"), ge=0, decimal_places=2)
    max_items_per_person: int = Field(default=8, ge=1)


class Trip(BaseModel):
    model_config = dict(extra="forbid", str_strip_whitespace=True)

    id: UUID = Field(default_factory=uuid4)
    shopper_id: UUID
    circle_id: UUID
    store: str
    depart_at: datetime
    caps: TripCaps = Field(default_factory=TripCaps)
    status: TripStatus = TripStatus.OPEN
    created_at: datetime = Field(default_factory=datetime.utcnow)


class Item(BaseModel):
    model_config = dict(extra="forbid", str_strip_whitespace=True)

    id: UUID = Field(default_factory=uuid4)
    request_id: UUID
    trip_id: UUID
    name: str
    qty: int = Field(default=1, ge=1)
    unit: Optional[str] = None  # "lb", "pack", "bunch"
    note: Optional[str] = None  # "ripe", "unsalted", brand hints
    max_price: Optional[Decimal] = Field(default=None, decimal_places=2)
    section: StoreSection = StoreSection.OTHER
    status: ItemStatus = ItemStatus.PENDING
    substitute_of: Optional[UUID] = None  # set on replacement item
    actual_price: Optional[Decimal] = Field(default=None, decimal_places=2)  # from receipt split
    created_at: datetime = Field(default_factory=datetime.utcnow)


class Request(BaseModel):
    model_config = dict(extra="forbid", str_strip_whitespace=True)

    id: UUID = Field(default_factory=uuid4)
    trip_id: UUID
    requester_id: UUID
    status: RequestStatus = RequestStatus.PENDING
    items: List[Item] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=datetime.utcnow)


class Parse(BaseModel):
    model_config = dict(extra="forbid", str_strip_whitespace=True)

    id: UUID = Field(default_factory=uuid4)
    user_id: UUID
    source: ParseSource
    raw_ref: str  # text body, or storage path for photo/audio
    transcript: Optional[str] = None  # voice only
    parsed: Optional[dict] = None  # ParsedList (stored as dict in MongoDB)
    confirmed: bool = False
    confirmed_items: Optional[List[dict]] = None  # ItemDraft list (stored as dict)
    created_at: datetime = Field(default_factory=datetime.utcnow)


class Receipt(BaseModel):
    model_config = dict(extra="forbid", str_strip_whitespace=True)

    id: UUID = Field(default_factory=uuid4)
    trip_id: UUID
    image_ref: str
    split: Optional[dict] = None  # ReceiptSplit (stored as dict)
    assignments: Optional[List[dict]] = None  # LineAssignment list
    created_at: datetime = Field(default_factory=datetime.utcnow)


class Settlement(BaseModel):
    model_config = dict(extra="forbid", str_strip_whitespace=True)

    id: UUID = Field(default_factory=uuid4)
    trip_id: UUID
    requester_id: UUID
    lines: List[dict] = Field(default_factory=list)  # SettlementLine list
    subtotal: Decimal = Field(decimal_places=2)
    tax_share: Decimal = Field(decimal_places=2)
    total: Decimal = Field(decimal_places=2)
    venmo_link: Optional[str] = None  # HttpUrl serialized as string
    marked_paid: bool = False
    created_at: datetime = Field(default_factory=datetime.utcnow)


class LedgerEvent(BaseModel):
    model_config = dict(extra="forbid", str_strip_whitespace=True)

    id: UUID = Field(default_factory=uuid4)
    circle_id: UUID
    user_id: UUID
    type: LedgerEventType
    value: Decimal = Field(decimal_places=2)
    trip_id: Optional[UUID] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)


class LedgerRow(BaseModel):
    model_config = dict(extra="forbid", str_strip_whitespace=True)

    user: User
    trips_run: int
    favors_received: int
    dollars_carried: Decimal = Field(decimal_places=2)


# ============================================================================
# VLM OUTPUT MODELS (AI Surfaces #1–#3)
# ============================================================================

class ItemDraft(BaseModel):
    model_config = dict(extra="forbid", str_strip_whitespace=True)

    name: str = Field(min_length=1, max_length=80)
    qty: int = Field(default=1, ge=1)
    unit: Optional[str] = None
    note: Optional[str] = None  # "ripe", "unsalted", brand hints
    max_price: Optional[Decimal] = Field(default=None, decimal_places=2)
    confidence: float = Field(ge=0, le=1)
    needs_confirmation: bool  # True if confidence < 0.7 or qty/name ambiguous
    raw_span: Optional[str] = None  # text/handwriting fragment


class ParsedList(BaseModel):
    model_config = dict(extra="forbid", str_strip_whitespace=True)

    source: ParseSource
    items: List[ItemDraft] = Field(max_length=30)
    unparsed_fragments: List[str] = Field(default_factory=list)
    language: str = "en"


class ShelfCandidate(BaseModel):
    model_config = dict(extra="forbid", str_strip_whitespace=True)

    name: str
    brand: Optional[str] = None
    size: Optional[str] = None  # "16 oz"
    price: Optional[Decimal] = Field(default=None, decimal_places=2)
    confidence: float = Field(ge=0, le=1)
    reason: str = Field(max_length=120)


class ShelfCandidates(BaseModel):
    model_config = dict(extra="forbid", str_strip_whitespace=True)

    item_id: UUID
    original_item_name: str
    candidates: List[ShelfCandidate] = Field(max_length=4)
    shelf_summary: Optional[str] = None


class ReceiptLine(BaseModel):
    model_config = dict(extra="forbid", str_strip_whitespace=True)

    line_no: int
    description: str  # as printed, e.g. "ORG BANANAS 2.31 LB"
    normalized_name: str  # model's best guess, e.g. "organic bananas"
    qty: Decimal = Field(default=Decimal(1))
    unit_price: Optional[Decimal] = Field(default=None, decimal_places=2)
    line_total: Decimal = Field(decimal_places=2)
    confidence: float = Field(ge=0, le=1)


class ReceiptSplit(BaseModel):
    model_config = dict(extra="forbid", str_strip_whitespace=True)

    store: Optional[str] = None
    purchased_at: Optional[datetime] = None
    lines: List[ReceiptLine]
    subtotal: Decimal = Field(decimal_places=2)
    tax: Decimal = Field(decimal_places=2)
    total: Decimal = Field(decimal_places=2)

    @model_validator(mode="after")
    def totals_reconcile(self):
        """PRD §10: split must reconcile to the receipt."""
        lines_sum = sum(line.line_total for line in self.lines)
        if abs(lines_sum - self.subtotal) > Decimal("0.05"):
            raise ValueError(f"lines sum ({lines_sum}) != subtotal ({self.subtotal})")
        if abs(self.subtotal + self.tax - self.total) > Decimal("0.02"):
            raise ValueError(f"subtotal+tax ({self.subtotal + self.tax}) != total ({self.total})")
        return self


# ============================================================================
# MATCHING / SETTLEMENT MODELS
# ============================================================================

class LineAssignment(BaseModel):
    model_config = dict(extra="forbid", str_strip_whitespace=True)

    line_no: int
    item_id: Optional[UUID] = None  # None = shopper's own / unassigned
    requester_id: Optional[UUID] = None
    score: float = Field(ge=0, le=1)
    ambiguous: bool = False
    alternatives: List[UUID] = Field(default_factory=list)


class SettlementLine(BaseModel):
    model_config = dict(extra="forbid", str_strip_whitespace=True)

    item_id: UUID
    description: str
    amount: Decimal = Field(decimal_places=2)


class MergedListRow(BaseModel):
    model_config = dict(extra="forbid", str_strip_whitespace=True)

    item: Item
    requester: User
    running_total: Decimal = Field(decimal_places=2)
    cap: Decimal = Field(decimal_places=2)
    over_cap: bool = False


class MergedList(BaseModel):
    model_config = dict(extra="forbid", str_strip_whitespace=True)

    trip_id: UUID
    sections: dict[StoreSection, List[MergedListRow]] = Field(default_factory=dict)
    totals_by_requester: dict[UUID, Decimal] = Field(default_factory=dict)


class SubstitutionPrompt(BaseModel):
    model_config = dict(extra="forbid", str_strip_whitespace=True)

    id: UUID = Field(default_factory=uuid4)
    item_id: UUID
    requester_id: UUID
    candidates: ShelfCandidates
    expires_at: datetime
    decision: Optional[SubstitutionDecision] = None
    chosen_index: Optional[int] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)
