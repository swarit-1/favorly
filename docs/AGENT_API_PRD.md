# Favor Recommendations — Agent Service PRD

**Audience:** the frontend agent/engineer building the Favorly app UI.
**Service:** `/agents` (Trellis), default `http://localhost:8010`.
**Status:** implemented and running. Every response shape below is live and
typed in the service's OpenAPI schema at `/openapi.json` (browsable at `/docs`).

---

## 0. Running it

```bash
cp .env.example .env          # at the REPO ROOT; python-dotenv walks up to find it
cd agents
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python app.py                 # :8010, applies schema.sql on startup
```

Needs Postgres with pgvector. Locally:
```bash
docker run -d --name trellis-pg -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=trellis \
  -p 5432:5432 pgvector/pgvector:pg16
```

`MOCK_LLM=1` (the `.env.example` default) runs extraction and recommendation
on deterministic rules with **zero API calls** — the service is fully
exercisable without a key. Set `MOCK_LLM=0` plus `LLM_API_KEY` for real
OpenAI. After switching, run `POST /admin/reextract`: mock embeddings aren't
comparable to real ones, so existing claims must be rebuilt from the event log.

`backend/` keeps its own `.env` (it needs `PORT=8000` where this needs 8010).

## 1. What this service does

It answers one product question: **"which favors should I do, and why?"**

A neighbor posts something they need help with. The service decides which of
those open needs to surface to each other neighbor, ranked, each with a
one-sentence reason grounded in real history — *"Bob picked up groceries for
you 2 times recently"*, not *"you might like this"*.

Scope is grocery runs only. It does not do social introductions, general
handyman favors, or matchmaking between people.

## 2. The algorithm

Two stages. This split matters for the UI, because the response tells you
which stage produced the result.

### Stage 1 — the graph retrieves and scores (deterministic)

SQL pulls every open need posted by someone *other* than the viewer, then
scores each on five signals. All arithmetic, no model involved.

| signal | weight | fires when |
| --- | --- | --- |
| `trip` | 0.35 | the viewer has an open/shopping trip in `trips`. 1.0 if the need names that store, else 0.7 |
| `reciprocity` | 0.25 | the requester has done favors *for the viewer* recently (decayed, 30-day e-folding) |
| `mutual` | 0.15 | they share favor-graph connections. 0.5 for one mutual, 1.0 for two or more |
| `fit` | 0.15 | viewer's situation complements theirs. 1.0 = viewer has a car and they don't; 0.4 = viewer has a car |
| `freshness` | 0.10 | recency of the post, 48-hour half-life. Tiebreaker only — never produces a reason |

`score = Σ(weight × signal)`, descending. Favor edges decay exponentially, so
a favor from last week counts far more than one from three months ago.

### Stage 2 — the model decides (LLM)

The scored candidates plus the viewer's profile are handed to the model as
bounded context (fixed size regardless of graph size — it never scans raw
history). The model chooses which favors are worth surfacing, orders them,
and writes `title` / `action` / `reason` / `effort`.

**It may** reorder and drop candidates.
**It may not** invent. Enforced, not requested:

- every returned `need_id` must be one that was passed in, or it's dropped
- every proper noun and number in its text must trace to the known facts, or
  it's dropped
