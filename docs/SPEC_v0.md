pip install -r requirements.txt# Favorly v0 — Engineering Spec (splits, models, pipelines, stack)

Companion to `PRD.md`. This document freezes three things so four people can build in parallel for 24h
without stepping on each other: (1) the work splits and their contracts, (2) the Pydantic models that
every VLM call and every API boundary must conform to, (3) the matching algorithms and pipeline flows
behind the three AI surfaces.

Principle carried from the PRD: **AI parses, matches, suggests. Humans approve. Nothing becomes canonical
until a shopper or requester confirms it.**

---

## 1. Work splits

Four lanes, one shared contract. Lane owners can be swapped, but the boundaries should not move.

| Lane | Owns | Consumes | Frozen artifact (H2) |
|---|---|---|---|
| **A. Contracts + Backend** | Pydantic models (`shared/contracts`), FastAPI routes, Postgres schema (Supabase), Realtime channels, seed script | — | `contracts/*.py`, `openapi.json`, migration `0001_init.sql` |
| **B. AI / Vision** | `VisionService` interface, Muse Spark + OpenAI adapters, prompts, matching algorithms (§4), cached-response fallback store | Contracts | `ai/vision_service.py`, `ai/fixtures/*.json` (canned output for every demo beat) |
| **C. Frontend (PWA)** | Next.js mobile screens for shopper + requester, camera/voice capture, realtime subscriptions, Venmo deep links | Contracts, Backend | Screens against mock API by H8 |
| **D. Demo + Data** | Demo circle seed, staged photos (handwritten list, shelf, receipt), rehearsal script, device testing (iOS PWA push, Venmo links) | Everything | `seed/demo_circle.json`, `seed/images/` |

**Dependency order:** A publishes contracts (H0–2) → B and C build against fixtures in parallel (H2–8) →
B swaps mock for real VLM (H8–14) → C wires realtime + substitution (H14–18) → D runs rehearsals (H18–24).

**Interface rules**
- Backend ↔ Flutter: REST JSON, every body/response is a Pydantic model serialized with `model_dump(mode="json")`; Dart types generated from `openapi.json` (or hand-written, minimal). Flutter SDK: `supabase-flutter` for auth/storage/realtime.
- Backend ↔ AI: in-process Python call through `VisionService` (no network hop in v0). AI returns a Pydantic model or raises `VisionError`; the backend persists the raw output in `parses.parsed_json` and never mutates it.
- Realtime: Supabase Realtime subscriptions on `trips`, `items`, `substitution_prompts`, `settlements` tables (Postgres NOTIFY/LISTEN). Flutter client subscribes per `trip_id`; backend WebSocket optional. Supabase broadcasts changes automatically.

---

## 2. Tech stack (boring on purpose)

| Layer | Choice | Why |
|---|---|---|
| Frontend | **Flutter 3.x**, Dart, native iOS/Android | Single codebase, native perf, 3 physical phones for demo |
| Backend | **FastAPI** (Python 3.11), Pydantic v2, `uvicorn` | Pydantic models double as VLM output schemas — one source of truth |
| Database | **Supabase** (PostgreSQL), `supabase-py` async client | One dashboard: auth, DB, storage, realtime. Free tier. |
| Auth | **Supabase Auth** (magic link, Google, anon) | Built-in, JWT compatible, works with FastAPI + Flutter SDK |
| Storage | **Supabase Storage** (S3-backed, images: lists, shelves, receipts) | Built-in to Supabase dashboard |
| Realtime | **Supabase Realtime** (Postgres NOTIFY/LISTEN) | Automatic on table subscriptions; Flutter SDK + FastAPI WebSocket both work |
| Primary VLM | **Meta Muse Spark** via Meta Model API — OpenAI-SDK-compatible, so `openai.OpenAI(base_url=META_BASE_URL, api_key=META_API_KEY)` | PRD requirement; same client code path as fallback |
| Fallback VLM | **OpenAI `gpt-4o`** via the same `openai` SDK, `response_format={"type":"json_schema", ...}` from `Model.model_json_schema()` | Structured outputs enforce the contract at the API layer |
| Speech | **OpenAI Whisper (`whisper-1`)**; fallback Deepgram `nova-2` | One-call transcript; transcript then goes through the text parser |
| Structured output | `openai` SDK + `pydantic` `model_validate_json`; retry once with a "repair" prompt on `ValidationError` | Strict JSON guaranteed at the boundary |
| Fuzzy matching | `rapidfuzz` (`token_set_ratio`) + a tiny synonym/brand table | Deterministic, offline, fast; no embedding service to run |
| Image handling | `Pillow` (downscale to ≤1600px, EXIF rotate, JPEG q85 before upload) | Cuts VLM latency and cost — every beat must be <20s |
| Deploy | Flutter: TestFlight/Play Store beta, Fly.io (backend), Supabase cloud | All free tiers; physical phones for demo |
| Dev | `uv` for Python, Flutter SDK, `docker-compose` optional | |

