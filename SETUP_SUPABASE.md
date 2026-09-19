# Supabase Setup Guide

Complete setup in **5 minutes**. Supabase provides auth, database, storage, and realtime in one dashboard.

---

## Quick Start (5 minutes)

### 1. Create Supabase Project

1. Go to https://supabase.com
2. Click "Start your project" or "Sign in"
3. Create account (Google or email)
4. Confirm email
5. Click "New project"
6. Project name: `favorly-demo`
7. Database password: `favorly_demo_123` (or generate)
8. Region: **US East** (us-east-1)
9. Click "Create new project"
10. **Wait 2–3 minutes** ⏳ for database to initialize

### 2. Get Connection Strings

Once project is ready, go to **Settings** → **Database** (left sidebar):

**PostgreSQL Connection String (for backend):**
```
postgresql://postgres:favorly_demo_123@db.xxxxx.supabase.co:5432/postgres
```

**Supabase URL & Keys (for backend + Flutter):**
1. Go to **Settings** → **API**
2. Copy:
   - `Project URL`: `https://xxxxx.supabase.co`
   - `anon key`: `eyJ...` (public key)
   - `service_role key`: `eyJ...` (secret key)

**Save these for Step 3.**

### 3. Create Environment Variables

#### Backend `.env`:
```bash
# Supabase
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_KEY=eyJ...  # anon key
SUPABASE_SERVICE_ROLE_KEY=eyJ...  # service role key
DATABASE_URL=postgresql://postgres:favorly_demo_123@db.xxxxx.supabase.co:5432/postgres

# Server
ENVIRONMENT=development
PORT=8000
```

#### Flutter `.env` (or in code):
```dart
const String supabaseUrl = 'https://xxxxx.supabase.co';
const String supabaseAnonKey = 'eyJ...';  // anon key
```

### 4. Enable Authentication

1. Left sidebar → **Authentication** → **Providers**
2. Enable:
   - ✅ **Email** (Magic Link)
   - ✅ **Anonymous** (for testing)
   - ✅ **Google** (optional, for OAuth)
3. Each should toggle green

### 5. Enable Storage (for image uploads)

1. Left sidebar → **Storage**
2. Click **Create new bucket**
3. Bucket name: `images`
4. Toggle **Public bucket** ON (for demo; RLS later)
5. Click **Create bucket**
6. Upload folders (optional):
   - `images/trips/`
   - `images/lists/`
   - `images/receipts/`
   - `images/shelf/`

### 6. Enable Realtime (for live updates)

1. Left sidebar → **Realtime**
2. Click **Replication** tab
3. Enable realtime for tables:
   - `trips`
   - `items`
   - `requests`
   - `substitution_prompts`
   - `settlements`

Each table gets an "Enable Realtime" toggle → click to turn green.

---

## Set Up Database Schema

### 1. Run SQL Migration

Go to **SQL Editor** (left sidebar) and copy-paste this:

```sql
-- Users
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  circle_id UUID NOT NULL,
  name VARCHAR NOT NULL,
  venmo_handle VARCHAR,
  created_at TIMESTAMP DEFAULT NOW()
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
CREATE INDEX idx_users_circle_id ON users(circle_id);
CREATE INDEX idx_circles_invite_code ON circles(invite_code);
CREATE INDEX idx_trips_shopper_status ON trips(shopper_id, status);
CREATE INDEX idx_trips_circle_created ON trips(circle_id, created_at);
CREATE INDEX idx_requests_trip_requester ON requests(trip_id, requester_id);
CREATE INDEX idx_items_request_id ON items(request_id);
CREATE INDEX idx_items_trip_status ON items(trip_id, status);
CREATE INDEX idx_parses_user_created ON parses(user_id, created_at);
CREATE INDEX idx_receipts_trip_id ON receipts(trip_id);
CREATE INDEX idx_settlements_trip_requester ON settlements(trip_id, requester_id);
CREATE INDEX idx_ledger_circle_user ON ledger_events(circle_id, user_id);
CREATE INDEX idx_cached_vision_key_surface ON cached_vision_responses(cache_key, surface);
```

Click **Run** (or Ctrl+Enter).

✅ All 10 tables created with indexes.

### 2. Enable Realtime on Tables

Go to **Realtime** tab (left sidebar):

For each table, toggle **Realtime** ON:
- [ ] `trips`
- [ ] `items`
- [ ] `requests`
- [ ] `substitution_prompts`
- [ ] `settlements`

---

## Set Up Row Level Security (RLS)

Disable for demo (enable later for security):

1. Go to **Authentication** → **Policies** (left sidebar)
2. Select each table
3. Disable RLS (toggle OFF) for demo

**⚠️ Security Note:** Enable RLS before production deployment.

---

## Flutter Setup

Install Flutter SDK and set up Supabase client:

```bash
# In your Flutter project
flutter pub add supabase flutter_appauth

# Initialize Supabase
import 'package:supabase_flutter/supabase_flutter.dart';

await Supabase.initialize(
  url: 'https://xxxxx.supabase.co',
  anonKey: 'eyJ...',
);
```

See Flutter docs: https://supabase.com/docs/guides/auth/auth-flutter

---

## Backend Setup

Python dependencies for Supabase:

```bash
# requirements.txt
supabase==2.4.0
python-dotenv==1.0.0
# ... other deps
```

Use Supabase Python client:

```python
from supabase import create_client, Client

url = os.getenv("SUPABASE_URL")
key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
supabase: Client = create_client(url, key)

# Insert
response = supabase.table("users").insert({"name": "Alice", "circle_id": "..."}).execute()

# Select
data = supabase.table("users").select("*").execute()

# Realtime (FastAPI WebSocket)
realtime = supabase.realtime
```

---

## Test Connection

```bash
# Backend
python -c "
from supabase import create_client
import os
from dotenv import load_dotenv
load_dotenv()

url = os.getenv('SUPABASE_URL')
key = os.getenv('SUPABASE_SERVICE_ROLE_KEY')
supabase = create_client(url, key)
data = supabase.table('users').select('*').limit(1).execute()
print(f'✅ Supabase connected: {data}')
"
```

---

## Key URLs

- **Supabase Dashboard:** https://app.supabase.com
- **Project Settings:** https://app.supabase.com/project/xxxxx/settings
- **SQL Editor:** https://app.supabase.com/project/xxxxx/sql
- **Authentication:** https://app.supabase.com/project/xxxxx/auth/users
- **Storage:** https://app.supabase.com/project/xxxxx/storage/buckets

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| "Database still initializing" | Wait 2–3 min, refresh browser |
| "RLS policy denies access" | Disable RLS for demo (Security → Policies) |
| "Realtime not working" | Enable realtime on table (Realtime tab) |
| "Authentication failed" | Check `anon key` vs `service_role key` (different permissions) |
| "Storage upload failed" | Ensure bucket is public or RLS allows it |

---

## Next Steps

1. ✅ Backend: Use `supabase-py` client in FastAPI routes
2. ✅ Flutter: Use `supabase_flutter` SDK for auth, storage, realtime
3. ✅ Demo data: Populate with `seed_demo.py`
