# Step 1 Complete: Experience Rating Model & Demo Store

## What Was Added ✅

### 1. **Data Models** (`lib/models/models.dart`)
- **ExperienceRating** — Tracks one person's feedback about working with another
  - overall_rating (1-5)
  - Optional detailed ratings: reliability, accuracy, communication (1-5 each)
  - Optional comment
  
- **MemberCompatibility** — Computed score for member partnerships
  - score (0.0-1.0)
  - tripsWorkedTogether (count)
  - averageRating (1.0-5.0)

### 2. **Demo Store Methods** (`lib/state/demo_store.dart`)
- `submitRating()` — Create new experience rating
- `ratingsFor(memberId)` — Get all ratings about a member
- `ratingsFrom(memberId)` — Get all ratings someone gave
- `compatibilityScore(id1, id2)` — Compute partnership score
- `recommendedPartners(memberId)` — Get top 3 best partners

### 3. **Sample Seed Data**
Costco trip includes realistic ratings between Ana, Ben, and Maya showing:
- Ana rates Ben (5★) and Maya (4★)
- Ben rates Ana (5★)
- Maya rates Ana (5★)

### 4. **Documentation** (in `docs/`)
- `SUPABASE_SCHEMA.md` — Full schema design with all tables explained
- `migrations_experience_ratings.sql` — Ready-to-run migration file
- `EXPERIENCE_SYSTEM_GUIDE.md` — Complete feature guide with examples
- `INTEGRATION_FLOW.md` — End-to-end flow diagrams and code examples

## Code Quality ✅
- ✅ Passes `dart analyze` (no issues)
- ✅ Follows Dart/Flutter coding standards
- ✅ Immutable models with `copyWith()`
- ✅ Strong typing (no `dynamic`)

## What You Need to Do Next

### 🟢 **IMMEDIATE**: Set Up Supabase Tables

1. Go to **Supabase Dashboard → SQL Editor**
2. Copy-paste all contents of:
   ```
   docs/migrations_experience_ratings.sql
   ```
3. Run it
4. Verify tables were created:
   - `experience_ratings`
   - `member_compatibility_cache`

This creates:
- `experience_ratings` table with UNIQUE constraint (one rating per person per trip)
- `member_compatibility_cache` for fast lookups
- `refresh_member_compatibility()` function to recompute scores

### 🟡 **NEXT**: Wire Backend API Routes

Add these routes to `backend/app.py`:

```python
from backend.shared.contracts.models import ExperienceRating

# POST /experiences
@app.post("/experiences")
async def submit_experience_rating(
    trip_id: str,
    rated_id: str,
    overall_rating: int,
    reliability_rating: int | None = None,
    accuracy_rating: int | None = None,
    communication_rating: int | None = None,
    comment: str | None = None,
    current_user_id: str = Depends(get_current_user_id),
):
    # INSERT into experience_ratings
    # Then trigger: SELECT refresh_member_compatibility(circle_id)
    pass

# GET /experiences
@app.get("/experiences")
async def get_experiences(
    rated_id: str | None = None,
    rated_by_id: str | None = None,
):
    # SELECT from experience_ratings with filters
    pass

# GET /members/{id}/compatibility
@app.get("/members/{id}/compatibility")
async def get_member_compatibility(
    id: str,
    circle_id: str,
    limit: int = 3,
):
    # SELECT from member_compatibility_cache ORDER BY score DESC LIMIT 3
    pass
```

Map these in `backend/shared/contracts/models.py`:
```python
class ExperienceRating(BaseModel):
    id: str
    trip_id: str
    rated_by_id: str
    rated_id: str
    overall_rating: int
    reliability_rating: int | None = None
    accuracy_rating: int | None = None
    communication_rating: int | None = None
    comment: str | None = None
    created_at: datetime
```

### 🔵 **THEN**: Build Survey Screen

Create `lib/screens/survey_screen.dart` that:
1. Appears after `HandoffScreen` (after "Mark delivered")
2. Shows each requester who participated
3. Lets shopper rate each person (1-5 slider)
4. Optional: detailed ratings (reliability, accuracy, communication)
5. Optional: comment field
6. Submit button calls:
   ```dart
   ref.read(storeProvider).submitRating(
     tripId: tripId,
     ratedId: person.id,
     overallRating: rating,
     comment: comment,
   );
   // Then: await ApiClient.submitExperience(...)
   ```

### 🟣 **LATER**: Show Recommendations

Use the matching algorithm to:
- Display in trip creation: "You've worked with Ben before (4.9★, 2 trips)"
- Show in ledger/member profiles: "Best partners: Ben (0.92), Maya (0.87)"
- Suggest team rebuilds: "You work great together!"

## Demo It Now

Test the model without the UI:

```dart
// In a test or debug screen
final store = ref.read(storeProvider);

// Check seed data loaded
print(store.experiences.length); // Should be 4 (Ana & Ben, Ana & Maya, etc.)

// Compute compatibility
final anaBen = store.compatibilityScore('ana', 'ben');
print('Ana & Ben score: ${anaBen.score}'); // 1.0 (perfect match from demo data)

// Get recommendations for Ana
final partners = store.recommendedPartners('ana');
partners.forEach((member, compat) {
  print('${member.name}: ${compat.score} (worked ${compat.tripsWorkedTogether}x)');
});
```

## Files Changed

```
lib/models/models.dart
  ├─ Added ExperienceRating class
  └─ Added MemberCompatibility class

lib/state/demo_store.dart
  ├─ Added experiences map
  ├─ Added submitRating() method
  ├─ Added ratingsFor() method
  ├─ Added ratingsFrom() method
  ├─ Added compatibilityScore() method
  ├─ Added recommendedPartners() method
  └─ Seeded with sample experience data

docs/
  ├─ SUPABASE_SCHEMA.md (new)
  ├─ migrations_experience_ratings.sql (new)
  ├─ EXPERIENCE_SYSTEM_GUIDE.md (new)
  └─ INTEGRATION_FLOW.md (new)
```

## Architecture Overview

```
User completes trip
    ↓
HandoffScreen: confirmHandoff()
    ↓
[NEW] SurveyScreen: rate each person
    ↓
submitRating() → DemoStore.experiences map
    ↓
POST /experiences → Supabase experience_ratings table
    ↓
Backend triggers: refresh_member_compatibility()
    ↓
member_compatibility_cache updated
    ↓
Next trip creation:
  recommendedPartners() → fetch from cache
  ↓
Show: "Ben works great with you (0.92★)"
```

## Algorithm

Compatibility score = frequency (60%) + quality (40%)

```
frequency = min(trips_worked_together / 3) * 0.6
quality = (average_rating / 5.0) * 0.4
final_score = frequency + quality

Example: Ana & Ben
  - Worked together 1 time
  - Average rating 5.0/5
  - frequency = min(1/3, 1) * 0.6 = 0.2
  - quality = (5/5) * 0.4 = 0.4
  - score = 0.6 → "good partnership"
```

## Ready to Continue?

Once you run the Supabase migration, let me know and we can:
1. Build the survey screen
2. Wire the backend routes
3. Test end-to-end
4. Display recommendations in the UI
