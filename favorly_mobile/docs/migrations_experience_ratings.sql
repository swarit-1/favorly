-- Favorly: Experience Ratings & Matching Algorithm
-- This migration adds tables to track collaboration quality and compute member compatibility.
--
-- Run this in Supabase SQL Editor or apply via: supabase db push
--
-- NOTE: Uses UUID for all IDs to match backend schema (setup_db.py)
-- Maps to: users (not members), trips, circles, etc.

-- ============================================================================
-- Experience Ratings Table
-- ============================================================================
-- Tracks how well members worked together. Used by the matching algorithm to
-- reconnect people who have positive history.

CREATE TABLE IF NOT EXISTS experience_ratings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  circle_id UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
  rated_by_id UUID NOT NULL REFERENCES users(id),
  rated_id UUID NOT NULL REFERENCES users(id),

  -- Overall satisfaction with the working relationship
  overall_rating INT NOT NULL CHECK (overall_rating >= 1 AND overall_rating <= 5),

  -- Optional detailed ratings (1-5 scale)
  reliability_rating INT CHECK (reliability_rating IS NULL OR (reliability_rating >= 1 AND reliability_rating <= 5)),
  accuracy_rating INT CHECK (accuracy_rating IS NULL OR (accuracy_rating >= 1 AND accuracy_rating <= 5)),
  communication_rating INT CHECK (communication_rating IS NULL OR (communication_rating >= 1 AND communication_rating <= 5)),

  comment TEXT,
  created_at TIMESTAMP DEFAULT NOW(),

  -- Prevent duplicate ratings: one person rates another once per trip
  UNIQUE(trip_id, rated_by_id, rated_id)
);

-- Indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_experience_ratings_trip ON experience_ratings(trip_id);
CREATE INDEX IF NOT EXISTS idx_experience_ratings_rated ON experience_ratings(rated_id);
CREATE INDEX IF NOT EXISTS idx_experience_ratings_rated_by ON experience_ratings(rated_by_id);
CREATE INDEX IF NOT EXISTS idx_experience_ratings_circle ON experience_ratings(circle_id);

-- ============================================================================
-- Member Compatibility Cache Table
-- ============================================================================
-- Denormalized cache of computed compatibility scores between member pairs.
-- Should be refreshed after each trip completes (via cron or manually).
--
-- Score is computed as:
--   - frequency_score (60%): min(trips_worked_together / 3.0, 1.0) * 0.6
--   - quality_score (40%): (average_rating / 5.0) * 0.4
--   - total_score = frequency_score + quality_score (0.0 to 1.0)

CREATE TABLE IF NOT EXISTS member_compatibility_cache (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  circle_id UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
  member_id_1 UUID NOT NULL REFERENCES users(id),
  member_id_2 UUID NOT NULL REFERENCES users(id),

  score NUMERIC NOT NULL, -- 0.0 to 1.0, rounded to 2 decimal places
  trips_worked_together INT DEFAULT 0,
  average_rating NUMERIC, -- 1.0 to 5.0

  updated_at TIMESTAMP DEFAULT NOW(),

  -- Ensure canonical ordering: member_id_1 < member_id_2
  UNIQUE(circle_id, member_id_1, member_id_2),
  CHECK (member_id_1 < member_id_2)
);

CREATE INDEX IF NOT EXISTS idx_compatibility_circle ON member_compatibility_cache(circle_id);
CREATE INDEX IF NOT EXISTS idx_compatibility_score ON member_compatibility_cache(score DESC);
CREATE INDEX IF NOT EXISTS idx_compatibility_members ON member_compatibility_cache(member_id_1, member_id_2);

-- ============================================================================
-- Refresh Function (PostgreSQL)
-- ============================================================================
-- Periodically call this to update member_compatibility_cache from experience_ratings.
-- Can be triggered after each handoff or run on a schedule (e.g., nightly).

CREATE OR REPLACE FUNCTION refresh_member_compatibility(p_circle_id UUID DEFAULT NULL)
RETURNS void AS $$
DECLARE
  v_member_1 UUID;
  v_member_2 UUID;
  v_score NUMERIC;
  v_trips INT;
  v_avg_rating NUMERIC;
BEGIN
  -- Delete existing cache entries (or for specific circle)
  IF p_circle_id IS NOT NULL THEN
    DELETE FROM member_compatibility_cache WHERE circle_id = p_circle_id;
  ELSE
    DELETE FROM member_compatibility_cache;
  END IF;

  -- Compute and insert new scores for all member pairs
  INSERT INTO member_compatibility_cache (id, circle_id, member_id_1, member_id_2, score, trips_worked_together, average_rating, updated_at)
  WITH pairs AS (
    -- Get all unique trips each pair has worked together on
    SELECT DISTINCT
      t.circle_id,
      LEAST(er1.rated_by_id, er2.rated_by_id) AS member_id_1,
      GREATEST(er1.rated_by_id, er2.rated_by_id) AS member_id_2,
      COUNT(DISTINCT er1.trip_id) AS trips_count,
      ROUND(AVG((COALESCE(er1.overall_rating, 0) + COALESCE(er2.overall_rating, 0)) / 2.0), 2) AS avg_rating
    FROM experience_ratings er1
    JOIN experience_ratings er2 ON er1.trip_id = er2.trip_id
      AND er1.rated_by_id = er2.rated_id
      AND er2.rated_by_id = er1.rated_id
    JOIN trips t ON t.id = er1.trip_id
    WHERE p_circle_id IS NULL OR t.circle_id = p_circle_id
    GROUP BY t.circle_id, member_id_1, member_id_2
  )
  SELECT
    gen_random_uuid(),
    circle_id,
    member_id_1,
    member_id_2,
    ROUND(
      (LEAST(trips_count / 3.0, 1.0) * 0.6) + ((avg_rating / 5.0) * 0.4),
      2
    ),
    trips_count,
    avg_rating,
    NOW()
  FROM pairs
  ORDER BY circle_id, member_id_1, member_id_2;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Error refreshing compatibility: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Grant Permissions (if using RLS)
-- ============================================================================
-- Uncomment if you're using Row-Level Security on your tables:
--
-- ALTER TABLE experience_ratings ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE member_compatibility_cache ENABLE ROW LEVEL SECURITY;
--
-- CREATE POLICY select_own_experiences ON experience_ratings FOR SELECT
--   USING (rated_by_id = auth.uid() OR rated_id = auth.uid());
--
-- CREATE POLICY insert_own_experiences ON experience_ratings FOR INSERT
--   WITH CHECK (rated_by_id = auth.uid());

-- ============================================================================
-- Done!
-- ============================================================================
-- The app will now use these tables to:
-- 1. Store experience ratings after each trip (POST /experiences)
-- 2. Compute compatibility scores between members
-- 3. Recommend trip partners based on past experiences
--
-- To refresh the compatibility cache after a trip:
--   SELECT refresh_member_compatibility('{circle_id}');
--
-- Or refresh all circles:
--   SELECT refresh_member_compatibility();
