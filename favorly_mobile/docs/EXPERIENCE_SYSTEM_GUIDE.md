# Experience Tracking & Matching System Guide

## Overview

Favorly now tracks how well members work together through **experience ratings**. After each trip, the shopper rates the requesters, and vice versa. This data powers a **matching algorithm** that can reconnect people who have positive history.

## What Was Added

### 1. **Models** (`lib/models/models.dart`)

#### `ExperienceRating`
Represents one person's feedback about working with another after a trip.

```dart
final rating = ExperienceRating(
  id: 'exp_123',
  tripId: 'trip_tj',
  ratedById: 'ana',           // Who gave the rating
  ratedId: 'ben',             // Who was rated
  overallRating: 5,           // 1-5 scale
  reliabilityRating: 5,       // Optional: 1-5
  accuracyRating: 5,          // Optional: 1-5
  communicationRating: 4,     // Optional: 1-5
  comment: 'Ben is reliable', // Optional feedback
  createdAt: DateTime.now(),
);
```

#### `MemberCompatibility`
Computed score for how well two members work together.

```dart
final compat = MemberCompatibility(
  memberId1: 'ana',
  memberId2: 'ben',
  score: 0.92,              // 0.0 to 1.0
  tripsWorkedTogether: 3,
  averageRating: 4.67,      // 1.0 to 5.0
);
```

### 2. **Demo Store Methods** (`lib/state/demo_store.dart`)

#### Submit a rating
```dart
store.submitRating(
  tripId: 'trip_tj',
  ratedId: 'ben',
  overallRating: 5,
  reliabilityRating: 5,
  accuracyRating: 5,
  communicationRating: 4,
  comment: 'Great work!',
);
```

#### Get ratings for a member
```dart
final ratingsForBen = store.ratingsFor('ben');           // Ratings other people gave Ben
final ratingsFromBen = store.ratingsFrom('ben');         // Ratings Ben gave others
```

#### Compute compatibility between two members
```dart
final compat = store.compatibilityScore('ana', 'ben');
// Returns: score (0-1), trips worked together, average rating
```

#### Get recommended partners
```dart
final partners = store.recommendedPartners('ana', limit: 3);
// Returns: List of (Member, MemberCompatibility) sorted by score descending
```

## Integration Steps

### Step 1: Add Supabase Tables ✅

1. Go to **Supabase Dashboard → SQL Editor**
2. Copy-paste the contents of `docs/migrations_experience_ratings.sql`
3. Run the migration

This creates:
- `experience_ratings` — Stores all ratings
- `member_compatibility_cache` — Caches computed scores
- `refresh_member_compatibility()` — Function to recompute scores

### Step 2: Wire Backend API Routes (Next)

Add these routes to `backend/app.py`:

```python
# POST /experiences
@app.post("/experiences")
async def submit_experience_rating(
    trip_id: str,
    rated_id: str,
    overall_rating: int,
    reliability_rating: Optional[int] = None,
    accuracy_rating: Optional[int] = None,
    communication_rating: Optional[int] = None,
    comment: Optional[str] = None,
    current_user_id: str = Depends(get_current_user_id),
):
    # Insert into experience_ratings table
    # rated_by_id = current_user_id
    # Return 201 with the rating object

# GET /experiences
@app.get("/experiences")
async def get_experiences(
    rated_id: Optional[str] = None,
    rated_by_id: Optional[str] = None,
    circle_id: str = Depends(get_circle_id),
):
    # Query experience_ratings table with filters
    # Return list of ratings

# GET /members/{id}/compatibility
@app.get("/members/{id}/compatibility")
async def get_member_compatibility(
    id: str,
    circle_id: str = Depends(get_circle_id),
    limit: int = 3,
):
    # Query member_compatibility_cache
    # Return top partners by score
```

### Step 3: Build Survey Screen (In Progress)

A new screen will appear after "Mark delivered" on the handoff flow:

1. Show each requester's avatar + name
2. Let shopper rate each person (1-5 scale)
3. Optionally capture detailed ratings (reliability, accuracy, communication)
4. Optional comment field
5. Submit ratings → DemoStore.submitRating() → Backend API

### Step 4: Display Recommendations (Future)

Use `recommendedPartners()` to suggest trip partners when creating a new trip:

- Show in trip detail screen: "Ben and Maya worked great together last time"
- Show in trip creation: "Suggest inviting Ben (you've worked together 3 times, 4.9★)"
- Add to ledger/circle screen: "Best partners for Ana: Ben (0.92), Maya (0.87)"

## Algorithm: Compatibility Score

The matching algorithm computes a score from 0.0 to 1.0:

```
frequency_score = min(trips_worked_together / 3) * 0.6    // 60% weight
quality_score = (average_rating / 5) * 0.4                 // 40% weight
final_score = frequency_score + quality_score
```

**Example:**
- Ana & Ben worked together 2 times, average rating 4.5/5
- frequency_score = min(2/3, 1.0) * 0.6 = 0.4
- quality_score = (4.5/5) * 0.4 = 0.36
- final_score = 0.76 (good partnership)

## Demo Data

The seeded demo includes sample ratings from the Costco trip:
- Ana rates Ben (5★) and Maya (4★)
- Ben rates Ana (5★)
- Maya rates Ana (5★)

Try it:
```dart
final compat = store.compatibilityScore('ana', 'ben');
// Returns: MemberCompatibility(score: 1.0, tripsWorkedTogether: 1, averageRating: 5.0)
```

## Refreshing Compatibility Cache

After each trip handoff, refresh the cache so recommendations stay current:

```sql
-- In Supabase or backend cron:
SELECT refresh_member_compatibility('{circle_id}');
```

Or in the Flutter app after submitting ratings:
```dart
// Call backend API to trigger refresh
await ApiClient.refreshCompatibility(circleId: store.me.circleId);
```

## Testing

### Unit Tests
Add tests for:
```dart
test('compatibilityScore returns 0 for new pairs', () {
  final compat = store.compatibilityScore('ana', 'unknown');
  expect(compat.score, 0.0);
});

test('recommendedPartners sorts by score', () {
  final partners = store.recommendedPartners('ana');
  expect(partners[0].$2.score, greaterThanOrEqualTo(partners[1].$2.score));
});
```

### Widget Tests
Test the survey screen:
```dart
testWidgets('survey screen shows all requesters', (tester) async {
  // Show survey for trip with Ben and Maya
  await tester.pumpWidget(SurveyScreen(tripId: 'trip_tj'));
  expect(find.text('Ben Okafor'), findsOneWidget);
  expect(find.text('Maya Iyer'), findsOneWidget);
});
```

## Next Steps

1. ✅ **Model & DemoStore** — Done (this PR)
2. ⬜ **Survey Screen** — Build post-trip rating UI
3. ⬜ **Backend Routes** — Wire experience_ratings endpoints
4. ⬜ **Recommendations UI** — Show in trip creation & ledger
5. ⬜ **Analytics** — Display compatibility in member profiles

## FAQ

**Q: Can people rate themselves?**
A: The model allows it (check `ratedById != ratedId` in the UI/backend).

**Q: What if someone doesn't submit ratings?**
A: Ratings are optional; the algorithm only considers submitted feedback.

**Q: How often should I refresh the compatibility cache?**
A: After each trip handoff is ideal. Could also batch-refresh nightly.

**Q: Can I weight recent ratings more heavily?**
A: Yes—modify `refresh_member_compatibility()` to add a time decay factor.

**Q: Does this work with multiple circles?**
A: Yes. The schema includes `circle_id` for all ratings, so compatibility is per-circle.
