# Favorly v2 PRD: any favor, the right neighbor

**Target:** HackMIT 2026 demo. **Clock:** 3h30 from kickoff. **Primary track:** Meta, "Bringing People Closer Together with AI". **Stretch track:** Visa.
**Reader:** Claude Code, working in the `favorly` repo. Written against `main` at `9ce33ac`.
**Suggested location:** `docs/PRD_v2_any_favor.md`

---

## 0. Rules of engagement (read before touching code)

1. **Phases are in priority order.** Finish a phase, run its gate, commit (`v2 phase N: <what>`), move on. Every phase leaves the app demoable. Never start a stretch item before the Phase 5 gate passes.
2. **Additive only.** Do not rename or remove existing endpoints, fields, tables, or screens. New fields are optional with defaults so old clients and cached JSON still decode. The grocery loop (trips, merged list, substitution, receipt split, settlement) must keep working untouched.
3. **Offline first.** Every new LLM call has (a) JSON-only output, (b) a hard timeout, (c) a deterministic fallback. `cd backend && python -m pytest tests/` and Trellis with `MOCK_LLM=1` must work with zero API keys.
4. **Copy rules** (existing house style, keep it):
   - No em dashes or en dashes in user-facing strings. Commas, periods, middle dots.
   - Person first, task second. Never imply debt or obligation. Never show a score, percentage, or rank number about a person.
   - Do not guess gender. Use the name or "they".
   - Pre-acceptance, location is relative ("two floors up"). Unit numbers only after both sides said yes.
5. **No new dependencies in `agents/`** (Vercel size limit, see the note in `agents/requirements.txt`). Use stdlib (`difflib`, `re`) and `networkx`, which is already there. **No new Flutter packages.**
6. **Do not touch:** auth, vision grocery routes, settlement, `favorly_mobile/lib/state/demo_store.dart` internals, golden images.
7. **If this document and the code disagree, the code wins.** Adapt, and leave a `# PRD-DEVIATION: <why>` comment.
8. **Latency budget (hard requirement, it is the demo):** SMS ack within 2 s of the webhook. Three matches within 6 s. App shows progress within 300 ms of tapping.

### Lanes (run two Claude Code sessions if you can)

Files are disjoint, so use two worktrees: `git worktree add ../favorly-flutter -b v2-flutter`.

| Lane | Owns | Starts |
|---|---|---|
| **A: brain + texting** | `agents/`, `backend/` | T+0:00 |
| **B: app** | `favorly_mobile/` | T+0:00, builds against the fixtures in Appendix C until Lane A is live |
| **C: stretch (optional teammate)** | S1 and S2 are isolated. A free teammate can start either on a branch now. Merge only if green by T+2:45. | any time |

### Timeline

| Clock | Lane A | Lane B |
|---|---|---|
| T+0:00 to 0:15 | **P0** Unbreak texting, identity bridge | Read sections 3 and 4, add models + fixtures |
| T+0:15 to 0:55 | **P1** Any-favor intake + scope check | **P4.1 to 4.3** categories, home CTA, cards |
| T+0:55 to 1:50 | **P2** People graph, helper ranking, seed | **P4.4 to 4.5** Ask and Matches screens on fixtures |
| T+1:50 to 2:25 | **P3** Text loop end to end | **P4.6** wire live API, My Ask card, polling |
| T+2:25 to 2:45 | **P5** Reset, warmup, demo script | **P4.7** graph path highlight (first thing to cut) |
| T+2:45 to 3:10 | S1 or S2, only if every gate is green | |
| T+3:10 to 3:30 | Rehearse twice, record a backup video, freeze | |

Single lane order: P0, P1, P2, P3, P4 (4.1 to 4.5 only), P5. No stretch.

**Cut lines.** Behind at T+1:50: drop 4.7 and 2.8. Behind at T+2:25: drop the decline/advance branch in P3 and the group thread. The P3 gate alone is a complete demo.

---

## 1. Known defects at HEAD (verified, fix in P0)

1. **Texting is dead on `main`.** `backend/routes/linq_webhook.py::_sync_trellis` calls `trellis.register_person(...)`. That function was deleted from `backend/services/trellis_client.py` in `bf31a35`. `handle_message` appends a `("person", profile)` event on every message, and `_sync_trellis` runs before `send_reply`, so every inbound text raises `AttributeError` and **no reply is ever sent**. Reproduced locally by calling `_process(...)`.
2. **Seed members never load.** In `backend/agent/store.py` the block that reads `LINQ_USER_PHONES` and builds `self.profiles` sits after `return drained` inside `drain_events()`. It is unreachable (and references `seed`, a local of `__init__`). `store.profiles` is empty at startup.
3. **Texters are invisible to the graph.** Unknown phones get a random in-memory UUID. Trellis requires `person_id` to exist in `app_people` (Supabase Auth + `users`), so `post_need` 404s and is swallowed. Nothing a texter says reaches the graph.
4. **Three casts that do not match:** `backend/seed/demo_circle.json` (Alice, Bob, Carol), `backend/seed/cast.py` (Ana, Ben, Chloe, Maya Iyer), `agents/seed_data.py` (eight other residents, plus "Ana (Shopper)"). `cast.py` becomes the single source of truth in P2.
5. `_TRIP_RE` in `backend/agent/nlu.py` reads "I'm going to need help moving a couch" as a trip to the store "Need Help Moving A Couch".
6. The SMS reply prints `(match score 0.62)`. House style says never show scores.
7. `trellis_client._TIMEOUT` is 2.0 s, too short for a ranking call.
8. `favorly_mobile/lib/screens/web_screen.dart` (the favor graph) is not reachable from `shell.dart`. The graph exists and nobody can see it.
9. The "people matching" the team remembers was the intro-routing scorer. It was removed when scope narrowed to groceries (see the docstrings in `agents/schema.sql`, `agents/graph_metrics.py`, `agents/llm.py`). What remains ranks *needs for a helper*. v2 adds the inverse: *helpers for a need*. v2 deliberately reverses the "no matchmaking" note. Update the docstrings you touch.

---

## 2. Product thesis

> We all live twenty feet from someone who owns a ladder. We just do not know them.

Favorly v1: one neighbor's grocery trip carries the building. Favorly v2: **text what you need, and Favorly introduces you to the neighbor who should help, and tells you why.** Groceries become one category of favor among many.

The design choice that wins the Meta track: **the matcher does not optimize for the fastest fulfilment. It optimizes for ties worth forming.** Concretely:

