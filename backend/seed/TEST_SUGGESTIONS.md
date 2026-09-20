# Testing Trip Suggestions

## Problem
The trip suggestions feature returns empty results because the test data only has one shopper (Ana) creating trips. The algorithm looks for requests on **OTHER people's trips**, not requests on your own trip.

## Solution
Run the test data script to create a proper multi-shopper scenario:

```bash
cd /Users/joshuawu/favorly/backend
python seed/test_trip_suggestions.py
```

This creates:
- **Ana's Trader Joe's trip** with requests from Ben & Chloe
- **Ben's Trader Joe's trip** ← Will show Ana & Chloe's requests
- **Chloe's CVS trip** ← Will show Maya's requests

## How It Works

The endpoint `GET /trips/{trip_id}/suggestions` searches for:
1. All **other open trips** in the same circle
2. **Pending requests** on those other trips
3. **Score** them against your trip's store
4. **Return** top 5 with AI nudges

```
User A creates Trip 1 → Algorithm looks for requests on Trip 2, Trip 3, etc.
User B creates Trip 2 → Endpoint returns requests from Trip 1 (from User A)
```

## Testing Manually

1. Create the test data:
   ```bash
   python seed/test_trip_suggestions.py
   ```

2. Create a trip (as any user in the circle):
   ```bash
   POST http://localhost:8000/trips
   {
     "store": "Trader Joe's",
     "depart_at": "2026-09-20T20:00:00",
     "caps": {"max_requesters": 6, "max_dollars_per_person": 40}
   }
   ```

3. Check suggestions with the returned trip ID:
   ```bash
   GET http://localhost:8000/trips/{trip_id}/suggestions
   ```

## Expected Results

If you create a trip as Ben (who has requests on Ana's trip), you should see:
- Ana & Chloe's items
- AI nudges like "Good fit — Dark Chocolate, Organic Spinach is likely at Trader Joe's."

## Key Insight

**You need multiple different users creating trips** for suggestions to work. The feature shows cross-circle collaboration:
- I'm going to store X
- Here's what my neighbors need from store X
- Should I pick it up for them?
