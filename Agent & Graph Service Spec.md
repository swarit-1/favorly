# Trellis — Agent & Graph Service Spec

2026-09-19 · @Someone

Backend spec for the agent + graph layer. Frontend and SMS are separate services; contracts are in §11.

## 1. Scope

**This service owns:** the event log, the graph, extraction, routing, intro generation, and outcome tracking. It is the only thing that writes to the database.

**It does not own:** rendering, auth, session handling, SMS delivery, or webhook receipt. Those are the frontend and texting side.

**The boundary:** the texting service receives an inbound SMS and POSTs it to `/events`. It does not interpret it. Later, this service decides an intro should happen and POSTs to the texting service. Everything that looks like judgment happens here; everything that looks like plumbing happens there.

The graph's one-sentence job: **hold enough structured, sourced memory that the agent can answer "who should meet whom, why, and is now a good time" without reading raw message history at inference time.**

That last clause is the real design constraint. If the agent has to scan everyone's messages to make a decision, you have an O(n) prompt and a system that gets slower and dumber as the neighborhood grows. The graph exists so retrieval is a bounded query, not a scan.

## 2. Core design decision

**The event log is the source of truth. The graph is a projection you can throw away and rebuild.**

Everything that enters the system lands in an append-only `events` table first: raw text, sender, timestamp, channel. Nothing is ever edited or deleted there. The graph — people, claims, edges, weights — is derived from that log by running extraction over it.

This matters for three reasons, and the third is the one that saves your demo.

1. **Provenance is free.** Every claim in the graph points back to the event that produced it, with a character span. When the agent says "Maya rebuilt her balcony," you can click through to the exact message. That is your defense against hallucinated intros, and it's a striking thing to show a judge.
2. **Extraction is not a one-shot decision.** Your prompts will be wrong at 2am. When you fix them, you replay the log and get a new graph. You are never stuck with early bad extractions baked into state.
3. **Your demo becomes deterministic.** Seed a fixed event log, replay it, get the same graph every time. You can rebuild the entire neighborhood in seconds between demo runs instead of praying your live state survived.

### Storage: Postgres, not Neo4j

Use **Postgres + pgvector**, plus **networkx in-process** for graph metrics. Do not reach for Neo4j.

The instinct is that a graph problem needs a graph database. At your scale it doesn't. You'll have somewhere between 50 and 500 nodes. That entire graph fits in memory with room to spare — you can load it into networkx in under 50ms and run betweenness centrality, clustering coefficients, and triangle enumeration with library calls you don't have to write.

What Postgres gives you that Neo4j doesn't: pgvector for semantic matching in the same query as your relational filters, one database instead of two, a schema your teammates can read, and no time lost to Cypher at 3am. Neo4j earns its complexity at millions of edges and deep traversals. You have neither.

The split in practice:

- **Postgres** stores everything and answers "who, what, when, how confident, similar to what."
- **networkx** answers "what shape is this network" — centrality, components, triangles. Load, compute, cache for 60 seconds, discard.

If you want to say something sharper than "we used Postgres" on stage: *the graph is small enough to hold in memory, so we treat topology as a pure function of the event log and recompute it rather than maintaining it.* That is a real architectural position, and it's the correct one at this scale.

## 3. Data model

Six tables. Resist adding a seventh until something breaks.

