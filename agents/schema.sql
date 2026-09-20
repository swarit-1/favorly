-- Trellis agent + graph service schema -- scoped to grocery-trip favor
-- tracking and reciprocity. No introductions/matchmaking: extraction still
-- mines grocery-relevant signal (dietary needs, car access, etc.) so a
-- person's profile is informative, but nothing proposes that two people meet.
--
-- Never UPDATE or DELETE `events`. Claims are superseded, never updated.

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pgcrypto; -- gen_random_uuid()

-- Identity lives in Supabase Auth. `auth.users` is the only place a person is
-- born; `public.users` (owned by the errand-coordination backend) is their
-- profile -- name, circle, venmo -- and its id IS the auth id. This service
-- owns no identity table of its own: every person_id/giver_id/receiver_id
-- below references public.users(id), which in turn references auth.users(id),
-- so a graph row can only ever belong to a real authenticated account.
--
-- Read identity through the `app_people` view at the bottom of this file.
-- Consequence: this service no longer runs standalone -- it needs the
-- backend's `users` table and Supabase's `auth` schema in the same database.

-- Append-only. Never UPDATE, never DELETE.
CREATE TABLE IF NOT EXISTS events (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id   UUID NOT NULL REFERENCES users(id),
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
  person_id   UUID NOT NULL REFERENCES users(id),
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
  src_id      UUID NOT NULL REFERENCES users(id),
  dst_id      UUID NOT NULL REFERENCES users(id),
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
  person_id   UUID NOT NULL REFERENCES users(id),
  body        TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'open',  -- open | claimed | fulfilled | cancelled
  claimed_by  UUID REFERENCES users(id),
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


-- How a finished favor went, captured at hand-off. Separate from `needs`
-- because a need is the ask and this is the aftermath: it arrives later, it is
-- optional, and it belongs to whoever is doing the rating.
CREATE TABLE IF NOT EXISTS favor_reviews (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  need_id     UUID NOT NULL REFERENCES needs(id),
  reviewer_id UUID NOT NULL REFERENCES users(id),
  rating      SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- One review per person per favor; re-submitting updates it.
  UNIQUE (need_id, reviewer_id)
);
CREATE INDEX IF NOT EXISTS favor_reviews_need_idx ON favor_reviews (need_id);

-- Identity, read-only, assembled from the auth account and its profile. Named
-- `app_people` rather than `people` so nothing can mistake it for a table this
-- service owns: it is a view, and the rows behind it belong to Supabase Auth
-- and the backend. `display_name` keeps the column name the graph queries used.
-- v2 appended unit/floor/availability/bio at the END (columns may only be
-- appended, or CREATE OR REPLACE VIEW fails). The users ALTERs live in the
-- v2 block at the bottom of this file; they run before this on a fresh
-- database only if... they don't. So they are duplicated here, first.
ALTER TABLE users ADD COLUMN IF NOT EXISTS address_unit TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS address_floor TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS availability JSONB NOT NULL DEFAULT '[]';
ALTER TABLE users ADD COLUMN IF NOT EXISTS bio TEXT;

CREATE OR REPLACE VIEW app_people AS
SELECT u.id,
       u.name        AS display_name,
       a.email       AS email,
       u.circle_id   AS circle_id,
       u.venmo_handle,
       a.created_at  AS joined_at,
       u.address_unit,
       u.address_floor,
       u.availability,
       u.bio
FROM public.users u
JOIN auth.users a ON a.id = u.id;
-- Grocery trips offered via the SMS agent (mirrors the errand-coordination
-- backend's trips shape; standalone-DB equivalent of sharing its table).
-- recommendations._upcoming_trip reads this for the `trip` signal.
CREATE TABLE IF NOT EXISTS trips (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shopper_id  UUID NOT NULL REFERENCES users(id),
  store       TEXT NOT NULL,
  depart_at   TIMESTAMPTZ NOT NULL,
  status      TEXT NOT NULL DEFAULT 'open',   -- open | shopping | done
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- v2: any favor in (mirrors migrations/001_any_favor.sql -- change both
-- together). Additive only; the shared database must never lose a row.
-- ============================================================================

-- PRD-DEVIATION: public.users lacked these profile columns; added additively
-- so the v2 app_people view (unit, floor, availability, bio) can exist.
ALTER TABLE users ADD COLUMN IF NOT EXISTS address_unit TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS address_floor TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS address_buzzer TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS address_notes TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS availability JSONB NOT NULL DEFAULT '[]';
ALTER TABLE users ADD COLUMN IF NOT EXISTS bio TEXT;

ALTER TABLE needs ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT 'errand';
ALTER TABLE needs ADD COLUMN IF NOT EXISTS title TEXT;
ALTER TABLE needs ADD COLUMN IF NOT EXISTS requires JSONB NOT NULL DEFAULT '[]';
ALTER TABLE needs ADD COLUMN IF NOT EXISTS when_text TEXT;
ALTER TABLE needs ADD COLUMN IF NOT EXISTS duration_minutes INT;
ALTER TABLE needs ADD COLUMN IF NOT EXISTS shortlist JSONB NOT NULL DEFAULT '[]';

CREATE TABLE IF NOT EXISTS need_invites (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  need_id      UUID NOT NULL REFERENCES needs(id),
  helper_id    UUID NOT NULL REFERENCES users(id),
  status       TEXT NOT NULL DEFAULT 'pending',   -- pending | accepted | declined | expired
  rank         INT,
  reason       TEXT,
  spark        TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  responded_at TIMESTAMPTZ,
  UNIQUE (need_id, helper_id)
);
CREATE INDEX IF NOT EXISTS need_invites_helper_idx ON need_invites (helper_id, status);

-- Append columns at the END only, or CREATE OR REPLACE VIEW fails.
CREATE OR REPLACE VIEW app_people AS
SELECT u.id, u.name AS display_name, a.email AS email, u.circle_id, u.venmo_handle,
       a.created_at AS joined_at,
       u.address_unit, u.address_floor, u.availability, u.bio
FROM public.users u JOIN auth.users a ON a.id = u.id;
