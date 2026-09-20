-- v2: any favor in. Additive only, idempotent, safe on the shared database.
-- Applied by hand (Vercel skips apply_schema() on cold start); the same
-- statements are appended to schema.sql so a persistent host picks them up.

-- PRD-DEVIATION: public.users (owned by the backend) does not yet have the
-- profile columns the v2 app_people view exposes (address_unit, address_floor,
-- availability, bio) even though backend/routes/auth.py already reads them
-- defensively with .get(). Added here, additively, so the view can exist.
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
