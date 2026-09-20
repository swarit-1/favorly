# Experience System Integration Flow

## End-to-End Flow

This document shows how experience tracking flows through the entire system, from trip completion through algorithm matching.

```
┌─────────────────────────────────────────────────────────────────────┐
│                       TRIP HANDOFF FLOW                             │
└─────────────────────────────────────────────────────────────────────┘

1. SHOPPING TRIP COMPLETES
   └─ Shopper navigates to HandoffScreen
      └─ Confirms items delivered
         └─ confirmHandoff() called on DemoStore
            └─ Trip status → TripStatus.done
            └─ Ledger updated (tripsRun++, dollarsCarried+=$)
            └─ lastCompletedTripId set

2. SURVEY SCREEN APPEARS (NEW)
   └─ After handoff confirmed
      └─ Shows each requester who participated
         └─ Shopper rates on 1-5 scale
         └─ Optional: detailed ratings (reliability, accuracy, communication)
         └─ Optional: comment field
         └─ Submit button saves all ratings

3. RATINGS SUBMITTED
   └─ For each requester:
      └─ DemoStore.submitRating() creates ExperienceRating
         └─ Stores in experiences map locally
         └─ (Backend: INSERT into experience_ratings table)
      └─ POST /experiences sent to backend

4. COMPATIBILITY CACHE REFRESHED
   └─ Backend receives ratings
      └─ Triggers refresh_member_compatibility(circle_id)
      └─ Recomputes all member pairs' compatibility scores
      └─ Updates member_compatibility_cache table

┌─────────────────────────────────────────────────────────────────────┐
│                     MATCHING ALGORITHM USAGE                        │
└─────────────────────────────────────────────────────────────────────┘

WHEN CREATING A NEW TRIP:
   │
   ├─ Shopper fills in store, departure time, caps
   │
   └─ App shows "Recommended partners" (NEW)
      └─ Calls store.recommendedPartners('shopper_id')
         └─ Queries member_compatibility_cache
         └─ Finds members with highest scores
         └─ Displays top 3: "You've worked great with Ben (0.92★)"
            └─ Shopper can tap to mention/invite them

WHEN VIEWING CIRCLE:
   │
   └─ Member profile shows:
      ├─ Trips run
      ├─ Favors received
      ├─ Dollars carried
      └─ Best partners (NEW)
         └─ "Works best with: Ben (5★), Maya (4.67★)"

┌─────────────────────────────────────────────────────────────────────┐
│                         DATA STRUCTURES                             │
└─────────────────────────────────────────────────────────────────────┘

FLUTTER (lib/models/models.dart):
  └─ ExperienceRating
     ├─ id: String
     ├─ tripId: String
     ├─ ratedById: String
     ├─ ratedId: String
     ├─ overallRating: int (1-5)
     ├─ reliabilityRating?: int (1-5)
     ├─ accuracyRating?: int (1-5)
     ├─ communicationRating?: int (1-5)
     ├─ comment?: String
     └─ createdAt: DateTime

  └─ MemberCompatibility
     ├─ memberId1: String
     ├─ memberId2: String
     ├─ score: double (0.0-1.0)
     ├─ tripsWorkedTogether: int
     └─ averageRating: double (1.0-5.0)

SUPABASE:
  └─ experience_ratings table
     ├─ id (PK)
     ├─ trip_id (FK trips)
     ├─ circle_id (FK circles)
     ├─ rated_by_id (FK members)
     ├─ rated_id (FK members)
     ├─ overall_rating (1-5, NOT NULL)
     ├─ reliability_rating (1-5, nullable)
     ├─ accuracy_rating (1-5, nullable)
     ├─ communication_rating (1-5, nullable)
     ├─ comment (nullable)
     ├─ created_at
     └─ UNIQUE(trip_id, rated_by_id, rated_id)

  └─ member_compatibility_cache table
     ├─ id (PK)
     ├─ circle_id (FK circles)
     ├─ member_id_1 (FK members, < member_id_2)
     ├─ member_id_2 (FK members, > member_id_1)
     ├─ score (0.0-1.0, rounded to 2 places)
     ├─ trips_worked_together (int)
     ├─ average_rating (1.0-5.0)
     ├─ updated_at
     └─ UNIQUE(circle_id, member_id_1, member_id_2)

┌─────────────────────────────────────────────────────────────────────┐
│                         API CONTRACTS                               │
└─────────────────────────────────────────────────────────────────────┘

POST /experiences
  Request:
    {
      "trip_id": "trip_tj",
      "rated_id": "ben",
      "overall_rating": 5,
      "reliability_rating": 5,
      "accuracy_rating": 5,
      "communication_rating": 4,
      "comment": "Ben is reliable"
    }
  Response (201):
    {
      "id": "exp_123",
      "trip_id": "trip_tj",
      "rated_by_id": "ana",
      "rated_id": "ben",
      "overall_rating": 5,
      "reliability_rating": 5,
      "accuracy_rating": 5,
      "communication_rating": 4,
      "comment": "Ben is reliable",
      "created_at": "2026-09-20T12:34:56Z"
    }

GET /experiences?rated_id={memberId}
  Response (200):
    [
      { "id": "exp_123", "rated_by_id": "ana", "overall_rating": 5, ... },
      { "id": "exp_124", "rated_by_id": "chloe", "overall_rating": 4, ... }
    ]

GET /members/{id}/compatibility?circle_id={circleId}&limit=3
  Response (200):
    [
      {
        "member_id_1": "ben",
        "member_id_2": "ana",
        "score": 0.92,
        "trips_worked_together": 2,
        "average_rating": 4.8
      },
      { ... }
    ]

POST /cron/refresh-compatibility?circle_id={circleId}
  Response (200):
    {
      "status": "ok",
      "pairs_updated": 6,
      "timestamp": "2026-09-20T12:34:56Z"
    }

┌─────────────────────────────────────────────────────────────────────┐
│                        ALGORITHM SCORES                             │
└─────────────────────────────────────────────────────────────────────┘

Compatibility Score Formula:
  frequency_score = min(trips_worked_together / 3.0, 1.0) * 0.6
  quality_score = (average_rating / 5.0) * 0.4
  final_score = frequency_score + quality_score

Examples:

  Ana & Ben:
    ├─ trips_worked_together: 1
    ├─ average_rating: 5.0
    ├─ frequency_score = min(1/3, 1.0) * 0.6 = 0.333 * 0.6 = 0.2
    ├─ quality_score = (5.0/5.0) * 0.4 = 1.0 * 0.4 = 0.4
    └─ final_score = 0.2 + 0.4 = 0.6

  Maya & Chloe:
    ├─ trips_worked_together: 3
    ├─ average_rating: 4.0
    ├─ frequency_score = min(3/3, 1.0) * 0.6 = 1.0 * 0.6 = 0.6
    ├─ quality_score = (4.0/5.0) * 0.4 = 0.8 * 0.4 = 0.32
    └─ final_score = 0.6 + 0.32 = 0.92

┌─────────────────────────────────────────────────────────────────────┐
│                       CODE EXAMPLES                                 │
└─────────────────────────────────────────────────────────────────────┘

SUBMIT A RATING (in survey screen):
  ref.read(storeProvider).submitRating(
    tripId: tripId,
    ratedId: member.id,
    overallRating: 5,
    reliabilityRating: 5,
    accuracyRating: 4,
    communicationRating: 5,
    comment: 'Great work!'
  );

GET COMPATIBILITY SCORE:
  final compat = store.compatibilityScore('ana', 'ben');
  print('Score: ${compat.score}');           // 0.92
  print('Worked together: ${compat.tripsWorkedTogether} times');
  print('Avg rating: ${compat.averageRating}');

RECOMMEND PARTNERS:
  final partners = store.recommendedPartners('ana', limit: 3);
  for (final (member, compat) in partners) {
    print('${member.name}: ${compat.score} ⭐');
  }
  // Output:
  // Ben Okafor: 0.92 ⭐
  // Maya Iyer: 0.87 ⭐

GET ALL RATINGS FOR A MEMBER:
  final ratingsForBen = store.ratingsFor('ben');
  final avgRating = ratingsForBen.isEmpty
    ? 0.0
    : ratingsForBen.fold(0.0, (sum, r) => sum + r.overallRating) /
      ratingsForBen.length;
  print('Ben average rating: $avgRating/5');

┌─────────────────────────────────────────────────────────────────────┐
│                     IMPLEMENTATION CHECKLIST                        │
└─────────────────────────────────────────────────────────────────────┘

PHASE 1: Models & Demo (✅ DONE)
  ✅ ExperienceRating model added
  ✅ MemberCompatibility model added
  ✅ DemoStore methods: submitRating, ratingsFor, ratingsFrom, compatibilityScore, recommendedPartners
  ✅ Sample seed data with ratings

PHASE 2: Supabase (⬜ PENDING)
  ⬜ Create experience_ratings table
  ⬜ Create member_compatibility_cache table
  ⬜ Create refresh_member_compatibility() function
  ⬜ Set up RLS policies (if applicable)

PHASE 3: Backend API (⬜ PENDING)
  ⬜ POST /experiences — submit rating
  ⬜ GET /experiences — fetch ratings with filters
  ⬜ GET /members/{id}/compatibility — get recommended partners
  ⬜ POST /cron/refresh-compatibility — refresh cache

PHASE 4: Frontend Survey Screen (⬜ PENDING)
  ⬜ Create SurveyScreen widget
  ⬜ Show after trip handoff
  ⬜ Allow rating each requester
  ⬜ Submit ratings via API
  ⬜ Show success message

PHASE 5: Display Recommendations (⬜ PENDING)
  ⬜ Add to trip detail screen
  ⬜ Add to circle/members screen
  ⬜ Add to trip creation flow
  ⬜ Show compatibility scores

PHASE 6: Analytics & Insights (⬜ FUTURE)
  ⬜ Member profile: best partners
  ⬜ Circle analytics: most reliable members
  ⬜ Suggestions: "You should work with X more often"
