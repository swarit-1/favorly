# Vision Analysis Database Migration & Testing Guide

## Overview

The vision analysis endpoints now persist results to the `pantry_scans` table in Supabase, enabling users to view their historical analysis results and confirmations.

## What Changed

### 1. New Database Table: `pantry_scans`
- Stores vision analysis results with full metadata
- Includes RLS (Row Level Security) policies for user isolation
- Auto-timestamps creation and updates
- Foreign keys to `users` and `trips` tables (optional)

### 2. Updated Vision Endpoints
- **POST /vision/grocery/pantry-scan** now accepts:
  - `files` (required) - Image files to analyze
  - `user_id` (optional) - UUID of the user performing the scan
  - `trip_id` (optional) - UUID of the associated trip
  - Returns `analysis_id` that can be used to retrieve the stored scan later

- **GET /vision/grocery/pantry-scans** (NEW)
  - Retrieves saved pantry scans for a user
  - Returns array of all stored analyses with metadata

### 3. New Model: `PantryScan` (Pydantic)
Located in `shared/contracts/models.py`:
```python
class PantryScan(BaseModel):
    id: UUID
    user_id: Optional[UUID]
    trip_id: Optional[UUID]
    detected_items: List[dict]
    low_or_empty: List[str]
    summary: Optional[str]
    expiration_warnings: List[dict]
    recommendations: List[str]
    image_paths: List[str]
    analysis_type: AnalysisType  # pantry, shelf, receipt, damage, yard, pet, cleaning
    confidence_score: Optional[float]
    vision_model: str  # muse-spark-1.3
    is_placeholder: bool  # True if using mock data
    created_at: datetime
    updated_at: Optional[datetime]
```

## Migration Steps

### Step 1: Apply SQL Migration to Supabase

The migration file is at: `backend/supabase/migrations/004_create_pantry_scans_table.sql`

**Option A: Manual SQL Editor (Recommended for now)**
1. Go to Supabase Dashboard → SQL Editor
2. Create a new query
3. Copy the entire contents of `004_create_pantry_scans_table.sql`
4. Click "Run"
5. Verify the table appears in your database

**Option B: Automated Migration Script**
```bash
# Set environment variables
export SUPABASE_URL="https://your-project.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="your_service_role_key"

# Run the migration
python3 backend/supabase/apply_migrations_http.py
```

### Step 2: Verify Table Creation
In Supabase SQL Editor, run:
```sql
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name = 'pantry_scans';
```

Should return one row with `table_name = pantry_scans`.

## Testing

### Test 1: Basic Pantry Scan with Database Persistence

```bash
# Create a test image
python3 << 'EOF'
from PIL import Image
import io
img = Image.new('RGB', (100, 100), color='red')
img.save('/tmp/test_pantry.jpg')
print("✅ Test image created at /tmp/test_pantry.jpg")
EOF

# Call the pantry scan endpoint
curl -X POST http://localhost:8000/vision/grocery/pantry-scan \
  -F "files=@/tmp/test_pantry.jpg" \
  -F "user_id=550e8400-e29b-41d4-a716-446655440000" \
  -F "trip_id=550e8400-e29b-41d4-a716-446655440001" | python3 -m json.tool
```

**Expected response:**
```json
{
  "analysis_id": "uuid-string",
  "domain_type": "grocery_shopping",
  "detected_items": [...],
  "summary": "...",
  "image_refs": [...],
  "analyzed_at": "2026-09-20T...",
  "is_placeholder": false
}
```

**Verify database persistence:**
```sql
-- In Supabase SQL Editor
SELECT id, user_id, trip_id, summary, is_placeholder, created_at 
FROM pantry_scans 
ORDER BY created_at DESC 
LIMIT 1;
```

### Test 2: Retrieve Saved Scans

```bash
# Get all scans (for testing)
curl http://localhost:8000/vision/grocery/pantry-scans | python3 -m json.tool

# Get scans for a specific user
curl "http://localhost:8000/vision/grocery/pantry-scans?user_id=550e8400-e29b-41d4-a716-446655440000" | python3 -m json.tool
```