Both VLM adapters implement the same `VisionService` Protocol; `VISION_PROVIDER=muse|openai|mock` selects
at boot. Every VLM call is wrapped in `with_fallback(primary, fallback, cache_key)`: try Muse (timeout
12s) → OpenAI → cached fixture keyed by the staged image's hash. This is how success criterion "every
VLM-dependent demo beat has a cached fallback" is met structurally, not by hand. Cached fixtures and all
metadata are stored in Supabase PostgreSQL (table: `cached_vision_responses`).

---

## 3. Pydantic models

Package `shared/contracts` (`favorly_contracts`). All models: `ConfigDict(extra="forbid", str_strip_whitespace=True)`.
Stored in Supabase PostgreSQL tables (one model per table, e.g., `users`, `trips`, `items`).
IDs are `uuid4` strings (stored as PostgreSQL `uuid` type); money is `Decimal` quantized to cents (`condecimal(ge=0, decimal_places=2)`),
serialized as strings in JSON. Confidence is `float` in `[0,1]`.

### 3.1 Enums

```python
class TripStatus(StrEnum):      OPEN = "open"; SHOPPING = "shopping"; SETTLING = "settling"; DONE = "done"
class RequestStatus(StrEnum):   PENDING = "pending"; ACCEPTED = "accepted"; DECLINED = "declined"
class ItemStatus(StrEnum):      PENDING = "pending"; GOT = "got"; SUBSTITUTED = "substituted"; SKIPPED = "skipped"
class ParseSource(StrEnum):     TEXT = "text"; PHOTO = "photo"; VOICE = "voice"
class StoreSection(StrEnum):    PRODUCE = "produce"; DAIRY = "dairy"; MEAT = "meat"; BAKERY = "bakery"
                                FROZEN = "frozen"; PANTRY = "pantry"; BEVERAGES = "beverages"
                                HOUSEHOLD = "household"; PERSONAL_CARE = "personal_care"; OTHER = "other"
class LedgerEventType(StrEnum): TRIP_RUN = "trip_run"; FAVOR_RECEIVED = "favor_received"
class SubstitutionDecision(StrEnum): CHOOSE = "choose"; SKIP = "skip"; TIMEOUT_SKIP = "timeout_skip"
```

### 3.2 Domain entities (mirror PRD §7 tables)

```python
class User(BaseModel):
    id: UUID; circle_id: UUID; name: str; venmo_handle: str | None = None

class Circle(BaseModel):
    id: UUID; name: str; invite_code: str  # 6 chars, uppercase

class TripCaps(BaseModel):
    max_requesters: PositiveInt = 6
    max_dollars_per_person: Money = Decimal("40.00")
    max_items_per_person: PositiveInt = 8

class Trip(BaseModel):
    id: UUID; shopper_id: UUID; circle_id: UUID
    store: str; depart_at: datetime; caps: TripCaps
    status: TripStatus = TripStatus.OPEN
    created_at: datetime

class Item(BaseModel):
    id: UUID; request_id: UUID
    name: str; qty: PositiveInt = 1; unit: str | None = None      # "lb", "pack", "bunch"
    note: str | None = None; max_price: Money | None = None
    section: StoreSection = StoreSection.OTHER
    status: ItemStatus = ItemStatus.PENDING
    substitute_of: UUID | None = None                              # set on the replacement item
    actual_price: Money | None = None                              # filled from receipt split

class Request(BaseModel):
    id: UUID; trip_id: UUID; requester_id: UUID
    status: RequestStatus = RequestStatus.PENDING
    items: list[Item]

class Parse(BaseModel):
    id: UUID; user_id: UUID; source: ParseSource
    raw_ref: str                      # text body, or storage path for photo/audio
    transcript: str | None = None     # voice only
    parsed: ParsedList                # VLM output, immutable
    confirmed: bool = False
    confirmed_items: list[ItemDraft] | None = None   # what the human actually submitted

class Receipt(BaseModel):
    id: UUID; trip_id: UUID; image_ref: str
    split: ReceiptSplit               # VLM output, immutable
    assignments: list[LineAssignment] # canonical after shopper confirms

class Settlement(BaseModel):
    id: UUID; trip_id: UUID; requester_id: UUID
    lines: list[SettlementLine]; subtotal: Money; tax_share: Money; total: Money
    venmo_link: HttpUrl; marked_paid: bool = False

class LedgerEvent(BaseModel):
    id: UUID; circle_id: UUID; user_id: UUID
    type: LedgerEventType; value: Money; trip_id: UUID; created_at: datetime

class LedgerRow(BaseModel):           # read model for GET /circles/{id}/ledger
    user: User; trips_run: int; favors_received: int; dollars_carried: Money
```

