-- Favorly backend schema. Mirrors shared/contracts/models.py.
-- Runs against the same Postgres/Supabase instance as agents/schema.sql --
-- table names are namespaced enough (users/circles/trips/... vs
-- people/events/claims/...) that the two never collide.
--
-- NOTE: as of 2026-09-19, users/circles/trips/items/requests/parses/receipts/
-- settlements/ledger_events/cached_vision_responses/substitution_prompts
-- already exist in the live Supabase project (built directly against it,
-- outside this file -- see the "fix backend" commits). Every timestamp here
-- is TIMESTAMP WITHOUT TIME ZONE to match what's actually deployed; asyncpg
-- will reject a tz-aware datetime against these columns (strip tzinfo before
-- inserting -- see app.py and seed/seed_demo.py). CREATE TABLE IF NOT EXISTS
-- makes this a no-op against the live project; it exists so a fresh
-- Postgres instance ends up with the same shape.

CREATE EXTENSION IF NOT EXISTS pgcrypto; -- gen_random_uuid()

CREATE TABLE IF NOT EXISTS circles (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  invite_code   TEXT NOT NULL UNIQUE CHECK (char_length(invite_code) = 6),
  created_at    TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  circle_id     UUID NOT NULL REFERENCES circles(id),
  name          TEXT NOT NULL,
  venmo_handle  TEXT,
  created_at    TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS trips (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shopper_id    UUID NOT NULL REFERENCES users(id),
  circle_id     UUID NOT NULL REFERENCES circles(id),
  store         TEXT NOT NULL,
  depart_at     TIMESTAMP NOT NULL,
  -- TripCaps: {max_requesters, max_dollars_per_person, max_items_per_person}
  caps          JSONB NOT NULL DEFAULT '{"max_requesters": 6, "max_dollars_per_person": 40.00, "max_items_per_person": 8}',
  status        TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'shopping', 'settling', 'done')),
  created_at    TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS trips_circle_idx ON trips (circle_id);

CREATE TABLE IF NOT EXISTS requests (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id       UUID NOT NULL REFERENCES trips(id),
  requester_id  UUID NOT NULL REFERENCES users(id),
  status        TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined')),
  created_at    TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS requests_trip_idx ON requests (trip_id);

CREATE TABLE IF NOT EXISTS items (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id      UUID NOT NULL REFERENCES requests(id),
  trip_id         UUID NOT NULL REFERENCES trips(id),
  name            TEXT NOT NULL,
  qty             INT NOT NULL DEFAULT 1 CHECK (qty >= 1),
  unit            TEXT,
  note            TEXT,
  max_price       NUMERIC(10, 2),
  section         TEXT NOT NULL DEFAULT 'other' CHECK (section IN (
                    'produce', 'dairy', 'meat', 'bakery', 'frozen', 'pantry',
                    'beverages', 'household', 'personal_care', 'other'
                  )),
  status          TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'got', 'substituted', 'skipped')),
  substitute_of   UUID REFERENCES items(id),
  actual_price    NUMERIC(10, 2),
  created_at      TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS items_trip_idx ON items (trip_id);
CREATE INDEX IF NOT EXISTS items_request_idx ON items (request_id);

CREATE TABLE IF NOT EXISTS parses (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES users(id),
  source            TEXT NOT NULL CHECK (source IN ('text', 'photo', 'voice')),
  raw_ref           TEXT NOT NULL,
  transcript        TEXT,
  parsed            JSONB,             -- ParsedList
  confirmed         BOOLEAN NOT NULL DEFAULT false,
  confirmed_items   JSONB,             -- ItemDraft[]
  created_at        TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS parses_user_idx ON parses (user_id);

CREATE TABLE IF NOT EXISTS receipts (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id       UUID NOT NULL REFERENCES trips(id),
  image_ref     TEXT NOT NULL,
  split         JSONB,   -- ReceiptSplit
  assignments   JSONB,   -- LineAssignment[]
  created_at    TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS receipts_trip_idx ON receipts (trip_id);

CREATE TABLE IF NOT EXISTS settlements (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id       UUID NOT NULL REFERENCES trips(id),
  requester_id  UUID NOT NULL REFERENCES users(id),
  lines         JSONB NOT NULL DEFAULT '[]',  -- SettlementLine[]
  subtotal      NUMERIC(10, 2) NOT NULL,
  tax_share     NUMERIC(10, 2) NOT NULL,
  total         NUMERIC(10, 2) NOT NULL,
  venmo_link    TEXT,
  marked_paid   BOOLEAN NOT NULL DEFAULT false,
  created_at    TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS settlements_trip_idx ON settlements (trip_id);

CREATE TABLE IF NOT EXISTS ledger_events (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  circle_id   UUID NOT NULL REFERENCES circles(id),
  user_id     UUID NOT NULL REFERENCES users(id),
  type        TEXT NOT NULL CHECK (type IN ('trip_run', 'favor_received')),
  value       NUMERIC(10, 2) NOT NULL,
  trip_id     UUID REFERENCES trips(id),
  created_at  TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ledger_events_circle_idx ON ledger_events (circle_id);

-- Discovered already live -- VLM response cache (PRD §5: "every parse ...
-- cached") and the substitution flow (PRD §4.4), matching ShelfCandidates /
-- SubstitutionPrompt in shared/contracts/models.py. Neither is wired up by
-- this backend yet (both need real VLM calls); documented here so a fresh
-- install has the same shape as the live project.
CREATE TABLE IF NOT EXISTS cached_vision_responses (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cache_key     TEXT NOT NULL,
  surface       TEXT NOT NULL,   -- e.g. list_parse | substitution | receipt
  response      JSONB NOT NULL,
  provider      TEXT,
  latency_ms    INT,
  created_at    TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS cached_vision_responses_key_idx ON cached_vision_responses (cache_key);

CREATE TABLE IF NOT EXISTS substitution_prompts (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id       UUID NOT NULL REFERENCES items(id),
  requester_id  UUID NOT NULL REFERENCES users(id),
  candidates    JSONB NOT NULL,   -- ShelfCandidates
  expires_at    TIMESTAMP NOT NULL,
  decision      TEXT CHECK (decision IN ('choose', 'skip', 'timeout_skip')),
  chosen_index  INT,
  created_at    TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS substitution_prompts_item_idx ON substitution_prompts (item_id);
