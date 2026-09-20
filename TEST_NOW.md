# 🚀 Favorly - Ready to Test

All backend APIs and Flutter frontend are implemented and ready for testing!

---

## Quick Start (2 minutes)

### Step 1: Start Backend Server

```bash
cd /Users/joshuawu/favorly/backend
source venv/bin/activate
python3 -m uvicorn app:app --reload --port 8000
```

Expected output:
```
🚀 Starting Favorly backend...
✅ Supabase connected
✅ All systems ready!
INFO:     Uvicorn running on http://0.0.0.0:8000
```

### Step 2: Run Flutter App

In a new terminal:
```bash
cd /Users/joshuawu/favorly/favorly_mobile
flutter run
```

Select your device (iOS simulator, Android emulator, or physical device)

### Step 3: Test Signup Flow

1. **App launches** → Shows login screen
2. **Tap "Sign up"** → Navigate to signup form
3. **Fill in:**
   - Name: `Test User`
   - Email: `test@example.com`
   - Password: `password123`
   - Invite Code: `DEMO01`
4. **Tap "Sign up"** → Creates account → Redirects to trips screen

✅ **Expected Result:** See greeting with your name + empty trips list

---

## Test Cases

### Test 1: Create Account ✅

**Status:** 🟢 READY TO TEST

```
Flow: Signup → Validate Email → Create User → Login
Files: 
  - Backend: routes/auth.py
  - Frontend: screens/signup_screen.dart
  - State: providers/auth_provider.dart
```

**Steps:**
1. Launch Flutter app
2. Tap "Sign up"
3. Enter email, password, name, invite code "DEMO01"
4. Tap "Sign up"
5. Should see trips screen with greeting

**Expected:** New user created in Supabase `users` table

**Verify in Supabase:**
```
Go to: https://app.supabase.com
→ Project: favorly-demo
→ SQL Editor
→ SELECT * FROM users;
(Should see your new user)
```

---

### Test 2: Create Trip ✅

**Status:** 🟢 READY TO TEST

```
Flow: Select Store → Select Time → Post → Trip Appears
Files:
  - Backend: routes/trips.py
  - Frontend: screens/post_trip_screen.dart
  - State: providers/trip_provider.dart
```

**Steps:**
1. On trips screen, tap "Post a trip" button
2. Select store from dropdown (e.g., "Trader Joe's")
3. Select date/time (must be in future)
4. Tap "Post trip"
5. Should return to trips screen

**Expected:** Trip appears in "Upcoming trips" list

**Verify in Supabase:**
```
SQL: SELECT * FROM trips WHERE status = 'open';
(Should see your newly created trip)
```

---

### Test 3: Add Request to Trip ✅

**Status:** 🟢 READY TO TEST

```
Flow: Trip Created → Add Items → Submit Request → Items Stored
Files:
  - Backend: routes/requests.py
  - Frontend: screens/post_trip_screen.dart (add items form)
  - API: api_client.dart
```

**Steps:**
1. Create a trip (Test 2)
2. Tap "Add my list" on active trip card
3. Add items (example):
   - Item 1: "Bananas", Qty: 2, Price: $3.99
   - Item 2: "Milk", Qty: 1, Price: $4.99
4. Tap submit
5. Items should appear in merged list

**Expected:** Request created with items in database

**Verify in Supabase:**
```
SQL: SELECT * FROM requests;
(Should see your new request)

SQL: SELECT * FROM items WHERE request_id = '<request_id>';
(Should see your items)
```

---

### Test 4: View Merged List ✅

**Status:** 🟢 READY TO TEST

```
Flow: Trip with Multiple Requests → Aggregate → Show by Section
Files:
  - Backend: routes/merged_list.py
  - Frontend: ready to integrate
  - API: GET /trips/{trip_id}/merged-list
```

**Steps:**
1. Have multiple users add requests to same trip
2. Merged list shows all items grouped by section (produce, dairy, etc.)
3. Running totals calculated per requester
4. Caps highlighted if exceeded

**Manual API Test:**
```bash
# Get merged list directly from API
curl -s http://localhost:8000/trips/{trip_id}/merged-list | python3 -m json.tool

# Should show:
{
  "trip_id": "...",
  "sections": {
    "produce": [...],
    "dairy": [...],
    ...
  },
  "totals_by_requester": {
    "user_id": "amount"
  }
}
```

---

## API Endpoints - Quick Reference

### Auth
```bash
# Signup
curl -X POST http://localhost:8000/auth/signup \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test User",
    "email": "test@example.com",
    "password": "password123",
    "invite_code": "DEMO01"
  }'

# Login
curl -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "password123"
  }'
```

### Trips
```bash
# Create trip
curl -X POST http://localhost:8000/trips \
  -H "Content-Type: application/json" \
  -H "Authorization: User-{user_id}" \
  -d '{
    "store": "Trader Joes",
    "depart_at": "2026-09-20T15:00:00"
  }'

# List trips
curl http://localhost:8000/trips/circle/{circle_id}

# Get merged list
curl http://localhost:8000/trips/{trip_id}/merged-list
```