### 3.3 VLM output models (AI Surfaces #1–#3) — the contract Muse/OpenAI must emit

```python
class ItemDraft(BaseModel):                      # shared by ParsedList and human-confirmed submission
    name: str = Field(min_length=1, max_length=80)
    qty: PositiveInt = 1
    unit: str | None = None
    note: str | None = None                      # "ripe", "unsalted", brand hints
    max_price: Money | None = None
    confidence: float = Field(ge=0, le=1)
    needs_confirmation: bool                     # True when confidence < 0.7 or qty/name ambiguous
    raw_span: str | None = None                  # the text/handwriting fragment this came from

class ParsedList(BaseModel):                     # Surface #1
    source: ParseSource
    items: list[ItemDraft] = Field(max_length=30)
    unparsed_fragments: list[str] = []           # things the model saw but couldn't turn into items
    language: str = "en"

class ShelfCandidate(BaseModel):
    name: str
    brand: str | None = None
    size: str | None = None                      # "16 oz"
    price: Money | None = None                   # only if legible on the shelf tag
    confidence: float = Field(ge=0, le=1)
    reason: str = Field(max_length=120)          # "same category, unsalted like the note"

class ShelfCandidates(BaseModel):                # Surface #2
    item_id: UUID
    original_item_name: str
    candidates: list[ShelfCandidate] = Field(max_length=4)   # 0 allowed = "nothing suitable"
    shelf_summary: str | None = None

class ReceiptLine(BaseModel):
    line_no: int
    description: str                             # as printed, e.g. "ORG BANANAS 2.31 LB"
    normalized_name: str                         # model's best guess at the product, "organic bananas"
    qty: Decimal = Decimal(1)
    unit_price: Money | None = None
    line_total: Money
    confidence: float = Field(ge=0, le=1)

class ReceiptSplit(BaseModel):                   # Surface #3 (extraction only; assignment is ours)
    store: str | None = None
    purchased_at: datetime | None = None
    lines: list[ReceiptLine]
    subtotal: Money; tax: Money; total: Money

    @model_validator(mode="after")
    def totals_reconcile(self):                  # PRD §10: split must reconcile to the receipt
        if abs(sum(l.line_total for l in self.lines) - self.subtotal) > Decimal("0.05"): raise ValueError("lines != subtotal")
        if abs(self.subtotal + self.tax - self.total) > Decimal("0.02"): raise ValueError("subtotal+tax != total")
        return self
```

### 3.4 Matching / settlement models (produced by our code, confirmed by humans)

```python
class LineAssignment(BaseModel):
    line_no: int
    item_id: UUID | None                         # None = shopper's own / unassigned
    requester_id: UUID | None
    score: float                                 # matcher score 0–1
    ambiguous: bool                              # True → shopper must confirm this line
    alternatives: list[UUID] = []                # other item_ids within the ambiguity band

class SettlementLine(BaseModel):
    item_id: UUID; description: str; amount: Money

class MergedListRow(BaseModel):                  # GET /trips/{id}/merged-list
    item: Item; requester: User; running_total: Money; cap: Money; over_cap: bool

class MergedList(BaseModel):
    trip_id: UUID
    sections: dict[StoreSection, list[MergedListRow]]     # ordered by STORE_SECTION_ORDER
    totals_by_requester: dict[UUID, Money]

class SubstitutionPrompt(BaseModel):             # realtime row the requester's phone subscribes to
    id: UUID; item_id: UUID; requester_id: UUID
    candidates: ShelfCandidates
    expires_at: datetime                         # now + N minutes (N=3 for demo)
    decision: SubstitutionDecision | None = None
    chosen_index: int | None = None
```

---

## 4. Matching algorithms

All three are deterministic, offline, and cheap. The VLM does perception; our code does matching, so
results are explainable and testable without an API key.

