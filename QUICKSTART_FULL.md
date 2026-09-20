# Favorly - Full Stack Quick Start

Complete setup and testing guide for the full Favorly application (Backend + Frontend).

---

## Prerequisites

- Python 3.11+ (with pip or uv)
- Flutter 3.13+
- Git

---

## 1. Backend Setup (FastAPI + Supabase)

### 1a. Install Python Dependencies

```bash
cd /Users/joshuawu/favorly/backend

# Using uv (recommended)
uv sync

# OR using pip
pip install -r requirements.txt
```

### 1b. Verify .env Configuration

Check that `/Users/joshuawu/favorly/backend/.env` has your Supabase credentials:

```bash
cat backend/.env
```

Should contain (get values from your Supabase dashboard):
```
SUPABASE_URL=https://your-project-id.supabase.co
SUPABASE_KEY=your_anon_key_here
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key_here
ENVIRONMENT=development
PORT=8000
```

⚠️ **Never commit actual secrets to git!** Use `.env` file (already in .gitignore) for real credentials.

### 1c. Set Up Supabase Database Schema

Go to: https://app.supabase.com
1. Select your `favorly-demo` project
2. Go to **SQL Editor**
3. Copy-paste the schema from `SETUP_SUPABASE.md`
4. Click **Run**

This creates all 10 tables with indexes.

### 1d. Enable Realtime on Tables

In Supabase dashboard:
1. Go to **Realtime** tab
2. Click **Replication**
3. Enable for these tables:
   - `trips`
   - `items`
   - `requests`
   - `substitution_prompts`
   - `settlements`

### 1e. Seed Demo Data

```bash
cd /Users/joshuawu/favorly/backend
python seed/seed_demo.py
```

Expected output:
```
🌱 Seeding demo data...
✅ Created circle: Maple St · Building B
✅ Created user: Ana (Shopper)
✅ Created user: Bob (Requester 1)
✅ Created user: Charlie (Requester 2)
✅ Created trip: Trader Joe's
✅ Created request 1 with 3 items
✅ Created request 2 with 3 items

✅ Demo data seeded successfully!

📝 Demo Credentials:
Circle Invite Code: DEMO01

Users:
  - Ana (Shopper)
  - Bob (Requester 1)
  - Charlie (Requester 2)
```

### 1f. Run Backend Server

```bash
cd /Users/joshuawu/favorly/backend
python -m uvicorn app:app --reload --port 8000
```

Expected output:
```
🚀 Starting Favorly backend...
✅ Supabase connected
✅ All systems ready!

INFO:     Uvicorn running on http://0.0.0.0:8000
```

API documentation: http://localhost:8000/docs

---

## 2. Flutter Frontend Setup

### 2a. Install Flutter Dependencies

```bash
cd /Users/joshuawu/favorly/favorly_mobile

# Update dependencies
flutter pub get
```

### 2b. Run Flutter App

```bash
# On iOS simulator
flutter run -d macos

# On Android emulator
flutter run -d emulator-5554

# On physical device
flutter run
```

---

## 3. Test Basic Functionalities

### 3a. Sign Up (Create Account)

1. **Start on Login Screen**
   - App shows login screen

2. **Tap "Sign up"**
   - Navigate to signup form

3. **Fill signup form:**
   - Name: `Bob Test`
   - Email: `bob@example.com`
   - Password: `password123`
   - Invite Code: `DEMO01`

4. **Tap "Sign up"**
   - Account created
   - Logged in automatically
   - Redirected to Trips screen

✅ **Success**: User account created in Supabase

---

### 3b. Create a Trip

1. **On Trips Screen**
   - Tap "Post a trip" button

2. **Fill Trip Details:**
   - Store: Select "Trader Joe's" (or another)
   - When: Select a date/time in the future

3. **Tap "Post trip"**
   - Trip created in Supabase
   - Redirected to main screen

✅ **Success**: Trip appears in backend database

---

### 3c. Add a Request to a Trip

1. **On Active Trip Card**
   - Tap "Add my list"

2. **Add Items:**
   - Item 1: "Bananas" - Qty: 2 - Max Price: $3.99
   - Item 2: "Milk" - Qty: 1 - Max Price: $4.99

3. **Tap "Confirm"**
   - Request created with items
   - Items appear in merged list

✅ **Success**: Request and items stored in database

---

### 3d. View Merged List (Shopper View)

1. **Navigate to Active Trip**
   - See all requests aggregated by section
   - Shows: Item name, quantity, requester, running total