- facts are handed over pre-phrased and directional ("Bob picked up groceries
  for you twice recently"), because a bare count invites the model to invert
  who helped whom

If the model is unavailable, errors, or fails validation, the service returns
a deterministic ranking **in the identical response shape**. The contract
never changes; only `decided_by` does.

## 3. What the frontend calls

### Get recommendations

```
GET /people/{person_id}/recommendations?limit=10
```

```json
{
  "person_id": "61f48091-…",
  "decided_by": "model",
  "favors": [
    {
      "need_id": "460db4e4-…",
      "title": "Grab oat milk for Bob",
      "action": "Pick up oat milk at Trader Joe's.",
      "requested_by": { "id": "a6c03105-…", "display_name": "Bob (Requester 1)" },
      "original_request": "could someone grab oat milk? I'm lactose intolerant and out",
      "reason": "Bob picked up groceries for you 2 times recently and you're already going to Trader Joe's today.",
      "effort": "low",
      "score": 0.6526,
      "signals": { "trip": 0.7, "reciprocity": 1.0, "mutual": 0.0, "fit": 0.4, "freshness": 0.97 },
      "posted": "1h ago"
    }
  ]
}
```

**Field guide for rendering a card:**

| field | use |
| --- | --- |
| `title` | card header. Short, imperative, already includes the item and first name |
| `action` | subtitle — what they'd actually do |
| `reason` | the "why you" line. This is the differentiated part; don't bury it |
| `requested_by.display_name` | who it's for (avatar, name) |
| `original_request` | the verbatim ask. Show on expand — it's the ground truth behind `title` |
| `effort` | `low` / `medium` / `high`. `low` means it's on a trip they're already making |
| `posted` | pre-formatted relative time ("1h ago") — no date math needed |
| `need_id` | pass to the claim endpoint |
| `score`, `signals` | ordering is already applied; surface only for debug/explainability |
| `decided_by` | `"model"` or `"graph"`. Useful in dev; not meant for end users |

`favors` may be empty — render an empty state, not an error.

### Post a need

```
POST /needs          { "person_id": "...", "body": "free text" }
→ 201 { "id": "...", "status": "open", "created_at": "..." }
```

Free text, no structured item entry. The service extracts grocery-relevant
facts from it automatically.

### Browse and act

```
GET  /needs?status=open              → { "needs": [ … ] }
POST /needs/{id}/claim  { person_id } → 200, status "claimed"
POST /needs/{id}/fulfill              → 200, writes the favor edge
```

One-sided flow: whoever decides to help claims it. No mutual approval step.
Guards return 409 (already claimed/fulfilled) and 422 (claiming your own
need) — surface both as inline messages.

**`fulfill` is what closes the loop.** It writes the favor edge, which is what
makes the *next* recommendation to the person who was helped say "they helped
you before." Don't skip it.

### Supporting reads

```
GET /people/{id}/profile   → { display_name, claims[], connection_count }
GET /graph?since=<iso>     → { nodes[], edges[] } for a network view
GET /stream                → SSE: need_posted, need_claimed, claim_extracted,
                             edge_created, extraction_complete
```

`/stream` lets the feed update live instead of polling.

## 4. Errors

| status | meaning | UI |
| --- | --- | --- |
| 404 | person or need not found | not-found state |
| 409 | need already claimed/fulfilled | "someone already grabbed this", refresh |
| 422 | malformed id, or claiming your own need | inline validation message |
| 503 | replay failed (admin only) | n/a |

A malformed UUID returns 422 with the reason, never a 500.

## 5. Deliberate non-goals

- **No karma score, no ledger shown to users.** `give_balance` (favors given
  minus received) is computed and used internally, but is never returned by
  any endpoint. Don't build UI for it — the moment it's visible it becomes a
  scoreboard and changes why people help.
- **No reputation or ratings.** There's no way to rate a neighbor.
- **No introductions.** This doesn't suggest that two people meet.
- **Reasons never imply debt.** No "you owe them", no "pay it back".

## 6. Test data

```
POST /admin/demo-history
```
Additive — builds neighbors, claims, a dense favor web, and open needs so all
five signals fire. Safe against a shared database; truncates nothing.

`POST /admin/seed { "scenario": "warm" }` also exists but **wipes first** —
don't run it against a shared database.

## 7. Known gaps

- Reason quality depends on data density. With no shared history the model
  falls back to weaker reasons ("posted 2h ago, no one's offered yet").
- `fit` currently only reasons about car access; dietary/budget/preference
  claims are extracted and shown on profiles but don't affect ranking.
- Needs have no expiry — stale ones stay open until claimed.
- No auth. `person_id` is trusted from the caller.
