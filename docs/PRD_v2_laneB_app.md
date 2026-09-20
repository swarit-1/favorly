# Favorly v2 — Lane B: the app (`favorly_mobile/` only)

**Split from `v2prd.md` for parallel execution. You are Engineer B.** Engineer A works `agents/` + `backend/` from `docs/PRD_v2_laneA_brain.md` at the same time. Your tree is disjoint from theirs — work in a worktree:

```bash
git worktree add ../favorly-flutter -b v2-flutter
```

**Target:** HackMIT 2026 demo, Meta track. **Clock:** 3h30. Written against `main` at `9ce33ac`.

## Coordination protocol (the only section that mentions Lane A)

- **Section 2 (contracts) is frozen and duplicated in both lane docs.** You build against the fixtures in Appendix C — which match these shapes exactly — until Lane A announces each endpoint is live (intake at ~T+0:55, helpers at ~T+1:50, full loop at ~T+2:25). You flip to live API in 4.6 at T+1:50.
- If a contract must change, both docs get updated and both engineers are told. If code and this doc disagree, the code wins; leave a `// PRD-DEVIATION: <why>` comment.
- You never touch `agents/` or `backend/`. Lane A never touches `favorly_mobile/`.

## Rules of engagement

1. **Phases in priority order.** 4.1 → 4.7, gate, commit (`v2 phase 4.N: <what>`). Every step leaves the app demoable.
2. **Additive only.** No renames or removals of existing screens, models, or cached-JSON fields. New model fields are optional with defaults — **old caches in shared_preferences must still decode**.
3. **No new Flutter packages.**
4. **Copy rules:** no em/en dashes in user-facing strings (commas, periods, middle dots). Person first, task second. Never imply debt. **Never show a score, percentage, or rank number about a person.** Never guess gender (name or "they"). Pre-acceptance location is relative ("two floors up"); unit numbers only after both sides said yes.
5. **Do not touch:** auth, `lib/state/demo_store.dart` internals, golden images, the grocery flows (trips, merged list, substitution, receipt, settlement).
6. **Latency budget:** the app shows progress within 300 ms of any tap.

## Your timeline

| Clock | Work |
|---|---|
| T+0:00–0:15 | Read sections 1–2 here, add models + fixtures (4.1) |
| T+0:15–0:55 | **4.1–4.3** categories, home CTA, cards |
| T+0:55–1:50 | **4.4–4.5** Ask and Matches screens on fixtures |
| T+1:50–2:25 | **4.6** wire live API, My Ask card, polling |
| T+2:25–2:45 | **4.7** graph path highlight (**first thing to cut**) |
| T+3:10–3:30 | Rehearse with Lane A, freeze |

**Cut line:** behind at T+1:50 → drop 4.7.

## 1. The product in one screenful (context for every copy decision)

Favorly v2: text or type what you need, and Favorly introduces you to the neighbor who should help, and tells you why. The matcher optimizes for **ties worth forming**, not fastest fulfilment: every match carries a true, specific, human reason (never a score); the top three are three different kinds of tie (someone you know, a friend of a friend, a new face); a fulfilled friend-of-a-friend favor closes a triangle — the app shows a dashed two-hop path becoming a solid edge and "your building: 2.6 to 2.5 degrees apart".

**The app journey that must work (this is your spec):** Home → tap **Ask for anything** → type or speak "I need to borrow a ladder for an hour today" → three person cards, each with a tie pill, a headline, a reason, a path strip (You · Nora · Marcus) → tap **Ask Marcus** → waiting state → (poll) "Marcus is in" + spark + unit + **Message Marcus**. On Marcus's phone the ask is pinned on top of "Who needs you" as "Swarit asked for you".

Favor categories:

| Category | Meaning | App label | Icon (verify it compiles) |
|---|---|---|---|
| errand | pick something up on a trip | Pick up | `CupertinoIcons.cart` |
| borrow | borrow or lend a thing | Borrow | `CupertinoIcons.arrow_right_arrow_left` |
| hands | extra hands, under ~two hours | Extra hands | `CupertinoIcons.hammer` |
| skill | know-how | Know-how | `CupertinoIcons.wrench` |
| company | do something together | Company | `CupertinoIcons.person_2` |
| ride | a lift nearby | Ride | `CupertinoIcons.car` |
| care | keep an eye on something | Look after | `CupertinoIcons.heart` |
| other | fits the size rule, none of the above | Favor | `CupertinoIcons.sparkles` |

Unknown or missing category decodes as `errand` (old rows, old caches).

## 2. Contracts you consume (FROZEN — duplicated in the Lane A doc)

