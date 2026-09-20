-- Phase 2.3: User locations table for live map tracking
CREATE TABLE IF NOT EXISTS user_locations (
  user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  circle_id uuid NOT NULL REFERENCES circles(id),
  lat double precision NOT NULL,
  lng double precision NOT NULL,
  trip_id uuid REFERENCES trips(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE user_locations ENABLE ROW LEVEL SECURITY;

-- Policy: Circle members can read locations of users in their circle
CREATE POLICY "circle members read locations" ON user_locations
  FOR SELECT
  USING (
    circle_id IN (
      SELECT circle_id
      FROM users
      WHERE id = auth.uid()
    )
  );

-- Policy: Users can insert their own location
CREATE POLICY "users insert own location" ON user_locations
  FOR INSERT
  WITH CHECK (user_id = auth.uid());

-- Policy: Users can update their own location
CREATE POLICY "users update own location" ON user_locations
  FOR UPDATE
  USING (user_id = auth.uid());

-- Add to realtime publication for live subscriptions
ALTER PUBLICATION supabase_realtime ADD TABLE user_locations;