2. **Verify Data:**
   - All requested items display correctly
   - Quantities are accurate
   - Prices calculated properly

✅ **Success**: Merged list aggregates items from multiple requesters

---

## 4. API Endpoints Reference

### Auth
- `POST /auth/signup` - Create account
- `POST /auth/login` - Login

### Trips
- `POST /trips` - Create trip
- `GET /trips/{trip_id}` - Get trip details
- `GET /trips/circle/{circle_id}` - List circle trips
- `PATCH /trips/{trip_id}/status` - Update trip status

### Requests
- `POST /requests/{trip_id}` - Create request with items
- `GET /requests/{request_id}` - Get request details
- `GET /requests/trip/{trip_id}` - List trip requests
- `PATCH /requests/{request_id}/status` - Accept/decline request

### Merged List
- `GET /trips/{trip_id}/merged-list` - Get aggregated list by section

### Users
- `GET /users/{user_id}` - Get user info
- `GET /users/circle/{circle_id}` - Get circle members

---

## 5. Troubleshooting

### Backend fails to start

**Error**: `SUPABASE_URL and SUPABASE_KEY must be set`

**Fix**:
```bash
cd backend
cat .env  # Verify credentials are present
python -m uvicorn app:app --reload --port 8000
```

---

### Flutter can't connect to backend

**Error**: `Connection refused` when signing up

**Fix**:
1. Ensure backend is running on http://localhost:8000
2. Restart Flutter app: `flutter run`
3. Check backend health: `curl http://localhost:8000/health`

---

### Supabase "Table does not exist" error

**Error**: `relation "users" does not exist`

**Fix**:
1. Go to Supabase SQL Editor
2. Copy-paste the full schema from `SETUP_SUPABASE.md`
3. Click **Run**

---

### "Invalid invite code" on signup

**Error**: `Invalid invite code` in signup

**Fix**:
Use the invite code created during seeding: `DEMO01`

---

## 6. Next Steps

After successfully running basic tests:

1. **Test on real devices** - Run on iOS and Android
2. **Implement remaining features**:
   - Substitution flow (shelf photo + alternatives)
   - Receipt splitting
   - Settlement/Venmo links
   - Ledger view
3. **Add automated tests**
4. **Deploy to production**

---

## 7. Key Files

- Backend API: `backend/app.py`
- Auth Routes: `backend/routes/auth.py`
- Trip Routes: `backend/routes/trips.py`
- Request Routes: `backend/routes/requests.py`
- Merged List: `backend/routes/merged_list.py`
- Flutter Main: `favorly_mobile/lib/main.dart`
- Auth Provider: `favorly_mobile/lib/providers/auth_provider.dart`
- Trip Provider: `favorly_mobile/lib/providers/trip_provider.dart`
- API Client: `favorly_mobile/lib/services/api_client.dart`
- Login Screen: `favorly_mobile/lib/screens/login_screen.dart`
- Trips Screen: `favorly_mobile/lib/screens/trips_screen.dart`
- Post Trip Screen: `favorly_mobile/lib/screens/post_trip_screen.dart`

---

## 8. Architecture

```
favorly/
├── backend/
│   ├── app.py                    # FastAPI entry point
│   ├── shared/contracts/         # Pydantic models
│   ├── routes/
│   │   ├── auth.py              # Auth endpoints
│   │   ├── trips.py             # Trip CRUD
│   │   ├── requests.py          # Request CRUD
│   │   ├── merged_list.py       # Merged list aggregation
│   │   └── users.py             # User/circle endpoints
│   ├── seed/seed_demo.py        # Demo data seeder
│   └── requirements.txt
│
└── favorly_mobile/
    ├── lib/
    │   ├── main.dart            # App entry point
    │   ├── theme.dart           # Design tokens
    │   ├── providers/           # Riverpod state management
    │   │   ├── auth_provider.dart
    │   │   └── trip_provider.dart
    │   ├── services/
    │   │   └── api_client.dart  # HTTP client
    │   ├── screens/             # UI screens
    │   │   ├── login_screen.dart
    │   │   ├── signup_screen.dart
    │   │   ├── trips_screen.dart
    │   │   └── post_trip_screen.dart
    │   └── widgets/             # Reusable widgets
    └── pubspec.yaml
```

---

## Support

For issues:
1. Check `SETUP_SUPABASE.md` for database setup
2. Check backend health: `curl http://localhost:8000/health`
3. Check Supabase dashboard for table status
4. Review API docs: http://localhost:8000/docs
