# Favorly — Product Requirements Document (v0, Hackathon Barebones)

**One-liner:** A neighbor posts "I'm going shopping at 3." Neighbors attach requests in any format. One trip carries the whole building. Zero fees, zero coordination.

**Positioning:** Instacart monetizes a stranger doing your errand; Favorly de-monetizes a trip that was already happening.

**Scope discipline:** This PRD covers the CORE SERVICE LOOP only. Connection features (relationship routing, intros, story cards), incentive systems (karma redemption, merchant perks), and revenue integrations (building amenity, senior phone line) are explicitly OUT OF SCOPE for v0 and will be layered on after the loop works end to end.

---

## 1. Problem

- Delivery apps charge 20–30% in fees/markups for trips a neighbor was already making.
- Informal proxy-shopping (group chats, mutual-aid spreadsheets) dies on coordination overhead: parsing lists, merging carts, substitutions, splitting receipts, chasing repayment.
- The coordination admin is exactly what a VLM pipeline can delete.

## 2. Core Loop (v0 must complete this end to end)

1. **Post Trip** — Shopper posts store + departure time (tap or voice). Sets caps: max requests, max $ per person.
2. **Attach Requests** — Circle members attach requests as (a) typed text, (b) voice note, (c) photo of a handwritten list. VLM parses all three into structured items with quantities and per-item requester caps.
3. **Merged List** — Shopper sees one aisle-ordered list, each item tagged to requester + cap. Accept/decline per item. Declines are invisible to requesters.
4. **Substitution Flow** — Item out of stock → shopper snaps the shelf → VLM identifies alternatives → requester taps a substitute remotely. (Demo-critical "magic beat.")
5. **Receipt Split** — Shopper snaps receipt → VLM assigns line items to requesters → each requester sees exactly what they owe → Venmo deep-link. No in-app payments, no escrow.
6. **Handoff + Ledger** — Doorstep handoff confirmed (photo optional). Reciprocity ledger increments: trips run / favors received per member. Display-only in v0.

## 3. Users

- **Shopper (carrier):** wants bounded, zero-admin helping. Needs caps, merged list, no chasing money.
- **Requester:** wants items without fees. Needs low-friction request entry, substitution control, transparent split.
- **Circle:** a building/floor/street group (v0: one hardcoded demo circle, join via invite code).

## 4. Functional Requirements

### 4.1 Trips
- Create trip: store name, departure time, caps (max requesters, max $/person, max items/person).
- Trip states: OPEN → SHOPPING → SETTLING → DONE.
- Push/real-time notification to circle on trip creation.

### 4.2 Request Intake (AI Surface #1)
- Text input: free-text → structured items [{name, qty, note, max_price}].
- Photo input: handwritten/scribbled list image → same structure. Confidence flags on low-certainty items; requester confirms before submit.
- Voice input: audio → transcript → same structure.
- Requester reviews/edits parsed items before attaching to trip.

### 4.3 Merged List
- Aggregate accepted requests into single list, grouped by store section (static section mapping is fine for v0).
- Per-item: requester tag, cap, note. Running total per requester vs their cap.

### 4.4 Substitution (AI Surface #2)
- Shopper marks item unavailable → camera → shelf photo → VLM returns 2–4 candidate products (name, price if visible).
- Requester gets real-time prompt → taps choice or "skip item" → shopper's list updates live.
- Fallback if requester unresponsive in N minutes: skip item (v0 default).

### 4.5 Receipt Split (AI Surface #3)
- Receipt photo → VLM extracts line items + prices → auto-assign to requesters by matching against merged list → shopper confirms ambiguous lines.
- Per-requester settlement screen: items, subtotal, tax share (proportional), Venmo deep-link with amount + note prefilled.
- No money moves through the app in v0.

### 4.6 Ledger
- Per member: trips_run, favors_received (count + $ carried).
- Circle view: simple list. No gamification, no redemption in v0.

## 5. AI Architecture