```sql
CREATE EXTENSION IF NOT EXISTS vector;

-- People. Thin on purpose: almost everything about a person
-- is a claim, not a column.
CREATE TABLE people (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  display_name  TEXT NOT NULL,
  phone         TEXT UNIQUE,
  joined_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- comfort/openness, 0..1, learned from behavior (see §10)
  openness      REAL NOT NULL DEFAULT 0.5,
  -- pause intros without deleting the person
  paused_until  TIMESTAMPTZ
);

-- Append-only. Never UPDATE, never DELETE.
CREATE TABLE events (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id   UUID NOT NULL REFERENCES people(id),
  kind        TEXT NOT NULL,   -- message | favor_logged | intro_reply | system
  body        TEXT NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- dedup key from the texting layer; makes /events idempotent
  source_key  TEXT UNIQUE
);
CREATE INDEX ON events (person_id, occurred_at DESC);

-- Everything the model believes about a person.
-- One table for capabilities, needs, and affinities --
-- they differ by `kind`, not by shape.
CREATE TABLE claims (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id   UUID NOT NULL REFERENCES people(id),
  kind        TEXT NOT NULL,   -- capability | need | affinity | constraint
  canonical   TEXT NOT NULL,   -- normalized label, see §5
  raw_label   TEXT NOT NULL,   -- what the model actually said
  confidence  REAL NOT NULL,
  embedding   VECTOR(1536),
  -- provenance: the event and the exact span that produced it
  event_id    UUID NOT NULL REFERENCES events(id),
  span_start  INT,
  span_end    INT,
  -- corroboration: bumped when a second event supports it (§4)
  observations INT NOT NULL DEFAULT 1,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  superseded_by UUID REFERENCES claims(id)
);
CREATE INDEX ON claims (person_id, kind) WHERE superseded_by IS NULL;
CREATE INDEX ON claims USING ivfflat (embedding vector_cosine_ops);

-- Relationships. Directed rows; read them as undirected
-- unless the kind says otherwise.
CREATE TABLE edges (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  src_id      UUID NOT NULL REFERENCES people(id),
  dst_id      UUID NOT NULL REFERENCES people(id),
  kind        TEXT NOT NULL,   -- favor | intro_accepted | co_occurrence | affinity
  weight      REAL NOT NULL DEFAULT 1.0,
  event_id    UUID REFERENCES events(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (src_id, dst_id, kind, event_id)
);
CREATE INDEX ON edges (src_id);
CREATE INDEX ON edges (dst_id);

-- Every intro the router proposed, accepted or not.
-- This is your training signal and your demo narration.
CREATE TABLE intros (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  a_id          UUID NOT NULL REFERENCES people(id),
  b_id          UUID NOT NULL REFERENCES people(id),
  bridge_id     UUID REFERENCES people(id),  -- the shared contact, if any
  reason_text   TEXT NOT NULL,   -- what the human was shown
  -- claim ids the reason is grounded in; validator enforces (§9)
  grounded_in   UUID[] NOT NULL,
  score         REAL NOT NULL,
  score_parts   JSONB NOT NULL,  -- {affinity, bridge, load, timing}
  status        TEXT NOT NULL DEFAULT 'proposed',
                -- proposed | sent | accepted | declined | expired | met
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at   TIMESTAMPTZ
);
CREATE INDEX ON intros (a_id, b_id);

-- Cached topology so you aren't recomputing per request.
CREATE TABLE graph_metrics (
  person_id     UUID PRIMARY KEY REFERENCES people(id),
  degree        INT NOT NULL,
  betweenness   REAL NOT NULL,
  clustering    REAL NOT NULL,
  -- favors given minus received, decayed. Internal only.
  give_balance  REAL NOT NULL DEFAULT 0,
  computed_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### Three decisions worth defending

**`claims` is one table, not three.** Capabilities, needs, and affinities have identical structure — a label, a confidence, an embedding, a source. Splitting them into separate tables means writing the same query three times and joining them back together for every retrieval. Keep `kind` as a column.

**Claims are superseded, never updated.** When someone's situation changes, write a new claim and set `superseded_by` on the old one. You keep the history, and "what did the graph believe last Tuesday" stays answerable. Cheap now, painful to retrofit.

**`give_balance` lives in `graph_metrics`, not on `people`.** It is a derived routing signal, not a fact about a person. Putting it in the metrics table is a structural reminder that it is never rendered, never returned by the API, and never shown to a user. The moment it leaks into the UI you have built a karma score, and the product dies.

## 4. Write path: extraction

One event in, zero or more claims out. This runs async — the POST to `/events` returns as soon as the row is written, and extraction happens on a worker. Never make the texting service wait on a model call.

### The pipeline

```
event row written
  → extract claims (structured output call)
  → drop anything below confidence floor
  → canonicalize labels (§5)
  → embed
  → corroborate against existing claims
  → write claims + update edges
  → enqueue routing check for this person
```

### The extraction call

Force structured output. Ask for a JSON array where every element carries its own evidence:

```json
[
  {
    "kind": "capability",
    "label": "bicycle repair",
    "confidence": 0.7,
    "evidence": "finally got the derailleur working",
    "span": [14, 48]
  }
]
```

Four rules in the prompt that matter more than the rest:

1. **Every claim must quote a span from the input.** Not a paraphrase — the literal substring. Then verify it: if `event.body[span_start:span_end]` doesn't match the quoted evidence, discard the claim. This single check kills most hallucinated capabilities before they enter the graph, and it costs you four lines of Python.
2. **Return an empty array freely.** Most messages contain nothing. Models will invent a claim rather than return nothing, so say explicitly that empty is the common and correct answer.
3. **Confidence is about the inference, not the writing.** "I fixed my derailleur" is high confidence for bike repair. "My roommate's bike is broken" is low confidence — someone mentioned a bike, that's all.
4. **Distinguish doing from wanting.** "I fixed my bike" is a capability. "I need to fix my bike" is a need. Same noun, opposite routing consequence, and models blur them constantly if you don't force the distinction.

### The corroboration rule

This is the mechanism that keeps the graph honest.

A new claim is checked against that person's existing claims by embedding similarity. Above 0.85 cosine, treat it as the same claim: increment `observations` and raise confidence toward 1.0 rather than writing a duplicate row.

```python
new_conf = 1 - (1 - old_conf) * (1 - incoming_conf)
```

Noisy-OR. Two independent 0.6 observations produce 0.84 — more than either alone, never above 1.

The important half: **single-observation claims below 0.6 confidence are not eligible for routing.** They sit in the graph, visible for debugging, but the router can't build an intro on them. A capability earns its way into a real introduction by being mentioned twice, or once with high confidence.

This is what stops the failure mode where someone says "ugh, plumbing" once and gets asked to fix a stranger's sink.

## 5. Entity resolution

This is the bug that will quietly ruin your demo if you skip it.

The model will extract `bike repair`, `fixing bikes`, `bicycle maintenance`, `derailleur adjustment`, and `cycling repair` from five messages that all mean the same thing. String-match them and you have five disconnected capabilities and zero matches. Your graph looks populated and finds nothing.

### The fix: embed-and-snap, with a growing vocabulary

Seed a small canonical vocabulary — 40 to 60 labels covering the categories you expect (`bike_repair`, `childcare`, `tutoring_math`, `moving_help`, `gardening`, `pet_care`, `cooking`, `tools_power`, `tools_hand`, `rides`, `tech_support`, `home_repair`). Embed each once at startup.

For every incoming label:

```python
sim, match = nearest_canonical(embed(raw_label))
if sim > 0.82:
    canonical = match              # snap to existing
elif sim > 0.70:
    canonical = llm_adjudicate(raw_label, top_3_candidates)
else:
    canonical = mint_new(raw_label)  # genuinely new concept
