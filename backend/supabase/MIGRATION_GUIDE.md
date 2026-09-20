# Phase 2: Database Schema Migrations

This guide walks through applying the three Supabase database migrations for live messaging, notifications, and real-time location tracking.

## Overview

Three tables are being created:

1. **`messages`** — Live chat messages in trips (RLS: visible to circle members)
2. **`notifications`** — User notifications for trip events (RLS: visible only to user)
3. **`user_locations`** — Real-time GPS locations for map display (RLS: visible to circle members)

Each table includes:
- Row-Level Security (RLS) policies
- Realtime publication for Supabase subscriptions
- Indexes for query performance

## Option 1: Supabase Dashboard (Easiest)

1. Go to [supabase.com/dashboard](https://supabase.com/dashboard)
2. Select your Favorly project
3. Navigate to **SQL Editor**
4. Click **New Query**
5. Copy and paste the contents of **`migrations/001_create_messages_table.sql`**
6. Click **Run** (⌘ + Enter)
7. Repeat for `002_create_notifications_table.sql` and `003_create_user_locations_table.sql`

## Option 2: Supabase CLI

```bash
# Install if not already installed
npm install -g supabase

# Link your project (interactive)
supabase link

# Run migrations
cd backend/supabase
./run_migrations.sh
```

Or manually:
```bash
supabase db push --filepath migrations/001_create_messages_table.sql
supabase db push --filepath migrations/002_create_notifications_table.sql
supabase db push --filepath migrations/003_create_user_locations_table.sql
```

## Verification

After running migrations, verify in Supabase Dashboard:

1. **SQL Editor** → Run:
   ```sql
   SELECT table_name FROM information_schema.tables
   WHERE table_schema = 'public';
   ```
   You should see: `messages`, `notifications`, `user_locations`

2. **Authentication** → **Policies** tab
   - Verify policies exist for each table
   - Ensure RLS is enabled (lock icon visible on each table)

3. **Database** → **Realtime** tab
   - Verify all three tables are in the `supabase_realtime` publication

## Troubleshooting

**Q: "Relation already exists"**
- The migration files include `IF NOT EXISTS` — they're safe to re-run

**Q: RLS policies not applying**
- Ensure you're logged in as an authenticated user in the Supabase client
- After login in the app, `Supabase.instance.client.auth.currentUser` should be non-null

**Q: Realtime not working**
- Check that the table is added to `supabase_realtime` publication
- In Supabase Dashboard → Database → Realtime → verify table checkboxes

## Next Steps

After migrations are applied:
1. Implement **Phase 3**: Backend routes for `/messages` and `/notifications`
2. Create notification fan-out logic on trip state changes
3. Implement **Phase 4**: Flutter providers and UI for chat, notifications, and map