- Every match comes with a true, specific, human reason (mutual friend, shared interest, floor), never a score.
- The top three are deliberately three different kinds of tie: someone you know, a friend of a friend, a new face.
- A friend-of-a-friend favor closes a triangle in the building's graph. After the favor, a two-hop path is a direct tie. The app shows it: a dashed path becomes a solid edge, and "your building: 2.6 to 2.5 degrees apart".
- The building's one super-helper is quietly down-weighted (internal `give_balance`, never shown) so asks spread out and new ties form.
- The AI introduces and then gets out of the way. Each intro carries a "spark": one true thing the two people have in common.

Closing line for the pitch: **"Favorly does not get your errand done faster. It makes your building smaller."**

---

## 3. The locked user journey (this is the spec and the demo script)

### 3.1 Hero journey, over iMessage

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

   (Marcus's phone)
   FAVORLY  Swarit on floor 3, a friend of Nora, is hoping to borrow a ladder today.
            Up for it? Reply YES or NO. No pressure either way.
   MARCUS   yes
   FAVORLY  You are on. Swarit is in 3C. Text DONE here when it is wrapped up.
            You both follow F1.

FAVORLY  Marcus is in. They are in 6C. You both follow F1, ask about Sunday's race.

   ... later ...
MARCUS   done
FAVORLY  (to both) Done. That was your first favor together. Your building just got a little closer.
```

Names above are illustrative. After seeding, run the real query and write the real output into `docs/DEMO_SCRIPT.md`. **Tune the seed, never the weights, until the three options tell three different stories.**

### 3.2 Locked decisions

| Decision | Locked value | Why |
|---|---|---|
| How many options | **3** over SMS. App shows 3 with "See more" up to 5. | Three fit on one iMessage screen without scrolling. |
| Two messages, not one | Ack that echoes the parsed title, then the matches | The echo proves understanding and buys 4 s of patience. |
| How to pick | A digit. Also a first name, EVERYONE, CANCEL. | Zero typing on stage. |
| Consent | Helper gets a no-pressure YES/NO. A decline reaches the asker as "can't make it today" plus an offer to ask the next person. | Asking must feel safe on both sides. |
| Plate size | One active favor per helper (existing rule). Busy helpers are excluded from ranking. | A favor is a thread, not a queue. |
| Conversation state | **Derived from the database, not process memory** (`GET /people/{id}/state`). | Survives restarts, tunnels, serverless. |
| Privacy | Relative location before acceptance, unit after. Phones never leave `backend/`. | Trust. |
| Scores | Never shown, on any surface. | House style, and it is the point. |
| Same brain for both surfaces | App and SMS call the same Trellis endpoints. | They can never disagree on stage. |

### 3.3 Other journeys that must work

- **Too big.** "help me build a house" gets: "That is more than one favor. Want to start with a piece of it, like: help me frame and raise one wall, about two hours? Reply YES to post that, or tell me again in your own words." YES posts the right-sized version and continues at the ack.
- **Needs a pro.** "can someone rewire my breaker panel" gets one sentence steering to a licensed electrician, and offers the safe adjacent favor ("ask the building who they would recommend").
- **Not ok.** One polite sentence. No lecture.
- **Company.** "anyone want to walk the reservoir around 6?" ranks on shared interest and availability, not tools.
- **Errand (regression).** "can someone grab me oat milk and eggs" behaves exactly as today.
- **Offer.** "I have a ladder if anyone ever needs one" gets "Noted. I will remember you have a ladder." and becomes a `has_item` claim.
- **Nobody fits.** "Nobody has told me they have a pasta maker yet. Want me to ask the whole building? Reply EVERYONE."
- **In the app.** Home, tap **Ask for anything**, type or speak, three person cards, tap **Ask Marcus**, waiting state, "Marcus is in". On Marcus's phone the ask is pinned on top of "Who needs you" as "Swarit asked for you".

---

## 4. Contracts (freeze these first, both lanes build to them)

### 4.1 Favor categories

`errand | borrow | hands | skill | company | ride | care | other`

| Category | Meaning | App label | Icon (verify it compiles) |
|---|---|---|---|
| errand | pick something up on a trip | Pick up | `CupertinoIcons.cart` |
| borrow | borrow or lend a thing | Borrow | `CupertinoIcons.arrow_right_arrow_left` |
| hands | extra hands, under about two hours | Extra hands | `CupertinoIcons.hammer` |
| skill | know-how | Know-how | `CupertinoIcons.wrench` |
| company | do something together | Company | `CupertinoIcons.person_2` |
| ride | a lift nearby | Ride | `CupertinoIcons.car` |
| care | keep an eye on something | Look after | `CupertinoIcons.heart` |
| other | fits the size rule, none of the above | Favor | `CupertinoIcons.sparkles` |

Unknown or missing category decodes as `errand` (old rows, old caches).

### 4.2 Trellis (`agents/`) new and changed endpoints

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
`confirm_right_sized: true` means `text` is a previously returned `right_sized`; skip the scope check. `intent: offer_help` writes an event (so extraction learns the claim), creates no need. Intake never runs claim extraction inline.

**`GET /needs/{need_id}/helpers?limit=3`** rank people for a need. Side effect: stores the ordered ids in `needs.shortlist`.
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

**`POST /needs/{need_id}/invite`** `{ "helper_id": "uuid" }` returns `{ "status": "pending" }`. 409 if the need is not open, 422 on self-invite. Idempotent per (need, helper).

**`POST /needs/{need_id}/invites/{helper_id}/respond`** `{ "accept": true }`
- accept: invite accepted, need claimed by helper (same rules as `/claim`), other pending invites expire. Returns `{ "status": "accepted" }`.
- decline: returns `{ "status": "declined", "next": <HelperMatch or null> }`, the next shortlist entry not yet invited.

**`POST /needs/{need_id}/broadcast`** clears the shortlist and leaves the need open to the feed. **`POST /needs/{need_id}/cancel`** sets status `cancelled`.

**`GET /people/{person_id}/state`** everything a stateless client needs to interpret "2", "yes", "done".
```jsonc
{ "person": { "id": "..", "display_name": "..", "first_name": "..", "floor": 3, "unit": "3C" },
  "open_ask": { "need_id": "..", "title": "Borrow a ladder", "category": "borrow",
                "shortlist": [ { "rank": 1, "person_id": "..", "first_name": "Marcus", "invite_status": "pending" } ] },
  "pending_invite": { "need_id": "..", "title": "..", "category": "borrow", "when_text": "today",
                      "asker": { "id": "..", "first_name": "Swarit", "floor": 3 }, "mutual_first_name": "Nora" },
  "active_favor": { "need_id": "..", "title": "..", "role": "helper",
                    "other": { "id": "..", "first_name": "Swarit", "unit": "3C" }, "spark": "..." } }
```
Each of the three is `null` when absent. Most recent wins.

**`GET /people/{person_id}/asks`** for the app's My Ask card: open and claimed needs I posted, plus any fulfilled in the last 10 minutes, each with its helpers (with `invite_status`) and the accepted helper.

**`GET /graph/stats?person_id=`** returns `{ "people": 16, "ties": 23, "avg_separation": 2.61, "triangles": 7 }`, circle-scoped. `avg_separation` is `nx.average_shortest_path_length` over the largest connected component.

**Changed, backward compatible:**
- `POST /needs` accepts optional `category, title, requires, when_text, duration_minutes, extract` (default true).
- `POST /needs/{id}/fulfill` response adds `first_favor_together: bool` and `separation: { before, after }`.
- `FavorSuggestion` (recommendations) adds `category`, `when_text`, `invited: bool`. Invited needs sort first.
- `GET /graph` edges may carry the new kinds `knows` and `neighbor`.

### 4.3 Backend (`backend/`)

No new public endpoints in the core path. The webhook becomes thin plumbing over the contracts above. Stretch: `POST /vision/assist` (S1), `POST /route/plan` (S2).

---

## Phase 0. Unbreak texting (15 min, Lane A)

**0.1** `backend/routes/linq_webhook.py`: delete the `kind == "person"` branch (registration is implicit now). In `_process`, a Trellis failure must never block a reply: wrap sync in `try/except`, log, send the reply anyway.

**0.2** `backend/agent/store.py`: remove the unreachable block from `drain_events()`. Do not resurrect `demo_circle.json` identities. Use 0.3.

**0.3** New `backend/agent/identity.py`, the phone-to-person bridge. `AgentStore.user_for_phone` delegates to it.
1. In-memory cache.
2. `users.phone` lookup through `db/client.py::get_supabase_client()`. Migration `backend/supabase/migrations/005_users_phone.sql`: `ALTER TABLE users ADD COLUMN IF NOT EXISTS phone TEXT;` plus a unique index where not null.
3. Env `LINQ_USER_PHONES="+16175550101=Swarit Srivastava,+16175550102=Marcus Hill"`: resolve by exact `users.name` inside the demo circle, then write the phone onto the row so step 2 hits next time.
4. Unknown phone: auto-provision. Create the Supabase Auth user first (`supabase.auth.admin.create_user`, email `p<digits>@favorly.test`, `DEV_PASSWORD`, `email_confirm: True`), then the `users` row with the same id, `circle_id` = the demo circle from `seed/cast.py`, `name = "Neighbor 1234"`, `phone`. Reuse the ordering logic in `backend/seed/seed_auth_users.py`. This is what lets a judge text the number cold and still get ranked matches.
5. No Supabase env (tests): current behaviour, random in-memory UUID.

**0.4** `backend/agent/nlu.py`: after `_TRIP_RE` or `_RUN_RE` matches, reject the match when the captured store starts with a verb (`need|help|be|have|get|do|make|move|build|borrow|ask|go|try|see`) or has more than four words. Add a test.

**0.5** `backend/agent/handlers.py`: remove `(match score ...)` from both reply strings. Update any test that asserts on it.

**0.6** `backend/services/trellis_client.py`: keep 2 s for fire-and-forget posts. Add `_LONG = httpx.Timeout(8.0)` for intake, helpers, and state.

**Gate 0**
```bash
cd backend && python -m pytest tests/ -q
uvicorn app:app --port 8000 &
curl -s -X POST localhost:8000/webhooks/linq -H 'Content-Type: application/json' -d '{
 "event_type":"message.received","data":{"chat":{"id":"c1"},"direction":"inbound",
 "sender_handle":{"handle":"+15550000001"},"parts":[{"type":"text","value":"can someone grab me oat milk"}]}}'