```

The middle band is where the model earns its place. `derailleur adjustment` vs `bike_repair` sits around 0.75 — too far to snap blindly, too close to mint a new category. A one-line model call with the top three candidates resolves it correctly, and it only fires on ambiguous cases, so it's cheap.

Keep both labels. `canonical` is what the router matches on; `raw_label` is what the intro text uses, because *"Maya adjusts derailleurs"* is a far better sentence than *"Maya has capability bike\_repair."* The specificity is what makes an intro feel written by someone who was paying attention.

### Semantic matching still matters on top of this

Canonicalization handles "the same thing said differently." It does not handle "different things that belong together."

A crib and a stroller canonicalize to different labels, correctly. But the people buying them are both new parents, and the affinity embedding is what catches that. So: match on `canonical` for capability-to-need routing (someone needs a drill, someone has a drill — that should be exact), and match on `embedding` cosine for affinity routing (life stage, interests, circumstance).

Two different matching modes for two different kinds of connection. Say this out loud in the demo; it's the difference between a lookup table and a system that understands people.

## 6. Edge weights, decay, and balance

### Edges are append-only too

Don't update a weight when two people interact again — insert another edge row. The effective strength of a relationship is the decayed sum of its rows:

```sql
SELECT src_id, dst_id,
       SUM(weight * EXP(-EXTRACT(EPOCH FROM (now() - created_at)) / 2592000.0)) AS strength
FROM edges
GROUP BY src_id, dst_id;
```

That's a 30-day e-folding time. A favor from last week counts nearly full; one from three months ago counts about a third. This is how a relationship that stopped being maintained fades out of the routing without anyone deleting anything, which is what actually happens to human relationships.

For the demo you'll want a much shorter constant — a few minutes — so decay is visible on stage. Make it an env var.

### Weights by kind

| kind | weight | meaning |
| --- | --- | --- |
| `favor` | 1.0 | someone actually did something |
| `intro_accepted` | 0.6 | they agreed to meet |
| `met` | 0.9 | confirmed it happened |
| `co_occurrence` | 0.3 | same thread or event |
| `affinity` | 0.2 | inferred similarity, no contact yet |

The gap between `affinity` and `favor` is the point. Inferred similarity is a weak signal that should nudge routing; a real favor is strong evidence of a real tie. If you weight them equally, the router starts treating "these two people are alike" as if it were "these two people know each other," and every intro it makes will be between strangers who have nothing but a vector in common.

### Reciprocity balance

```python
give_balance = Σ(decayed favors given) − Σ(decayed favors received)
```

Used in exactly two places:

1. **Routing.** High positive balance means this person has been carrying the group — route asks away from them, and route *opportunities to receive* toward them.
2. **Burnout detection.** High balance plus rising response latency plus shortening messages is the churn signature. Flag it, stop sending asks, and surface an offer that benefits them instead.

It is never returned by the API, never rendered, never mentioned in an intro. If a teammate asks to display it, the answer is no — see §3.

## 7. Read path: context assembly

The agent never sees raw message history. It sees an assembled context object built from bounded queries — the same budget whether the neighborhood has 50 people or 5,000.

### `build_intro_context(a_id, b_id, bridge_id) -> dict`

| slice | query | cap |
| --- | --- | --- |
| A's profile | top claims by `confidence × observations`, `superseded_by IS NULL` | 8 |
| B's profile | same | 8 |
| Overlap | claims of A and B within 0.8 cosine of each other | 5 |
| Bridge context | the favor events connecting bridge→A and bridge→B | 2 |
| Recent signal | A's and B's last event timestamps and lengths | — |
| History | prior intros between A and B, any status | all |
| Constraints | `paused_until`, `openness`, declines in last 14 days | — |
|  |  |  |

That's roughly 800 tokens. Fixed. The queries are all indexed lookups on `person_id`, so cost doesn't move with graph size.

### The overlap slice is the valuable one

Everything else is background. The overlap — the specific pair of claims that make these two people worth introducing — is what the intro sentence gets built from, and it's the only slice where you should spend real query effort.

```sql
SELECT a.id, a.raw_label, b.id, b.raw_label,
       1 - (a.embedding <=> b.embedding) AS sim
FROM claims a
JOIN claims b ON b.person_id = $2
WHERE a.person_id = $1
  AND a.superseded_by IS NULL AND b.superseded_by IS NULL
  AND a.confidence >= 0.6 AND b.confidence >= 0.6
  AND 1 - (a.embedding <=> b.embedding) > 0.7
ORDER BY sim DESC
LIMIT 5;
```

Note the confidence floor from §4 applied on both sides. Weakly-held beliefs can inform the score but can never be the thing you say out loud to a human.

### Pass claim IDs, not just text

Every claim in the context object carries its `id`. The generation call must cite the ids it used, and the validator in §9 checks them. If you pass bare strings, the model can write a lovely sentence about something nobody said and you have no way to catch it.

## 8. Triangle selection

This is the part that is deliberately **not** AI, and saying so clearly is what makes the AI claims elsewhere credible.

### Candidate generation

After any write, enqueue a routing check for the affected person. Candidates come from three sources:

**Open triangles** — A knows B, A knows C, B doesn't know C:

```sql
SELECT DISTINCT e1.dst_id AS b, e2.dst_id AS c, e1.src_id AS bridge
FROM edges e1
JOIN edges e2 ON e1.src_id = e2.src_id AND e1.dst_id < e2.dst_id
WHERE e1.src_id = $1
  AND NOT EXISTS (
    SELECT 1 FROM edges x
    WHERE (x.src_id = e1.dst_id AND x.dst_id = e2.dst_id)
       OR (x.src_id = e2.dst_id AND x.dst_id = e1.dst_id)
  );
