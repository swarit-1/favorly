-- Phase 2.2: Notifications table for real-time notifications
CREATE TABLE IF NOT EXISTS notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  trip_id uuid REFERENCES trips(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('new_message', 'trip_departed', 'request_accepted', 'item_substituted')),
  title text NOT NULL,
  body text NOT NULL,
  read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Index for efficient querying by user and read status
CREATE INDEX IF NOT EXISTS notifications_user_read_idx ON notifications(user_id, read, created_at DESC);

-- Enable RLS
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Policy: Users can only read their own notifications
CREATE POLICY "users read own notifications" ON notifications
  FOR SELECT
  USING (user_id = auth.uid());

-- Policy: Users can only update their own notifications (mark as read)
CREATE POLICY "users update own notifications" ON notifications
  FOR UPDATE
  USING (user_id = auth.uid());

-- Note: Backend writes notifications using service role key (no INSERT policy needed for authenticated users)

-- Add to realtime publication for live subscriptions
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
