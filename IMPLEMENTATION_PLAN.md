# Implementation Plan — Supabase + Flutter Edition

**Timeline:** 24 hours from H0 (project start)

---

## Work Lanes

| Lane | Owns | Tech | Frozen by | Status |
|------|------|------|-----------|--------|
| **A. Backend** | FastAPI, Pydantic models, Supabase schema | FastAPI, Python | H2 | ✅ Ready |
| **B. AI/Vision** | VisionService, LLM integration, matching | Python | H8–H14 | Blocked on A |
| **C. Frontend** | Flutter mobile app, UI/UX, realtime | Flutter, Dart | H8–H18 | Blocked on A |
| **D. Demo** | Seed data, staged images, rehearsal | JSON, images | H18–H24 | Blocked on A–C |

**Dependency:** A → {B & C in parallel} → D

---

## H0–H2: Lane A (Backend Contracts)

### Deliverables
✅ **Pydantic models** (15 total) — frozen API contract
✅ **Supabase schema** (10 tables) — frozen database schema
✅ **FastAPI routes** (8 endpoints + WebSocket) — frozen API surface
✅ **OpenAPI spec** (`/openapi.json`) — for Dart code generation
✅ **Tests** (`test_contracts.py`) — model validation

### What You Get
- Frozen contracts so Lanes B & C can build independently
- Backend server running on `localhost:8000`
- Supabase dashboard with initialized tables + realtime
- 8 stub route endpoints (ready for Lane B implementation)

### What's NOT Implemented
- VLM calls (Lane B)
- Matching algorithms (Lane B)
- Flutter UI screens (Lane C)
- Real data in Supabase (Lane D)

---

## H2–H8: Lanes B & C (Parallel)

### Lane B: AI/Vision
1. Mock `VisionService` with canned responses
2. Implement three surfaces:
   - `parse_list(source, text|image) → ParsedList` (request intake)
   - `identify_shelf_candidates(item, image) → ShelfCandidates` (substitution)
   - `split_receipt(image) → ReceiptSplit` (receipt split)
3. Test with mocked Pydantic models
4. Cache responses in `cached_vision_responses` table

### Lane C: Flutter Frontend
1. Generate Dart types from OpenAPI spec
2. Build screens:
   - Login screen (Supabase Auth)
   - Shopper trip creation
   - Requester request entry
   - Merged list view
   - Substitution chooser
   - Settlement screen
   - Ledger view
3. Wire Supabase Auth (magic link, Google)
4. Subscribe to Supabase Realtime (items, settlements, etc.)
5. Test on iOS simulator / Android emulator

### Mock Until H8
- Lane B returns fixed responses for demo data
- Lane C builds UI against mocks
- No real VLM calls yet

---

## H8–H14: Real Integration

### Lane B
- Swap mock → real Muse Spark (Meta Model API)
- Fallback to OpenAI `gpt-4o`
- Cache responses in Supabase
- Implement retry logic + repair prompts

### Lane C
- Wire real backend API (no longer mocks)
- Test with real Supabase data
- Implement image capture (camera, gallery)
- Upload photos to Supabase Storage
- Display real VLM responses

---

## H14–H18: Matching + Settlement

### Lane B
Implement matching algorithms:
- Section assignment (keyword-based)
- Duplicate merge (grouping similar items)
- Cap enforcement (running totals)
- Substitution ranking (confidence + similarity)
- Receipt line assignment (Hungarian algorithm)
- Ledger increments

### Lane C
- Settlement screens with totals
- Venmo deep-link generation
- Ledger view
- Handoff confirmation
- Full end-to-end flow

---

## H18–H24: Demo + Polish

### Lane D
- Populate demo circle + users (Supabase)
- Stage 3 images (handwritten list, shelf, receipt)
- Cache VLM responses for demo beats
- Create rehearsal script with timings

### All Lanes
- End-to-end testing on 3 physical iPhones/Android phones
- Cached fallbacks for every demo beat
- Polish UI/UX
- Final rehearsals
- Freeze

---

## Tech Stack

| Layer | Choice |
|-------|--------|
| **Backend** | FastAPI (Python 3.11) |
| **Database** | Supabase (PostgreSQL) |
| **Auth** | Supabase Auth (magic link, Google) |
| **Storage** | Supabase Storage (images) |
| **Realtime** | Supabase Realtime (Postgres NOTIFY) |
| **Frontend** | Flutter 3.x (Dart) |
| **Mobile** | iOS + Android (native) |
| **VLM** | Meta Muse Spark + OpenAI fallback |

---

## Frozen Contracts (H0–H2)

