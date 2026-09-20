# Supabase Schema for Favorly

This document describes the database schema needed in Supabase to support the Favorly algorithm, including experience tracking and member matching.

## Tables

### circles
Stores information about neighborhood circles (groups of members).

```sql
CREATE TABLE circles (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  invite_code TEXT NOT NULL UNIQUE,
  created_at TIMESTAMP DEFAULT NOW()
);
```

### members
Members of a circle.

```sql
CREATE TABLE members (
  id TEXT PRIMARY KEY,
  circle_id TEXT NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  venmo_handle TEXT,
  tint TEXT DEFAULT 'blue', -- blue, green, amber, plum
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_members_circle ON members(circle_id);
```

### trips
Shopping trips organized by members.

```sql
CREATE TABLE trips (
  id TEXT PRIMARY KEY,
  circle_id TEXT NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
  shopper_id TEXT NOT NULL REFERENCES members(id),
  store TEXT NOT NULL,
  depart_at TIMESTAMP NOT NULL,
  status TEXT DEFAULT 'open', -- open, shopping, settling, done
  max_requesters INT DEFAULT 5,
  max_dollars_per_person NUMERIC DEFAULT 40,
  max_items_per_person INT DEFAULT 8,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_trips_circle ON trips(circle_id);
CREATE INDEX idx_trips_shopper ON trips(shopper_id);
CREATE INDEX idx_trips_status ON trips(status);
```

### trip_requests
Individual requests on a trip.

```sql
CREATE TABLE trip_requests (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  requester_id TEXT NOT NULL REFERENCES members(id),
  taking BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_trip_requests_trip ON trip_requests(trip_id);
CREATE INDEX idx_trip_requests_requester ON trip_requests(requester_id);
```

### trip_items
Individual line items in a trip request.

```sql
CREATE TABLE trip_items (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  request_id TEXT NOT NULL REFERENCES trip_requests(id),
  requester_id TEXT NOT NULL REFERENCES members(id),
  name TEXT NOT NULL,
  qty INT DEFAULT 1,
  unit TEXT,
  note TEXT,
  max_price NUMERIC,
  section TEXT DEFAULT 'other', -- produce, bakery, meat, dairy, frozen, pantry, beverages, household, personalCare, other
  status TEXT DEFAULT 'pending', -- pending, got, substituted, skipped
  substitute_name TEXT,
  substitute_price NUMERIC,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_trip_items_trip ON trip_items(trip_id);
CREATE INDEX idx_trip_items_request ON trip_items(request_id);
```

### receipts
Receipt splits for trips.

```sql
CREATE TABLE receipts (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL UNIQUE REFERENCES trips(id) ON DELETE CASCADE,
  store TEXT NOT NULL,
  subtotal NUMERIC NOT NULL,
  tax NUMERIC NOT NULL,
  total NUMERIC NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_receipts_trip ON receipts(trip_id);
```

### receipt_lines
Line items on a receipt.

```sql
CREATE TABLE receipt_lines (
  id TEXT PRIMARY KEY,
  receipt_id TEXT NOT NULL REFERENCES receipts(id) ON DELETE CASCADE,
  line_no INT NOT NULL,
  description TEXT NOT NULL,
  total NUMERIC NOT NULL,
  item_id TEXT REFERENCES trip_items(id),
  assigned_to TEXT REFERENCES members(id),
  ambiguous BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_receipt_lines_receipt ON receipt_lines(receipt_id);
```

### settlements
Final settlement records for a trip (who owes whom).

```sql
CREATE TABLE settlements (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  requester_id TEXT NOT NULL REFERENCES members(id),
  subtotal NUMERIC NOT NULL,
  tax_share NUMERIC NOT NULL,
  total NUMERIC NOT NULL,
  venmo_link TEXT,
  paid BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_settlements_trip ON settlements(trip_id);
CREATE INDEX idx_settlements_requester ON settlements(requester_id);
```

### ledger_rows
Running ledger for each member (trips run, favors received, dollars carried).

```sql
CREATE TABLE ledger_rows (
  member_id TEXT PRIMARY KEY REFERENCES members(id) ON DELETE CASCADE,
  trips_run INT DEFAULT 0,
  favors_received INT DEFAULT 0,
  dollars_carried NUMERIC DEFAULT 0,
  updated_at TIMESTAMP DEFAULT NOW()
);
```

### experience_ratings ⭐ NEW
**Tracks collaboration quality between members.** Used by the matching algorithm to reconnect people who work well together.

