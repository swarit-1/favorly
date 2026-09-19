# Lane D — Demo + Data

Owner: _TBD_ · Depends on: A (seed endpoint), B (cached fixtures), C (screens) · Blocks: the demo
Drives PRD §8 (3 phones, ~2.5 min, every beat <20s) and §10 (zero manual DB edits).

## Mission
Make the demo deterministic. Stage every input, pre-record every AI output, seed a circle that looks
alive, rehearse until the run is boring.

## In scope
- `seed/demo_circle.json` — loaded by `POST /dev/seed` (Lane A). Contents:
  - Circle **"Maple St — Building B"**, invite code `MAPLE7`.
  - Users: **Ana** (Phone A, shopper, venmo `@ana-r`), **Ben** (Phone B, requester, `@ben-k`), **Chloe** (Phone C, requester, `@chloe-m`), plus 3 background neighbors.
  - 4 prior DONE trips over the last 2 weeks (Trader Joe's, Costco, H-Mart, CVS) with requests, items, receipts, settlements and ledger events so `/ledger` shows real numbers (Ana 2 trips run; Ben 3 favors received / $61.40 carried, etc.).
  - No OPEN trip — Phone A creates it live (beat 1).
- `seed/images/` — staged, tested photos (also pushed to Supabase Storage by the seed):
  - `list_handwritten.jpg` — Chloe's legible 5-item handwritten list (bananas, oat milk, sourdough, unsalted butter, dark chocolate). One deliberately messy item ("2 lemns") to show the confirm flow.
  - `shelf_butter.jpg` — a butter shelf with 3–4 visible brands and price tags; the intended substitute (Kerrygold unsalted, $4.49) must be legible.
  - `receipt_tj.jpg` — Trader Joe's receipt, 10–12 lines, tax line, total; contains every item from Ben's + Chloe's lists (with the substitute), plus 2 of Ana's own items.
  - `handoff.jpg` — bag on a doorstep.
- `seed/audio/trip_post.webm` — "I'm going to Trader Joe's at three, max five people, forty bucks each." Also the typed fallback string.
- `seed/typed_list_ben.txt` — Ben's typed list (6 items) pasted from clipboard during the demo.
- `demo/RUNBOOK.md` — beat-by-beat script with who taps what, expected screen, expected latency, and the **fallback action** for each beat.
- `demo/CHECKLIST.md` — pre-flight: phones charged, PWA installed, same Wi-Fi + hotspot backup, `VISION_PROVIDER` set, cache warmed, seed reloaded, Venmo installed on B and C.

## Demo script (PRD §8, target 2:30)

| # | Phone | Action | Expected | Budget | Fallback |
|---|---|---|---|---|---|
| 1 | A | Tap mic, say the trip | fields prefilled, tap Post; B/C feeds show it | 15s | type it |
| 2 | B | Paste typed list → review → attach | 6 items, 0 flags | 15s | — |
| 2 | C | Photograph handwritten list → review → fix "lemns" → attach | 5 items, 1 flag | 20s | pick `list_handwritten.jpg` from gallery (cached fixture) |
| 3 | A | Open Shop view | merged list, 3 sections, running totals | 5s | — |
| 4 | A | Butter → Out of stock → shoot shelf | C's phone shows 3 candidates | 20s | gallery photo → cached |
| 4 | C | Tap Kerrygold | A's list updates live | 5s | — |
| 5 | A | Shoot receipt → confirm 1 ambiguous line | B and C see itemized totals + Venmo button | 20s | gallery → cached |
| 5 | B | Tap Pay with Venmo | Venmo opens with amount + note prefilled | 5s | show web link |
| 6 | A | Handoff photo → confirm | `/ledger` on all phones updates | 10s | skip photo |

## Out of scope
Building any feature, changing contracts, writing prompts (report failures to B with the image and the bad output attached).

## Milestones
- **H0–2:** `demo_circle.json` v1 (users + circle + 1 prior trip) so A can test the seed; buy/stage physical items and shoot `shelf_butter.jpg`, `receipt_tj.jpg`, `list_handwritten.jpg` (real store run — do this early, daylight).
- **H2–8:** full seed (4 prior trips, ledger numbers), typed list, audio clip; verify Venmo deep link with C on both platforms and record the answer in `RUNBOOK.md`.
- **H8–14:** run each image through B's real pipeline; log outcomes; iterate the images (reshoot) rather than the prompts when legibility is the problem.
- **H14–18:** first full 3-phone run on real devices; time every beat; file issues per lane with screenshots.
- **H18–22:** warm B's cache for every staged input; runbook + checklist final; PWA install on all 3 phones; hotspot backup tested.
- **H22–24:** ≥3 clean end-to-end rehearsals in a row with `VISION_PROVIDER=muse`, ≥1 with `mock`. Freeze.

## Acceptance
- `POST /dev/seed` on an empty DB → `/ledger` shows the seeded numbers; re-running is idempotent.
- Every image in `seed/images/` has a matching cached fixture in `ai/fixtures/MANIFEST.md`.
- Three consecutive rehearsals complete in <3:00 with zero manual DB edits and every beat within budget.
- Receipt split totals in the demo equal `receipt_tj.jpg`'s printed total to the cent.
