# Lane A — Contracts + Backend

Owner: _TBD_ · Depends on: nothing · Blocks: B, C, D
Source of truth for models and algorithms: [`docs/SPEC_v0.md`](../SPEC_v0.md) §3–§4.

## Mission
Ship the frozen contract by H2 and a FastAPI backend that every other lane can build against — first on
fixtures, then on Supabase. If this lane slips, everyone slips.

## In scope
- `shared/contracts/favorly_contracts/` — every Pydantic model in SPEC §3 (enums, entities, VLM outputs, matching/settlement models). `extra="forbid"`, `Money` = `condecimal(ge=0, decimal_places=2)`.
- `backend/` — FastAPI app, routers per resource, Supabase Postgres via `supabase-py` (service role on the server), Storage bucket `uploads`, Realtime enabled on `trips`, `items`, `substitution_prompts`, `settlements`.
- Migration `supabase/migrations/0001_init.sql` mirroring PRD §7 (+ `substitution_prompts`).
- Matching module `backend/matching/` implementing SPEC §4.1–§4.6 (sections, adjacency groups, caps, substitution re-rank, receipt assignment + settlement math, ledger events). Pure functions, no I/O.
- `openapi.json` exported at build (`python -m backend.export_openapi`) — Lane C generates TS types from it.
- Seed endpoint/CLI `POST /dev/seed` that loads Lane D's `seed/demo_circle.json`.
- Auth v0: `POST /circles/join {invite_code, name}` → creates user, returns `{user, token}`; token is a signed user id in `Authorization: Bearer`. No passwords, no magic links.

## Out of scope
VLM calls (Lane B — you call `VisionService` and persist what it returns), any UI, push notifications (realtime rows are the notification), payments.

## Endpoints (all JSON; request/response bodies are SPEC §3 models)

| Method | Path | Body → Response | Notes |
|---|---|---|---|
| POST | `/circles/join` | `{invite_code, name}` → `{user: User, token}` | 404 on bad code |
| GET | `/circles/{id}/members` | → `list[User]` | |
| GET | `/circles/{id}/ledger` | → `list[LedgerRow]` | §4.6 read model |
| POST | `/trips` | `{store, depart_at, caps?}` → `Trip` | shopper = caller; inserts row → realtime fan-out |
| GET | `/trips?circle_id=&status=` | → `list[Trip]` | feed, newest first |
| GET | `/trips/{id}` | → `Trip` + `requests: list[Request]` | |
| PATCH | `/trips/{id}/status` | `{status}` → `Trip` | enforce OPEN→SHOPPING→SETTLING→DONE; DONE emits ledger events |
| POST | `/parses` | multipart: `source`, `text?`, `file?` → `Parse` | photo/voice: upload to Storage first, then `VisionService.parse_list` |
| PATCH | `/parses/{id}/confirm` | `{items: list[ItemDraft]}` → `Parse` | sets `confirmed=true`, stores `confirmed_items` |
| POST | `/trips/{id}/requests` | `{parse_id}` → `Request` | copies confirmed items → `Item`s; assigns sections (§4.1); 409 if caps exceeded (`max_requesters`, `max_items_per_person`) |
| PATCH | `/requests/{id}` | `{status: accepted|declined}` → `Request` | shopper only |
| GET | `/trips/{id}/merged-list` | → `MergedList` | §4.1–4.3 |
| POST | `/items/{id}/substitution` | multipart `file` → `SubstitutionPrompt` | `VisionService.identify_shelf_candidates` → re-rank §4.4 → insert prompt (expires +3m) |
| PATCH | `/substitutions/{id}` | `{decision, chosen_index?}` → `SubstitutionPrompt` | choose → new Item(`substitute_of`), original SUBSTITUTED; skip → SKIPPED |
| PATCH | `/items/{id}` | `{status: got|skipped}` → `Item` | shopper marks progress |
| POST | `/trips/{id}/receipt` | multipart `file` → `Receipt` | `VisionService.split_receipt` → §4.5 steps 1–4 |
| PATCH | `/receipts/{id}/assignments` | `{assignments: list[LineAssignment]}` → `{receipt, settlements}` | §4.5 step 6; inserts settlements; trip → SETTLING |
| GET | `/trips/{id}/settlements` | → `list[Settlement]` | requester sees only their own unless shopper |
| PATCH | `/settlements/{id}/paid` | → `Settlement` | display only |
| POST | `/trips/{id}/handoff` | multipart `file?` → `Trip` | trip → DONE |
| GET | `/health` | → `{ok, provider, db}` | |
| POST | `/dev/seed` | → `{circle_id, invite_code}` | dev only |

Errors: `{"error": {"code": "cap_exceeded", "message": "..."}}` with proper HTTP status. Codes: `not_found`, `invalid_transition`, `cap_exceeded`, `vision_failed`, `not_shopper`, `expired`.

## Realtime contract (Lane C subscribes)
- `trips` INSERT (channel `circle:{circle_id}`) → new trip in feed.
- `items` UPDATE, `requests` UPDATE (channel `trip:{trip_id}`) → merged list refresh.
- `substitution_prompts` INSERT/UPDATE (channel `user:{requester_id}`) → chooser opens/closes.
- `settlements` INSERT (channel `user:{requester_id}`) → "you owe $X".
Row-level security: v0 uses the anon key on the client with RLS policies scoped by `circle_id`; server uses service role.

## Milestones
- **H0–2 (frozen):** contracts package + `openapi.json` + `0001_init.sql` + in-memory fixture mode (`DB=memory`) so B/C can run without Supabase. Tag `contracts-v0`.
- **H2–8:** trips, parses, requests, merged-list on Supabase; seed loaded; realtime verified on `trips`/`items`.
- **H8–14:** receipt split + assignments + settlements; Venmo link builder; reconciliation tests green.
- **H14–18:** substitution prompts + timeout sweep (`asyncio` task every 30s); handoff + ledger.
- **H18–24:** hardening: request timeouts, idempotency on multipart retries, `/health` shows provider + db.

## Acceptance
- `uv run pytest` green: `test_contracts.py`, `test_matching.py` (golden receipt reconciles to the cent), `test_sections.py`, `test_transitions.py`.
- `uv run uvicorn backend.main:app` with `DB=memory VISION_PROVIDER=mock` boots with zero env; `curl /trips` returns the seeded feed.
- `openapi.json` diff is empty vs `contracts-v0` after H2 except additive changes (announce in channel before merging any).

## Contract change policy after H2
Additive only (new optional fields, new endpoints). Renames/removals need all four lanes' ack. Bump `favorly_contracts.__version__`.