```sql
CREATE TABLE experience_ratings (
  id TEXT PRIMARY KEY,
  trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  circle_id TEXT NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
  rated_by_id TEXT NOT NULL REFERENCES members(id),
  rated_id TEXT NOT NULL REFERENCES members(id),
  overall_rating INT NOT NULL CHECK (overall_rating >= 1 AND overall_rating <= 5),
  reliability_rating INT CHECK (reliability_rating IS NULL OR (reliability_rating >= 1 AND reliability_rating <= 5)),
  accuracy_rating INT CHECK (accuracy_rating IS NULL OR (accuracy_rating >= 1 AND accuracy_rating <= 5)),
  communication_rating INT CHECK (communication_rating IS NULL OR (communication_rating >= 1 AND communication_rating <= 5)),
  comment TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  
  -- Prevent duplicate ratings (one person rates another once per trip)
  UNIQUE(trip_id, rated_by_id, rated_id)
);

CREATE INDEX idx_experience_ratings_trip ON experience_ratings(trip_id);
CREATE INDEX idx_experience_ratings_rated ON experience_ratings(rated_id);
CREATE INDEX idx_experience_ratings_rated_by ON experience_ratings(rated_by_id);
CREATE INDEX idx_experience_ratings_circle ON experience_ratings(circle_id);
```

### member_compatibility_cache ⭐ NEW
**Cached compatibility scores between member pairs.** Computed from experience_ratings.
Refresh this table periodically (e.g., after each trip handoff).

```sql
CREATE TABLE member_compatibility_cache (
  id TEXT PRIMARY KEY,
  circle_id TEXT NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
  member_id_1 TEXT NOT NULL REFERENCES members(id),
  member_id_2 TEXT NOT NULL REFERENCES members(id),
  score NUMERIC NOT NULL, -- 0.0 to 1.0
  trips_worked_together INT DEFAULT 0,
  average_rating NUMERIC, -- 1.0 to 5.0
  updated_at TIMESTAMP DEFAULT NOW(),
  
  UNIQUE(circle_id, member_id_1, member_id_2),
  CHECK (member_id_1 < member_id_2) -- Ensure canonical order
);

CREATE INDEX idx_compatibility_circle ON member_compatibility_cache(circle_id);
CREATE INDEX idx_compatibility_score ON member_compatibility_cache(score DESC);
```

## Migrations

### To apply these tables to Supabase:

1. **Copy the SQL above into Supabase SQL Editor** (or use the migration approach below)
2. **Run the experience_ratings and member_compatibility_cache table creation** separately to ensure they're included

### Using Supabase Migration Files

If using `supabase` CLI (from `backend/supabase/` directory):

```bash
supabase migration new add_experience_ratings
```

Then add the experience_ratings and member_compatibility_cache table creation to the migration file.

## Key Design Decisions

1. **experience_ratings table**
   - Tracks every rating from one member to another on a trip
   - Foreign key constraint on `trip_id` ensures data integrity
   - UNIQUE constraint prevents duplicate ratings (one person rates another once per trip)
   - CHECK constraints enforce 1-5 rating scale

2. **member_compatibility_cache**
   - Denormalized cache of computed compatibility scores
   - Should be refreshed after each trip completes and ratings are submitted
   - Enables fast recommendation queries without computing scores on-the-fly
   - `member_id_1 < member_id_2` ensures canonical ordering (no duplicate pairs in reverse order)

3. **Indexes**
   - Query patterns: find ratings for a member, find ratings from a member, find compatibility scores
   - Index on `circle_id` for multi-circle support in the future
   - Index on `score DESC` for fast "top partners" queries

## API Routes (Backend)

The following routes should map to table mutations:

- **POST /experiences** → `INSERT INTO experience_ratings`
- **GET /experiences?rated_id={memberId}** → `SELECT * FROM experience_ratings WHERE rated_id = ?`
- **GET /experiences?rated_by_id={memberId}** → `SELECT * FROM experience_ratings WHERE rated_by_id = ?`
- **GET /members/{id}/compatibility** → `SELECT * FROM member_compatibility_cache WHERE (member_id_1 = ? OR member_id_2 = ?) ORDER BY score DESC`
- **POST /cron/refresh-compatibility** → Compute and upsert member_compatibility_cache for a circle

## Frontend Flow

1. **After trip handoff** (POST /trips/{id}/handoff):
   - Show survey screen prompting the shopper to rate each requester who participated
   - Submit ratings via POST /experiences

2. **When creating a new trip** (POST /trips):
   - Optionally show "Recommended partners" based on member_compatibility_cache
   - Use scores to suggest who to invite/mention

3. **Ledger & analytics**:
   - Display average rating alongside trips run and dollars carried
   - Show which members work best together (for encouragement)
