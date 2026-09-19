# Favorly UX/UI direction

This direction is based on the product requirements, engineering spec, updated architecture notes, implementation plan, lane briefs, backend contracts, seed data, and the checked-in Flutter and FastAPI source.

## Product in one sentence

Favorly lets a neighbor who is already going to a store carry a few bounded requests for people in their circle, while the app removes the coordination work around interpreting lists, handling substitutions, splitting the receipt, and recording the favor.

It is mutual-aid infrastructure, not a delivery marketplace. The product should feel like a trusted building group made calmer and more reliable by software.

## Core product principles

1. **Bound the favor.** Requester, item, and dollar caps make helping feel safe before a trip is posted.
2. **Let people communicate naturally.** Typed text, speech, and a photo of a handwritten list all lead to the same editable item structure.
3. **AI proposes; people approve.** Uncertain interpretations, substitutions, and receipt assignments are always reviewable before becoming canonical.
4. **Show exceptions, not admin.** The shopper sees one aisle-ordered list and should only have to resolve unavailable items or ambiguous receipt lines.
5. **Keep money transparent and external.** Favorly calculates what each person owes, then opens Venmo; it is not a wallet or escrow product.
6. **Record reciprocity without gamifying it.** The ledger is a history of giving and receiving, with no points, ranks, or redemption mechanics in v0.

## Product roles and state model

There should not be a permanent shopper mode and requester mode. A person is the shopper for a trip when `trip.shopper_id` matches them; otherwise they are a requester. The interface should adapt inside the trip.

The trip lifecycle is:

`OPEN` → `SHOPPING` → `SETTLING` → `DONE`

- **Open:** neighbors can attach requests; the shopper can accept what fits.
- **Shopping:** the merged aisle list becomes the primary workspace; substitutions happen in real time.
- **Settling:** the shopper scans and confirms the receipt split; requesters see their totals.
- **Done:** handoff is confirmed and the reciprocity ledger is updated.

## Recommended information architecture

Use three persistent destinations:

- **Trips:** active and upcoming trips, plus the action to post one.
- **Circle:** members and the reciprocity ledger.
- **You:** profile, payment handle, notification preferences, and app settings.

Avoid global `Request` and `Shop` tabs. Both actions require a trip context, and putting them in the main navigation creates empty or ambiguous states. The checked-in Flutter shell currently has `Trips`, `Request`, `Shop`, and `Ledger`; the mockups intentionally revise this to `Trips`, `Circle`, and `You`.

## End-to-end UX flow

### 1. Post a trip

The trip feed answers three questions at a glance: where, when, and whether there is room. `Post a trip` opens a short form for store, departure time, and caps. Voice can prefill the form, but it remains an optional accelerator rather than the primary interaction.

Success criteria:

- A trip can be posted in roughly 15 seconds.
- Caps read as reassurance, not policy language.
- The voice transcript is visible before posting.

### 2. Attach a request

On the trip detail, `Add my list` opens three equal input methods: type, speak, or photograph. Every method leads to the same review screen. Only uncertain rows are highlighted, and the requester can edit name, quantity, note, and cap before attaching.

Success criteria:

- The interface never implies that AI output is final.
- Uncertainty is expressed as a specific, actionable `Check this`, not a confidence percentage.
- The attached state tells the requester what happens next.

### 3. Shop the merged list

The shopper gets one list grouped in store-section order. Each item retains a requester chip, cap, and any note. `Got it` and `Unavailable` are the dominant row actions. Requests from different people remain separate even when adjacent.

Success criteria:

- The shopper can scan and act with one thumb.
- Requester identity and caps never disappear.
- Progress is visible without turning shopping into a task-management dashboard.

### 4. Resolve a substitution

`Unavailable` opens a shelf camera with the original item, requester, and cap fixed in the header. After the shelf is scanned, the requester receives up to three ranked choices, a short reason, a countdown, and a clear skip option. The shopper's list updates through realtime after the choice.