```

**Capability→need matches** — someone needs `X`, someone within two hops has `X`.

**Affinity matches** — high embedding similarity, no edge. Use sparingly; these are the weakest and most likely to feel random.

### The scoring function

```python
score = (0.35 * affinity      # claim overlap, semantic
       + 0.25 * bridge_value  # betweenness gain if this edge exists
       + 0.20 * load_balance  # favors the under-connected
       + 0.20 * timing)       # recent activity, openness, cooldowns
```

**`affinity`** — max overlap similarity from §7, or 1.0 on an exact capability→need match.

**`bridge_value`** — how much this edge would connect otherwise-separate parts of the graph. Compute with networkx: take the two nodes' community labels, and score cross-community edges higher. Approximating with `1 - jaccard(neighbors(b), neighbors(c))` is fine and much faster — if they share no neighbors beyond the bridge, connecting them genuinely fuses two clusters.

**`load_balance`** — `1 - normalized_degree(c)`, so a person with two connections outranks a person with twelve. This is the over-giver protection expressed as arithmetic.

**`timing`** — recency of activity, `openness`, and hard cooldowns. Multiply, don't add: if either person is paused or declined recently, this term goes to zero and kills the candidate outright regardless of how good the match looks.

### Then, and only then, the model

Take the top 3 by score and pass them to a judgment call: *given everything we know about these people, is this a good idea right now?* The model can veto. It cannot promote anything the scoring function didn't surface.

This ordering is the whole architecture in one paragraph, and it's what you say on stage: **the graph decides what is structurally worth doing; the model decides whether it's socially a good idea and how to phrase it.**

We learned this the hard way. The first version shipped the highest-bridge-value intro every time, and in simulation they got rejected constantly — structural value has almost nothing to do with whether two people want to meet on a Tuesday.

## 9. Intro generation and grounding

The generation call returns structured output, not prose:

```json
{
  "to_a": "Maya down the block rebuilt her balcony last spring — you mentioned wanting to redo yours. Want me to introduce you?",
  "to_b": "Sam's planning a balcony project and you've been through it. Open to a quick intro?",
  "grounded_in": ["claim-uuid-1", "claim-uuid-2"],
  "confidence": 0.8
}
```

Two messages, because the framing differs by direction — one person has a need, the other has experience, and telling both the same sentence reads as a mail merge.

### The validator

Before anything is sent, three checks. Fail any one, drop the intro silently and move to the next candidate. Never repair-and-send.

1. **Citations resolve.** Every id in `grounded_in` exists, belongs to A or B, and is above the confidence floor.
2. **No uncited specifics.** Extract named entities and concrete nouns from the message text. Every one must appear in a cited claim's `raw_label` or its evidence span. This is what catches the model inventing a detail that makes the intro *better* and *false*.
3. **No private leakage.** Nothing about third parties, nothing about `give_balance`, no reference to the routing logic. The human-facing reason is always about the two people, never about the graph.

Check 2 is the one worth building carefully. Models embellish under instruction to be warm and specific, and an intro containing a plausible, checkable, wrong fact about a neighbor is the single worst output this system can produce.

### Writing constraints

In the prompt, as hard rules:

- Under 30 words.
- State the reason, don't assert the relationship. "You both like gardening" is presumptuous; "Maya's been redoing her balcony" is a fact the reader can act on.
- Always end with a question, never an instruction. The human decides.
- Never mention that anyone helped anyone. No implied debt, ever — that's the ledger creeping in through the copy.
- No superlatives about either person.

### Human in the loop

The agent proposes; both people approve before either learns who the other is. Store as `proposed` → `sent` → `accepted`/`declined`. Only on mutual accept do you exchange identities and write the `intro_accepted` edge.

This is a design position, not a limitation, and you should say it in the demo before a judge asks: *Trellis never introduces two people without both of them saying yes.*

## 10. Outcome feedback

Every resolved intro writes back. This is what turns the system from a static rules engine into something that visibly learns, and it's cheap to build.

### On accept

- Write `intro_accepted` edge, weight 0.6.
- Nudge both people's `openness` up: `openness += 0.05 * (1 - openness)`.
- Recompute `graph_metrics` for the affected neighborhood.
- Schedule a follow-up: if they later confirm they met, upgrade to a `met` edge at 0.9.

### On decline

- Nudge `openness` down by the same asymptotic rule.
- Write a 14-day cooldown on that pair.
- **Attribute the decline.** Was it the match or the timing? A short model call on the reply text — *"not right now"* is timing, *"I don't really know them"* is the match — decides whether you suppress the pair or just delay it. Getting this wrong permanently kills pairs that were fine.

### Weight learning

Store `score_parts` on every intro (§3). Once you have 20 or so resolved outcomes, fit a logistic regression on accept/decline against the four components and update the weights.

With simulated residents you can generate hundreds of outcomes in minutes, so this is genuinely runnable during the hackathon rather than aspirational. Show the before/after weights in the demo — *we started with hand-picked weights and the system learned that timing matters twice as much as we thought* is a concrete, honest result, and very few teams will have one.

### Openness as a first-class signal

`openness` starts at 0.5 and moves only from behavior. It gates the `timing` term, so someone who declines repeatedly drifts out of the routing pool without ever being told they've been deprioritized, and drifts back in if they start accepting again.

Three declines in a row sets `paused_until = now() + 30 days`. The model treats a decline as information, never as an objection to overcome. That framing is worth stating explicitly in the demo, because "an AI that introduces you to strangers" is a scary sentence and this is the sentence that defuses it.

## 11. API surface

Freeze this in the first hour so the frontend and texting work can proceed against stubs. Return hardcoded shapes until the real thing works — an unblocked teammate is worth more than a correct endpoint.

### Write

```
POST /events
  { person_id, kind, body, source_key?, occurred_at? }
  → 202 { event_id }
