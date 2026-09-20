# Favorly Linq Agent

Text the Favorly agent on iMessage (via [Linq](https://linqapp.com)) to ask for
favors or get favor recommendations. The agent understands natural language,
matches asks to open store runs with the deterministic matching engine
(SPEC_v0 §4.1-style fuzzy section assignment + trip scoring), and proactively
notifies both sides when a match happens.

## How it flows

```
you text the Linq number
        │  Linq webhook (message.received)
        ▼
POST /webhooks/linq  (backend/routes/linq_webhook.py)
        │  identify sender by phone (agent/store.py)
        │  parse intent — Claude if ANTHROPIC_API_KEY set, rules otherwise (agent/nlu.py)
        │  match via backend/matching/engine.py
        ▼
reply in the same chat + notify matched neighbors (agent/linq_client.py)
```

### What you can text it

| You say | Intent | What happens |
|---|---|---|
| "can someone grab me oat milk and 2 avocados?" | `ask_favor` | Items parsed → sections assigned → ranked against open trips. Attached to the best trip (shopper gets a text) or pooled as a pending ask. |
| "I'm going to Trader Joe's at 3" | `offer_trip` | Trip created; pending asks that fit the store/time auto-attach; each requester gets a text. |
| "what should I pick up?" | `get_recommendations` | Your run's merged list (aisle sections included) plus the best-fitting pending asks — this is the matching-algorithm output. |
| "status" | `status` | Open runs + your pending asks. |
| "call me Sam" | `set_name` | Names your number in the circle. |

### The matching score

`score = 0.5·coverage + 0.3·time_fit + 0.2·capacity`

- **coverage** — fraction of the ask's items whose store section (assigned via
  rapidfuzz `token_set_ratio ≥ 80` over `SECTION_KEYWORDS`, spec §4.1) the
  trip's store plausibly carries (CVS ≠ produce, Trader Joe's = everything)
- **time_fit** — trips departing sooner score higher (12h linear decay)
- **capacity** — room left under the trip's `max_requesters` cap

Matches require `score ≥ 0.45` (`MATCH_THRESHOLD` in `backend/matching/engine.py`).

## Setup

### 1. Env vars (`backend/.env`)

```bash
LINQ_API_KEY=...              # from dashboard.linqapp.com (sandbox signup)
ANTHROPIC_API_KEY=...         # optional — enables LLM intent parsing; rules otherwise
LINQ_USER_PHONES=+15551234567=Alice,+15559876543=Bob   # optional: map seed members to phones
```

Unknown numbers are auto-registered as "Neighbor XXXX" and can rename via
"call me ...". Without `LINQ_API_KEY`, replies print to the server console
(dry-run mode) so everything is testable locally.

### 2. Run the backend + tunnel

```bash
cd backend
.venv/bin/uvicorn app:app --port 8000
ngrok http 8000          # or any public tunnel
```

### 3. Register the webhook with Linq (once)

```bash
LINQ_API_KEY=... .venv/bin/python scripts/register_linq_webhook.py https://<your-tunnel>.ngrok.app
```

### 4. Text the Linq number

Send "can someone grab me oat milk?" to your Linq-provisioned number. Done.

## Local testing without Linq

```bash
curl -X POST localhost:8000/webhooks/linq -H 'Content-Type: application/json' -d '{
  "event_type": "message.received",
  "data": {
    "chat": {"id": "chat-1", "is_group": false},
    "direction": "inbound",
    "sender_handle": {"handle": "+15550000002", "service": "iMessage"},
    "parts": [{"type": "text", "value": "can someone grab me oat milk and eggs?"}]
  }
}'
```

The reply appears in the server log as `[linq:dry-run] ...`.

Unit tests: `.venv/bin/python -m pytest tests/test_agent_flow.py`

## Notes / next steps

- State is in-memory (`agent/store.py`), seeded from `seed/demo_circle.json` —
  swap for Supabase without touching `handlers.py`.
- No model-to-model interaction: one agent, one LLM call per inbound text
  (strict JSON schema via `output_config.format`), deterministic everything else.
- Receipt-split settlement (spec §4.5) still lives in the Flutter demo store;
  the agent hands off to the app after the run ("settle up via Venmo").
