# Lane C — Frontend (Next.js PWA)

Owner: _TBD_ · Depends on: A (`openapi.json` at H2, realtime channels) · Blocks: D (device rehearsals)
Screens map 1:1 to the demo beats in PRD §8. Every beat must complete in <20s on a phone.

## Mission
One mobile-first PWA, two roles (shopper / requester), installable from a URL on three phones, driven
entirely by Lane A's API + Supabase Realtime. No business logic in the client — render what the API says.

## In scope
- `frontend/` — Next.js 14 App Router, TypeScript, Tailwind, `@supabase/supabase-js` (realtime only; auth is the bearer token from `/circles/join` stored in `localStorage`).
- Types generated from `openapi.json` with `openapi-typescript` into `frontend/src/api/types.ts` (`npm run gen:api`). No hand-written API types.
- `src/api/client.ts` — typed fetch wrapper (`openapi-fetch`), base URL `NEXT_PUBLIC_API_URL`, multipart helper for photo/audio.
- Realtime hook `useTripChannel(tripId)` / `useUserChannel(userId)` per SPEC §A realtime contract; optimistic UI not required — refetch on event.
- PWA: `app/manifest.ts`, icons, `theme-color`, standalone display, `viewport-fit=cover`. Camera via `<input type="file" accept="image/*" capture="environment">`; voice via `MediaRecorder` → `audio/webm` upload.
- Venmo deep link: try `venmo://paycharge?...` then fall back to `https://venmo.com/...` after 800ms (SPEC §4.5.7). Test on iOS + Android at H2.

## Screens (routes)

| Route | Role | Beat | Renders | Actions |
|---|---|---|---|---|
| `/join` | both | setup | invite code + display name | `POST /circles/join` |
| `/` | both | 1,3 | trip feed (`GET /trips`), "Post a trip" FAB, ledger link | tap trip → `/trips/{id}` |
| `/trips/new` | shopper | 1 | store, depart time, caps; **voice button** → transcript → prefilled fields (via `POST /parses source=voice` + `TripDraft`) | `POST /trips` |
| `/trips/{id}` | requester | 2 | trip header; "Add my list" → intake sheet; my request + item statuses | opens `/trips/{id}/request` |
| `/trips/{id}/request` | requester | 2 | 3 tabs: type / speak / photo → `POST /parses` → **review list** (rows with `needs_confirmation` highlighted, inline edit qty/name/cap) → attach | `PATCH /parses/{id}/confirm`, `POST /trips/{id}/requests` |
| `/trips/{id}/shop` | shopper | 3 | `MergedList` grouped by section, requester chip + cap + running total, accept/decline per request, per item: Got / Out of stock | `PATCH /requests/{id}`, `PATCH /items/{id}`, `PATCH /trips/{id}/status shopping` |
| `/trips/{id}/shop/sub/{itemId}` | shopper | 4 | camera → upload → "asking {name}…" spinner → live result when requester decides | `POST /items/{id}/substitution` |
| (modal) substitution chooser | requester | 4 | opens on `substitution_prompts` INSERT: 2–4 candidate cards (name, size, price, reason), Skip, countdown to `expires_at` | `PATCH /substitutions/{id}` |
| `/trips/{id}/receipt` | shopper | 5 | camera → upload → lines table; **only ambiguous/unassigned lines** get a requester picker; totals footer; Confirm | `POST /trips/{id}/receipt`, `PATCH /receipts/{id}/assignments` |
| `/trips/{id}/settle` | requester | 5 | my items, subtotal, tax share, total, **Pay with Venmo** button, Mark paid | `GET /trips/{id}/settlements`, `PATCH /settlements/{id}/paid` |
| `/trips/{id}/handoff` | shopper | 6 | optional photo, Confirm handoff | `POST /trips/{id}/handoff` |
| `/ledger` | both | 6 | `LedgerRow` list: name, trips run, favors received, $ carried | — |

Role is derived per trip: `trip.shopper_id === me.id` → shopper views; otherwise requester views. Declined requests render as "pending" to the requester (PRD §2.3).

## Out of scope
Push notifications (realtime + in-app banners only; PRD §12 fallback), onboarding polish, multi-circle, any offline mode beyond PWA shell caching, animations beyond what Tailwind gives for free.

## Milestones
- **H0–2:** app shell, `/join`, `/` feed against Lane A's `DB=memory` mocks; PWA installable on one phone; Venmo deep-link probe on iOS + Android (report result in channel).
- **H2–8:** `/trips/new` (typed), `/trips/{id}/request` text + photo intake with review list, `/trips/{id}/shop` merged list.
- **H8–14:** realtime hooks wired; voice intake + voice trip post; `/receipt` + `/settle`.
- **H14–18:** substitution camera flow + requester modal with countdown; `/handoff`; `/ledger`.
- **H18–22:** loading/error states for every VLM call (skeleton + "still thinking…" after 5s + retry), large tap targets, dark mode off, 3-phone smoke test with Lane D.

## Acceptance
- `npm run typecheck && npm run lint && npm run build` green; `npm run gen:api` produces no diff against committed types.
- Lighthouse PWA installable on iOS Safari and Android Chrome; add-to-home-screen works.
- Full demo script (PRD §8) completes on 3 phones using `VISION_PROVIDER=mock` with no page reloads and no manual DB edits.
- Every screen usable one-handed at 375×667.
