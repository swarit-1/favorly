# Favorly v2 — Lane A: brain + texting (`agents/` + `backend/`)

**Split from `v2prd.md` for parallel execution. You are Engineer A.** Engineer B works `favorly_mobile/` from `docs/PRD_v2_laneB_app.md` at the same time. Files are disjoint; B runs in a worktree (`git worktree add ../favorly-flutter -b v2-flutter`).

**Target:** HackMIT 2026 demo, Meta track. **Clock:** 3h30. Written against `main` at `9ce33ac`.

## Coordination protocol (the only section that mentions Lane B)

- **Section 4 (contracts) is frozen and duplicated in both lane docs.** If you must change a contract, update BOTH docs and tell Lane B immediately — they build against fixtures matching these shapes until you're live.
- **Announce to Lane B when:** P1 intake is live (they can hit `/needs/intake`), P2 helpers is live (`/needs/{id}/helpers`), P3 loop is live. Lane B goes live-API at T+1:50 (their P4.6).
- If this document and the code disagree, the code wins. Adapt, leave a `# PRD-DEVIATION: <why>` comment, and tell Lane B if a contract shape changed.

## Rules of engagement

1. **Phases in priority order.** Finish a phase, run its gate, commit (`v2 phase N: <what>`), move on. Every phase leaves the app demoable. No stretch before the Phase 5 gate.
2. **Additive only.** Never rename or remove existing endpoints, fields, tables. New fields optional with defaults. The grocery loop (trips, merged list, substitution, receipt split, settlement) keeps working untouched.
3. **Offline first.** Every new LLM call: JSON-only output, hard timeout, deterministic fallback. `cd backend && python -m pytest tests/` and Trellis with `MOCK_LLM=1` must pass with zero API keys.
4. **Copy rules:** no em/en dashes in user-facing strings (commas, periods, middle dots). Person first, task second. Never imply debt. Never show a score, percentage, or rank. Never guess gender (name or "they"). Pre-acceptance location is relative ("two floors up"); unit numbers only after both said yes.
5. **No new dependencies in `agents/`** (Vercel size limit). Stdlib (`difflib`, `re`) and `networkx` only.
6. **Do not touch:** auth, vision grocery routes, settlement, `favorly_mobile/` (that's Lane B's tree), golden images.
7. **Latency budget (hard, it is the demo):** SMS ack within 2 s of the webhook. Three matches within 6 s.

## Your timeline

| Clock | Phase |
|---|---|
| T+0:00–0:15 | **P0** Unbreak texting, identity bridge |
| T+0:15–0:55 | **P1** Any-favor intake + scope check |
| T+0:55–1:50 | **P2** People graph, helper ranking, seed |
| T+1:50–2:25 | **P3** Text loop end to end |
| T+2:25–2:45 | **P5** Reset, warmup, demo script |
| T+2:45–3:10 | S1 or S2, only if every gate is green |
| T+3:10–3:30 | Rehearse twice, record backup video, freeze |

**Cut lines.** Behind at T+1:50: drop 2.8. Behind at T+2:25: drop the decline/advance branch in P3 and the group thread. The P3 gate alone is a complete demo.

## Known defects at HEAD (all yours, fix in P0)

