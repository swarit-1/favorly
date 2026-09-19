# Favorly Backend — Quick Reference

FastAPI + Supabase + Flutter stack.

---

## Quick Start (20 min)

1. **Supabase Setup:** See `SETUP_SUPABASE.md` (5 min)
2. **Backend Setup:**
   ```bash
   cd backend
   cp .env.example .env
   # Edit .env with Supabase credentials
   uv sync
   python -m uvicorn app:app --reload
   ```
3. **Flutter Setup:**
   ```bash
   flutter create favorly_mobile
   cd favorly_mobile
   flutter pub add supabase flutter_appauth go_router
   # Add Supabase init to main.dart
   flutter run
   ```

---

## Backend Structure

```
backend/
├── app.py                    # FastAPI app
├── requirements.txt
├── .env.example
├── shared/contracts/
│   └── models.py            # 15 Pydantic models
├── db/
│   └── supabase_client.py   # Supabase connection
├── auth/
│   └── supabase_auth.py     # Supabase Auth
├── routes/                  # 8 endpoints (stubs)
├── realtime/
│   └── websocket_manager.py # Realtime updates
└── tests/
    └── test_contracts.py    # Model validation
```

---

## Supabase Client Setup

**Python (Backend):**
```python
from supabase import create_client, Client
import os

url = os.getenv("SUPABASE_URL")
key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
supabase: Client = create_client(url, key)

# Insert
supabase.table("users").insert({"name": "Alice", "circle_id": "..."}).execute()

# Select
data = supabase.table("users").select("*").execute()

# Realtime
realtime = supabase.realtime
```

**Dart (Flutter):**
```dart
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

// Insert
await supabase.from('users').insert({
  'name': 'Alice',
  'circle_id': '...',
});

// Select
final data = await supabase.from('users').select();

// Realtime
supabase
    .from('items')
    .stream(primaryKey: ['id'])
    .listen((data) {
      print('Realtime update: $data');
    });
```

---

## API Routes

### Trips
```
POST   /trips                    Create trip
GET    /trips/{trip_id}         Get trip
PATCH  /trips/{trip_id}/status  Update status (open→shopping→settling→done)
```

### Requests
```
POST   /trips/{trip_id}/requests      Create request (attach items)
PATCH  /requests/{request_id}         Accept/decline request
```

### Parsing (VLM Surface #1)
```
POST   /parses                   Create parse (text/photo/voice)
PATCH  /parses/{parse_id}/confirm     Confirm parsed items
```

### Merged List
```
GET    /trips/{trip_id}/merged-list   Get aisle-ordered list
```

### Substitution (VLM Surface #2)
```
POST   /trips/{trip_id}/substitutions        Create substitution prompt
PATCH  /substitutions/{substitution_id}     Choose substitute or skip
```

### Receipt Split (VLM Surface #3)
```
POST   /trips/{trip_id}/receipts            Upload + parse receipt
PATCH  /receipts/{receipt_id}/assignments   Confirm line assignments
```

### Settlement
```
POST   /trips/{trip_id}/handoff              Confirm delivery → update ledger
GET    /circles/{circle_id}/ledger           Get circle member ledger
```

### Realtime
```
WS     /ws/trips/{trip_id}                   Subscribe to live updates
```

### Health
```
GET    /health                   Verify Supabase connection
```

---

## Authentication

**Supabase Auth:**
```python
# Backend (FastAPI dependency)
from auth.supabase_auth import get_current_user

@app.post("/protected")
async def protected_route(user = Depends(get_current_user)):
    return {"user_id": user.id}
```

```dart
// Flutter
final user = supabase.auth.currentUser;
if (user != null) {
  print('Logged in: ${user.email}');
  final session = user.session;
  final token = session?.accessToken;
}
```

---

## Supabase Realtime (Dart)

Subscribe to table changes:

```dart
supabase
    .from('items')
    .stream(primaryKey: ['id'])
    .listen((data) {
      setState(() {
        items = data;
      });
    });

// Or specific filter
supabase
    .from('items')
    .stream(primaryKey: ['id'])
    .eq('trip_id', tripId)
    .listen((data) {
      print('Items updated: $data');
    });
```

---

## Environment Variables

```bash
# .env
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_KEY=eyJ...  # anon key (public)
SUPABASE_SERVICE_ROLE_KEY=eyJ...  # service role (secret)

ENVIRONMENT=development
PORT=8000
```

---

## Testing

```bash
# Validate models
pytest tests/test_contracts.py -v

# Health check
curl http://localhost:8000/health

# API docs
open http://localhost:8000/docs
```

---

## Common Issues

| Problem | Fix |
|---------|-----|
| "RLS denies access" | Disable RLS for demo (Supabase → Security → Policies) |
| "Table not found" | Run SQL migration (SETUP_SUPABASE.md) |
| "Realtime not updating" | Enable realtime on table (Supabase → Realtime tab) |
| "Auth fails" | Check `anon key` vs `service_role key` |
| "Import 'supabase' not found" | `pip install supabase` or `flutter pub add supabase` |
| "CORS error from Flutter" | Backend CORS middleware already configured |

---

## Deployment

**Backend:**
```bash
# Fly.io
fly deploy

# Railway
railway up
```

**Flutter:**
```bash
# iOS
flutter build ios

# Android
flutter build apk
```

---

## Key Differences from MongoDB

| Aspect | MongoDB | Supabase |
|--------|---------|----------|
| Setup | 3 services (MongoDB, Firebase, Firebase Storage) | 1 dashboard (Supabase) |
| Database | `db.collection.insert()` | `supabase.table().insert()` |
| Auth | Firebase Auth | Supabase Auth (built-in) |
| Realtime | Manual WebSocket + change streams | Automatic with `.stream()` |
| Storage | Firebase Storage | Supabase Storage (built-in) |
| Setup time | 15–20 min | 5 min |

---

## Supabase Dashboard

- **SQL Editor:** Run migrations and raw SQL
- **Tables:** View/edit data directly
- **Authentication:** Manage users and auth methods
- **Storage:** Upload/manage files
- **Realtime:** Enable/disable per table
- **API:** Copy connection strings and keys
- **Logs:** Check queries and errors

---

## Next: Lane B & C

**Backend is frozen by H2.** Lanes B & C can now:
- Lane B: Implement VisionService, mock responses
- Lane C: Build Flutter screens, call mock API, subscribe to Supabase Realtime

See `IMPLEMENTATION_PLAN.md` for timeline.
