#!/usr/bin/env python3
"""Set up Supabase database schema."""

import os
from dotenv import load_dotenv
from supabase import create_client, Client

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")

if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
    print("❌ SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")
    exit(1)

supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

SQL_SCHEMA = """
-- Users
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  circle_id UUID NOT NULL,
  name VARCHAR NOT NULL,
  venmo_handle VARCHAR,
  bio TEXT,
  photo_url TEXT,
  role VARCHAR DEFAULT 'both' CHECK (role IN ('shopper', 'requester', 'both')),
  address_unit VARCHAR,
  address_floor VARCHAR,
  address_buzzer VARCHAR,
  address_notes TEXT,
  dietary TEXT[] DEFAULT '{}',
  preferred_stores TEXT[] DEFAULT '{}',
  availability TEXT[] DEFAULT '{}',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Circles
CREATE TABLE IF NOT EXISTS circles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR NOT NULL,
  invite_code VARCHAR(6) UNIQUE NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Trips
CREATE TABLE IF NOT EXISTS trips (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shopper_id UUID NOT NULL REFERENCES users(id),
  circle_id UUID NOT NULL REFERENCES circles(id),
  store VARCHAR NOT NULL,
  depart_at TIMESTAMP NOT NULL,
  caps JSONB DEFAULT '{"max_requesters": 6, "max_dollars_per_person": "40.00", "max_items_per_person": 8}',
  status VARCHAR DEFAULT 'open' CHECK (status IN ('open', 'shopping', 'settling', 'done')),
  created_at TIMESTAMP DEFAULT NOW()
);

-- Requests
CREATE TABLE IF NOT EXISTS requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id UUID NOT NULL REFERENCES trips(id),
  requester_id UUID NOT NULL REFERENCES users(id),
  status VARCHAR DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined')),
  created_at TIMESTAMP DEFAULT NOW()
);

-- Items
CREATE TABLE IF NOT EXISTS items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id UUID NOT NULL REFERENCES requests(id),
  trip_id UUID NOT NULL REFERENCES trips(id),
  name VARCHAR NOT NULL,
  qty INTEGER DEFAULT 1,
  unit VARCHAR,
  note VARCHAR,
  max_price NUMERIC(10, 2),
  section VARCHAR DEFAULT 'other',
  status VARCHAR DEFAULT 'pending' CHECK (status IN ('pending', 'got', 'substituted', 'skipped')),
  substitute_of UUID REFERENCES items(id),
  actual_price NUMERIC(10, 2),
  created_at TIMESTAMP DEFAULT NOW()
);

-- Parses (VLM outputs)
CREATE TABLE IF NOT EXISTS parses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id),
  source VARCHAR NOT NULL CHECK (source IN ('text', 'photo', 'voice')),
  raw_ref VARCHAR NOT NULL,
  transcript VARCHAR,
  parsed JSONB,
  confirmed BOOLEAN DEFAULT FALSE,
  confirmed_items JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Receipts
CREATE TABLE IF NOT EXISTS receipts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id UUID NOT NULL REFERENCES trips(id),
  image_ref VARCHAR NOT NULL,
  split JSONB,
  assignments JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Settlements
CREATE TABLE IF NOT EXISTS settlements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id UUID NOT NULL REFERENCES trips(id),
  requester_id UUID NOT NULL REFERENCES users(id),
  lines JSONB DEFAULT '[]',
  subtotal NUMERIC(10, 2),
  tax_share NUMERIC(10, 2),
  total NUMERIC(10, 2),
  venmo_link VARCHAR,
  marked_paid BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Ledger Events
CREATE TABLE IF NOT EXISTS ledger_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  circle_id UUID NOT NULL REFERENCES circles(id),
  user_id UUID NOT NULL REFERENCES users(id),
  type VARCHAR NOT NULL CHECK (type IN ('trip_run', 'favor_received')),
  value NUMERIC(10, 2),
  trip_id UUID REFERENCES trips(id),
  created_at TIMESTAMP DEFAULT NOW()
);

-- Substitution Prompts
CREATE TABLE IF NOT EXISTS substitution_prompts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id UUID NOT NULL REFERENCES items(id),
  requester_id UUID NOT NULL REFERENCES users(id),
  candidates JSONB NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  decision VARCHAR CHECK (decision IN ('choose', 'skip', 'timeout_skip')),
  chosen_index INTEGER,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Cached Vision Responses
CREATE TABLE IF NOT EXISTS cached_vision_responses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cache_key VARCHAR UNIQUE NOT NULL,
  surface VARCHAR NOT NULL,
  response JSONB NOT NULL,
  provider VARCHAR,
  latency_ms INTEGER,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Create Indexes
CREATE INDEX IF NOT EXISTS idx_users_circle_id ON users(circle_id);
CREATE INDEX IF NOT EXISTS idx_circles_invite_code ON circles(invite_code);
CREATE INDEX IF NOT EXISTS idx_trips_shopper_status ON trips(shopper_id, status);
CREATE INDEX IF NOT EXISTS idx_trips_circle_created ON trips(circle_id, created_at);
CREATE INDEX IF NOT EXISTS idx_requests_trip_requester ON requests(trip_id, requester_id);
CREATE INDEX IF NOT EXISTS idx_items_request_id ON items(request_id);
CREATE INDEX IF NOT EXISTS idx_items_trip_status ON items(trip_id, status);
CREATE INDEX IF NOT EXISTS idx_parses_user_created ON parses(user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_receipts_trip_id ON receipts(trip_id);
CREATE INDEX IF NOT EXISTS idx_settlements_trip_requester ON settlements(trip_id, requester_id);
CREATE INDEX IF NOT EXISTS idx_ledger_circle_user ON ledger_events(circle_id, user_id);
CREATE INDEX IF NOT EXISTS idx_cached_vision_key_surface ON cached_vision_responses(cache_key, surface);
"""

try:
    print("🚀 Setting up Supabase database schema...")

    # Execute SQL using the Supabase client
    result = supabase.rpc("execute_sql", {"sql": SQL_SCHEMA}).execute()

    print("✅ Database schema created successfully!")
    print("\n📋 Next steps:")
    print("1. Go to Supabase dashboard: https://app.supabase.com")
    print("2. Select your project")
    print("3. Enable Realtime on these tables:")
    print("   - trips")
    print("   - items")
    print("   - requests")
    print("   - substitution_prompts")
    print("   - settlements")
    print("\n4. Run: python backend/seed/seed_demo.py")
    print("5. Run: cd backend && python -m uvicorn app:app --reload --port 8000")

except Exception as e:
    print(f"⚠️  Schema setup note: {e}")
    print("\n✅ To set up schema manually:")
    print("1. Go to Supabase dashboard → SQL Editor")
    print("2. Copy the schema from SETUP_SUPABASE.md")
    print("3. Paste and run in the SQL editor")
    print("4. Enable Realtime on required tables")
