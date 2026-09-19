# Updated Architecture — Supabase + Flutter

**Stack Change:**
- ❌ MongoDB + Firebase → ✅ Supabase (one dashboard)
- ❌ Next.js PWA → ✅ Flutter (native iOS/Android)

**Benefits:**
- 1 dashboard instead of 3 services
- Native mobile performance instead of web
- Faster hackathon setup
- Better realtime story (automatic)

---

## Tech Stack Comparison

### Old Stack (MongoDB + Firebase + Next.js)
```
Frontend:  Next.js PWA (React/TypeScript)
Mobile:    Browser (URLs)
Backend:   FastAPI
Database:  MongoDB Atlas
Auth:      Firebase Auth
Storage:   Firebase Storage
Realtime:  Firebase Realtime + WebSocket

Setup time: 15–20 min
Services:   4 (MongoDB, Firebase, Firebase Storage, FastAPI)
```

### New Stack (Supabase + Flutter)
```
Frontend:  Flutter (Dart)
Mobile:    Native iOS/Android
Backend:   FastAPI
Database:  Supabase (PostgreSQL)
Auth:      Supabase Auth (built-in)
Storage:   Supabase Storage (built-in)
Realtime:  Supabase Realtime (built-in)

Setup time: 5 min
Services:   2 (Supabase, FastAPI)
```

---

## What Changed

### Database
- ✅ **Postgres (Supabase)** replaces MongoDB
  - Same Pydantic models (work with Postgres via `databases` or `sqlalchemy`)
  - Same 10 tables
  - Same indexes
  - Same data structure

### Frontend
- ✅ **Flutter** replaces Next.js
  - Native app instead of web PWA
  - iOS + Android simultaneously
  - Single Dart codebase
  - Same API (FastAPI, same routes)
  - Native camera, storage, permissions
  - Better mobile UX

### Authentication
- ✅ **Supabase Auth** replaces Firebase Auth
  - Same magic link + Google OAuth
  - JWT tokens (same format)
  - Same FastAPI dependency injection pattern
  - Supabase Flutter SDK for client

### Storage
- ✅ **Supabase Storage** replaces Firebase Storage
  - S3-compatible backend
  - Same bucket structure
  - Built into Supabase dashboard

### Realtime
- ✅ **Supabase Realtime** replaces MongoDB change streams
  - Automatic Postgres NOTIFY/LISTEN
  - Flutter client: `.stream()` and `.listen()`
  - Backend: FastAPI WebSocket still works
  - No manual change stream setup

---

## API Compatibility

**No breaking changes!**

All 14 routes stay the same:
```
POST   /trips
GET    /trips/{trip_id}
PATCH  /trips/{trip_id}/status
POST   /trips/{trip_id}/requests
PATCH  /requests/{request_id}
POST   /parses
PATCH  /parses/{parse_id}/confirm
GET    /trips/{trip_id}/merged-list
POST   /trips/{trip_id}/substitutions
PATCH  /substitutions/{substitution_id}
POST   /trips/{trip_id}/receipts
PATCH  /receipts/{receipt_id}/assignments
POST   /trips/{trip_id}/handoff
GET    /circles/{circle_id}/ledger
WS     /ws/trips/{trip_id}
GET    /health
```

---

## Implementation Impact

### Backend (FastAPI)
| Change | Old | New |
|--------|-----|-----|
| Database driver | `Motor` (MongoDB async) | `supabase-py` or `databases` |
| Auth middleware | Firebase JWT | Supabase JWT (same format) |
| Realtime | Manual MongoDB change streams | FastAPI WebSocket (unchanged) |
| Models | Stored in MongoDB | Stored in Postgres |
| No other changes | Same Pydantic models, same routes | ✅ |

### Frontend (Flutter)
| Change | Old | New |
|--------|-----|-----|
| Framework | React (Next.js) | Flutter (Dart) |
| Realtime | Manual API calls + WebSocket | Supabase `.stream()` |
| Auth | Firebase SDK | Supabase Flutter SDK |
| Storage | Firebase Storage SDK | Supabase Storage SDK |
| Platform | Web browser | Native iOS/Android |

### Database
| Change | Old | New |
|--------|-----|-----|
| DBMS | MongoDB (NoSQL) | PostgreSQL (SQL) |
| Client | `pymongo`, `motor` | `supabase-py`, `databases` |
| Schema | JSON collections | SQL tables |
| Indexes | Mongo indexes | Postgres indexes |
| Data: Same | 10 tables, same structure | ✅ Same structure |

---

## File Changes

### Created
- ✅ `SETUP_SUPABASE.md` — One-stop setup guide (replaces MongoDB + Firebase guides)
- ✅ `START_HERE.md` — Updated for Supabase + Flutter
- ✅ `IMPLEMENTATION_PLAN.md` — New detailed plan (backend + frontend)
- ✅ `QUICKSTART.md` — Updated quick reference
- ✅ `UPDATED_ARCHITECTURE.md` — This file

### Updated
- ✅ `PRD.md` — Section 6 (stack)
- ✅ `docs/SPEC_v0.md` — Section 2 (tech stack), interface rules, etc.

### Removed
- ❌ `SETUP_MONGODB.md` — Not needed
- ❌ `SETUP_FIREBASE.md` — Not needed

### Backend Implementation (unchanged, ready)
- ✅ `backend/app.py` — Still works with Supabase
- ✅ `backend/shared/contracts/models.py` — Pydantic models (same)
- ✅ `backend/requirements.txt` — Add `supabase` instead of `motor`
- ✅ `backend/db/supabase_client.py` — New (replaces `mongo_client.py`)
- ✅ `backend/auth/supabase_auth.py` — New (replaces `firebase_auth.py`)