- **Primary VLM:** Meta Muse Spark via Meta Model API (OpenAI-SDK-compatible client) — list photo parsing, shelf substitution ID, receipt itemization.
- **Fallback:** any frontier VLM behind the same interface (abstract as `VisionService`) so demo never blocks on one API.
- **Speech:** Whisper-class API or Deepgram for voice notes.
- **Prompting pattern:** every VLM call returns strict JSON (schema in /shared/contracts). All parses are human-confirmed before becoming canonical (shopper or requester approves).
- **No autonomous actions:** AI parses, matches, and suggests. Humans approve everything. (Core product principle.)

## 6. Suggested Stack (Devin-friendly, boring on purpose)

- **Frontend:** Next.js PWA (mobile-first) or Expo/React Native if team prefers native. PWA recommended for 3-phone demo speed (no app store, just URLs).
- **Backend:** Node (Express/Fastify) or FastAPI. REST + WebSocket (or Supabase Realtime) for live list/substitution updates.
- **DB:** Postgres (Supabase recommended: auth, realtime, storage for images in one box).
- **Storage:** image uploads (lists, shelves, receipts) → Supabase storage/S3.
- **Auth:** magic link or invite-code + display name (v0 minimal).

## 7. Data Model (sketch)

- `users` (id, name, circle_id, venmo_handle)
- `circles` (id, name, invite_code)
- `trips` (id, shopper_id, store, depart_at, caps{...}, status)
- `requests` (id, trip_id, requester_id, status[pending/accepted/declined])
- `items` (id, request_id, name, qty, note, max_price, status[pending/got/substituted/skipped], substitute_of)
- `parses` (id, user_id, source[text/photo/voice], raw_ref, parsed_json, confirmed)
- `receipts` (id, trip_id, image_ref, lines_json, assignments_json)
- `settlements` (id, trip_id, requester_id, amount, venmo_link, marked_paid)
- `ledger_events` (id, circle_id, user_id, type, value)

## 8. Demo Requirements (drives all scope decisions)

3 phones, ~2.5 minutes:
1. Phone A posts "Trader Joe's at 3" by voice.
2. Phone B types a list; Phone C photographs a handwritten one → both parse → attach.
3. A sees merged aisle-ordered list.
4. A snaps a (pre-staged) shelf photo → C picks substitute live.
5. A snaps receipt → B and C receive itemized splits with Venmo links.
6. Handoff photo → ledger updates.

Every beat < 20 seconds. Seeded demo data must make the circle look alive (prior trips in ledger).

## 9. Milestones (24h)

- **H0–2:** Repo scaffold, contracts frozen (API spec + JSON schemas), Supabase up, mock VisionService returning canned JSON.
- **H2–8:** Trip CRUD + request intake (text first, then photo) + merged list. Frontend screens against mocks.
- **H8–14:** Real VLM integration (photo parse, receipt split). Realtime updates. Voice intake.
- **H14–18:** Substitution flow. Settlement screens + Venmo links. Ledger.
- **H18–22:** Demo seeding, polish, failure fallbacks (canned images + cached VLM responses for every demo beat).
- **H22–24:** Full demo rehearsals on real phones. Freeze.

## 10. Success Criteria (v0)

- Full loop completes live on 3 devices with zero manual DB edits.
- All three intake formats parse correctly on demo inputs.
- Receipt split totals reconcile to the receipt.
- Every VLM-dependent demo beat has a cached fallback.

## 11. Out of Scope (v1+ backlog, do not build)

- Relationship routing, opt-in intros, readiness detection
- Karma redemption, merchant perks, milestone rewards
- Consumption forecasting, pantry vision, trip advising
- Senior voice line, translation, story/recap cards
- In-app payments, escrow, real card rails
- Multi-circle membership, discovery, onboarding polish

## 12. Open Questions

- Muse Spark API access + rate limits (confirm at Meta booth H0).
- PWA push notifications on iOS — if flaky, fall back to in-app realtime + SMS via Twilio for the demo.
- Venmo deep-link behavior on both platforms (test H2, not H20).