# expect a line in the server log: [linq:dry-run] reply to c1: ...
```

---

## Phase 1. Any favor in, right-sized (40 min, Lane A)

This is priority one. The scope check is one lightweight JSON call that parses and right-sizes together, so it costs one round trip.

**1.1 Schema.** New `agents/migrations/001_any_favor.sql`, and append the same statements to `agents/schema.sql`. Trellis on Vercel skips `apply_schema()` on cold start (`SERVERLESS`), so **run this file once by hand** against the database.
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

**1.2 `agents/llm.py`: `parse_favor(text, now) -> dict`.** Same pattern as `extract_claims`: real path uses `_chat_json` with the prompt in Appendix B1, 4 s timeout, any failure falls to the mock. Mock path is rules:

| Pattern (case-insensitive) | Result |
|---|---|
| `\b(grab|pick up|get me|buy|bring me)\b` plus item-like text | errand |
| `\b(borrow|lend me|does anyone have|anyone have an?)\b` | borrow, `requires` = the noun after it |
| `help me (build|assemble|hang|put up|move|carry|lift|install|mount)` | hands, `requires` includes `handy`, plus `drill` for build, hang, mount, put up |
| `(set ?up|fix|repair|tune|configure).*(sound system|speakers|wifi|router|bike|printer|tv)` | skill, `requires` = the mapped skill (`audio setup`, `wifi`, `bike repair`) |
| `\b(walk|run|jog|coffee|gym|workout|study|watch the game) with me\b`, `anyone want to` | company |
| `\b(ride|lift|drive me|drop me)\b` | ride, `requires: ["car"]` |
| `\b(water my plants|feed my (cat|dog|fish)|watch my|hold a package)\b` | care |
| `\bi have (a|an|some) .+ (if anyone|anyone can|happy to lend)\b`, `i can help with` | intent `offer_help` |
| too big: `build a house`, `renovate`, `remodel`, `move (apartments|out|house)`, `paint (my|the) (whole|entire)`, `plan my wedding` | `too_big` with a canned `right_sized` per pattern |
| needs pro: `rewire`, `breaker`, `gas (line|leak)`, `roof`, `cut down .*tree`, `asbestos` | `needs_pro` |
| not ok: `follow (my|him|her)`, `spy`, `track (my|his|her)`, `pay (you|someone)`, `fake`, `prescription` | `not_ok` |

`when_text`: regex for `today|tonight|tomorrow|this (morning|afternoon|evening|weekend)|(mon|tues|wednes|thurs|fri|satur|sun)day( morning| afternoon| evening)?|at \d{1,2}(:\d{2})?\s?(am|pm)?|around \d{1,2}`.

**1.3 `agents/routes/needs.py`: `POST /needs/intake`** per 4.2. `POST /needs` and `GET /needs` accept and return the new optional fields. New models in `agents/models.py`: `IntakeIn`, `IntakeOut`, `NeedOut`.

**1.4 De-grocery the helper-side copy** so the home feed reads right for any favor:
- `recommendations._build_reason` and `_reciprocity_fact`: "picked up groceries for you" becomes "helped you out". Add `helped` to `_REASON_STOPWORDS`.
- `_fallback_suggestions`: title is `need.title` when present, else the current "Grab X for Bob".
- `llm.DECIDE_SYSTEM_PROMPT`: "neighborhood grocery app" becomes "neighborhood favor app", the title example becomes category-neutral, and add the no-gender rule.
- `recommend_for` selects `category, title, when_text` and passes them through `_as_suggestion`.

**1.5 Backend routing**, new `backend/agent/favor_flow.py` with `async def handle_inbound(store, phone, text, now) -> tuple[list[str], list[Notification]]` (a list of replies, so ack and matches can be two messages). The webhook calls this. Order:
1. **Fast path, no LLM.** Fetch `state`. If the text is a short reply that the state can interpret, act on it (wired in P3; stub for now).
2. `parsed = parse_rules(text)`. If it is `offer_trip`, `status`, `get_recommendations`, `set_name`, or a grocery-verb `ask_favor` with items: call the existing sync `handle_message`. **Zero change to the grocery path.**
3. Otherwise call Trellis `POST /needs/intake`. Branch on the response:
   - `errand` with items: `store.create_ask(...)`, set `ask.trellis_need_id = need.id`, run the existing trip matching. In `_sync_trellis`, skip `post_need` when the id is already set.
   - `scope: ok`: reply 1 is the ack (`"{title}, {when_text}. Finding the right neighbor."`, drop the when clause if null). Reply 2 comes from P3. Until P3 lands: "Posted. I will text you when someone picks it up."
   - `too_big` or `needs_pro`: `"{scope_reply} Reply YES to post that, or tell me again in your own words."`. Remember `right_sized` for this phone in `store.pending_action` (the one allowed in-memory state, since it holds free text that lives nowhere else).
   - `not_ok` or `unclear`: `scope_reply`.
   - `offer_help`: "Noted. I will remember that."
   - Trellis unreachable: fall back to today's `parse_message` and `handle_message`.
4. After replying, fire-and-forget `trellis.log_event(person_id, text)` so extraction learns from what people say.

Update `HELP_TEXT` with two non-grocery examples.

**Gate 1.** New `backend/tests/test_favor_intake.py` (offline) and `agents/tests/test_parse_favor.py` (mock path):

| Text | Expect |
|---|---|
| can someone grab me oat milk and eggs | errand, ok, 2 items, existing reply unchanged |
| I need to borrow a ladder for an hour today | borrow, ok, requires has `ladder`, when `today` |
| can someone help me put up a shelf saturday morning | hands, ok, requires has `drill` |
| anyone want to go on a walk with me around 6 | company, ok |
| need help setting up my sound system | skill, requires has `audio setup` |
| can someone give me a ride to south station at 4 | ride, requires `car` |
| could someone water my plants next week | care, ok |
| help me build a house | too_big, `right_sized` not null |
| help me move apartments | too_big |
| can someone rewire my breaker panel | needs_pro |
| can someone follow my ex and tell me where she goes | not_ok |
| I have a ladder if anyone ever needs one | intent offer_help, no need created |
| I'm going to need help moving a couch | NOT offer_trip |

---

## Phase 2. The people graph and "who should help" (55 min, Lane A)

### 2.1 What the graph knows about a person

Widen claim kinds from four to eight. `claims.kind` is free text, no migration.

| Kind | Example labels | New |
|---|---|---|
| `has_item` | 6 ft ladder, drill, car, folding table, projector | yes |
| `skill` | handy with tools, audio setup, bike repair, sewing | yes |
| `interest` | formula 1, climbing, walking, chess, gardening, dog owner | yes |
| `availability` | free sunday afternoons, works from home, evenings | yes |
| `mobility`, `dietary`, `budget`, `preference` | as today | no |

- `agents/extraction.py`: widen `VALID_CLAIM_KINDS`.
- `agents/llm.py`: replace `EXTRACTION_SYSTEM_PROMPT` with Appendix B2. It includes a never-store list (health beyond diet, religion, politics, income, relationships, third parties, when a home is empty). Keep the verbatim-evidence span check exactly as is.
- `_MOCK_RULES`: add the rows in Appendix A.3 so `MOCK_LLM=1` produces every seeded claim.
- `agents/canonicalization.py::SEED_LABELS`: add `ladder, drill, tools, car, handy with tools, audio setup, bike repair, sewing, formula 1, climbing, running, walking, chess, gardening, dog owner, free weekends, works from home`.

### 2.2 Edges: a weighted graph per circle

`agents/config.py::EDGE_WEIGHTS` becomes `{"favor": 1.0, "knows": 0.6, "co_occurrence": 0.3, "neighbor": 0.25}`.
- `favor`: directed, decays (exists).
- `knows`: a declared tie. Seeded now, later from onboarding. **Does not decay.**
- `neighbor`: same floor, generated by the seeder. **Does not decay.**

In `edges.all_edges_decayed`, apply decay only to `favor` and `co_occurrence`:
`SUM(weight * CASE WHEN kind IN ('favor','co_occurrence') THEN <decay> ELSE 1 END)`.

### 2.3 New module `agents/matching.py`

```python
@dataclass
class Person:  id; display_name; first_name; floor: int | None; unit: str | None; availability: list[str]