```

Idempotent on `source_key`. Returns immediately; extraction is async.

```
POST /favors
  { giver_id, receiver_id, description }
  → 202 { event_id }
```

Sugar over `/events` that writes the `favor` edge directly.

```
POST /intros/:id/respond
  { person_id, accepted: bool, reply_text? }
  → 200 { status, both_accepted: bool, counterpart? }
```

`counterpart` is present only when both sides have accepted.

### Read

```
GET /people/:id/profile
  → { display_name, claims: [{ kind, raw_label, confidence }], connection_count }
```

No `give_balance`. No `openness`. Not an oversight.

```
GET /graph?since=<iso>
  → { nodes: [{ id, name, degree, cluster }],
      edges: [{ src, dst, kind, strength }] }
```

This is the visualization endpoint. `since` lets the frontend animate deltas instead of redrawing, which is what makes the graph *grow* on screen rather than flicker.

```
GET /people/:id/pending
  → { intros: [{ id, reason_text, created_at }] }
```

### Demo control

Worth building. It's the difference between a smooth demo and a frozen one.

```
POST /admin/seed      { scenario: "cold" | "warm" }
POST /admin/reset
POST /admin/tick      { steps: int }   -- advance the simulation
GET  /admin/explain/:intro_id
  → { score_parts, candidates_considered, grounded_claims, prompt }
```

`/admin/explain` is your secret weapon in Q&A. When a judge asks *why did it pick those two*, you open a URL and show the four score components, the candidates it rejected, and the exact claims the sentence was grounded in. Most teams answer that question with hand-waving.

### Events push

SSE at `GET /stream` emitting `claim_extracted`, `intro_proposed`, `intro_accepted`, `edge_created`. The frontend animates off this. Avoids polling and makes the live graph feel like it's reacting rather than refreshing.

## 12. Failure modes

### The empty graph

With no edges, there are no triangles, and the router produces nothing. This is your most likely demo failure and it happens in the first 90 seconds.

Mitigation: seed with `scenario: "warm"` — a dozen residents with a handful of existing edges. Show the cold version only if you have time to narrate it. And build the **offer generation** fallback: when no triangle exists, generate a low-stakes offer someone could make. Offering costs nothing socially; asking costs a lot. This is both the real cold-start answer and your demo safety net.

### Extraction returns nothing

Real messages are mostly empty of signal. If a judge types "hey" and nothing happens, you look broken.

Mitigation: the SSE stream emits `extraction_complete` with a count even when it's zero, and the UI shows *"nothing to learn from that one"*. Visible no-ops beat silence. It also quietly demonstrates that you aren't hallucinating claims from noise, which is a better look than it sounds.

### The creepy intro

An intro that reveals more than it should, or infers something too personal. This is the demo-ending failure — one bad output in front of a judge and the safety questions take over the room.

Mitigation: the §9 validator, plus a hard blocklist of claim categories that never appear in intro text (anything health, financial, relationship, or immigration related). Extract them if they help routing; never say them.

### Latency

Extraction plus canonicalization plus scoring plus generation plus validation is several seconds of model calls. Dead air on stage.

Mitigation: everything async, SSE for progress, and the UI shows each stage as it completes. A visible pipeline advancing through stages reads as *sophisticated*. A spinner reads as *broken*. Same latency.

### Rate limits at 3am

You'll hit them. Cache embeddings by text hash aggressively — canonical labels get embedded once, ever. Batch extraction calls when seeding. Have a `MOCK_LLM=1` path that returns fixture responses so the rest of the system stays testable when the API is unavailable or you're out of credits.

### The hardcode list

Decide now, not at 4am, what you will fake if you run out of time. In descending order of acceptability:

1. Pre-computed embeddings for seed residents — fine, nobody cares.
2. Fixed weights instead of learned ones — fine, just don't claim you learned them.
3. A scripted demo path with real components running — acceptable if you say it's a scripted path.
4. Fake intro text — **no**. That's the thing being judged. If generation is broken, demo without it.

The line: faking *inputs* is fine, faking *judgment* is not.

## 13. Build order

Sequenced so there is a working end-to-end path early, and everything after that is depth rather than plumbing. Hours are from your start, not the clock.

**H0–H1 — Contracts.** Write §11 as a FastAPI app returning hardcoded JSON. Commit. Your teammates are now unblocked and you haven't written a line of real logic. This is the highest-leverage hour of the whole build.

**H1–H3 — Schema and events.** Postgres up, §3 schema applied, `/events` writing real rows. No extraction yet.

**H3–H6 — Extraction.** The structured-output call, span verification, embeddings, canonicalization. At the end of this block a message in produces claims in the database. **Do not move on until span verification works** — it's the foundation of every grounding claim you'll make on stage.

**H6–H8 — Edges and topology.** Favor edges, decay query, networkx load, `graph_metrics` table. Now `GET /graph` returns something real and the frontend has a graph to draw.

**H8–H11 — Routing.** Triangle SQL, the scoring function, the model veto. Log every candidate with its parts — that's what `/admin/explain` reads.

**H11–H14 — Generation.** Context assembly, the intro call, the validator. End-to-end path now works: favor in → intro out.

**H14–H17 — Simulated residents.** 50 personas with schedules and constraints, driving `/events` on a loop. This is also your test data for everything above, which is why it comes after rather than before — you want it exercising a real system, not shaping one.

**H17–H19 — Feedback loop.** Outcomes writing back, openness updates, the weight fit. If time is short, cut the logistic regression and keep the openness updates.

**H19–H21 — Demo hardening.** Seed scenarios, reset endpoint, `/admin/explain`, the hardcode list from §12. Run the full demo five times and fix what breaks.

**H21+ — Stop building.** Rehearse. Every hour past this spent on features is worth less than an hour spent making the existing demo not fail.

### Cut list, in order

If you're behind, cut in this order: learned weights → the model veto → affinity-only candidates → SSE (poll instead) → burnout detection.

**Never cut:** span verification, the intro validator, or human-in-the-loop approval. Those three are what make the system defensible, and they're also the cheapest things on the list.

## 14. "Is this actually a graph?" — the judge answer

Yes. A graph is nodes and edges with traversal, not a particular vendor. You have `people` (nodes), `edges` (edges), and recursive queries plus networkx for traversal. Neo4j is a graph *database*; it is not the definition of a graph.

If a judge pushes, the answer is a positional one, not a defensive one:

> *We're running graph algorithms — triangle enumeration, betweenness, community detection — on a graph stored relationally. At our scale the whole graph fits in memory, so the expensive part isn't traversal, it's the model calls. Optimizing storage for traversal would be solving a problem we don't have.*

Then give the numbers, because specificity is what makes this land:

| scale | approach | why it holds |
| --- | --- | --- |
| < 10k people | load whole graph into networkx | \~10k nodes is a few MB; full recompute in well under a second |
| 10k–1M | partition by geography | neighborhoods don't span cities — this graph is *naturally* sharded, so you run per-region subgraphs in parallel |
| 1M+ | incremental metrics + a graph store | only then does maintaining centrality beat recomputing it |

The geographic point is the strong one and it's specific to this product. Social graphs like Facebook's are global and can't be partitioned without cutting real edges. **A neighborhood graph is physically local by definition** — someone in Cambridge and someone in Austin will never be candidates, so the partition is free. That means this architecture scales by adding partitions, not by re-architecting.

### What would actually force a change

Be honest about this; it's more convincing than claiming the design scales forever. Two things:

1. **Deep traversal.** If routing ever needed 4+ hop paths, recursive CTEs get ugly and a graph store starts earning its complexity. Right now we go two hops, because a friend-of-a-friend-of-a-friend introduction has no social meaning anyway.
2. **Real-time metrics on a hot graph.** If the graph changed thousands of times per second, recomputing topology would stop being viable and you'd move to incremental algorithms.

Neither is near. Saying which specific thing would break the design is a stronger answer than insisting nothing would.

## 15. Supabase

The §3 schema runs as-is — Supabase is Postgres. Enable `vector` from the dashboard extensions page. Four things change.

### Realtime replaces SSE

This is a straight win. Delete the `/stream` endpoint from §11 and have the frontend subscribe directly:

```js
supabase.channel('trellis')
  .on('postgres_changes',
      { event: 'INSERT', schema: 'public', table: 'edges' },
      payload => graph.addEdge(payload.new))
  .on('postgres_changes',
      { event: 'INSERT', schema: 'public', table: 'claims' },
      payload => ui.flashClaim(payload.new))
  .subscribe()
