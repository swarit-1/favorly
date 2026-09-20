# Supabase Migration - FIXED ✅

## The Issue
The migration was using TEXT for IDs, but your backend uses **UUID** for all IDs.

Error was:
```
ERROR: 42804: foreign key constraint "experience_ratings_trip_id_fkey" cannot be implemented
DETAIL: Key columns "trip_id" and "id" are of incompatible types: text and uuid.
```

## What Was Fixed
Updated `docs/migrations_experience_ratings.sql` to use:
- **UUID** for all ID columns (matching your backend)
- **users** table instead of members (matching your backend)
- **gen_random_uuid()** for auto-generated IDs
- Proper UUID variable types in the refresh function

## Ready to Use
You can now copy-paste the migration into Supabase SQL Editor without type errors:

```bash
# In Supabase SQL Editor:
# 1. Copy contents of: docs/migrations_experience_ratings.sql
# 2. Paste into SQL Editor
# 3. Click "Run"
# 4. Verify tables were created:
#    - experience_ratings
#    - member_compatibility_cache
```

## What Gets Created
✅ `experience_ratings` table — stores all ratings
✅ `member_compatibility_cache` table — caches computed scores  
✅ `refresh_member_compatibility()` function — recomputes scores

All with proper UUID foreign keys matching:
- trips (UUID)
- circles (UUID)
- users (UUID)

## Next Steps (Flutter App)
1. ✅ Models & DemoStore done
2. ⏳ Build survey screen
3. ⏳ Wire backend API
4. ⏳ Test end-to-end
5. ⏳ Display recommendations