@dataclass
class CircleContext:
    people: dict[str, Person]
    claims: dict[str, list[dict]]      # person_id -> active claims with confidence >= floor
    G: nx.Graph                        # undirected. edge attrs: strength (all kinds, both directions), favors_ab, favors_ba
    give_balance: dict[str, float]     # INTERNAL. Never returned, never phrased.
    busy: set[str]                     # people with a claimed, unfulfilled need
    recent: list[str]                  # last 10 favor one-liners in this circle, for LLM context

async def load_circle(conn, person_id) -> CircleContext
```
**Performance rule: exactly four SQL queries per ranking call** (members, claims for those members, decayed edges among them, claimed needs). Everything else is in memory. The existing per-pair `_reciprocity`, `_mutuals`, `_claims` helpers are N+1 and will blow the 6 s budget from Vercel. Do not call them in the new path.

**Signals.** Each returns `(value 0..1, evidence)`. Pure functions, unit-testable with no database.

| Signal | Weight | How |
|---|---|---|
| `capability` | 0.30 | Normalize tags (lowercase, strip plurals, synonym map: ladder/step ladder; drill/tools/toolbox; car/truck/suv; handy/carpentry/diy; audio setup/speakers/sound system/audio engineering). Match `need.requires` against the helper's `has_item` and `skill` claims (canonical and raw_label): all tokens contained or `difflib` ratio >= 0.85 is **1.0**; synonym hit **0.7**; when `MOCK_LLM=0`, embedding cosine >= 0.80 is **0.7**. Category fallbacks when `requires` is empty or unmatched: `company` = named activity matches an interest **1.0**, any shared interest **0.5**; `hands` = handy or moving-help skill **0.6**, else **0.3**; `ride` and `errand` = has car **1.0**, open trip **1.0**; `care` = same floor **0.6**. Evidence = the matched label, which becomes `headline` ("Has a 6 ft ladder", "Handy with tools", "Walks the reservoir most evenings"). |
| `tie` | 0.20 | Hop-minimal path via `nx.all_shortest_paths`; among ties pick the path with the best bottleneck strength. 1 hop **1.0**, 2 hops **0.85**, 3 hops **0.55**, 4 or more **0.30**, no path **0.15**. Labels: 1 = `close` / "You know each other"; 2 = `friend_of_friend` / "Friend of {mutual first name}"; 3+ = `extended` / "New to you"; none = `new` / "New to the building" when they joined in the last 30 days, else "New to you". |
| `similarity` | 0.15 | Jaccard over canonical labels of kind interest, preference, dietary, availability. One shared **0.5**, two or more **1.0**. Evidence = shared labels. Feeds `spark`. |
| `reciprocity` | 0.10 | From `G[a][b]`: favors in either direction, decayed, capped at 1. Evidence keeps direction ("Elena helped you out last week" vs "You helped Elena move a desk"). |
| `nearness` | 0.10 | Same floor **1.0** "same floor"; 1 apart **0.8** "1 floor up"; 3 or fewer **0.6** "N floors up/down"; same building **0.4**; unknown **0.3**. Becomes `where`. Never a unit number. |
| `availability` | 0.10 | The helper's `users.availability` days and `availability` claims against `when_text` and today's weekday. Match **1.0**, unknown **0.5**, conflict **0.2**. Evidence like "usually free Sunday afternoons". |
| `balance` | 0.05 | Internal. `1.0` normally, sliding to `0.4` when the helper's `give_balance` is far above the circle median. **No evidence string. Never enters copy, context, or the API.** |

**Hard filters:** not the asker, same circle, not in `busy`. For `borrow`, require `capability > 0`. If nobody passes, return `helpers: []` (the client says "nobody has told me they have X yet").

**Diversity rule:** after sorting, if the top three share one `tie` class and a candidate of another class scores at least 0.8 times the third, swap it into slot three. Three kinds of tie beats three near-duplicates.

**Cold-start asker** (no edges): `tie` is constant, so ranking falls to capability, nearness, similarity. Fact: "This would be your first favor in the building."

### 2.4 Reasons: the graph finds, the model phrases, the validator checks

Copy the `suggest_favors` pattern exactly.
1. Build pre-phrased, second-person `facts` per candidate, deterministically.
2. `llm.phrase_helpers(context)` with Appendix B3. Timeout **2.5 s**. Returns `reason` and `spark` per person. It may reorder or drop. It may not add.
3. Run `recommendations.validate_reason` on every string against the allowed text (names, labels, facts). Any failure means the template for that candidate.
4. Template fallback: headline, plus the strongest human fact. `spark` template: "You both {shared label phrase}." or null.
5. `strip_dashes` on everything. `decided_by` reports which path produced the result.

Include `recent` in the context so reasons can be timely ("Marcus lent his drill to Dev on Friday").

### 2.5 Endpoints

Implement in a new `agents/routes/helpers.py` and register it in `agents/app.py`: `GET /needs/{id}/helpers`, `POST /needs/{id}/invite`, `POST /needs/{id}/invites/{helper_id}/respond`, `POST /needs/{id}/broadcast`, `POST /needs/{id}/cancel`, `GET /people/{id}/state`, `GET /people/{id}/asks`, `GET /graph/stats`. Accepting an invite reuses the claim logic, do not duplicate it. `fulfill_need` computes `avg_separation` before and after the edge write, and `first_favor_together` (no prior favor edge either way).

### 2.6 Helper-side mirror (the home feed)

Minimal patch to `recommend_for`, not a rewrite:
- Add a `capability` signal using `matching.capability(need.requires, ...)` against the helper's own claims.
- New weights: `trip 0.20, capability 0.20, reciprocity 0.20, mutual 0.15, affinity 0.10, fit 0.10, freshness 0.05`.
- Left join `need_invites`: `invited = true` adds 0.5 and sorts first. Fact for the reason: "{first} asked for you."
- Reason fragment: "you have what they need: {label}".

### 2.7 Seed: `cast.py` is the single source of truth

- Extend `backend/seed/cast.py::ALL_CHARACTERS` to the 16 people in Appendix A.1 (stable ids via `make_stable_uuid`). The four canonical people keep their ids. Unit collisions are resolved in the appendix.
- Make sure the seeder writes both the Auth account and the `users` row (check `seed_auth_users.py` and `seed_demo.py`, one of them owns each). Idempotent. Only touches the demo circle.
- `agents/seed_data.py`: new scenario `"block"` alongside `warm` and `cold`. `cast.py` owns identity (ids, units, floors, availability). `seed_data.py` lists the same names as plain strings and resolves them with the existing `_resolve_identities`, which already fails loudly (`MissingIdentities`) if the two drift. **Do not import across packages:** Trellis deploys to Vercel without `backend/`. Seed **messages, not claims** (house rule), so extraction builds the profiles. Seed the edges in Appendix A.2, generate `neighbor` edges for same-floor pairs, and seed four open needs of mixed categories so the home feed is not all groceries.
- Presenters map onto cast members with `LINQ_USER_PHONES`. A teammate's real phone *plays* Marcus. The asker is added under their real name (env `DEMO_ASKER_NAME`, unit 3C).

### 2.8 (Cut first) Profile input

One free-text field on `profile_setup_screen.dart`: "What could neighbors borrow from you or ask you about?" It posts to Trellis `/events`, extraction does the rest.

**Gate 2**
```bash
cd agents && python -m pytest tests/ -q   # new: tests/test_matching.py, pure functions
curl -s -X POST $TRELLIS/admin/seed -H 'Content-Type: application/json' -d '{"scenario":"block"}'
NEED=$(curl -s -X POST $TRELLIS/needs/intake -H 'Content-Type: application/json' \
  -d '{"person_id":"<ASKER_ID>","text":"I need to borrow a ladder for an hour today"}' | jq -r .need.id)