Success criteria:

- Both sides know who is waiting on whom.
- The requester can decide in one tap plus confirmation.
- Timeout behavior is clear and defaults to skipping, as defined by the spec.

### 5. Split the receipt

The shopper sees the reconciled subtotal, tax, and total first. Correct matches are collapsed; only ambiguous or unassigned lines require attention. Confirming generates a settlement per requester.

Success criteria:

- Receipt totals visibly reconcile before confirmation.
- The shopper reviews exceptions rather than an entire table.
- A requester sees items, subtotal, proportional tax, total, and an external Venmo action.

### 6. Confirm handoff and update the ledger

After handoff, the trip becomes done and the circle ledger updates. The ledger uses plain-language counts and carried value, with explicit copy explaining that there are no scores or rankings.

## Visual direction

- **Personality:** neighborly, calm, capable, and transparent.
- **Primary:** deep evergreen `#214E3B` for trust and action.
- **Accent:** soft apricot `#F2A56B` for posting and attention.
- **Surfaces:** warm off-white `#FAF7F0`, with pale sage success and pale amber review states.
- **Typography:** friendly geometric sans serif with large titles and compact, readable metadata.
- **Components:** generous 48px+ touch targets, restrained cards, requester chips, inline status, and sticky primary actions.
- **Avoid:** marketplace imagery, delivery tracking maps, gig-worker language, competitive scores, technical AI terminology, glassmorphism, and finance-app styling.

## Architecture the UX depends on

The intended architecture is:

1. A Flutter iOS/Android client handles auth, capture, review, trip workflows, and realtime UI.
2. FastAPI exposes the domain API and keeps canonical state transitions and matching logic off the client.
3. Supabase provides PostgreSQL, authentication, image/audio storage, and realtime table subscriptions.
4. An in-process `VisionService` abstracts list parsing, shelf recognition, and receipt extraction.
5. Vision calls use a primary provider, an OpenAI-compatible fallback, and staged cached responses for demo resilience.
6. Pydantic models define API and vision-output contracts. Deterministic code handles store sections, cap flags, substitution ranking, receipt matching, tax allocation, and ledger updates.

Realtime is especially important at two points: a substitution prompt appearing on the requester's device, and settlements appearing after receipt confirmation.

## Current repository reality

The documents describe the intended product more completely than the checked-in implementation:

- `favorly_mobile/lib/main.dart` is a four-tab placeholder shell with no feature screens.
- `favorly_mobile/pubspec.yaml` does not yet include Supabase, routing, camera, audio, or networking dependencies.
- `backend/app.py` connects to Supabase but all domain routes are stubs.
- The backend Pydantic contracts exist and cover the major entities and three AI surfaces.
- `backend/.env.example` and `backend/seed/seed_demo.py` still reference MongoDB/Firebase even though the current architecture calls for Supabase.
- The older Lane C brief still describes a Next.js PWA, while the newer architecture and current source tree target Flutter.

Before building screens, treat Flutter + FastAPI + Supabase as authoritative, replace the remaining MongoDB/Firebase artifacts, and freeze typed request/response models for the routes rather than leaving route bodies as generic dictionaries.

## Mockup set

1. [Trip feed and posting](mockups/01-trip-feed-and-posting.png) — trip discovery, bounded trip creation, and voice-prefilled confirmation.
2. [Request intake and review](mockups/02-request-intake-and-review.png) — multimodal input, human review of an uncertain item, and attached status.
3. [Shopping and substitution](mockups/03-shopping-and-substitution.png) — aisle-ordered merged list, shelf capture, and realtime requester choice.
4. [Receipt, settlement, and ledger](mockups/04-receipt-settlement-and-ledger.png) — exception-only receipt review, itemized amount owed, and noncompetitive reciprocity history.

These are directional high-fidelity concepts, not pixel-perfect implementation specs. Exact spacing and platform chrome should be normalized in Flutter, while the hierarchy, state transitions, and interaction model should remain.