```

Your worker writes a row; the graph animates. No endpoint, no polling, no event bus. Enable replication on `edges`, `claims`, and `intros` in the dashboard or the subscription silently receives nothing — that's a 20-minute bug, so check it first.

### The worker does not go in an Edge Function

Edge Functions have short timeouts and cold starts. Your extraction chain is several sequential model calls.

Run the agent as a **normal Python process** — locally during the hackathon, on Railway or Render if you need it hosted — connecting to Supabase over the connection string with the **service role key**. Supabase is your database and your realtime bus; it is not your compute. Use Edge Functions only for the thin webhook that receives inbound SMS and inserts into `events`.

### RLS: enable it, then bypass it

Turn RLS on for every table (Supabase will nag otherwise, and an open database is a bad thing for a judge to notice). Your agent uses the service role key, which bypasses RLS entirely, so it's unaffected. The frontend uses the anon key and gets real policies:

```sql
ALTER TABLE claims ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_claims ON claims FOR SELECT
  USING (person_id = auth.uid());

ALTER TABLE graph_metrics ENABLE ROW LEVEL SECURITY;
-- no SELECT policy at all: give_balance is never client-readable
```

That second one is worth mentioning out loud in the demo. The ledger isn't just hidden in the UI — **the client literally cannot read it**, enforced at the database. That's a much stronger claim than "we chose not to display it."

### Vector search as an RPC

pgvector works, but wrap the §7 overlap query in a Postgres function so it's one RPC call rather than a query built in application code:

```sql
CREATE FUNCTION claim_overlap(a UUID, b UUID, threshold REAL DEFAULT 0.7)
RETURNS TABLE (a_claim UUID, a_label TEXT, b_claim UUID, b_label TEXT, sim REAL)
LANGUAGE sql STABLE AS $$
  SELECT ca.id, ca.raw_label, cb.id, cb.raw_label,
         1 - (ca.embedding <=> cb.embedding)
  FROM claims ca, claims cb
  WHERE ca.person_id = a AND cb.person_id = b
    AND ca.superseded_by IS NULL AND cb.superseded_by IS NULL
    AND ca.confidence >= 0.6 AND cb.confidence >= 0.6
    AND 1 - (ca.embedding <=> cb.embedding) > threshold
  ORDER BY 5 DESC LIMIT 5;
