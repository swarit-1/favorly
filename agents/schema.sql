-- Trellis agent + graph service schema -- scoped to grocery-trip favor
-- tracking and reciprocity. No introductions/matchmaking: extraction still
-- mines grocery-relevant signal (dietary needs, car access, etc.) so a
-- person's profile is informative, but nothing proposes that two people meet.
--
-- Never UPDATE or DELETE `events`. Claims are superseded, never updated.

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pgcrypto; -- gen_random_uuid()

-- People. Thin on purpose: almost everything about a person is a claim, not a column.
-- id has no server-side default: when this runs alongside the errand-
-- coordination backend (backend/schema.sql) in the same Supabase project,
-- POST /people is called with id = users.id so the two tables share the same
-- identity for a given human and every person_id/giver_id/receiver_id the
-- backend already has resolves here with no lookup or mapping table needed.
-- Demo/seed residents (agents/seed_data.py) just let the caller mint one.
CREATE TABLE IF NOT EXISTS people (
  id            UUID PRIMARY KEY,
  display_name  TEXT NOT NULL,
  phone         TEXT UNIQUE,
  joined_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Append-only. Never UPDATE, never DELETE.
CREATE TABLE IF NOT EXISTS events (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id   UUID NOT NULL REFERENCES people(id),
  kind        TEXT NOT NULL,   -- message | favor_logged | system
  body        TEXT NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  source_key  TEXT UNIQUE
);
CREATE INDEX IF NOT EXISTS events_person_time_idx ON events (person_id, occurred_at DESC);

-- Grocery-relevant facts extracted from messages: dietary needs, car access,
-- budget constraints, store preferences. Informational (surfaced on a
-- person's profile) -- nothing matches on these to propose an introduction.
CREATE TABLE IF NOT EXISTS claims (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id   UUID NOT NULL REFERENCES people(id),
  kind        TEXT NOT NULL,   -- dietary | mobility | budget | preference
  canonical   TEXT NOT NULL,
  raw_label   TEXT NOT NULL,
  confidence  REAL NOT NULL,
  embedding   VECTOR(1536),
  event_id    UUID NOT NULL REFERENCES events(id),
  span_start  INT,
  span_end    INT,
  observations INT NOT NULL DEFAULT 1,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  superseded_by UUID REFERENCES claims(id)
);
CREATE INDEX IF NOT EXISTS claims_person_kind_idx ON claims (person_id, kind) WHERE superseded_by IS NULL;
-- Skip ivfflat at hackathon scale -- sequential scan is fine and correct below a few thousand rows.

-- Favor edges. Directed rows, append-only: don't update a weight when two
-- people interact again -- insert another row and let decay (edges.py)
-- compute the effective strength.
CREATE TABLE IF NOT EXISTS edges (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  src_id      UUID NOT NULL REFERENCES people(id),
  dst_id      UUID NOT NULL REFERENCES people(id),
  kind        TEXT NOT NULL,   -- favor | co_occurrence
  weight      REAL NOT NULL DEFAULT 1.0,
  event_id    UUID REFERENCES events(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (src_id, dst_id, kind, event_id)
);
CREATE INDEX IF NOT EXISTS edges_src_idx ON edges (src_id);
CREATE INDEX IF NOT EXISTS edges_dst_idx ON edges (dst_id);

-- Something a neighbor needs help with, grocery-shaped ("can someone grab
-- milk", "I can't get to the store this week"). One-sided claim flow: whoever
-- decides to help claims it; fulfilling it writes the favor edge, which is
-- what feeds reciprocity into future recommendations.
CREATE TABLE IF NOT EXISTS needs (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id   UUID NOT NULL REFERENCES people(id),
  body        TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'open',  -- open | claimed | fulfilled | cancelled
  claimed_by  UUID REFERENCES people(id),
  event_id    UUID REFERENCES events(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS needs_status_idx ON needs (status, created_at DESC);
CREATE INDEX IF NOT EXISTS needs_person_idx ON needs (person_id);

-- Canonical vocabulary for entity resolution. Seeded at startup, grows over time.
CREATE TABLE IF NOT EXISTS canonical_labels (
  canonical   TEXT PRIMARY KEY,
  embedding   VECTOR(1536) NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
