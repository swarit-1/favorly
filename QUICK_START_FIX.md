# Vision Database Persistence - Quick Start

## TL;DR - What's Fixed

✅ Vision analysis results now **persist to database** (they didn't before)
✅ GET endpoint retrieves saved scans with pagination
✅ Fixed RLS policy that was silently rejecting records

## Apply the Fix (5 minutes)

### Step 1: Update Supabase RLS Policy

Go to **Supabase Dashboard → SQL Editor** and run:

```sql
-- Drop the old broken policy
DROP POLICY IF EXISTS pantry_scans_user_insert ON pantry_scans;

-- Create the fixed policy (allows NULL user_id for demo mode)
CREATE POLICY pantry_scans_user_insert ON pantry_scans
    FOR INSERT
    WITH CHECK (auth.uid()::uuid = user_id OR user_id IS NULL);
```

**Done!** The policy now allows demo/anonymous records.

### Step 2: Restart Backend

```bash
# Kill running server
pkill -f "uvicorn app:app" || true

# Start with latest code
python3 -m uvicorn app:app --port 8000
```

## Test It (2 minutes)

### Create a test scan
```bash
# Create test image
python3 << 'EOF'
from PIL import Image
img = Image.new('RGB', (100, 100), color='red')
img.save('/tmp/test_scan.jpg')
print("✅ Test image ready")
EOF

# Scan
curl -X POST http://localhost:8000/vision/grocery/pantry-scan \
  -F "files=@/tmp/test_scan.jpg" | python3 -m json.tool
```

Should return something like:
```json
{
  "analysis_id": "550e8400-...",
  "domain_type": "grocery_shopping",
  "is_placeholder": false,
  "summary": "..."
}
```

### Retrieve the scan
```bash
# Should return the scan you just created
curl http://localhost:8000/vision/grocery/pantry-scans | python3 -m json.tool
```

Should show:
```json
{
  "scans": [
    {
      "id": "550e8400-...",
      "summary": "...",
      "created_at": "2026-09-20T...",
      ...
    }
  ],
  "total": 1,
  "limit": 50,
  "offset": 0
}
```

## What Changed

| What | Before | After |
|------|--------|-------|
| Scans saved to DB | ❌ No (RLS rejected) | ✅ Yes |
| GET endpoint | ❌ Didn't exist | ✅ Added with pagination |
| RLS policy | ❌ Broke demo mode | ✅ Fixed (allows NULL user_id) |
| Logging | ❌ Too verbose (print) | ✅ Proper logging (INFO/DEBUG) |

## New Endpoints

### POST /vision/grocery/pantry-scan
Analyzes images and **saves to database** automatically

```bash
curl -X POST http://localhost:8000/vision/grocery/pantry-scan \
  -F "files=@image.jpg" \
  -F "user_id=550e8400-..." \  # optional
  -F "trip_id=550e8400-..."     # optional
```

### GET /vision/grocery/pantry-scans
Retrieves saved scans with pagination

```bash
curl "http://localhost:8000/vision/grocery/pantry-scans?limit=10&offset=0"
```

## Architecture

```
User uploads image(s)
    ↓
Vision API analyzes (real Muse or mock)
    ↓
Results saved to pantry_scans table ← THIS NOW WORKS
    ↓
Response returned + analysis_id given
    ↓
User can GET /pantry-scans to see history
```

## If It Still Doesn't Work

1. **Verify RLS policy was applied:**
   ```sql
   SELECT policyname FROM pg_policies WHERE tablename='pantry_scans';
   ```
   Should show 4 policies with `pantry_scans_user_insert` in the list.

2. **Check table exists:**
   ```sql
   SELECT table_name FROM information_schema.tables 
   WHERE table_schema='public' AND table_name='pantry_scans';
   ```

3. **Check logs:**
   ```bash
   grep -i "pantry\|database" /tmp/uvicorn.log | tail -20
   ```

## Full Documentation

- **Summary of changes:** `VISION_DATABASE_FIX_SUMMARY.md`
- **Detailed migration guide:** `VISION_DATABASE_MIGRATION_GUIDE.md`
- **Muse API testing:** `MUSE_API_TESTING_GUIDE.md`

## Next: Production Readiness

After testing:
1. Add authentication to routes (extract user from JWT)
2. Implement other analysis types (shelf, receipt, etc.)
3. Add UI to display scan history
4. Monitor database growth and add archival if needed