### 4.1 Section assignment (merged list ordering) — §4.3
- Static keyword table `SECTION_KEYWORDS: dict[StoreSection, list[str]]` (~150 words: "banana"→produce, "milk"→dairy…). Score each section by `max(token_set_ratio(item.name, kw))`; pick best if ≥ 80 else `OTHER`.
- Optional: ask the VLM for `section` inside `ItemDraft` and use it only as a tiebreaker. Not in v0 contract to keep the schema stable.
- Aisle order is `STORE_SECTION_ORDER` (produce → bakery → deli/meat → dairy → frozen → pantry → beverages → household → personal care → other). Per-store overrides are a v1 concern.

### 4.2 Duplicate merge across requesters (merged list) — §4.3
- Items from different requesters are **never merged** into one row (each row carries requester + cap). Instead, rows with `token_set_ratio(name_a, name_b) ≥ 90` are **grouped adjacently** with a "×2 neighbors want this" badge so the shopper grabs both at once. Pure display; no data change.

### 4.3 Cap enforcement — §4.1/4.3
- `running_total(requester) = Σ (item.max_price or estimated_price) over accepted items`; `over_cap = running_total > caps.max_dollars_per_person`. Estimated price for items with no `max_price` comes from a 50-row static price table (`PRICE_HINTS`) else $5.00. Shopper sees the flag; nothing is blocked automatically.