time curl -s "$TRELLIS/needs/$NEED/helpers?limit=3" | jq '.helpers[] | {n:.person.first_name, tie, headline, where, reason, spark}'
```
Pass: three people, at least two different `tie` values, every reason true against the seed, under 5 s warm, and the same shape with `MOCK_LLM=1` (`decided_by: "graph"`).
Also check: "help me put up a shelf" surfaces Tom Becker; "walk the reservoir at 6" surfaces Grace and Priya; Sam is not first everywhere.

---

## Phase 3. The text loop, end to end (35 min, Lane A)

All in `backend/agent/favor_flow.py`, plus new `trellis_client` functions: `intake, helpers, invite, respond_invite, broadcast, cancel, state, fulfill`. Phones come from `users.phone` on the backend side. Trellis never sees a phone.

**3.1 Fast path** (before any LLM call). Fetch `state`, then match in this order:

| If state has | And the text matches | Do |
|---|---|---|
| `pending_invite` | `^(yes|y|yep|yeah|sure|ok|okay|i can|happy to)\b` | respond accept, send ACCEPT to both |
| `pending_invite` | `^(no|n|nope|can'?t|cannot|not today|sorry)\b` | respond decline, send DECLINE to asker |
| `open_ask` with shortlist | `^[1-5]$`, or a shortlist first name | invite that helper, send INVITE and WAIT |
| `open_ask` | `^(everyone|all|anyone)\b` | broadcast |
| `open_ask` | `^(cancel|never ?mind|forget it)\b` | cancel |
| `open_ask` with a declined invite and a `next` | `^(yes|y|sure|ok)\b` | invite `next` |
| remembered `right_sized` | `^(yes|y|sure|ok|do that)\b` | intake with `confirm_right_sized: true` |
| `active_favor` | `^(done|all done|finished|returned|got it back|all set|thanks,? done)\b` | fulfill, send DONE to both |

**3.2 After the ack:** call `helpers`, send MATCHES as the second reply. Empty list sends NOBODY.

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
Use "One neighbor who fits" or "Two neighbors who fit" when fewer than three come back.

**3.4 Seeded people have no phone.** If the picked helper has no `users.phone`, they can only answer in the app. Env `DEMO_AUTOACCEPT_SECONDS` (default unset): when set, a phoneless seeded persona accepts after that delay, and the log line says `[demo] auto-accept for seeded persona`. This is a stand-in for people who do not exist, nothing more. On stage the hero helper is a real teammate on a real phone. Say so if a judge asks.

**3.5 (Timebox 10 min, then drop)** Group intro. `linq_client.send_reply` already posts `"to": [to]`, a list. After ACCEPT, try one message with `to: [asker_phone, helper_phone]`: "Swarit, meet Marcus. Marcus, meet Swarit. I will leave you to it." If Linq errors, keep the two 1:1 messages and move on.

**Gate 3.** Dry-run, two fake phones through the webhook with curl: ask, then "1", then "yes" from the helper phone, then "done". Assert the log shows ACK, MATCHES, WAIT, INVITE, both ACCEPTs, both DONEs, and `GET /graph` shows a new `favor` edge. Add `backend/tests/test_favor_loop.py` with `trellis_client` monkeypatched to fixtures.

---

## Phase 4. The app handles any favor (45 min, Lane B, parallel)

Not a redesign. The home screen is already person-first ("Who needs you", the blue "You are helping" hero). Generalize nouns and icons, add one composer and one matches screen.

**4.1 Models.** New `lib/models/favor_category.dart` (enum, `fromWire`, `label`, `icon`). In `lib/services/trellis_client.dart`: `FavorSuggestion` gains `category`, `whenText`, `invited` (default-safe in `fromJson` and `toJson`, because old caches in shared_preferences must still decode). New classes `HelperMatch`, `IntakeResult`, `MyAsk`, `GraphStats`. New methods `intake`, `helpers`, `invite`, `respondInvite`, `broadcast`, `cancel`, `myAsks`, `graphStats`. Add `lib/dev/fixtures.dart` holding Appendix C, behind `const bool kUseFixtures = bool.fromEnvironment('FIXTURES')`.

**4.2 Home** (`trips_screen.dart`), small edits only:
- Bottom bar: left button becomes **Ask for anything** (`CupertinoIcons.sparkles`) and opens `AskScreen`. **Post a trip** stays. The old "Add your list" moves inside `AskScreen` as the row "Have a grocery list? Snap it", which opens the existing `AddListScreen` or `StandaloneRequestScreen`.
- New `_MyAsk` section above "Who needs you", only when `myAsks` is non-empty: title, one status line ("Finding the right neighbor", "Waiting on Marcus", "Marcus is in"), tap opens `MatchesScreen`. Poll `myAsks` every 4 s while an ask is open and the tab is visible. Stop on dispose.
- Tab label `Trips` becomes `Home` (label only. `FTab` positions do not move. See the comment in `shell.dart`).
- Invited favors render first, with the eyebrow "Asked for you".

**4.3 Cards and detail.**
- `FavorCard`: a 16 px category glyph badge on the bottom-right of the avatar. The person still leads.
- `FavorDetailScreen._connectionFacts`: add `capability` "You have what they need", `nearness` "You live close by", `similarity` "You have things in common", `tie` "You share people in common". An invited favor gets a quiet **Not this time** text button that calls `respondInvite(accept: false)`.
- In-progress notice by category: borrow "Meet at the door. Close it out here once it is back with you."; company "Enjoy it. Close it out here afterwards."; hands and skill "Work through it together, then close it out here."; default unchanged.
- Grep `favor_*.dart` for `grocer|bags|aisle|store` and neutralize anything that is not inside the errand branch.

**4.4 `lib/screens/ask_screen.dart` (new).** Title "What do you need a hand with?". One multiline field with rotating placeholders ("Borrow a ladder for an hour", "Help me put up a shelf Saturday", "Walk the reservoir with me at 6", "Grab oat milk if you are out"). Mic button reuses `VoiceCaptureSheet`. A row of category `SelectChip`s that insert a starter phrase. CTA **Find my neighbor**.
- Loading is three honest steps tied to the two real calls: "Reading your ask" (intake), "Looking around your circle" and "Picking three people" (helpers).
- `too_big` and `needs_pro`: a `Notice` with `scope_reply`, the `right_sized` text in a quote block, buttons **Use that** and **Reword it**.
- `not_ok` and `unclear`: a `Notice` with the sentence.
- `errand`: route into the existing list flow with the parsed items.

**4.5 `lib/screens/matches_screen.dart` (new).** Header: title, when. Then one `PersonMatchCard` per helper in a `Panel`: `InitialsAvatar` 48, name, a tie pill (`StatusPill` with `tie_label`), `headline · where`, the `reason` on the same sparkles line style `FavorCard` uses, and a **path strip**: small dots joined by a line, labelled `You · Nora · Marcus`. That strip is the six-degrees idea, per card. Button **Ask {first}**. Footer text button **Ask everyone instead**.
After an invite: that card shows a pulsing "Waiting on Marcus", the others dim using the existing on-hold style. On acceptance (via polling): "Marcus is in", the `spark`, the unit, and **Message Marcus**. No scores anywhere.

**4.6 Go live.** Turn fixtures off, point at Trellis, run the hero journey on two devices or a device plus a simulator.

**4.7 (First to cut) Make the graph visible.** Mount the orphaned `WebScreen` as the first section of `CircleScreen`, or a "See the web" row that pushes it. `FavorGraphView` takes `highlightPath: List<String>` and draws that path dashed in `FColors.blue`. When the favor is fulfilled, refetch: the dashed path becomes a solid edge. Under the graph, from `graphStats`: "Your building: 2.5 degrees apart".

**Gate 4.** `flutter analyze` clean. `flutter test` green (goldens are skipped by default, leave them). A cached pre-v2 favors list still decodes. Hero journey works app to app.

---

## Phase 5. Demo hardening (20 min)

1. `POST /admin/demo/reset` on Trellis: reseed `block`, clear `need_invites`, cancel the presenters' open needs. `scripts/demo_reset.sh` calls it, clears `store.pending_action` through a dev-only backend route, then pings `/health` on both services.
2. **Warm up.** Trellis is on Vercel, and a cold start costs seconds. The app pings `/health` on launch. The reset script pings three times. Ping again 60 s before going on.
3. **Stale-on-error.** Cache the last good `helpers` response per need text for 10 minutes. Serve it only if ranking raises or times out, and log that it happened.
4. **Linq sandbox limits** (from the README): inbound first, 30 messages per 60 s per pair, **100 per day**. Every demo phone texts "hi" once up front. A full run is about 12 messages. Rehearse in console dry-run. At most three live rehearsals.
5. On each demo phone set both server URLs on the dev login screen (API and Trellis). `localhost` on a phone is the phone.
6. Write `docs/DEMO_SCRIPT.md` from section 3.1 **using the real output**. Add one README paragraph for the v2 flow.
7. Record one clean full run. That recording is the fallback if the venue wifi dies.

**Gate 5.** Two consecutive clean live runs from reset.

---

## Stretch S1. Assist mode (25 min, isolated)

When you are on a favor with someone, the screen becomes a workbench, and a photo gets you unstuck. It runs on the existing Meta Muse vision service, which is a good line for the Meta judges.

- **Backend.** `POST /vision/assist` in `backend/routes/vision.py`, copying the `/home-repair/damage-detection` pattern (multipart `files`, `image_storage.upload_images`). Form fields: `need_id, title, category, asker_first, helper_first, question?`. Add `VisionService.assist_favor(...)` that calls `_analyze_image_with_prompt` with Appendix B4. Add the same method to `OpenAIVisionService` and `MockVisionService`. Response: `{ observation, next_steps[<=3], together, safety, stop_and_call_pro }`.
- **The design point:** the `together` field always hands a step to *both* people ("One of you hold the shelf level while the other marks the holes"). The AI is the third pair of hands, not a replacement for the second person.
- **Flutter.** In `FavorDetailScreen` in-progress mode, for `hands`, `skill`, `borrow`: the bottom bar becomes two buttons, **Stuck? Snap a photo** (opens the existing `CameraScreen` with `domainType: 'favor_assist'`, `maxPhotos: 1`) and **Wrap up**. Show the result as a card: observation, numbered steps, the `together` line highlighted, `safety` as an attention `Notice`. `stop_and_call_pro` replaces the steps with the caution.
- **Gate:** a photo of a shelf bracket returns steps in under 8 s. The mock path works with no key.

## Stretch S2. Visa track: Favorly Route (40 min, isolated)

**The reframe.** The original idea steers the shopper toward things they did not plan to buy. That is the store's trick pointed at the same person, and a payments judge will hear "AI that makes you spend more". Flip whose side the agent is on.

> **A store is laid out for the store. Your route is laid out for you.**
> Favorly Route is a shopping agent that works for the shopper. It turns your list, plus everything your neighbors attached to your trip, into the shortest walk through the store. Along the way it proposes at most three stops, each explained, each one tap to accept or skip, and it never lets anyone go over the spending cap they set.

Suggested stops keep the "things you did not know you needed" idea, grounded in context you gave it:
1. **For a neighbor:** "Grace needs milk. Dairy is already on your route. Adds 0 m." This is the Favorly tie-in: the detour worth making is the one for a person.
2. **For future you:** "Your pantry scan on Thursday showed one egg left." (`pantry_scans` already exists.)
3. **Usually forgotten:** an item on your last three lists that is missing from this one, only if its section is already on the path.

Why it fits Visa: the open problem in agent-driven shopping is trust. Will the agent act in my interest, inside limits I set, and explain itself? Route is a working miniature: consent per suggestion, per-person spend caps (`TripCaps` already has them), a visible reason for every recommendation, a receipt-level audit at the end (the receipt split exists). Pitch-only roadmap line, do not build: each requester pre-authorizes a capped amount on their own card, so the shopper never fronts money. **I could not find the Visa challenge text online. Read the brief at their booth and adjust the one-liner to their wording.**

Build:
- `backend/seed/store_layouts/generic_grocery.json`: x,y in metres for `entrance`, `checkout`, and every `StoreSection` value (`produce, dairy, meat, bakery, frozen, pantry, beverages, household, personal_care, other`).
- `backend/routes/route.py`: `POST /route/plan { trip_id }` builds stops from the merged list grouped by section, solves the order with Held-Karp (10 nodes or fewer, exact and instant) over Manhattan distance from entrance to checkout, and returns `{ stops[], distance_m, baseline_distance_m, suggestions[], caps[] }`. `baseline_distance_m` is the same list walked in written order, so the "212 m instead of 480 m" line is computed, not invented.
- `lib/screens/route_screen.dart`: a `CustomPainter` floor plan with the path drawn through it, the stop list under it, suggestion cards with **Add** and **Skip**, and a running total against each person's cap. Entry point: a **Route** action on `ShoppingScreen`.
- **Gate:** a seeded trip renders a route. Accepting a suggestion re-plans. A cap warning fires.

---

## Non-goals

Payments. Push notifications. SSE in Flutter (poll instead). Multi-circle. Ratings changes. Learned weights. Any redesign of trips, substitution, receipt, or settlement.

---

## Appendix A. Seed (`block` scenario)

### A.1 Cast. Building: the demo circle from `cast.py`. `*` = canonical, keep the id.

| Name | Unit / floor | Seed messages (extraction turns these into claims) | `users.availability` |
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

The old Trellis resident "Maya Chen" is renamed **Nora Chen**. Two Mayas make "you both know Maya" ambiguous.

### A.2 Edges. `favor` = (giver, receiver, days ago). `knows` is undirected.

```
favor:  Nora->ASKER 6 · ASKER->Nora 12 · Elena->ASKER 4 · Nora->Marcus 9 · Marcus->Nora 3
        Sam->Nora 9 · Sam->Dev 7 · Sam->Priya 5 · Sam->Grace 3 · Sam->Ana 4
        Priya->Grace 5 · Marcus->Grace 8 · Dev->Elena 10 · Ana->Elena 13
        Ana->Ben 6 · Chloe->Ana 9 · Maya Iyer->Ben 11 · Lina->Marcus 14 · Noah->Grace 2
knows:  Nora-Marcus (climbing) · Dev-Noah (chess) · Ana-Chloe · Priya-Ben (music)
neighbor: generated for every same-floor pair
```
Intended shape: **Marcus is two hops from the asker through Nora** (the triangle to close). **Elena is one hop and same floor.** **Jordan has only floor-2 neighbor edges** (four hops out, the new face). **Tom Becker is almost disconnected**: the retired carpenter on the seventh floor nobody has met, who should surface for "help me build a shelf". **Sam is the hub** the balance signal gently rests. **Grace mostly receives**, and a walk lets her give.

Open needs to seed: Grace, errand, "could someone grab milk and eggs this week?" · Dev, skill, "anyone know how to hem trousers?" · Lina, hands, "need a hand carrying a bookshelf up to 6A Saturday" · Priya, company, "anyone up for the reservoir loop with me and the dog tonight?"

### A.3 Mock extraction rules to add to `_MOCK_RULES` (pattern, kind, label, confidence)

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
The mock extractor stops at five claims per message, so keep seed messages to one or two facts each. **Invariant, add a test:** after `seed("block")` under `MOCK_LLM=1`, every person holds the claims their messages imply.

---

## Appendix B. Prompts

### B1. `parse_favor` (Trellis, JSON mode, 4 s timeout)

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

### B3. `phrase_helpers` (Trellis, JSON mode, 2.5 s timeout)

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

---

## Appendix C. Fixture for the Flutter lane (`lib/dev/fixtures.dart`)

```json
{
  "intake": { "intent": "ask_favor", "scope": "ok", "scope_reply": null, "right_sized": null, "parsed_by": "model",
    "need": { "id": "need-1", "category": "borrow", "title": "Borrow a ladder", "body": "I need to borrow a ladder for an hour today",
              "requires": ["ladder"], "when_text": "today", "duration_minutes": 60, "items": [] } },
  "intake_too_big": { "intent": "ask_favor", "scope": "too_big", "need": null, "parsed_by": "model",
    "scope_reply": "That is more than one favor. Want to start with a piece of it?",
    "right_sized": "help me frame and raise one wall, about two hours" },
  "helpers": { "need_id": "need-1", "decided_by": "model", "helpers": [
    { "person": {"id":"p-marcus","display_name":"Marcus Hill","first_name":"Marcus"}, "rank":1,
      "tie":"friend_of_friend","tie_label":"Friend of Nora","hops":2,
      "path":[{"id":"me","name":"You"},{"id":"p-nora","name":"Nora"},{"id":"p-marcus","name":"Marcus"}],
      "headline":"Has a 6 ft ladder","where":"3 floors up",
      "reason":"Has a 6 ft ladder and is usually free Sunday afternoons. You both know Nora.",
      "spark":"You both follow F1.","signals":{},"why":{"mutual_names":["Nora Chen"],"shared":["formula 1"]},"invite_status":null },
    { "person": {"id":"p-elena","display_name":"Elena Vasquez","first_name":"Elena"}, "rank":2,
      "tie":"close","tie_label":"You know each other","hops":1,
      "path":[{"id":"me","name":"You"},{"id":"p-elena","name":"Elena"}],
      "headline":"Has a step ladder","where":"same floor",
      "reason":"Has a step ladder and lives on your floor. Elena helped you out last week.",
      "spark":null,"signals":{},"why":{},"invite_status":null },
    { "person": {"id":"p-jordan","display_name":"Jordan Reyes","first_name":"Jordan"}, "rank":3,
      "tie":"new","tie_label":"New to the building","hops":4,
      "path":[{"id":"me","name":"You"},{"id":"p-jordan","name":"Jordan"}],
      "headline":"Has a ladder","where":"1 floor down",
      "reason":"Still has a ladder from the move. This would be Jordan's first favor in the building.",
      "spark":null,"signals":{},"why":{},"invite_status":null } ] }
}
```
For `tie: "new"` or `hops > 3`, the path strip draws only the two endpoints with a dotted line between them.

---

## Appendix D. Three-minute run of show

| Time | Beat | Surface |
|---|---|---|
| 0:00 | "We all live twenty feet from someone who owns a ladder. We just do not know them." | slide or voice |
| 0:15 | Text the ask. Ack, then three people, three kinds of tie, three true reasons. | phone 1 mirrored |
| 0:45 | Reply "1". Teammate's phone buzzes on stage. They reply "yes". Both get the intro with the spark. | phones 1 and 2 |
| 1:10 | Open the app on phone 2: blue hero, "You are helping Swarit". Circle tab: the dashed path You, Nora, Marcus. | app |
| 1:35 | "done". The dashed path snaps solid. "Your building: 2.6 to 2.5 degrees apart." | app + phone |
| 1:55 | Range, rapid fire: "anyone want to walk the reservoir at 6?" then "help me build a house". | phone 1 |
| 2:25 | (If S1) snap the shelf bracket, read the `together` step aloud. (If S2) show the route. | app |
| 2:45 | "It did not pick the closest friend or the building's busiest helper. It picked the tie worth forming. Favorly does not get your errand done faster. It makes your building smaller." | voice |