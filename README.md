# Favorly

**A neighbor posts "I'm going shopping at 3." Neighbors attach requests. One trip carries the whole building.**

Favorly turns one person's grocery run into the building's grocery run. Ask for a favor by texting an agent on iMessage, or through the mobile app; a matching algorithm attaches your ask to a neighbor's open trip, the shopper gets one merged aisle-ordered list, and everyone settles up from the receipt via Venmo. Underneath, a favor graph tracks who helps whom, so recommendations come with real reasons — *"Bob picked up groceries for you twice recently"* — not *"you might like this"*.

Built at HackMIT 2026.

---

## The three surfaces

| Surface | What it does |
|---|---|
| **iMessage agent** (via [Linq](https://linqapp.com)) | Text the Favorly number in plain English: ask favors, offer runs, get recommendations. No app install needed — anyone who texts is auto-registered into the circle. |
| **Mobile app** (Flutter) | The full errand loop: post trips, attach requests, live merged shopping list, substitution prompts, receipt split, Venmo settle-up, circle ledger. |
| **Trellis** (agent + graph service) | Answers *"which favors should I do, and why?"* — a favor graph with reciprocity tracking, claim extraction from free text, and grounded one-sentence reasons. |

## How a favor flows

```
 "can someone grab me            "I'm going to
  gluten free bread?"             Trader Joe's at 5"
        │ iMessage                      │ iMessage
        ▼                               ▼
  ┌──────────────────────────────────────────────┐
  │  Linq webhook  →  intent parsing (Claude or   │   FastAPI backend
  │  rule-based)   →  logistics matcher           │   (backend/)
  └──────┬───────────────────────────┬───────────┘
         │ mirror asks/trips/claims  │ replies + match
         ▼                           ▼ notifications (iMessage)
  ┌──────────────────┐        ┌──────────────┐
  │  Trellis graph    │        │  Flutter app │  trips, merged list,
  │  (agents/)        │        │  (Supabase)  │  receipt split, ledger
  │  needs · claims · │        └──────────────┘
  │  favor edges ·    │
  │  recommendations  │
  └──────────────────┘
```

Texting the agent feeds the graph: every ask becomes a Trellis *need*, every offered run becomes a *trip*, every match becomes a *claim* — so the recommendation engine keeps getting smarter about your circle.

## The matching algorithms

**Layer 1 — logistics (instant, deterministic).** When an ask arrives, `backend/matching/engine.py` scores it against every open trip:

`score = 0.5·coverage + 0.3·time_fit + 0.2·capacity`

Items are assigned store sections by fuzzy keyword match (rapidfuzz `token_set_ratio ≥ 80`, per `docs/SPEC_v0.md` §4.1); *coverage* checks the trip's store plausibly carries them (CVS ≠ produce), *time_fit* favors runs leaving soon, *capacity* respects the trip's requester cap. Matches at ≥ 0.45 auto-attach and text both sides.

**Layer 2 — person-aware ranking (Trellis).** For *"what should I pick up?"*, `agents/recommendations.py` ranks open needs on six weighted signals:

| signal | weight | fires when |
|---|---|---|
| `trip` | 0.30 | you already have an open run (1.0 if the need names your store) |
| `reciprocity` | 0.25 | the requester has done favors *for you* recently (30-day decay) |
| `mutual` | 0.15 | you share favor-graph connections |
| `fit` | 0.15 | your situation complements theirs (you have a car, they can't carry bags) |
| `affinity` | 0.10 | you share the datapoints the ask depends on — a gluten-free helper buys the right bread for a gluten-free ask on the first try |
| `freshness` | 0.05 | recency tiebreaker only |

Claims (dietary, mobility, budget, store preference) are extracted from raw message text with span-verified LLM extraction (`MOCK_LLM=1` runs it fully offline). Reasons are assembled only from signals that actually fired and validated so the model can never invent a name or number about a neighbor.

## Tech stack

| Component | Tech |
|---|---|
| Backend API | **FastAPI** (Python 3.14) · **Supabase** (Postgres + Auth) · asyncpg · Pydantic v2 contracts |
| iMessage agent | **Linq partner API** (iMessage/RCS/SMS + webhooks) · **Claude** (`claude-opus-4-8`) structured-output intent parsing with a deterministic rule fallback · httpx |
| Matching | rapidfuzz fuzzy section assignment · pure-Python scoring (no model in the loop) |
| Trellis graph service | **FastAPI** · **Postgres + pgvector** (Docker) · networkx graph metrics · OpenAI-compatible LLM + embeddings (fully mockable) · scikit-learn weight learning · SSE live stream |
| Mobile app | **Flutter** (iOS / Android / web) · Riverpod state · Supabase client |
| Dev/deploy | Docker (pgvector) · cloudflared tunnel for webhook delivery · pytest |

## Repository layout

```
backend/           FastAPI backend: auth, trips, requests, merged list (Supabase)
  agent/           iMessage agent: NLU, conversation handlers, Linq client, in-memory store
  matching/        deterministic ask↔trip matching engine (spec §4.1)
  routes/          API routes incl. /webhooks/linq
  services/        trellis_client.py — mirrors SMS activity into the graph
  shared/contracts publicly typed Pydantic models (Trip, Request, Item, ReceiptSplit…)
agents/            Trellis: event log, claims, favor edges, needs, recommendations
favorly_mobile/    Flutter app (see its README for run instructions)
docs/              SPEC_v0.md · AGENT_API_PRD.md · LINQ_AGENT.md · UX/style guides
PRD.md             product requirements
```

## Quick start

Prereqs: Python 3.11+, Docker, Flutter 3.13+ (app only).

**1. Trellis (graph + recommendations), port 8010**

```bash
docker run -d --name favorly-trellis-pg -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=trellis -p 5434:5432 pgvector/pgvector:pg16
cd agents
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
cp .env.example .env   # set DATABASE_URL port to 5434; MOCK_LLM=1 needs no API key
.venv/bin/python app.py                      # applies schema.sql automatically
curl -X POST localhost:8010/admin/seed -d '{"scenario":"warm"}' -H 'Content-Type: application/json'
```

**2. Backend API, port 8000**

```bash
cd backend
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
# .env needs SUPABASE_URL / SUPABASE_KEY / SUPABASE_SERVICE_ROLE_KEY (see SETUP_SUPABASE.md)
.venv/bin/uvicorn app:app --port 8000
```

**3. iMessage agent (optional — works in console dry-run without keys)**

```bash
# in backend/.env:
#   LINQ_API_KEY=...        from dashboard.linqapp.com (sandbox signup)
#   ANTHROPIC_API_KEY=...   optional: LLM intent parsing (rules otherwise)
cloudflared tunnel --url http://localhost:8000        # or ngrok
.venv/bin/python scripts/register_linq_webhook.py https://<your-tunnel-url>
# → text your Linq number: "can someone grab me oat milk?"
```

Sandbox notes: Linq can only message numbers that have texted the agent at least once (inbound-first), 30 msgs/60s per pair, 100/day. Full walkthrough: `docs/LINQ_AGENT.md`.

**4. Flutter app**

```bash
cd favorly_mobile
flutter pub get && flutter run   # iOS simulator, Android emulator, or chrome
```

## Testing

```bash
cd backend && .venv/bin/python -m pytest tests/          # contracts + agent flow
```

The agent tests exercise the full text→parse→match→reply loop offline (no Linq, no LLM). Trellis runs fully offline with `MOCK_LLM=1`.

## Documentation index

- **`PRD.md`** — product requirements
- **`docs/SPEC_v0.md`** — data model, matching algorithms (§4), pipeline flows
- **`docs/AGENT_API_PRD.md`** — Trellis recommendation API contract (for the frontend)
- **`docs/LINQ_AGENT.md`** — iMessage agent setup + conversation reference
- **`START_HERE.md` / `SETUP_SUPABASE.md` / `QUICKSTART_FULL.md`** — environment setup walkthroughs
- **`docs/UX_UI_DIRECTION.md` / `docs/STYLE_GUIDE.md`** — design system (mobile)
