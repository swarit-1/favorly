-- Create pantry_scans table to store vision analysis results
CREATE TABLE IF NOT EXISTS pantry_scans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    trip_id UUID REFERENCES trips(id) ON DELETE CASCADE,

    -- Vision analysis results
    detected_items JSONB NOT NULL DEFAULT '[]',  -- Array of detected products
    low_or_empty TEXT[] DEFAULT ARRAY[]::TEXT[],  -- Items that need restocking
    summary TEXT,  -- Human-readable summary of findings
    expiration_warnings JSONB DEFAULT '[]'::JSONB,  -- Items expiring soon
    recommendations TEXT[] DEFAULT ARRAY[]::TEXT[],  -- Suggestions

    -- Image metadata
    image_paths TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],  -- Paths to uploaded images

    -- Analysis metadata
    analysis_type VARCHAR(50) DEFAULT 'pantry',  -- Type: pantry, shelf, receipt, damage, etc.
    confidence_score FLOAT,  -- Overall confidence (0-1)
    vision_model VARCHAR(100) DEFAULT 'muse-spark-1.3',  -- Which vision model was used
    is_placeholder BOOLEAN DEFAULT FALSE,  -- True if using mock/fallback data

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT valid_analysis_type CHECK (analysis_type IN ('pantry', 'shelf', 'receipt', 'damage', 'yard', 'pet', 'cleaning'))
);

-- Create indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_pantry_scans_user_id ON pantry_scans(user_id);
CREATE INDEX IF NOT EXISTS idx_pantry_scans_trip_id ON pantry_scans(trip_id);
CREATE INDEX IF NOT EXISTS idx_pantry_scans_created_at ON pantry_scans(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pantry_scans_analysis_type ON pantry_scans(analysis_type);

-- Enable RLS (Row Level Security)
ALTER TABLE pantry_scans ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can only see their own pantry scans
-- Allow SELECT for authenticated users (their own records)
CREATE POLICY pantry_scans_user_select ON pantry_scans
    FOR SELECT
    USING (auth.uid()::uuid = user_id);

-- Allow INSERT for authenticated users (their own records) or for demo/anonymous records
CREATE POLICY pantry_scans_user_insert ON pantry_scans
    FOR INSERT
    WITH CHECK (auth.uid()::uuid = user_id OR user_id IS NULL);

-- Allow UPDATE for authenticated users (their own records)
CREATE POLICY pantry_scans_user_update ON pantry_scans
    FOR UPDATE
    USING (auth.uid()::uuid = user_id);

-- Allow DELETE for authenticated users (their own records)
CREATE POLICY pantry_scans_user_delete ON pantry_scans
    FOR DELETE
    USING (auth.uid()::uuid = user_id);

-- Trigger to auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_pantry_scans_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER pantry_scans_timestamp_trigger
BEFORE UPDATE ON pantry_scans
FOR EACH ROW
EXECUTE FUNCTION update_pantry_scans_timestamp();

-- Add comment for documentation
COMMENT ON TABLE pantry_scans IS 'Stores results from vision analysis of pantry, fridge, shelves, receipts, and other visual tasks using Muse API';
COMMENT ON COLUMN pantry_scans.detected_items IS 'Array of detected products with name, brand, status, confidence, etc.';
COMMENT ON COLUMN pantry_scans.is_placeholder IS 'True if using mock data (fallback), false if real Muse API result';