### Requests
```bash
# Create request
curl -X POST http://localhost:8000/requests/{trip_id} \
  -H "Content-Type: application/json" \
  -H "Authorization: User-{user_id}" \
  -d '{
    "items": [
      {
        "name": "Bananas",
        "qty": 2,
        "max_price": 3.99,
        "section": "produce"
      }
    ]
  }'

# List requests for trip
curl http://localhost:8000/requests/trip/{trip_id}

# Update request status
curl -X PATCH http://localhost:8000/requests/{request_id}/status \
  -H "Content-Type: application/json" \
  -d '{"status": "accepted"}'
```

---

## API Documentation

Once backend is running:
👉 **http://localhost:8000/docs**

Interactive Swagger UI with:
- All endpoints listed
- Try it out feature
- Request/response examples
- Schema definitions

---

## Troubleshooting

### Backend won't start

**Error:** "Address already in use"
```bash
# Kill existing process
pkill -f "uvicorn"
# Then restart
source venv/bin/activate
python3 -m uvicorn app:app --reload --port 8000
```

### "Connection refused" in Flutter

**Error:** Backend not accessible
1. Check backend is running: `curl http://localhost:8000/health`
2. Check network settings on device/emulator
3. Make sure using `localhost` (not IP) if on same machine

### "Table does not exist" error

**Error:** Database schema not created
1. Go to Supabase dashboard
2. SQL Editor
3. Copy schema from `SETUP_SUPABASE.md`
4. Click Run

### Demo data not showing up

**Error:** Seed script didn't run
```bash
cd backend
python3 seed/seed_demo.py
```

Should output:
```
✅ Created circle: Maple St · Building B
✅ Created user: Ana (Shopper)
✅ Created user: Bob (Requester 1)
✅ Created user: Charlie (Requester 2)
✅ Created trip: Trader Joe's
```

---

## Demo Data

**Circle:** Maple St · Building B
**Invite Code:** `DEMO01`

**Pre-loaded Users:**
- Ana (Shopper)
- Bob (Requester 1)
- Charlie (Requester 2)

**Sample Trip:**
- Store: Trader Joe's
- Time: 2 hours from now
- Items: 6 pre-loaded from Bob and Charlie

---

## What's Implemented

### ✅ Backend
- Auth (signup/login with email)
- Trip CRUD (create, read, list, update status)
- Request CRUD (create, read, list, update status)
- Items (create, update, status tracking)
- Merged list aggregation by section
- Full validation with Pydantic models
- Error handling with proper HTTP status codes

### ✅ Frontend
- Login/signup screens with form validation
- Auth state management (Riverpod)
- Trip creation flow with date/time picker
- Trips list showing active and upcoming
- User greeting and navigation
- API client with all endpoints
- Error display and user feedback

### ✅ Database
- 10 tables with proper relationships
- Indexes for performance
- Realtime enabled on core tables
- Proper data types (UUID, Decimal, JSONB)

---

## Next Steps After Testing

1. **Test all flows** using Test Cases above
2. **Verify data** in Supabase dashboard
3. **Check API docs** at http://localhost:8000/docs
4. **Report any issues** or blockers

Once basic flows work:
- Implement substitution flow (Phase 2)
- Implement receipt splitting (Phase 2)
- Add voice input (Phase 2)
- Add ledger/history (Phase 2)

---

## Files to Reference

- **Backend Main:** `backend/app.py`
- **Backend Routes:** `backend/routes/*.py`
- **Frontend Main:** `favorly_mobile/lib/main.dart`
- **API Client:** `favorly_mobile/lib/services/api_client.dart`
- **Auth Screens:** `favorly_mobile/lib/screens/login_screen.dart`, `signup_screen.dart`
- **Trips Screen:** `favorly_mobile/lib/screens/trips_screen.dart`
- **Trip Creation:** `favorly_mobile/lib/screens/post_trip_screen.dart`

---

## System Status

```
✅ Backend: Ready (python -m uvicorn app:app --reload --port 8000)
✅ Frontend: Ready (flutter run)
✅ Database: Connected to Supabase
✅ Demo Data: Ready (DEMO01 invite code)
✅ API Docs: Available at /docs
✅ Tests: Ready to run

🟢 ALL SYSTEMS GO!
```

---

## Start Testing Now!

1. Start backend → `cd backend && source venv/bin/activate && python3 -m uvicorn app:app --reload --port 8000`
2. Start Flutter → `cd favorly_mobile && flutter run`
3. Signup with invite code `DEMO01`
4. Create a trip
5. Verify in Supabase dashboard

**Expected time to run basic tests: 5 minutes** ⏱️

Let me know if you hit any blockers! 🚀