### `POST /needs/intake` — parse + scope check + create (called from AskScreen)
```jsonc
// request
{ "person_id": "uuid", "text": "I need to borrow a ladder for an hour today",
  "confirm_right_sized": false, "source": "app" }
// response
{ "intent": "ask_favor",            // ask_favor | offer_help | not_a_favor
  "scope": "ok",                    // ok | too_big | needs_pro | not_ok | unclear
  "scope_reply": null,              // one sentence when scope != ok
  "right_sized": null,              // neighbor-sized rewrite when too_big / needs_pro
  "need": { "id": "uuid", "category": "borrow", "title": "Borrow a ladder",
            "body": "...", "requires": ["ladder"], "when_text": "today",
            "duration_minutes": 60, "items": [] },   // null unless scope == ok
  "parsed_by": "model" }
```
`confirm_right_sized: true` re-submits a previously returned `right_sized` and skips the scope check.

### `GET /needs/{need_id}/helpers?limit=3` — the ranked matches (MatchesScreen)
```jsonc
{ "need_id": "uuid", "decided_by": "model",
  "helpers": [ {
    "person": { "id": "uuid", "display_name": "Marcus Hill", "first_name": "Marcus" },
    "rank": 1,
    "tie": "friend_of_friend",                        // close | friend_of_friend | extended | new
    "tie_label": "Friend of Nora",
    "hops": 2,
    "path": [ {"id":"..","name":"You"}, {"id":"..","name":"Nora"}, {"id":"..","name":"Marcus"} ],
    "headline": "Has a 6 ft ladder",
    "where": "3 floors up",                           // never a unit number pre-acceptance
    "reason": "Has a 6 ft ladder and is usually free Sunday afternoons. You both know Nora.",
    "spark": "You both follow F1.",                   // or null
    "signals": { ... },                               // never render these
    "why": { "mutual_names": ["Nora Chen"], "shared": ["formula 1"], ... },
    "invite_status": null                             // null | pending | accepted | declined
  } ] }
```

### Invites
- `POST /needs/{need_id}/invite` `{ "helper_id": "uuid" }` → `{ "status": "pending" }` (409 need not open, 422 self-invite; idempotent per pair)
- `POST /needs/{need_id}/invites/{helper_id}/respond` `{ "accept": false }` → decline returns `{ "status": "declined", "next": <HelperMatch or null> }`
- `POST /needs/{need_id}/broadcast` — ask everyone instead. `POST /needs/{need_id}/cancel`.

### `GET /people/{person_id}/asks` — the My Ask card
Open and claimed needs I posted, plus any fulfilled in the last 10 minutes, each with its helpers (with `invite_status`) and the accepted helper.

### `GET /graph/stats?person_id=` — the degrees-apart line (4.7)
`{ "people": 16, "ties": 23, "avg_separation": 2.61, "triangles": 7 }`

### Changed, backward compatible (affects existing models)
- `FavorSuggestion` (recommendations) adds `category`, `when_text`, `invited: bool`. Invited needs sort first server-side.
- `POST /needs/{id}/fulfill` response adds `first_favor_together: bool` and `separation: { before, after }`.
- `GET /graph` edges may carry new kinds `knows` and `neighbor`.

---

## Phase 4. The app handles any favor (45 min of build, in order)

Not a redesign. Home is already person-first ("Who needs you", the blue "You are helping" hero). Generalize nouns and icons, add one composer and one matches screen.

### 4.1 Models

- New `lib/models/favor_category.dart`: enum with `fromWire` (unknown → errand), `label`, `icon` per the table above.
- `lib/services/trellis_client.dart`: `FavorSuggestion` gains `category`, `whenText`, `invited` — **default-safe in `fromJson` and `toJson`** (old shared_preferences caches must decode). New classes `HelperMatch`, `IntakeResult`, `MyAsk`, `GraphStats`. New methods `intake`, `helpers`, `invite`, `respondInvite`, `broadcast`, `cancel`, `myAsks`, `graphStats`.
- New `lib/dev/fixtures.dart` holding Appendix C, behind `const bool kUseFixtures = bool.fromEnvironment('FIXTURES')`. Run with `--dart-define=FIXTURES=true` until Lane A is live.

### 4.2 Home (`trips_screen.dart`), small edits only

- Bottom bar: left button becomes **Ask for anything** (`CupertinoIcons.sparkles`) → opens `AskScreen`. **Post a trip** stays. The old "Add your list" moves inside `AskScreen` as the row "Have a grocery list? Snap it" → existing `AddListScreen` / `StandaloneRequestScreen`.
- New `_MyAsk` section above "Who needs you", only when `myAsks` is non-empty: title, one status line ("Finding the right neighbor" / "Waiting on Marcus" / "Marcus is in"), tap → `MatchesScreen`. Poll `myAsks` every 4 s while an ask is open and the tab is visible. Stop on dispose.
- Tab label `Trips` becomes `Home` (**label only** — `FTab` positions do not move; see the comment in `shell.dart`).
- Invited favors render first with the eyebrow "Asked for you".

