-- Phase 2.1: Messages table for live chat in trips
CREATE TABLE IF NOT EXISTS messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id uuid NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES users(id),
  body text NOT NULL CHECK (char_length(body) <= 500),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Index for efficient querying by trip and creation time
CREATE INDEX IF NOT EXISTS messages_trip_created_idx ON messages(trip_id, created_at);

-- Enable RLS
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Policy: Circle members can read all messages in trips they're part of
CREATE POLICY "circle members read messages" ON messages
  FOR SELECT
  USING (
    trip_id IN (
      SELECT t.id
      FROM trips t
      JOIN users u ON u.circle_id = t.circle_id
      WHERE u.id = auth.uid()
    )
  );

-- Policy: Circle members can insert messages to trips they're part of
CREATE POLICY "circle members insert messages" ON messages
  FOR INSERT
  WITH CHECK (
    sender_id = auth.uid()
    AND trip_id IN (
      SELECT t.id
      FROM trips t
      JOIN users u ON u.circle_id = t.circle_id
      WHERE u.id = auth.uid()
    )
  );

-- Add to realtime publication for live subscriptions
ALTER PUBLICATION supabase_realtime ADD TABLE messages;