### 4.4 Substitution candidate ranking — §4.4
- VLM returns ≤4 candidates. We re-rank: `score = 0.6*confidence + 0.3*name_similarity(candidate, original) + 0.1*(price ≤ max_price ? 1 : 0)`. Candidates with `price > 1.5 × max_price` are dropped. Top-3 shown; order is the requester's choice list.
- Timeout policy: `SubstitutionPrompt.expires_at = now + 3 min`; a backend job (or the shopper's next poll) sets `decision=TIMEOUT_SKIP`, `item.status=SKIPPED`.

### 4.5 Receipt line → item assignment — §4.5 (the one that must reconcile)
Input: `ReceiptSplit.lines`, the trip's accepted `Item`s (including substitutes).

1. **Candidate scoring** for every (line, item) pair:
   `s = 0.55*token_set_ratio(line.normalized_name, item.name)/100 + 0.20*token_set_ratio(line.description, item.name)/100 + 0.15*price_fit + 0.10*qty_fit`
   where `price_fit = 1 - min(1, |line.line_total - item.max_price| / max(item.max_price, 1))` (0.5 if no cap) and `qty_fit = 1` if quantities match else 0.5.
2. **One-to-one assignment** with the Hungarian algorithm (`scipy.optimize.linear_sum_assignment` on `1-s`), lines > items allowed (extra lines = shopper's own).
3. **Thresholds:** `s ≥ 0.75` → assigned, not ambiguous. `0.5 ≤ s < 0.75` OR second-best within 0.1 of best → `ambiguous=True` with `alternatives`. `s < 0.5` → unassigned (`item_id=None`).
4. **Substituted items:** match against the *substitute's* name (`Item.substitute_of` chain) and credit the original requester.
5. **Human confirm:** shopper sees only ambiguous/unassigned lines (typically 0–3), taps the requester or "mine". `PATCH /receipts/{id}/assignments` makes it canonical.
6. **Settlement math:** `subtotal_r = Σ line_total for lines assigned to r`; `tax_share_r = tax × subtotal_r / Σ assigned subtotals` (rounded half-even to cents; last requester absorbs the rounding residue so Σ tax_share == tax exactly); `total_r = subtotal_r + tax_share_r`. Invariant asserted in a test: `Σ total_r + shopper_own == receipt.total`.
7. **Venmo link:** `https://venmo.com/{shopper_handle}?txn=pay&amount={total_r}&note=Favorly%20{store}%20{date}` (mobile: `venmo://paycharge?txn=pay&recipients={handle}&amount=…&note=…`, web link as fallback — test on both platforms at H2 per PRD §12).

### 4.6 Ledger increments — §4.6
- On `PATCH /trips/{id}/status → done`: one `TRIP_RUN` event for the shopper with `value = Σ requester totals`; one `FAVOR_RECEIVED` per requester with `value = total_r`. Ledger view is a `GROUP BY user_id` over events. Append-only; no edits.

---

## 5. Pipeline flows

### 5.1 Request intake (Surface #1)
```
[text]  ──────────────────────────────┐
[voice] → upload → Whisper → transcript┼→ VisionService.parse_list(source, text|image) → ParsedList
[photo] → upload → Pillow normalize ───┘         (Muse → OpenAI → cached fixture)
  → POST /parses stores {raw_ref, transcript, parsed}            (parses.confirmed=false)
  → requester edits items (needs_confirmation rows highlighted)
  → PATCH /parses/{id}/confirm {items: [ItemDraft]}  → assign sections (§4.1)
  → POST /trips/{id}/requests  → Request(pending) + Items      → realtime: shopper's list updates
```
Prompt contract for photo/text: system prompt includes `ParsedList.model_json_schema()`; instruction:
"Extract every shopping item. Never invent items. Set needs_confirmation=true when the handwriting or
quantity is unclear. Put anything you cannot turn into an item in unparsed_fragments." Temperature 0.

### 5.2 Shopper merged list
```
GET /trips/{id}/merged-list → accepted items → section (§4.1) → adjacency groups (§4.2) → caps (§4.3)
PATCH /requests/{id} accept|decline   (declines are invisible to the requester — status hidden client-side)
PATCH /trips/{id}/status shopping
```

### 5.3 Substitution (Surface #2) — the magic beat
```
Shopper taps "out of stock" on item → camera → upload shelf photo
  → VisionService.identify_shelf_candidates(item, image) → ShelfCandidates → re-rank (§4.4)
  → INSERT substitution_prompts (expires_at = +3m)      → realtime: requester's phone shows chooser
Requester taps candidate|skip → PATCH /substitutions/{id} {decision, chosen_index}
  → chosen: new Item(substitute_of=original, status=pending), original.status=substituted
  → skip / timeout: original.status=skipped
  → realtime: shopper's list updates live
```
Prompt: "You see a store shelf. The shopper needs `{item.name}` (`{item.note}`), budget `{max_price}`.
Return up to 4 products visible on the shelf that could substitute it. Include the price only if you can
read it on a tag. Rank by fit. Return [] if nothing fits."

### 5.4 Receipt split (Surface #3)
```
Shopper snaps receipt → upload → VisionService.split_receipt(image) → ReceiptSplit (validator: reconciles)
  → assign lines (§4.5 steps 1–4) → Receipt{split, assignments}
  → shopper confirms ambiguous lines → PATCH /receipts/{id}/assignments
  → compute Settlements (§4.5 step 6) → INSERT settlements  → realtime: requesters see "you owe $X" + Venmo link
  → PATCH /trips/{id}/status settling
```
If the reconciliation validator fails twice (Muse then OpenAI), fall back to the cached fixture for the staged receipt and surface a "receipt totals need a check" banner — the demo never blocks.

### 5.5 Handoff + ledger
```
POST /trips/{id}/handoff {photo?} → PATCH status done → ledger events (§4.6) → realtime: circle ledger view refreshes
```

### 5.6 Fallback chain (applies to every VLM call)
```
cache_key = sha256(image_bytes | text) + surface
1. Muse Spark (timeout 12s, 1 retry on ValidationError with repair prompt)
2. OpenAI gpt-4o structured output (timeout 12s)
3. ai/fixtures/{cache_key}.json  (pre-recorded during H18–22 for every staged demo image)
Always: persist raw model text + provider + latency in parses.raw_ref metadata for the post-mortem.
```

---

## 6. Test plan (what "contracts frozen" means)
- `tests/test_contracts.py`: every fixture in `ai/fixtures/` validates against its model; `ReceiptSplit` reconciliation validator rejects a fixture off by $0.10. Fixtures are seeded into Supabase during test setup.
- `tests/test_matching.py`: golden receipt (12 lines, 3 requesters, 1 substitute) → assignments and settlements sum to the receipt total to the cent; ambiguity band produces exactly the expected lines.
- `tests/test_sections.py`: 40 item names → expected sections.
- `tests/test_fallback.py`: primary raises → fallback used → cache checked in Supabase → provider recorded.

---

## 7. Open decisions for the PM (need answers before H2)
1. Does Muse Spark's OpenAI-compatible endpoint support `response_format=json_schema`? If not, we prompt for JSON and validate/repair (already in the flow) — confirm at the Meta booth H0.
2. Tax share: proportional (PRD) vs. only on taxable lines — v0 goes proportional; confirm.
3. Substitution timeout N: proposing 3 minutes for the demo, configurable per trip.
4. Voice for "Post Trip" (PRD §8 beat 1): parse `store` + `depart_at` with the same text parser via a tiny `TripDraft` model (`store: str; depart_at: datetime; confidence`) — adding it to §3.3 unless you object.
5. Flutter vs. native web: v0 uses Flutter (native iOS/Android); web PWA is a v1 post-launch concern if needed.

---

## Lane specs

- [A — Contracts + Backend](specs/A-contracts-backend.md)
- [B — AI / Vision](specs/B-ai-vision.md)
- [C — Frontend PWA](specs/C-frontend.md)
- [D — Demo + Data](specs/D-demo-data.md)