### Pydantic Models (15)
- **Enums (7):** TripStatus, RequestStatus, ItemStatus, ParseSource, StoreSection, LedgerEventType, SubstitutionDecision
- **Domain (9):** User, Circle, Trip, Request, Item, Parse, Receipt, Settlement, LedgerEvent, LedgerRow
- **VLM Outputs (3 surfaces):** ItemDraft, ParsedList (Surface #1), ShelfCandidates (Surface #2), ReceiptSplit (Surface #3)
- **Matching:** LineAssignment, SettlementLine, MergedListRow, MergedList, SubstitutionPrompt

### Supabase Tables (10)
```sql
users                    -- (id: uuid pk), (circle_id fk), name, venmo_handle
circles                  -- (id: uuid pk), name, (invite_code: unique)
trips                    -- (id: uuid pk), (shopper_id fk), (circle_id fk), store, depart_at, caps, status
requests                 -- (id: uuid pk), (trip_id fk), (requester_id fk), status
items                    -- (id: uuid pk), (request_id fk), (trip_id fk), name, qty, max_price, status, section
parses                   -- (id: uuid pk), (user_id fk), source, raw_ref, parsed (JSONB), confirmed
receipts                 -- (id: uuid pk), (trip_id fk), image_ref, split (JSONB), assignments (JSONB)
settlements              -- (id: uuid pk), (trip_id fk), (requester_id fk), lines, subtotal, tax_share, total
ledger_events            -- (id: uuid pk), (circle_id fk), (user_id fk), type, value, (trip_id fk)
substitution_prompts     -- (id: uuid pk), (item_id fk), (requester_id fk), candidates, expires_at, decision
cached_vision_responses  -- (id: uuid pk), (cache_key: unique), surface, response (JSONB), provider
```

### API Routes (14 endpoints)
```
POST   /trips                           -- Create trip
GET    /trips/{trip_id}                 -- Get trip
PATCH  /trips/{trip_id}/status          -- Update status

POST   /trips/{trip_id}/requests        -- Create request
PATCH  /requests/{request_id}           -- Accept/decline

POST   /parses                          -- Create parse (text/photo/voice)
PATCH  /parses/{parse_id}/confirm       -- Confirm items

GET    /trips/{trip_id}/merged-list     -- Get merged list

POST   /trips/{trip_id}/substitutions   -- Create substitution
PATCH  /substitutions/{id}              -- Choose substitute

POST   /trips/{trip_id}/receipts        -- Upload receipt
PATCH  /receipts/{id}/assignments       -- Confirm assignments

POST   /trips/{trip_id}/handoff         -- Confirm delivery
GET    /circles/{circle_id}/ledger      -- Get ledger

WS     /ws/trips/{trip_id}              -- Realtime updates
GET    /health                          -- Health check
```

---

## Setup Checklist (H0)

- [ ] Supabase project created (`favorly-demo`)
- [ ] Database schema initialized (10 tables)
- [ ] Realtime enabled on 5 key tables
- [ ] Storage bucket created (`images`)
- [ ] Auth providers enabled (Email, Anonymous, Google)
- [ ] Connection strings saved (3 Supabase credentials)
- [ ] Backend `.env` created with Supabase keys
- [ ] FastAPI server runs: `python -m uvicorn app:app --reload`
- [ ] `/health` returns `{"status": "ok", "supabase": "connected"}`
- [ ] `/docs` shows all 14 routes + WebSocket
- [ ] Tests pass: `pytest tests/test_contracts.py -v`
- [ ] Flutter project created: `flutter create favorly_mobile`
- [ ] Supabase Flutter SDK added: `flutter pub add supabase`
- [ ] Flutter app initializes Supabase client

---

## Documentation Files

| File | Purpose | Status |
|------|---------|--------|
| `START_HERE.md` | 20-min quick setup | ✅ |
| `SETUP_SUPABASE.md` | Detailed Supabase guide | ✅ |
| `QUICKSTART.md` | Backend quick ref | ✅ (needs update) |
| `PRD.md` | Product spec | ✅ (updated) |
| `docs/SPEC_v0.md` | Engineering spec | ✅ (updated) |
| `IMPLEMENTATION_CHECKLIST.md` | Verification | ✅ (needs update) |

---

## Success Criteria (H2)

- [ ] Backend server runs without errors
- [ ] Supabase connected and healthy
- [ ] All 10 tables exist with indexes
- [ ] Realtime enabled on key tables
- [ ] All Pydantic models validate
- [ ] 14 API routes accessible (stub responses)
- [ ] OpenAPI spec generated at `/docs`
- [ ] Flutter app compiles and initializes Supabase
- [ ] Tests pass: `pytest tests/test_contracts.py -v`

---

## Success Criteria (H24 – Demo Complete)

- [ ] Full loop works on 3 physical phones (iOS + Android)
- [ ] All 3 VLM surfaces working (or cached fallback)
- [ ] Receipt split reconciles to receipt total (±$0.01)
- [ ] All demo beats < 20 seconds each
- [ ] Realtime updates visible across phones
- [ ] Ledger updates after handoff
- [ ] Every VLM call has cached fallback

---

## Next: After Demo

**v0.1+ Backlog (post-24h):**
- Relationship routing (who to connect with)
- Opt-in intros between neighbors
- Karma redemption (points system)
- Merchant perks
- Multi-circle membership
- Consumption forecasting
- Senior voice line
- Translation
- In-app payments + escrow

**Production Hardening:**
- Enable RLS (Row Level Security)
- Add audit logging
- Rate limiting
- Error tracking (Sentry)
- Analytics
- Mobile app store deployment (TestFlight, Play Store)