1. **Texting is dead on `main`.** `backend/routes/linq_webhook.py::_sync_trellis` calls `trellis.register_person(...)`, deleted from `trellis_client.py` in `bf31a35`. Every inbound text raises `AttributeError` before `send_reply`; no reply is ever sent.
2. **Seed members never load.** In `backend/agent/store.py` the `LINQ_USER_PHONES` block sits after `return drained` inside `drain_events()` — unreachable, and references `seed`, a local of `__init__`. `store.profiles` is empty at startup.
3. **Texters are invisible to the graph.** Unknown phones get a random in-memory UUID; Trellis requires `person_id` in `app_people`, so `post_need` 404s. Nothing a texter says reaches the graph.
4. **Three casts that do not match:** `backend/seed/demo_circle.json` (Alice/Bob/Carol), `backend/seed/cast.py` (Ana/Ben/Chloe/Maya Iyer), `agents/seed_data.py` (eight others + "Ana (Shopper)"). `cast.py` becomes the single source of truth in P2.
5. `_TRIP_RE` in `backend/agent/nlu.py` reads "I'm going to need help moving a couch" as a trip to "Need Help Moving A Couch".
6. The SMS reply prints `(match score 0.62)`. House style: never show scores.
7. `trellis_client._TIMEOUT` is 2.0 s, too short for a ranking call.
8. (Lane B's screen, your awareness) `web_screen.dart` is orphaned from `shell.dart`.
9. The old intro-routing scorer was removed when scope narrowed to groceries. What remains ranks *needs for a helper*. v2 adds the inverse: *helpers for a need*, deliberately reversing the "no matchmaking" docstrings. Update docstrings you touch.

## Product thesis (context for copy and ranking decisions)

Text what you need; Favorly introduces the neighbor who should help, and says why. **The matcher optimizes for ties worth forming, not fastest fulfilment**: every match carries a true, specific, human reason (never a score); the top three are three different kinds of tie (someone you know, friend of a friend, a new face); a friend-of-a-friend favor closes a triangle; the super-helper is quietly down-weighted (internal `give_balance`, never shown); each intro carries one "spark" the two have in common. Pitch line: "Favorly does not get your errand done faster. It makes your building smaller."

## The locked SMS journey (spec + demo script)

```
YOU      I need to borrow a ladder for an hour today
FAVORLY  Borrow a ladder, today. Finding the right neighbor.          (within 2 s)
FAVORLY  Three neighbors who fit:                                     (within 6 s)
         1. Marcus · 3 floors up · friend of Nora
         Has a 6 ft ladder and is usually free Sunday afternoons. You both follow F1.
         2. Elena · same floor · you know each other
         Has a step ladder. Elena helped you out last week.
         3. Jordan · 1 floor down · new to the building
         Still has a ladder from the move. This would be Jordan's first favor here.
         Reply 1, 2 or 3 and I will ask them. Or reply EVERYONE.
YOU      1
FAVORLY  Asked Marcus. I will text you as soon as they answer.
   (Marcus)  FAVORLY  Swarit on floor 3, a friend of Nora, is hoping to borrow a ladder today.
                      Up for it? Reply YES or NO. No pressure either way.
   (Marcus)  yes  →   You are on. Swarit is in 3C. Text DONE here when it is wrapped up. You both follow F1.
FAVORLY  Marcus is in. They are in 6C. You both follow F1, ask about Sunday's race.
MARCUS   done
FAVORLY  (to both) Done. That was your first favor together. Your building just got a little closer.
```

Names illustrative. After seeding, run the real query and write the real output into `docs/DEMO_SCRIPT.md`. **Tune the seed, never the weights**, until the three options tell three different stories.

**Other journeys that must work:** too big ("help me build a house" → right-sized offer + YES to post); needs a pro (breaker panel → steer to electrician + safe adjacent favor); not ok (one polite sentence, no lecture); company ("walk the reservoir around 6" ranks on shared interest + availability); errand regression ("grab me oat milk and eggs" behaves exactly as today); offer ("I have a ladder…" → "Noted." + `has_item` claim); nobody fits ("Nobody has told me they have a pasta maker yet. Want me to ask the whole building? Reply EVERYONE.").

**Locked decisions:** 3 options over SMS; two messages (ack echoing the parsed title, then matches); pick by digit / first name / EVERYONE / CANCEL; helper gets no-pressure YES/NO, a decline reaches the asker as "can't make it today" + offer of the next; one active favor per helper (busy helpers excluded); conversation state derived from the database (`GET /people/{id}/state`), not process memory; relative location before acceptance, unit after; phones never leave `backend/`; scores never shown; app and SMS call the same Trellis endpoints.

---

## 4. Contracts (FROZEN — duplicated in the Lane B doc; changes must go to both)

### 4.1 Favor categories

`errand | borrow | hands | skill | company | ride | care | other` — unknown/missing decodes as `errand`.

### 4.2 Trellis endpoints you build

**`POST /needs/intake`** parse + scope check + create. Does not rank.
```jsonc
// request
{ "person_id": "uuid", "text": "I need to borrow a ladder for an hour today",
  "confirm_right_sized": false, "source": "sms" }
// response
{ "intent": "ask_favor",            // ask_favor | offer_help | not_a_favor
  "scope": "ok",                    // ok | too_big | needs_pro | not_ok | unclear
  "scope_reply": null,              // one sentence when scope != ok
  "right_sized": null,              // neighbor-sized rewrite when too_big / needs_pro
  "need": { "id": "uuid", "category": "borrow", "title": "Borrow a ladder",
            "body": "...", "requires": ["ladder"], "when_text": "today",
            "duration_minutes": 60, "items": [] },   // null unless scope == ok
  "parsed_by": "model" }            // model | rules
```
`confirm_right_sized: true` means `text` is a previously returned `right_sized`; skip the scope check. `intent: offer_help` writes an event, creates no need. Intake never runs claim extraction inline.

**`GET /needs/{need_id}/helpers?limit=3`** rank people for a need. Side effect: stores ordered ids in `needs.shortlist`.
```jsonc
{ "need_id": "uuid", "decided_by": "model",          // model | graph
  "helpers": [ {
    "person": { "id": "uuid", "display_name": "Marcus Hill", "first_name": "Marcus" },
    "rank": 1,
    "tie": "friend_of_friend",                        // close | friend_of_friend | extended | new
    "tie_label": "Friend of Nora",                    // deterministic, server-written
    "hops": 2,
    "path": [ {"id":"..","name":"You"}, {"id":"..","name":"Nora"}, {"id":"..","name":"Marcus"} ],
    "headline": "Has a 6 ft ladder",                  // deterministic, from the matched claim
    "where": "3 floors up",                           // deterministic, never a unit number
    "reason": "Has a 6 ft ladder and is usually free Sunday afternoons. You both know Nora.",
    "spark": "You both follow F1.",                   // or null
    "signals": { "capability": 1.0, "tie": 0.85, "similarity": 0.5, "reciprocity": 0.0,
                 "nearness": 0.6, "availability": 1.0, "balance": 1.0 },
    "why": { "weights": {}, "matched_claims": ["6 ft ladder"], "mutual_names": ["Nora Chen"],
             "shared": ["formula 1"], "favors_they_did_for_you": 0,
             "favors_you_did_for_them": 0, "graph_reason": "template sentence" },
    "invite_status": null                             // null | pending | accepted | declined
  } ] }
```

**`POST /needs/{need_id}/invite`** `{ "helper_id": "uuid" }` → `{ "status": "pending" }`. 409 if not open, 422 on self-invite. Idempotent per (need, helper).

**`POST /needs/{need_id}/invites/{helper_id}/respond`** `{ "accept": true }` — accept: need claimed by helper (same rules as `/claim`), other pending invites expire, `{ "status": "accepted" }`. Decline: `{ "status": "declined", "next": <HelperMatch or null> }` (next shortlist entry not yet invited).

**`POST /needs/{need_id}/broadcast`** clears shortlist, leaves need open to the feed. **`POST /needs/{need_id}/cancel`** sets `cancelled`.

**`GET /people/{person_id}/state`** everything a stateless client needs to interpret "2", "yes", "done":
```jsonc
{ "person": { "id": "..", "display_name": "..", "first_name": "..", "floor": 3, "unit": "3C" },
  "open_ask": { "need_id": "..", "title": "Borrow a ladder", "category": "borrow",
                "shortlist": [ { "rank": 1, "person_id": "..", "first_name": "Marcus", "invite_status": "pending" } ] },
  "pending_invite": { "need_id": "..", "title": "..", "category": "borrow", "when_text": "today",
                      "asker": { "id": "..", "first_name": "Swarit", "floor": 3 }, "mutual_first_name": "Nora" },
  "active_favor": { "need_id": "..", "title": "..", "role": "helper",
                    "other": { "id": "..", "first_name": "Swarit", "unit": "3C" }, "spark": "..." } }
```
Each null when absent. Most recent wins.

**`GET /people/{person_id}/asks`** open + claimed needs I posted, plus fulfilled in the last 10 min, each with helpers (`invite_status`) and the accepted helper.

**`GET /graph/stats?person_id=`** → `{ "people": 16, "ties": 23, "avg_separation": 2.61, "triangles": 7 }`, circle-scoped; `avg_separation` = `nx.average_shortest_path_length` over the largest connected component.

**Changed, backward compatible:** `POST /needs` accepts optional `category, title, requires, when_text, duration_minutes, extract`. `POST /needs/{id}/fulfill` adds `first_favor_together: bool` and `separation: { before, after }`. `FavorSuggestion` adds `category`, `when_text`, `invited: bool` (invited sort first). `GET /graph` edges may carry kinds `knows` and `neighbor`.

### 4.3 Backend

No new public endpoints in the core path — the webhook becomes thin plumbing over the contracts above. Stretch: `POST /vision/assist` (S1), `POST /route/plan` (S2).

---

## Phase 0. Unbreak texting (15 min)

**0.1** `backend/routes/linq_webhook.py`: delete the `kind == "person"` branch. In `_process`, wrap Trellis sync in try/except — a Trellis failure must never block a reply.

**0.2** `backend/agent/store.py`: remove the unreachable block from `drain_events()`. Do not resurrect `demo_circle.json` identities; use 0.3.

**0.3** New `backend/agent/identity.py`, the phone-to-person bridge. `AgentStore.user_for_phone` delegates to it.
1. In-memory cache.
2. `users.phone` lookup through `db/client.py::get_supabase_client()`. Migration `backend/supabase/migrations/005_users_phone.sql`: `ALTER TABLE users ADD COLUMN IF NOT EXISTS phone TEXT;` + unique index where not null.
3. Env `LINQ_USER_PHONES="+16175550101=Swarit Srivastava,..."`: resolve by exact `users.name` inside the demo circle, then write the phone onto the row so step 2 hits next time.
4. Unknown phone: auto-provision — Supabase Auth user first (`supabase.auth.admin.create_user`, email `p<digits>@favorly.test`, `DEV_PASSWORD`, `email_confirm: True`), then the `users` row with same id, demo circle from `seed/cast.py`, `name = "Neighbor 1234"`, phone. Reuse the ordering in `backend/seed/seed_auth_users.py`. This lets a judge text cold and still get ranked matches.
5. No Supabase env (tests): current behaviour, random in-memory UUID.

**0.4** `backend/agent/nlu.py`: after `_TRIP_RE`/`_RUN_RE` match, reject when the captured store starts with a verb (`need|help|be|have|get|do|make|move|build|borrow|ask|go|try|see`) or exceeds four words. Add a test.

**0.5** `backend/agent/handlers.py`: remove `(match score ...)` from both replies; update tests.

**0.6** `trellis_client.py`: keep 2 s for fire-and-forget posts; add `_LONG = httpx.Timeout(8.0)` for intake, helpers, state.

**Gate 0**
```bash
cd backend && python -m pytest tests/ -q
uvicorn app:app --port 8000 &
curl -s -X POST localhost:8000/webhooks/linq -H 'Content-Type: application/json' -d '{
 "event_type":"message.received","data":{"chat":{"id":"c1"},"direction":"inbound",
 "sender_handle":{"handle":"+15550000001"},"parts":[{"type":"text","value":"can someone grab me oat milk"}]}}'
# expect: [linq:dry-run] reply to c1: ...
```

---

## Phase 1. Any favor in, right-sized (40 min)

Priority one. The scope check is one lightweight JSON call that parses and right-sizes together — one round trip.

**1.1 Schema.** New `agents/migrations/001_any_favor.sql`, append the same to `agents/schema.sql`. Vercel skips `apply_schema()` on cold start (`SERVERLESS`) — **run the file once by hand**.
```sql
ALTER TABLE needs ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT 'errand';
ALTER TABLE needs ADD COLUMN IF NOT EXISTS title TEXT;
ALTER TABLE needs ADD COLUMN IF NOT EXISTS requires JSONB NOT NULL DEFAULT '[]';
ALTER TABLE needs ADD COLUMN IF NOT EXISTS when_text TEXT;
ALTER TABLE needs ADD COLUMN IF NOT EXISTS duration_minutes INT;
ALTER TABLE needs ADD COLUMN IF NOT EXISTS shortlist JSONB NOT NULL DEFAULT '[]';

CREATE TABLE IF NOT EXISTS need_invites (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  need_id      UUID NOT NULL REFERENCES needs(id),
  helper_id    UUID NOT NULL REFERENCES users(id),
  status       TEXT NOT NULL DEFAULT 'pending',   -- pending | accepted | declined | expired
  rank         INT,
  reason       TEXT,
  spark        TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  responded_at TIMESTAMPTZ,
  UNIQUE (need_id, helper_id)
);
CREATE INDEX IF NOT EXISTS need_invites_helper_idx ON need_invites (helper_id, status);

-- Append columns at the END only, or CREATE OR REPLACE VIEW fails.
CREATE OR REPLACE VIEW app_people AS
SELECT u.id, u.name AS display_name, a.email AS email, u.circle_id, u.venmo_handle,
       a.created_at AS joined_at,
       u.address_unit, u.address_floor, u.availability, u.bio
FROM public.users u JOIN auth.users a ON a.id = u.id;
```

**1.2 `agents/llm.py`: `parse_favor(text, now) -> dict`.** Same pattern as `extract_claims`: real path `_chat_json` with prompt B1 (below), 4 s timeout, failure → mock. Mock rules:

| Pattern (case-insensitive) | Result |
|---|---|
| `\b(grab|pick up|get me|buy|bring me)\b` + item-like text | errand |
| `\b(borrow|lend me|does anyone have|anyone have an?)\b` | borrow, `requires` = noun after it |
| `help me (build|assemble|hang|put up|move|carry|lift|install|mount)` | hands, requires `handy` (+ `drill` for build/hang/mount/put up) |
| `(set ?up|fix|repair|tune|configure).*(sound system|speakers|wifi|router|bike|printer|tv)` | skill, mapped skill (`audio setup`, `wifi`, `bike repair`) |
| `\b(walk|run|jog|coffee|gym|workout|study|watch the game) with me\b`, `anyone want to` | company |
| `\b(ride|lift|drive me|drop me)\b` | ride, `requires: ["car"]` |
| `\b(water my plants|feed my (cat|dog|fish)|watch my|hold a package)\b` | care |
| `\bi have (a|an|some) .+ (if anyone|anyone can|happy to lend)\b`, `i can help with` | intent `offer_help` |
| `build a house`, `renovate`, `remodel`, `move (apartments|out|house)`, `paint (my|the) (whole|entire)`, `plan my wedding` | `too_big` + canned `right_sized` per pattern |
| `rewire`, `breaker`, `gas (line|leak)`, `roof`, `cut down .*tree`, `asbestos` | `needs_pro` |
| `follow (my|him|her)`, `spy`, `track (my|his|her)`, `pay (you|someone)`, `fake`, `prescription` | `not_ok` |

`when_text` regex: `today|tonight|tomorrow|this (morning|afternoon|evening|weekend)|(mon|tues|wednes|thurs|fri|satur|sun)day( morning| afternoon| evening)?|at \d{1,2}(:\d{2})?\s?(am|pm)?|around \d{1,2}`.

**1.3 `agents/routes/needs.py`: `POST /needs/intake`** per contract. `POST /needs` and `GET /needs` accept/return the new optional fields. New models: `IntakeIn`, `IntakeOut`, `NeedOut`.

**1.4 De-grocery helper-side copy:** `recommendations._build_reason` and `_reciprocity_fact` — "picked up groceries for you" → "helped you out"; add `helped` to `_REASON_STOPWORDS`. `_fallback_suggestions` title = `need.title` when present. `llm.DECIDE_SYSTEM_PROMPT`: "neighborhood grocery app" → "neighborhood favor app", category-neutral title example, add no-gender rule. `recommend_for` selects and passes `category, title, when_text`.

**1.5 Backend routing:** new `backend/agent/favor_flow.py` with `async def handle_inbound(store, phone, text, now) -> tuple[list[str], list[Notification]]` (list of replies: ack + matches). Webhook calls this. Order:
1. **Fast path, no LLM:** fetch `state`; if the text is a short reply the state interprets, act (wired in P3; stub now).
2. `parsed = parse_rules(text)`. If `offer_trip`, `status`, `get_recommendations`, `set_name`, or grocery-verb `ask_favor` with items → existing sync `handle_message`. **Zero change to the grocery path.**
3. Else Trellis `POST /needs/intake`, branch:
   - `errand` with items: `store.create_ask(...)`, `ask.trellis_need_id = need.id`, existing trip matching. In `_sync_trellis`, skip `post_need` when id already set.
   - `scope: ok`: reply 1 = ack (`"{title}, {when_text}. Finding the right neighbor."`, drop when-clause if null). Reply 2 comes from P3; until then "Posted. I will text you when someone picks it up."
   - `too_big`/`needs_pro`: `"{scope_reply} Reply YES to post that, or tell me again in your own words."` Remember `right_sized` in `store.pending_action` (the one allowed in-memory state).
   - `not_ok`/`unclear`: `scope_reply`.
   - `offer_help`: "Noted. I will remember that."
   - Trellis unreachable: fall back to today's `parse_message` + `handle_message`.
4. Fire-and-forget `trellis.log_event(person_id, text)` after replying.

Update `HELP_TEXT` with two non-grocery examples.

**Gate 1.** New `backend/tests/test_favor_intake.py` (offline) and `agents/tests/test_parse_favor.py` (mock path):

| Text | Expect |
|---|---|
| can someone grab me oat milk and eggs | errand, ok, 2 items, existing reply unchanged |
| I need to borrow a ladder for an hour today | borrow, ok, requires `ladder`, when `today` |
| can someone help me put up a shelf saturday morning | hands, requires `drill` |
| anyone want to go on a walk with me around 6 | company, ok |
| need help setting up my sound system | skill, requires `audio setup` |
| can someone give me a ride to south station at 4 | ride, requires `car` |
| could someone water my plants next week | care, ok |
| help me build a house | too_big, `right_sized` not null |
| help me move apartments | too_big |
| can someone rewire my breaker panel | needs_pro |
| can someone follow my ex and tell me where she goes | not_ok |
| I have a ladder if anyone ever needs one | offer_help, no need created |
| I'm going to need help moving a couch | NOT offer_trip |

---

## Phase 2. The people graph and "who should help" (55 min)

### 2.1 Widen claim kinds (free text, no migration)

New kinds: `has_item` (6 ft ladder, drill, car, folding table, projector), `skill` (handy with tools, audio setup, bike repair, sewing), `interest` (formula 1, climbing, walking, chess, gardening, dog owner), `availability` (free sunday afternoons, works from home, evenings). Existing `mobility, dietary, budget, preference` unchanged.

- `agents/extraction.py`: widen `VALID_CLAIM_KINDS`.
- `agents/llm.py`: replace `EXTRACTION_SYSTEM_PROMPT` with B2 (below). Keep the verbatim-evidence span check exactly.
- `_MOCK_RULES`: add Appendix A.3 rows so `MOCK_LLM=1` produces every seeded claim.
- `canonicalization.py::SEED_LABELS`: add `ladder, drill, tools, car, handy with tools, audio setup, bike repair, sewing, formula 1, climbing, running, walking, chess, gardening, dog owner, free weekends, works from home`.

### 2.2 Edges

`EDGE_WEIGHTS = {"favor": 1.0, "knows": 0.6, "co_occurrence": 0.3, "neighbor": 0.25}`. `knows` (declared, seeded) and `neighbor` (same floor, generated) **do not decay**. In `edges.all_edges_decayed`: `SUM(weight * CASE WHEN kind IN ('favor','co_occurrence') THEN <decay> ELSE 1 END)`.

### 2.3 New `agents/matching.py`

```python
@dataclass
class Person:  id; display_name; first_name; floor: int | None; unit: str | None; availability: list[str]

@dataclass
class CircleContext:
    people: dict[str, Person]
    claims: dict[str, list[dict]]      # person_id -> active claims, confidence >= floor
    G: nx.Graph                        # undirected; edge attrs: strength, favors_ab, favors_ba
    give_balance: dict[str, float]     # INTERNAL. Never returned, never phrased.
    busy: set[str]                     # claimed, unfulfilled need
    recent: list[str]                  # last 10 favor one-liners, LLM context

async def load_circle(conn, person_id) -> CircleContext
```
**Performance rule: exactly four SQL queries per ranking call** (members, their claims, decayed edges among them, claimed needs). The per-pair `_reciprocity`/`_mutuals`/`_claims` helpers are N+1 — do not call them in the new path.

**Signals** — each `(value 0..1, evidence)`, pure, unit-testable:

| Signal | Weight | How |
|---|---|---|
| `capability` | 0.30 | Normalize tags (lowercase, strip plurals; synonyms: ladder/step ladder; drill/tools/toolbox; car/truck/suv; handy/carpentry/diy; audio setup/speakers/sound system/audio engineering). Match `need.requires` vs helper's `has_item` + `skill` (canonical and raw): all tokens contained or `difflib` >= 0.85 → **1.0**; synonym → **0.7**; `MOCK_LLM=0` embedding cosine >= 0.80 → **0.7**. Empty/unmatched fallbacks: `company` named activity matches interest **1.0**, any shared interest **0.5**; `hands` handy/moving skill **0.6** else **0.3**; `ride`/`errand` has car **1.0**, open trip **1.0**; `care` same floor **0.6**. Evidence → `headline` ("Has a 6 ft ladder"). |
| `tie` | 0.20 | Hop-minimal path via `nx.all_shortest_paths`; tie-break by best bottleneck strength. 1 hop **1.0**, 2 **0.85**, 3 **0.55**, 4+ **0.30**, none **0.15**. Labels: 1 `close` "You know each other"; 2 `friend_of_friend` "Friend of {mutual}"; 3+ `extended` "New to you"; none `new` "New to the building" if joined < 30 days else "New to you". |
| `similarity` | 0.15 | Jaccard over canonical labels of interest/preference/dietary/availability. One shared **0.5**, two+ **1.0**. Feeds `spark`. |
| `reciprocity` | 0.10 | From `G[a][b]`: favors either direction, decayed, cap 1. Evidence keeps direction. |
| `nearness` | 0.10 | Same floor **1.0**; 1 apart **0.8**; <=3 **0.6**; same building **0.4**; unknown **0.3**. → `where`. Never a unit. |
| `availability` | 0.10 | `users.availability` + availability claims vs `when_text` + today. Match **1.0**, unknown **0.5**, conflict **0.2**. |
| `balance` | 0.05 | Internal. 1.0 normally → 0.4 when far above circle median `give_balance`. **No evidence. Never in copy, context, or API.** |

**Hard filters:** not the asker, same circle, not busy. `borrow` requires `capability > 0`. Nobody passes → `helpers: []`.

**Diversity rule:** if the top three share one `tie` class and another-class candidate scores >= 0.8× the third, swap it into slot three.

**Cold-start asker** (no edges): tie constant; rank falls to capability, nearness, similarity. Fact: "This would be your first favor in the building."

### 2.4 Reasons: graph finds, model phrases, validator checks

Copy the `suggest_favors` pattern: (1) deterministic second-person `facts` per candidate; (2) `llm.phrase_helpers(context)` with B3, timeout 2.5 s, may reorder/drop, may not add; (3) `validate_reason` on every string vs allowed text — failure → template; (4) template fallback = headline + strongest human fact; spark template "You both {shared label phrase}." or null; (5) `strip_dashes` everything; `decided_by` reports the path. Include `recent` so reasons can be timely.

### 2.5 Endpoints

New `agents/routes/helpers.py`, register in `app.py`: helpers, invite, respond, broadcast, cancel, state, asks, graph/stats (shapes in section 4). Accepting an invite reuses claim logic. `fulfill_need` computes `avg_separation` before/after and `first_favor_together`.

### 2.6 Helper-side mirror (home feed), minimal patch to `recommend_for`

Add `capability` signal via `matching.capability(...)` vs helper's own claims. New weights: `trip 0.20, capability 0.20, reciprocity 0.20, mutual 0.15, affinity 0.10, fit 0.10, freshness 0.05`. Left join `need_invites`: `invited = true` adds 0.5, sorts first, fact "{first} asked for you." Reason fragment: "you have what they need: {label}".

### 2.7 Seed: `cast.py` is the single source of truth

- Extend `backend/seed/cast.py::ALL_CHARACTERS` to the 16 people in Appendix A.1 (stable ids via `make_stable_uuid`; canonical four keep ids).
- Seeder writes both Auth account and `users` row (check `seed_auth_users.py` / `seed_demo.py` ownership). Idempotent, demo circle only.
- `agents/seed_data.py`: new scenario `"block"`. `cast.py` owns identity; `seed_data.py` lists the same names as strings, resolved via `_resolve_identities` (fails loudly on drift). **No cross-package imports** (Vercel deploys without `backend/`). Seed **messages, not claims** — extraction builds profiles. Seed the edges in A.2, generate `neighbor` edges for same-floor pairs, and seed four open needs of mixed categories.
- Presenters map onto cast via `LINQ_USER_PHONES`; the asker is added under their real name (env `DEMO_ASKER_NAME`, unit 3C).

### 2.8 (Cut first) Profile input

One free-text field on `profile_setup_screen.dart` is Lane B's; your side is just `/events` which already exists. Skip unless idle.

**Gate 2**
```bash
cd agents && python -m pytest tests/ -q   # new: tests/test_matching.py, pure functions
curl -s -X POST $TRELLIS/admin/seed -H 'Content-Type: application/json' -d '{"scenario":"block"}'
NEED=$(curl -s -X POST $TRELLIS/needs/intake -H 'Content-Type: application/json' \
  -d '{"person_id":"<ASKER_ID>","text":"I need to borrow a ladder for an hour today"}' | jq -r .need.id)
time curl -s "$TRELLIS/needs/$NEED/helpers?limit=3" | jq '.helpers[] | {n:.person.first_name, tie, headline, where, reason, spark}'
```
Pass: three people, >= two different `tie` values, every reason true against the seed, < 5 s warm, same shape with `MOCK_LLM=1` (`decided_by: "graph"`). Also: "help me put up a shelf" surfaces Tom Becker; "walk the reservoir at 6" surfaces Grace and Priya; Sam is not first everywhere.

---

## Phase 3. The text loop, end to end (35 min)

All in `favor_flow.py`, plus new `trellis_client` functions: `intake, helpers, invite, respond_invite, broadcast, cancel, state, fulfill`. Phones come from `users.phone` on the backend side. **Trellis never sees a phone.**

**3.1 Fast path** (before any LLM). Fetch `state`, match in order:

| If state has | Text matches | Do |
|---|---|---|
| `pending_invite` | `^(yes|y|yep|yeah|sure|ok|okay|i can|happy to)\b` | respond accept, ACCEPT to both |
| `pending_invite` | `^(no|n|nope|can'?t|cannot|not today|sorry)\b` | respond decline, DECLINE to asker |
| `open_ask` with shortlist | `^[1-5]$` or shortlist first name | invite, send INVITE + WAIT |
| `open_ask` | `^(everyone|all|anyone)\b` | broadcast |
| `open_ask` | `^(cancel|never ?mind|forget it)\b` | cancel |
| `open_ask`, declined invite with `next` | `^(yes|y|sure|ok)\b` | invite `next` |
| remembered `right_sized` | `^(yes|y|sure|ok|do that)\b` | intake with `confirm_right_sized: true` |
| `active_favor` | `^(done|all done|finished|returned|got it back|all set|thanks,? done)\b` | fulfill, DONE to both |

**3.2 After the ack:** call `helpers`, send MATCHES as the second reply. Empty → NOBODY.

**3.3 Templates** (no dashes, no scores, no gendered pronouns):
```
ACK      {title}, {when_text}. Finding the right neighbor.
MATCHES  Three neighbors who fit:\n\n{n}. {first} · {where} · {tie_label lowercased}\n{reason}\n\n ... \n\nReply 1, 2 or 3 and I will ask them. Or reply EVERYONE.
WAIT     Asked {helper}. I will text you as soon as they answer.
INVITE   {asker} on floor {floor}{, a friend of {mutual}} is hoping for a hand: {title lowercased}{, {when_text}}. Up for it? Reply YES or NO. No pressure either way.
ACCEPT   (helper) You are on. {asker} is in {unit}. Text DONE here when it is wrapped up. {spark}
         (asker)  {helper} is in. They are in {unit}. {spark}
DECLINE  {helper} can't make it today. Want me to ask {next}? Reply YES, or pick a number.
DONE     Done. That was your first favor together. Your building just got a little closer.   (first_favor_together)
         Done. Thanks for showing up for {other}.                                             (otherwise)
NOBODY   Nobody has told me they have {requires[0]} yet. Want me to ask the whole building? Reply EVERYONE.
```
"One neighbor who fits" / "Two neighbors who fit" when fewer than three.

**3.4 Seeded people have no phone.** If the picked helper has no `users.phone`, they can only answer in the app. Env `DEMO_AUTOACCEPT_SECONDS` (default unset): a phoneless seeded persona accepts after that delay, log `[demo] auto-accept for seeded persona`. On stage the hero helper is a real teammate. Say so if a judge asks.

**3.5 (Timebox 10 min, then drop)** Group intro: after ACCEPT, one message with `to: [asker_phone, helper_phone]` — "Swarit, meet Marcus. …". Linq errors → keep the two 1:1s, move on.

**Gate 3.** Dry-run, two fake phones through the webhook with curl: ask → "1" → "yes" (helper phone) → "done". Assert ACK, MATCHES, WAIT, INVITE, both ACCEPTs, both DONEs in the log, and `GET /graph` shows a new `favor` edge. Add `backend/tests/test_favor_loop.py` with `trellis_client` monkeypatched.

---

## Phase 5. Demo hardening (20 min)

1. `POST /admin/demo/reset` on Trellis: reseed `block`, clear `need_invites`, cancel presenters' open needs. `scripts/demo_reset.sh` calls it, clears `store.pending_action` via a dev-only backend route, pings `/health` on both services.
2. **Warm up.** Trellis on Vercel cold-starts slowly. The reset script pings three times. Ping again 60 s before going on. (The app pings on launch — Lane B.)
3. **Stale-on-error.** Cache last good `helpers` response per need text for 10 min. Serve only if ranking raises or times out; log it.
4. **Linq sandbox limits:** inbound first, 30 msgs/60 s per pair, **100/day**. Every demo phone texts "hi" once up front. A full run ≈ 12 messages. Rehearse in console dry-run; at most three live rehearsals.
5. Demo phones set both server URLs on the dev login screen. `localhost` on a phone is the phone.
6. Write `docs/DEMO_SCRIPT.md` from the hero journey **using real output**. One README paragraph for v2.
7. Record one clean run — the wifi-dies fallback.

**Gate 5.** Two consecutive clean live runs from reset.

---

## Stretch S1 (backend half). Assist mode (25 min, isolated)

`POST /vision/assist` in `backend/routes/vision.py`, copying the `/home-repair/damage-detection` pattern (multipart `files`, `image_storage.upload_images`). Form fields: `need_id, title, category, asker_first, helper_first, question?`. `VisionService.assist_favor(...)` calls `_analyze_image_with_prompt` with B4; add to `OpenAIVisionService` and `MockVisionService`. Response `{ observation, next_steps[<=3], together, safety, stop_and_call_pro }`. The `together` field always hands a step to both people. Gate: shelf-bracket photo returns steps < 8 s; mock path keyless. (Flutter half is Lane B's.)

## Stretch S2 (backend half). Favorly Route (40 min, isolated)

Agent on the shopper's side: shortest walk through the store, at most three explained suggestions, never over the cap. Build: `backend/seed/store_layouts/generic_grocery.json` (x,y metres for `entrance`, `checkout`, every `StoreSection`); `backend/routes/route.py`: `POST /route/plan { trip_id }` — stops from merged list by section, Held-Karp (<= 10 nodes) over Manhattan distance entrance→checkout, returns `{ stops[], distance_m, baseline_distance_m, suggestions[], caps[] }` (`baseline_distance_m` = written order, so "212 m instead of 480 m" is computed). Suggestions: (1) for a neighbor ("Grace needs milk. Dairy is on your route. Adds 0 m."), (2) for future you (`pantry_scans`), (3) usually forgotten (last three lists, only if section already on path). Gate: seeded trip renders a route, accepting re-plans, cap warning fires. (Screen is Lane B's.)

---

## Non-goals

Payments. Push notifications. SSE in Flutter (poll). Multi-circle. Ratings changes. Learned weights. Any redesign of trips, substitution, receipt, settlement.

---

## Appendix A. Seed (`block` scenario) — yours

### A.1 Cast (16 people; `*` = canonical, keep the id). Building = demo circle from `cast.py`.

| Name | Unit / floor | Seed messages (extraction turns into claims) | `users.availability` |
|---|---|---|---|
| {DEMO_ASKER_NAME} | 3C / 3 | "big F1 fan, I never miss a race weekend" · "I play chess most evenings" | Sat, Sun |
| Marcus Hill | 6C / 6 | "I have a 6 ft ladder and a drill if anyone ever needs them" · "pretty handy with tools, I built most of my own furniture" · "F1 fan, I watch every race" · "usually free Sunday afternoons" | Sat, Sun |
| Elena Vasquez | 3D / 3 | "I have a small step ladder for my plants" · "I garden on the roof most mornings" · "always shop at trader joe's for produce" | Mon to Fri |
| Jordan Reyes | 2A / 2 | "just moved in, I still have a ladder and a hand truck from the move" · "looking for people to run with" | Sat, Sun |
| Nora Chen | 4B / 4 | "trying to eat vegetarian this year" · "I climb at the gym twice a week" · "I work from home" | Mon to Fri |
| Sam Okonkwo | 5C / 5 | "I have a car and I'm at the store constantly, happy to grab things" · "I have a full toolbox" · "happy to help move furniture, I'm pretty strong" | every day |
| Priya Raman | 4D / 4 | "I'm gluten free so I read every label" · "I walk my dog around the reservoir every evening" · "I set up the sound system for my band" | evenings |
| Grace Adebayo | 1A / 1 | "I don't have a car and I can't carry heavy bags anymore" · "I walk around the reservoir most evenings and would love company" · "I can sew and hem just about anything" | every day |
| Dev Patel | 2D / 2 | "money is tight this month so I'm sticking to a list" · "I fix bikes for fun" · "I play chess on weekends" | Sat, Sun |
| Tom Becker | 7A / 7 | "retired carpenter, forty years on the job" · "I have every tool you can think of" · "I'm around most days" | every day |
| Lina Haddad | 6A / 6 | "I have a projector and do movie nights" · "happy to help with speakers and TVs" | evenings |
| Noah Kim | 1C / 1 | "student, free most afternoons" · "I have a bike pump and a small toolkit" · "I climb and play chess" | Mon to Fri |
| Ana Delgado * | 3B / 3 | "vegetarian, weekday Trader Joe's runs" · "I have a stand mixer and bake on Sundays" | per cast.py |
| Ben Okafor * | 5A / 5 | "gluten free and dairy free" · "I work from home" · "I do audio engineering, happy to help with speakers" | per cast.py |
| Chloe Marchetti * | 2C / 2 | "vegan, Saturday shopper" · "yoga every morning" | per cast.py |
| Maya Iyer * | 7F / 7 | "Costco regular, I have a car" · "I have a folding table and extra chairs" | per cast.py |

Old Trellis resident "Maya Chen" is renamed **Nora Chen** (two Mayas make "you both know Maya" ambiguous).

### A.2 Edges. `favor` = (giver, receiver, days ago). `knows` undirected.

```
favor:  Nora->ASKER 6 · ASKER->Nora 12 · Elena->ASKER 4 · Nora->Marcus 9 · Marcus->Nora 3
        Sam->Nora 9 · Sam->Dev 7 · Sam->Priya 5 · Sam->Grace 3 · Sam->Ana 4
        Priya->Grace 5 · Marcus->Grace 8 · Dev->Elena 10 · Ana->Elena 13
        Ana->Ben 6 · Chloe->Ana 9 · Maya Iyer->Ben 11 · Lina->Marcus 14 · Noah->Grace 2
knows:  Nora-Marcus (climbing) · Dev-Noah (chess) · Ana-Chloe · Priya-Ben (music)
neighbor: generated for every same-floor pair
```
Intended shape: Marcus is two hops from the asker through Nora (the triangle to close). Elena is one hop, same floor. Jordan has only floor-2 neighbor edges (the new face). Tom Becker is almost disconnected (surfaces for "help me build a shelf"). Sam is the hub the balance signal gently rests. Grace mostly receives; a walk lets her give.

Open needs to seed: Grace, errand, "could someone grab milk and eggs this week?" · Dev, skill, "anyone know how to hem trousers?" · Lina, hands, "need a hand carrying a bookshelf up to 6A Saturday" · Priya, company, "anyone up for the reservoir loop with me and the dog tonight?"

### A.3 Mock extraction rules for `_MOCK_RULES` (pattern, kind, label, confidence)

```
(r"\b(\d+ ?ft )?(step ?)?ladder\b", "has_item", "ladder", 0.8)
(r"\bdrill\b", "has_item", "drill", 0.75)
(r"\btool ?(box|kit)\b|every tool", "has_item", "tools", 0.75)
(r"hand truck|dolly", "has_item", "hand truck", 0.7)
(r"folding table", "has_item", "folding table", 0.7)   (r"projector", "has_item", "projector", 0.7)
(r"stand mixer", "has_item", "stand mixer", 0.7)       (r"bike pump", "has_item", "bike pump", 0.7)
(r"handy with tools|built most of my own|carpenter", "skill", "handy with tools", 0.75)
(r"sound system|audio engineering|speakers", "skill", "audio setup", 0.7)
(r"fix(es)? bikes", "skill", "bike repair", 0.7)       (r"\bsew\b|\bhem\b", "skill", "sewing", 0.7)
(r"help move furniture|pretty strong", "skill", "moving help", 0.65)
(r"\bf1\b|formula 1|race weekend", "interest", "formula 1", 0.7)
(r"\bchess\b", "interest", "chess", 0.7)               (r"\bclimb", "interest", "climbing", 0.7)
(r"people to run with|\brunning\b", "interest", "running", 0.7)
(r"walk (my dog )?around|reservoir", "interest", "walking", 0.7)
(r"\bmy dog\b", "interest", "dog owner", 0.7)          (r"\bgarden", "interest", "gardening", 0.7)
(r"\byoga\b", "interest", "yoga", 0.7)                 (r"\bbak(e|ing)\b", "interest", "baking", 0.65)
(r"free (on )?(sunday|saturday|weekend)s?( afternoons?)?", "availability", "free weekends", 0.65)
(r"free most afternoons|around most days", "availability", "free afternoons", 0.65)
(r"work from home", "availability", "works from home", 0.65)
```
Mock extractor stops at five claims per message — keep seed messages to one or two facts each. **Invariant, add a test:** after `seed("block")` under `MOCK_LLM=1`, every person holds the claims their messages imply.

## Appendix B. Prompts — yours

### B1. `parse_favor` (JSON mode, 4 s)

```
You read one text message sent to Favorly, an agent that helps neighbors in the same building do small favors for each other. Return JSON only.

intent:
- "ask_favor": they want help with something.
- "offer_help": they are telling you about something they own, know how to do, or are willing to do for neighbors, without asking for anything.
- "not_a_favor": greetings, questions about the service, anything else.

category (ask_favor only):
- errand: pick something up on a trip someone is already making (groceries, pharmacy, a package). Fill items.
- borrow: borrow a physical thing (ladder, drill, folding table, air mattress).
- hands: an extra pair of hands (move a couch, put up a shelf, carry boxes, hang a mirror).
- skill: know-how (set up a sound system, fix wifi, tune a bike, hem trousers).
- company: do something together (a walk, a gym session, coffee, watching the game, studying).
- ride: a lift somewhere nearby.
- care: keep an eye on something (water plants, feed a cat, hold a package).
- other: anything else that still fits the size rule.

THE SIZE RULE. A favor is something one neighbor can do for another in about two hours or less, with no licence, no real danger, and no payment.
- scope "ok": it fits.
- scope "too_big": a real need, but too large or too long for one favor (build a house, renovate a kitchen, move a whole apartment, plan my wedding). Do NOT refuse. Put the first useful, concrete, neighbor-sized piece in right_sized, written in the asker's voice, with a rough duration ("help me carry the couch and bed frame down to the truck, about an hour"). scope_reply is one warm sentence that offers it.
- scope "needs_pro": licensed or risky work (electrical panel, gas, roof, tree felling, medical, legal). scope_reply says a professional should do it. right_sized is a safe adjacent favor if one exists ("ask the building who they would recommend as an electrician"), else null.
- scope "not_ok": illegal, harmful, sexual or romantic, watching or tracking a person, or paid labour. scope_reply is one polite sentence. No lecture.
- scope "unclear": you cannot tell what they need. scope_reply is ONE short question.
Never mention rules or policies. Never moralize. One sentence.

fields:
- title: imperative, at most 6 words, no names ("Borrow a ladder", "Put up a shelf together", "Walk the reservoir").
- requires: 0 to 3 lowercase tags a helper would need: things ("ladder", "drill", "car") or skills ("handy", "audio setup", "bike repair"). For company, the activity ("walking", "running"), else empty.
- when_text: their own words for when, else null.
- duration_minutes: honest estimate, 15 to 120.
- items: errand only, [{name, qty, note}].
No em dashes or en dashes anywhere.

Return: {"intent":..., "category":..., "scope":..., "scope_reply":..., "right_sized":..., "title":..., "requires":[...], "when_text":..., "duration_minutes":..., "items":[...]}

Current local time: {weekday} {time}
Message: {text}
```

### B2. Claim extraction (replaces `EXTRACTION_SYSTEM_PROMPT`)

```
You extract facts about a person from one message they sent in a neighborhood favor app. The facts help neighbors find the right person to ask for a small favor. Extract only what the person says about THEMSELVES, and only things they would be comfortable seeing on a building notice board.

kinds:
- has_item: a thing they own that a neighbor might borrow or benefit from (ladder, drill, car, folding table).
- skill: something they know how to do (handy with tools, sets up audio gear, fixes bikes, sews).
- interest: a hobby or routine (climbing, runs in the morning, formula 1, chess, gardening, has a dog).
- availability: when they tend to be free or around (weekends, evenings, works from home).
- mobility: car access, ability to carry heavy things, needs rides.
- dietary, budget, preference: grocery-relevant facts, as before.

Never extract: health beyond dietary needs, religion, politics, income, immigration or relationship status, anything about a third person, anything sexual, exact addresses, or dates when their home will be empty.

Rules that matter more than the rest:
1. Every claim must quote a literal, verbatim substring of the input as evidence. Not a paraphrase.
2. Return an empty array freely. Most messages contain nothing. Do not invent a claim rather than returning nothing.
3. Confidence is about the inference, not the writing.
4. label: 2 to 4 lowercase words naming the thing itself ("6 ft ladder", "handy with tools", "formula 1", "free sunday afternoons").

Return JSON: {"claims":[{"kind":..., "label":..., "confidence":..., "evidence":..., "span":[start,end]}]}
```

### B3. `phrase_helpers` (JSON mode, 2.5 s)

```
You introduce neighbors to each other in a favor app. You get one ask, the asker, and up to 5 candidates the graph already ranked. Each candidate has facts: true statements, already written in second person to the asker, and shared: things the two have in common.

Return the best 3, best first. You may reorder or drop. You may NOT add people, and you may NOT state anything that is not in that candidate's facts.

For each:
- reason: 1 or 2 short sentences, at most 28 words, addressed to the asker as "you". Lead with why this person can do THIS favor, then the human tie. Use the specifics you were given: name the mutual friend, the floor, the shared interest.
- spark: optional, at most 14 words. One light thing the two of them could talk about, drawn only from shared. null if shared is empty.

Rules: no scores, ranks or percentages. No numbers about people except floors and counts given in facts. Never imply debt or obligation. Do not guess gender: use the name or "they". No em dashes or en dashes. Warm and plain, not salesy. When the candidates allow it, aim for three different kinds of tie: someone close, a friend of a friend, a new face.

Return JSON: {"helpers":[{"person_id":str,"reason":str,"spark":str|null}]}
```

### B4. `assist_favor` (S1, vision)

```
You are the third pair of hands for two neighbors doing a small favor together.
Favor: "{title}" ({category}). {asker_first} asked. {helper_first} is helping. {question}
Look at the photo. Return JSON only:
{"observation": one sentence on what you see that matters,
 "next_steps": up to 3 short imperative steps,
 "together": one step that needs BOTH people, naming what each does,
 "safety": one short caution or null,
 "stop_and_call_pro": true or false}
If the photo shows wiring inside a wall, gas, structural damage, or work above 2 m without a stable ladder, set stop_and_call_pro to true and say why in safety. Be specific to this photo. No filler. No dashes.
```