$$;
```

Then `supabase.rpc('claim_overlap', {a, b})` from anywhere, including the frontend if you want a debug view.

Skip `ivfflat` indexes at this scale. Below a few thousand rows a sequential scan is faster than the index, and a badly-tuned `lists` parameter will quietly return wrong neighbors — a miserable bug to find at 3am.

## 16. Seed data

**Seed events, not claims.** Write the messages and let your real extraction pipeline build the graph from them. Two reasons: you're testing the actual pipeline every time you reset, and when a judge asks where a capability came from, you click through to a message instead of admitting you typed it into a table.

### The twelve residents

Designed so the graph has a specific shape: two loose clusters, one bridge person, one over-giver, and two isolates. The interesting intros are the ones that cross between clusters.

| # | name | cluster | role in the demo |
| --- | --- | --- | --- |
| 1 | Maya Chen | A | the bridge — knows people in both |
| 2 | Sam Okonkwo | A | the over-giver, high `give_balance` |
| 3 | Priya Raman | A | new parent |
| 4 | Dev Patel | A | has tools, says little |
| 5 | Elena Vasquez | B | gardener, teaches |
| 6 | Marcus Hill | B | new parent, doesn't know Priya |
| 7 | Aisha Rahman | B | bikes, tutors math |
| 8 | Tom Brennan | B | truck, moving help |
| 9 | Yuki Tanaka | B | cooks, hosts |
| 10 | Jordan Reyes | — | isolate, just moved in |
| 11 | Grace Adebayo | — | isolate, elderly, needs rides |
| 12 | Leo Moretti | — | isolate, dog owner |

**The planted intro** is Priya (3, cluster A) and Marcus (6, cluster B): both new parents, no shared edge, bridged only through Maya. High affinity, high bridge value, and an intro sentence that writes itself. That's the one your demo should land on.

### The seed messages

Three per person, phrased the way people actually text. Keep signal implicit — a message that says "I am skilled at bicycle repair" proves nothing about your extractor.

```sql
INSERT INTO events (person_id, kind, body, occurred_at) VALUES
-- Aisha: bike capability, stated obliquely
((SELECT id FROM people WHERE display_name='Aisha Rahman'), 'message',
 'finally got the derailleur on my old trek working, took all afternoon',
 now() - interval '6 days'),
((SELECT id FROM people WHERE display_name='Aisha Rahman'), 'message',
 'if anyone needs help with calc my inbox is open, I miss teaching it',
 now() - interval '4 days'),

-- Priya: new parent, need + life stage
((SELECT id FROM people WHERE display_name='Priya Raman'), 'message',
 'three weeks in and I have not slept. does the crib assembly get easier',
 now() - interval '5 days'),
((SELECT id FROM people WHERE display_name='Priya Raman'), 'message',
 'looking for a pediatrician rec, ours moved practices',
 now() - interval '2 days'),

-- Marcus: the other half of the planted match
((SELECT id FROM people WHERE display_name='Marcus Hill'), 'message',
 'our kid is 8 weeks. nobody warned me about the 4am shift',
 now() - interval '5 days'),
((SELECT id FROM people WHERE display_name='Marcus Hill'), 'message',
 'we found a stroller that actually fits in the trunk, small victories',
 now() - interval '3 days'),

-- Sam: the over-giver, all giving
((SELECT id FROM people WHERE display_name='Sam Okonkwo'), 'message',
 'happy to grab anything while I am at the store, just text me',
 now() - interval '8 days'),
((SELECT id FROM people WHERE display_name='Sam Okonkwo'), 'message',
 'sure I can do saturday too',
 now() - interval '1 day'),

-- Jordan: the isolate who arrives with nothing
((SELECT id FROM people WHERE display_name='Jordan Reyes'), 'message',
 'just moved to the building, still looking for where the good coffee is',
 now() - interval '1 day');