### 4.3 Cards and detail

- `FavorCard`: 16 px category glyph badge bottom-right of the avatar. The person still leads.
- `FavorDetailScreen._connectionFacts`: add `capability` → "You have what they need", `nearness` → "You live close by", `similarity` → "You have things in common", `tie` → "You share people in common". An invited favor gets a quiet **Not this time** text button → `respondInvite(accept: false)`.
- In-progress notice by category: borrow "Meet at the door. Close it out here once it is back with you."; company "Enjoy it. Close it out here afterwards."; hands and skill "Work through it together, then close it out here."; default unchanged.
- Grep `favor_*.dart` for `grocer|bags|aisle|store` and neutralize anything not inside the errand branch.

### 4.4 `lib/screens/ask_screen.dart` (new)

Title "What do you need a hand with?". One multiline field with rotating placeholders ("Borrow a ladder for an hour", "Help me put up a shelf Saturday", "Walk the reservoir with me at 6", "Grab oat milk if you are out"). Mic button reuses `VoiceCaptureSheet`. A row of category `SelectChip`s that insert a starter phrase. CTA **Find my neighbor**.
- Loading = three honest steps tied to the two real calls: "Reading your ask" (intake), "Looking around your circle" and "Picking three people" (helpers).
- `too_big` / `needs_pro`: a `Notice` with `scope_reply`, the `right_sized` text in a quote block, buttons **Use that** (re-submit with `confirm_right_sized: true`) and **Reword it**.
- `not_ok` / `unclear`: a `Notice` with the sentence.
- `errand`: route into the existing list flow with the parsed items.

### 4.5 `lib/screens/matches_screen.dart` (new)

Header: title, when. One `PersonMatchCard` per helper in a `Panel`:
- `InitialsAvatar` 48, name, tie pill (`StatusPill` with `tie_label`), `headline · where`, the `reason` on the same sparkles line style `FavorCard` uses.
- **Path strip**: small dots joined by a line, labelled `You · Nora · Marcus`. That strip is the six-degrees idea, per card. For `tie: "new"` or `hops > 3`, draw only the two endpoints with a dotted line between them.
- Button **Ask {first}**. Footer text button **Ask everyone instead** (→ broadcast).
- After an invite: that card shows a pulsing "Waiting on Marcus", the others dim with the existing on-hold style. On acceptance (via polling): "Marcus is in", the `spark`, the unit, and **Message Marcus**.
- **No scores anywhere. Never render `signals`.**

### 4.6 Go live

Turn fixtures off, point at Trellis, run the hero journey on two devices (or device + simulator). Remember: on a physical phone set both server URLs on the dev login screen — `localhost` on a phone is the phone.

### 4.7 (First to cut) Make the graph visible

Mount the orphaned `WebScreen` as the first section of `CircleScreen`, or a "See the web" row that pushes it. `FavorGraphView` takes `highlightPath: List<String>` and draws that path dashed in `FColors.blue`. When the favor is fulfilled, refetch: the dashed path becomes a solid edge. Under the graph, from `graphStats`: "Your building: 2.5 degrees apart".

**Gate 4.** `flutter analyze` clean. `flutter test` green (goldens skipped by default, leave them). A cached pre-v2 favors list still decodes. Hero journey works app to app.

## Demo prep that lands on you (from Phase 5)

- The app pings `/health` on launch (Trellis on Vercel cold-starts slowly — this is the warmup).
- On each demo phone set both server URLs on the dev login screen.
- Rehearse the app half of the run of show: phone 2 opens the app → blue hero "You are helping Swarit" → Circle tab shows the dashed path You · Nora · Marcus → on "done" the path snaps solid, "Your building: 2.6 to 2.5 degrees apart".

## Stretch S1 (Flutter half, only if Lane A ships `/vision/assist` and every gate is green)

In `FavorDetailScreen` in-progress mode, for `hands`, `skill`, `borrow`: bottom bar becomes two buttons — **Stuck? Snap a photo** (existing `CameraScreen`, `domainType: 'favor_assist'`, `maxPhotos: 1`) and **Wrap up**. Render the response as a card: `observation`, numbered `next_steps`, the `together` line highlighted, `safety` as an attention `Notice`. `stop_and_call_pro: true` replaces the steps with the caution.

## Stretch S2 (Flutter half, only if Lane A ships `/route/plan`)

`lib/screens/route_screen.dart`: a `CustomPainter` floor plan with the path drawn through it, the stop list under it, suggestion cards with **Add** and **Skip**, a running total against each person's cap. Entry point: a **Route** action on `ShoppingScreen`.

## Non-goals

Payments. Push notifications. SSE (poll instead). Multi-circle. Ratings changes. Any redesign of trips, substitution, receipt, or settlement.

---

## Appendix C. Your fixtures (`lib/dev/fixtures.dart`)

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