**Expected response:**
```json
{
  "scans": [
    {
      "id": "uuid",
      "user_id": "uuid",
      "trip_id": "uuid",
      "detected_items": [...],
      "summary": "...",
      "is_placeholder": false,
      "created_at": "2026-09-20T..."
    }
  ]
}
```

### Test 3: Real API vs Mock Data

The system automatically tracks whether results are from the real Muse API or fallback mock:

```bash
# Check the is_placeholder field in the response
# - is_placeholder: false = Real Muse API result
# - is_placeholder: true = Mock/fallback result

curl http://localhost:8000/vision/health | python3 -m json.tool
```

Expected with real API available:
```json
{
  "status": "ok",
  "vision_service": "real_with_fallback",
  "muse_api_key_configured": true
}
```

## Architecture

### Data Flow

```
User uploads image(s)
    ↓
POST /vision/grocery/pantry-scan
    ↓
ImageStorageService (upload & store images)
    ↓
VisionService (Meta Muse API or fallback to mock)
    ↓
Create PantryScan model ← Includes is_placeholder flag
    ↓
Supabase insertion (pantry_scans table)
    ↓
Return analysis_id + response to user
```

### Security (RLS Policies)

The `pantry_scans` table has Row Level Security enabled with these policies:

- **SELECT**: Users can only see their own scans (`auth.uid() = user_id`)
- **INSERT**: Users can only create scans for themselves
- **UPDATE**: Users can only update their own scans
- **DELETE**: Users can only delete their own scans

**Note**: For demo mode with `user_id = null`, RLS policies won't apply. In production, ensure authenticated users are always linked.

## Troubleshooting

### Table doesn't exist
- Verify migration was applied: Check Supabase → Tables → `pantry_scans` exists
- If not, manually run the SQL from `004_create_pantry_scans_table.sql`

### Database insertion fails silently
- Check logs: Look for "Warning: Failed to save to database"
- The endpoint returns successfully even if database save fails (graceful degradation)
- Verify SUPABASE_URL and SUPABASE_KEY are correct in `.env`

### Results show is_placeholder: true
- This means the mock API is being used
- Check MUSE_API_KEY is set: `echo $MUSE_API_KEY`
- Check endpoint connectivity: `curl https://api.meta.ai/v1/health`
- View logs for fallback reason: `tail -50 /tmp/uvicorn.log | grep -i fallback`

### Query returns empty scans list
- Check that user_id matches what was sent in the request
- Try without filtering: `GET /vision/grocery/pantry-scans` (get all)
- Verify records exist in Supabase: Run SQL query directly

## Next Steps

1. **Apply the migration** to your Supabase instance (Step 1 above)
2. **Test with real images** using the Muse API
3. **Integrate with UI** to display saved scans
4. **Implement retrieval endpoint** to show scan history to users
5. **Add confirmation flow** for users to review and confirm detected items

## Migration File Details

| Component | Details |
|-----------|---------|
| File | `backend/supabase/migrations/004_create_pantry_scans_table.sql` |
| Table | `pantry_scans` |
| Columns | 15 (id, user_id, trip_id, detected_items, etc.) |
| Indexes | 4 (user_id, trip_id, created_at, analysis_type) |
| RLS Policies | 4 (SELECT, INSERT, UPDATE, DELETE) |
| Trigger | Auto-update `updated_at` timestamp |
| Constraints | valid_analysis_type CHECK, foreign keys |

## API Endpoint Changes

### Before
```
POST /vision/grocery/pantry-scan
├─ files: UploadFile
```
No database persistence.

### After
```
POST /vision/grocery/pantry-scan
├─ files: UploadFile (required)
├─ user_id: str (optional)
└─ trip_id: str (optional)
↓
Saves to database automatically
Returns analysis_id for retrieval

GET /vision/grocery/pantry-scans
├─ user_id: str (optional filter)
└─ Returns: {"scans": [...]} sorted by created_at DESC
```

## Related Documentation

- Vision Service: `backend/services/vision_service.py`
- Vision Routes: `backend/routes/vision.py`
- Models: `backend/shared/contracts/models.py`
- Muse API Testing: `MUSE_API_TESTING_GUIDE.md`