```

Note Sam's second message: short, flat, and following a long streak of favors given. That's the burnout signature from §6, planted deliberately. If your detector flags Sam without being told to, that's a genuine result and worth showing.

### Seed edges

Only the favors, and skew them so Sam gives and rarely receives:

```sql
INSERT INTO edges (src_id, dst_id, kind, weight, created_at)
SELECT g.id, r.id, 'favor', 1.0, now() - (interval '1 day' * d)
FROM (VALUES
  ('Sam Okonkwo','Maya Chen',9), ('Sam Okonkwo','Dev Patel',7),
  ('Sam Okonkwo','Priya Raman',5), ('Sam Okonkwo','Grace Adebayo',3),
  ('Maya Chen','Priya Raman',8), ('Maya Chen','Marcus Hill',6),
  ('Elena Vasquez','Yuki Tanaka',7), ('Aisha Rahman','Tom Brennan',4),
  ('Yuki Tanaka','Marcus Hill',5), ('Tom Brennan','Elena Vasquez',2)
) AS v(giver, receiver, d)
JOIN people g ON g.display_name = v.giver
JOIN people r ON r.display_name = v.receiver;
```

Maya connects to Priya *and* Marcus, who don't connect to each other. That's your open triangle, and it should be the highest-scoring candidate the moment you run the router.

### Two scenarios

`scenario: "warm"` loads all of the above. Use it for the main demo — the graph already has shape and the router produces something immediately.

`scenario: "cold"` loads the twelve people with no events and no edges. Use it only if you have time to narrate the cold-start story, where the agent generates low-stakes offers because there's nothing to route yet. It's a better story and a riskier demo. Decide in rehearsal, not on stage.

## 17. Post-interaction feedback

Yes, build this. It closes the loop and it's the thing that makes the system visibly learn. But there's a trap in it, and the design has to dodge the trap on purpose.

### The trap

"This person sucked" is a **reputation** signal, and community reputation systems fail in well-known ways: two people's bad mood becomes a permanent quiet blacklist, the person never knows why they stopped hearing from anyone, and negative ratings land disproportionately on people who are already marginal in the group. You'd have rebuilt the ledger you refused to build in §3, except worse, because this one judges people instead of counting favors.

### The fix: private affinity, not public reputation

Feedback adjusts **the edge**, not the person.

```sql
CREATE TABLE feedback (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  intro_id    UUID NOT NULL REFERENCES intros(id),
  author_id   UUID NOT NULL REFERENCES people(id),
  subject_id  UUID NOT NULL REFERENCES people(id),
  raw_text    TEXT NOT NULL,
  -- extracted, -1..1
  valence     REAL NOT NULL,
  -- what it was about: fit | reliability | comfort | logistics
  dimension   TEXT NOT NULL,
  -- did it describe the person, or the circumstances?
  attribution TEXT NOT NULL,  -- person | situation | unclear
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

The rules:

- **Positive feedback is global.** "I loved this person" raises their `openness` and their general routing priority. Praise is safe to share.
- **Negative feedback is pairwise and private by default.** It writes a strong negative weight on that specific A↔B edge and suppresses that pair. It does **not** touch how anyone else is routed to them.
- **It takes three independent negatives, from unconnected people, on the same dimension, before anything global happens** — and even then the effect is reduced routing volume, not exclusion.
- **Safety reports are a different table and a different path.** Never blend "we didn't click" with "that person made me uncomfortable." One is preference; the other is a flag that a human should see. Collapsing them means either over-punishing awkwardness or under-reacting to a real problem.

### Attribution is where the model earns its place

This is the interesting part and it's a clean AI moment for the demo.

*"He kept checking his phone and left early"* is about the person. *"It was pouring and we couldn't really talk"* is about the situation. *"Nice enough, just not my thing"* is about fit — which is real information and not a criticism at all.

A rules engine treats all three as a thumbs-down. A model separates them, and the routing consequences are completely different: suppress the pair, retry in better conditions, or adjust the affinity vector and keep both people in full rotation.

Feed the raw text to an extraction call returning `{valence, dimension, attribution, evidence}`, same shape as §4. Reuse the pipeline.

### How it changes routing

```python
# §8 timing term, extended
timing *= (1 - 0.9 * pair_negative_valence)   # kills a bad pair fast
affinity *= (1 + 0.3 * subject_positive_mean) # well-liked people surface more
```

Asymmetric on purpose. One bad experience should nearly eliminate that pair immediately, because nobody should get re-matched with someone they didn't enjoy. One good experience should only nudge, because you don't want the graph collapsing onto four popular people.

### How to ask

After a confirmed meet, one message: *"How'd it go with Maya?"* Free text, no stars, no scale. Numeric ratings turn a neighbor into a service provider, and people won't give an honest 2/5 to someone they'll see at the mailbox. Prose gives you more signal and better feelings.

And never surface it. Maya is never told her rating, because she doesn't have one — what exists is an edge weight between two people and a private note that the system acted on.

## 18. The texting agent

Yes — different agent, different job, and keeping them separate is a real architectural decision rather than a convenience.

### Why two agents

They optimize for opposite things.

|  | routing agent (you) | texting agent |
| --- | --- | --- |
| runs | on events, async | in a conversation, sync |
| latency budget | seconds | under a second |
| state | the whole graph | one thread |
| job | decide *whether* | handle *how* |
| failure mode | a bad intro | an awkward reply |

One agent doing both means every incoming "ok sounds good" triggers graph traversal and scoring, and every routing decision waits on conversational context it doesn't need. Worse, the prompt becomes a mess of two unrelated jobs and both degrade.

### What the texting agent owns

- Parsing replies into intent: accept, decline, question, reschedule, unrelated chatter.
- Handling the back-and-forth of scheduling once both sides have said yes.
- Tone: brief, warm, never pushy, never salesy about an intro.
- Knowing when to shut up. Most inbound messages need no reply at all.

It holds one thread's context. It never queries the graph and never makes a routing decision.

### The contract

```
routing agent → texting agent:
  { thread_id, person_id, message_text, expects: "yes_no" | "free" | null }

texting agent → routing agent:
  POST /events              (everything, always — the log is the log)
  POST /intros/:id/respond  (only when it parses a clear accept/decline)
```

`expects` is the whole handshake. When the routing agent sends an intro proposal it sets `expects: "yes_no"`, and the texting agent knows the next inbound message from that person is probably an answer and should be parsed as one. Without it, the texting agent has to guess whether "sure" is an acceptance or small talk.

### The rule that keeps them separate

**The texting agent never decides anything the graph should decide.** If someone replies *"who else around here has a truck?"*, it does not answer. It logs the event and lets the routing agent decide whether that's a need worth acting on.

This is easy to get wrong under time pressure — it feels helpful to let the chat agent just answer. But then routing logic ends up in two places, one of them has no memory, and the two start contradicting each other. The chat agent is a mouth and ears, not a brain.

### Who builds it

Your teammate, against the contract above. It doesn't need the graph, the schema, or the model pipeline — just the two endpoints and a Twilio webhook. If you freeze this contract in hour one alongside §11, the two halves can be built in parallel without either of you blocking the other.
