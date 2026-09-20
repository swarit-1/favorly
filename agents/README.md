# Trellis — Grocery-Favor Graph Service

Owns the event log, the grocery-favor graph, extraction of grocery-relevant
signal, and reciprocity tracking. This is the only thing that writes to this
database — the Favorly errand-coordination backend (`/backend`) is a separate
service; the two talk over HTTP (see `backend/services/trellis_client.py`).

**Deliberately scoped to groceries.** This started from a broader spec
("Agent & Graph Service Spec.md") that included social introductions and
capability/need matchmaking between neighbors. That's been cut: extraction
now only mines grocery-relevant facts (dietary restrictions, mobility/car
access, budget, store preference), and nothing proposes that two people meet.
A person's `/profile` is informational; favors and reciprocity are the whole
mechanic.

## Run it

```bash
cd agents
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # defaults to MOCK_LLM=1 -- no API key needed

# Postgres + pgvector, e.g.:
docker run -d --name trellis-pg -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=trellis \
  -p 5432:5432 pgvector/pgvector:pg16

python app.py   # http://localhost:8010, applies schema.sql automatically
```

Then:

```bash
curl -X POST localhost:8010/admin/seed -d '{"scenario":"warm"}' -H 'Content-Type: application/json'
curl localhost:8010/graph
```

`MOCK_LLM=1` (the default) runs extraction and canonicalization adjudication
on deterministic rule-based fixtures, so the system is fully exercisable with
zero API key and zero network calls. Set `MOCK_LLM=0` and fill in
`LLM_API_KEY`/`LLM_BASE_URL` to use a real OpenAI-compatible model.

## Module map

| module | does |
| --- | --- |
| `schema.sql` | `people`, `events` (append-only), `claims` (grocery facts), `edges` (favors), `graph_metrics`, `canonical_labels` |
| `extraction.py` | span-verified structured extraction, corroboration (noisy-OR) |
| `canonicalization.py` | embed-and-snap entity resolution, grocery vocabulary |
| `edges.py` | decay, weights by kind, `give_balance` (reciprocity, never exposed) |
| `graph_metrics.py` | networkx topology for the `/graph` visualization endpoint |
| `routes/` | the API surface: `/events`, `/favors`, `/people`, `/graph`, `/admin/*`, `/stream` |
| `seed_data.py` | eight demo residents, warm/cold scenarios |

## API surface

```
POST /events                 { person_id, kind, body, source_key?, occurred_at? }
POST /favors                 { giver_id, receiver_id, description }  -- writes a favor edge
POST /people                 { display_name, phone?, id? }   -- id = backend users.id to link identities
GET  /people/:id/profile     -- grocery-relevant claims + connection count, no give_balance

POST /needs                  { person_id, body }   -- post something you need help with
GET  /needs?status=open      -- browse open needs
GET  /people/:id/recommendations?limit=10   -- ranked needs to help with, each with reasoning
POST /needs/:id/claim        { person_id }   -- one-sided: you decide to help
POST /needs/:id/fulfill      -- marks done AND writes the favor edge

GET  /graph?since=<iso>      -- nodes/edges for visualization
GET  /stream                 -- SSE: claim_extracted, edge_created, extraction_complete, need_posted, need_claimed
POST /admin/seed             { scenario: "warm" | "cold" }
POST /admin/reset
POST /admin/tick             { steps: int }  -- refreshes decay-derived topology
```

## Recommendations

`GET /people/:id/recommendations` works in two stages:

**1. The graph retrieves and scores.** SQL finds open needs from other people;
arithmetic scores each one. Bounded by design — the model sees a fixed-size
context no matter how large the graph gets.

| signal | weight | what it means |
| --- | --- | --- |
| `trip` | 0.35 | you already have a grocery trip that covers this |
| `reciprocity` | 0.25 | they've done favors for you recently |
| `mutual` | 0.15 | you share connections |
| `fit` | 0.15 | your situation complements theirs (car vs. no car) |
| `freshness` | 0.10 | tiebreaker only |

**2. The model decides.** It receives that context and chooses which favors
are worth surfacing, in what order, and how to frame each. It may reorder and
drop; it may not invent — every `need_id` is checked against the candidates it
was given, and every name and number in its text against the known facts.
Anything that fails validation falls back to the deterministic ranking, in the
identical response shape. `decided_by` tells you which path ran
(`"model"` or `"graph"`), and `signals` always shows what the graph contributed.

Response (typed in OpenAPI as `RecommendationsOut` / `FavorSuggestion`, so the
frontend can codegen against it):

```json
{
  "person_id": "...", "decided_by": "model",
  "favors": [{
    "need_id": "...",
    "title": "Grab oat milk for Bob",
    "action": "Pick up oat milk for Bob while at Trader Joe's.",
    "requested_by": { "id": "...", "display_name": "Bob" },
    "original_request": "could someone grab oat milk? I'm lactose intolerant and out",
    "reason": "Bob is out of oat milk and it's a quick stop on your trip.",
    "effort": "low", "score": 0.34,
    "signals": { "trip": 0.7, "reciprocity": 0.0, "mutual": 0.0, "fit": 0.0, "freshness": 0.98 },
    "posted": "1h ago"
  }]
}
```

Fulfilling a need writes the favor edge, which feeds `reciprocity` for the
next round — that's the loop: help someone, and later their need surfaces to
you with "they helped you before."

### On extraction and spans

The model must quote verbatim evidence for every claim, but it is **not**
trusted to report character offsets — LLMs quote reliably and count
unreliably, so correct quotes routinely arrive with wrong indices. The span is
located with `body.find(evidence)`; a quote that isn't in the message is
dropped. That keeps the grounding guarantee without depending on the model's
arithmetic.

## What's simplified vs. the original spec

- No introductions, routing/candidate-scoring, intro generation, outcome
  feedback (openness/decline attribution), or post-interaction feedback. All
  removed, not stubbed.
- The mock LLM extractor is a compact regex rule table tuned to grocery
  signal (dietary/mobility/budget/preference) plus the seed messages — not a
  real semantic extractor. Swap in a real model (`MOCK_LLM=0`) for anything
  beyond demo/dev.
