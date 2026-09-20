-- Phone-to-person identity bridge for the SMS agent (backend/agent/identity.py).
-- Additive and idempotent: safe to re-run against the shared database.
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS users_phone_unique_idx ON users (phone) WHERE phone IS NOT NULL;