---

## Backend Migration (H0)

**Step 1: Update requirements.txt**
```diff
- motor==3.3.2
- pymongo==4.6.0
- firebase-admin==6.2.0

+ supabase==2.4.0
+ databases==0.8.0  # Optional, for async SQL
```

**Step 2: Replace MongoDB client**
```python
# OLD: db/mongo_client.py
from motor.motor_asyncio import AsyncClient

# NEW: db/supabase_client.py
from supabase import create_client, Client
```

**Step 3: Replace Firebase auth**
```python
# OLD: auth/firebase_auth.py
from firebase_admin import auth as firebase_auth

# NEW: auth/supabase_auth.py
from supabase import create_client
```

**Step 4: Update routes to use Supabase**
```python
# OLD
db = await get_db()  # MongoDB
data = await db.users.find_one({"id": user_id})

# NEW
supabase = await get_supabase()
data = supabase.table("users").select("*").eq("id", user_id).execute()
```

---

## Frontend: Flutter Setup

**New directory:**
```
favorly_mobile/
├── lib/
│   ├── main.dart             # Supabase init + MaterialApp
│   ├── screens/
│   │   ├── login_screen.dart
│   │   ├── trip_screen.dart
│   │   ├── request_screen.dart
│   │   ├── merged_list_screen.dart
│   │   ├── substitution_screen.dart
│   │   ├── settlement_screen.dart
│   │   └── ledger_screen.dart
│   ├── models/               # Generated from OpenAPI or hand-written
│   ├── services/
│   │   ├── api_service.dart  # HTTP calls to FastAPI
│   │   ├── supabase_service.dart  # Auth + Realtime
│   │   └── storage_service.dart  # Image uploads
│   └── widgets/
│       ├── trip_card.dart
│       ├── item_list.dart
│       └── settlement_card.dart
├── pubspec.yaml              # Dart dependencies
└── test/
```

**Key dependencies:**
```yaml
dependencies:
  flutter:
    sdk: flutter
  supabase_flutter: ^1.10.0
  go_router: ^13.0.0
  flutter_appauth: ^6.0.0
  image_picker: ^1.0.0
  http: ^1.1.0
  provider: ^6.0.0
```

---

## Deployment

### Backend (unchanged)
```bash
# Fly.io
fly deploy

# Railway
railway deploy

# Backend: same FastAPI deployment
```

### Frontend (new)
```bash
# iOS TestFlight
flutter build ios

# Android Play Store
flutter build apk

# Local testing
flutter run
```

---

## Demo Day (3 Phones)

**Old:** PWA → open URLs in browser
**New:** Flutter → install on 3 phones

**Advantages:**
- ✅ Native feel (not web)
- ✅ Better camera/storage access
- ✅ Offline capable
- ✅ Faster performance
- ✅ More impressive demo

**Disadvantages:**
- ⚠️ Need TestFlight/Play Store beta builds (instead of URLs)
- ⚠️ 10 min app install time (vs instant with PWA)

**Mitigation:**
- Pre-install test builds on 3 phones before demo
- Have backup physical phone with fresh install
- Cache all demo data + VLM responses

---

## Timeline Impact

| Phase | Old | New | Δ |
|-------|-----|-----|---|
| **H0–H2: Setup** | 20 min | **5 min** | **15 min faster** |
| **H2–H8: Mock screens** | 2 h | **3 h** (Flutter learning curve) | +1 h |
| **H8–H14: Real integration** | 2 h | **2 h** (same) | — |
| **H14–H18: Polish** | 2 h | **2 h** (same) | — |
| **H18–H24: Demo + test** | 2 h | **2 h** (native app testing) | — |
| **Total** | **24 h** | **24 h** | 0 (no net change) |

**Net:** Faster setup, Flutter learning curve balanced by Supabase simplicity.

---

## Checklist: What Stays the Same

- ✅ Pydantic models (15 total) — unchanged
- ✅ API routes (14 endpoints) — unchanged
- ✅ FastAPI backend — unchanged
- ✅ Data structure — unchanged
- ✅ VLM integration (Lane B) — unchanged
- ✅ Matching algorithms (Lane B) — unchanged
- ✅ Ledger & settlement logic — unchanged

## Checklist: What's Different

- ✅ Database: MongoDB → Postgres (Supabase)
- ✅ Auth: Firebase → Supabase Auth
- ✅ Storage: Firebase → Supabase Storage
- ✅ Frontend: Next.js → Flutter
- ✅ Mobile: Web (PWA) → Native (iOS/Android)
- ✅ Setup time: 20 min → 5 min

---

## Questions?

**Why Supabase over Firebase?**
- Single dashboard (auth + DB + storage + realtime)
- Postgres is simpler than Firebase Firestore for this schema
- Easier backend integration

**Why Flutter over React Native?**
- Better native performance
- Single codebase for iOS/Android
- Faster to prototype
- Simpler than React Native for this use case

**Why not keep PWA?**
- Native app is more impressive demo
- Better camera/storage access
- Flutter is designed for mobile-first
- Realtime is built-in via Supabase

---

## Next Steps

1. ✅ Review `SETUP_SUPABASE.md` (5 min)
2. ✅ Set up Supabase project (5 min)
3. ✅ Initialize database schema (1 min SQL)
4. ✅ Update backend requirements.txt
5. ✅ Create Flutter project
6. ✅ Initialize Supabase in Flutter
7. ✅ Verify `/health` endpoint
8. ✅ Start building!

See `START_HERE.md` for quick setup.
