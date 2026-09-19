# ⚡ START HERE — Lane A + C Setup (20 min)

Quick checklist to get backend (FastAPI) and frontend (Flutter) running.

---

## 🟢 Step 1: Create Supabase Project (5 min)

Go to: https://supabase.com

1. Sign in (Google or email)
2. Click "New project"
3. Name: `favorly-demo`
4. Password: `favorly_demo_123`
5. Region: **US East**
6. **Wait 2–3 min** ⏳
7. Go to **Settings** → **API**
8. Copy and save:
   - `Project URL`
   - `anon key` (public)
   - `service_role key` (secret)

✅ Save all three for Step 3

---

## 🟢 Step 2: Set Up Database Schema

In Supabase dashboard, go to **SQL Editor** and run:

```sql
-- Copy-paste the schema from SETUP_SUPABASE.md
-- Click "Run" to create all 10 tables + indexes
```

(Full SQL in `SETUP_SUPABASE.md`)

Then enable Realtime on tables (Realtime tab):
- `trips`, `items`, `requests`, `substitution_prompts`, `settlements`

---

## 🟢 Step 3: Backend Setup

```bash
cd /Users/joshuawu/favorly/backend

# Copy env template
cp .env.example .env

# Edit .env with Supabase credentials
nano .env
```

Add:
```bash
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_KEY=eyJ...  # anon key
SUPABASE_SERVICE_ROLE_KEY=eyJ...  # service role key
ENVIRONMENT=development
PORT=8000
```

Install dependencies:
```bash
uv sync  # or: pip install -r requirements.txt
```

---

## 🟢 Step 4: Run Backend

```bash
cd /Users/joshuawu/favorly/backend
python -m uvicorn app:app --reload --port 8000
```

**Expected:**
```
INFO:     Uvicorn running on http://0.0.0.0:8000
✅ Supabase connected
✅ All systems ready!
```

Test: `curl http://localhost:8000/health`
→ `{"status": "ok", "supabase": "connected"}`

---

## 🟢 Step 5: Flutter Setup

```bash
# Install Flutter (if not already)
# https://flutter.dev/docs/get-started/install

# Create Flutter project
flutter create favorly_mobile
cd favorly_mobile

# Add Supabase
flutter pub add supabase flutter_appauth go_router

# Create lib/config/supabase_config.dart
```

Add to `lib/main.dart`:
```dart
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  await Supabase.initialize(
    url: 'https://xxxxx.supabase.co',
    anonKey: 'eyJ...',
  );
  runApp(const MyApp());
}
```

---

## 🟢 Step 6: Run Flutter App

```bash
flutter run
# Choose device (iOS simulator, Android emulator, or physical phone)
```

---

## ✅ You're Done!

- ✅ Backend running on `http://localhost:8000`
- ✅ Supabase database initialized
- ✅ Flutter app ready to build screens
- ✅ API docs at `http://localhost:8000/docs`

---

## 🆘 Quick Troubleshooting

| Problem | Fix |
|---------|-----|
| "Project still initializing" | Wait 2–3 min, refresh Supabase dashboard |
| "SUPABASE_URL not set" | Check `.env` has all 3 Supabase keys |
| "RLS denies access" | Disable RLS in Supabase (Security → Policies) |
| "Flutter SDK not found" | Install: https://flutter.dev/docs/get-started/install |
| "Port 8000 in use" | Use different port: `--port 8001` |

More help? See `SETUP_SUPABASE.md`

---

## 📚 Documentation

- **Full setup:** `SETUP_SUPABASE.md`
- **Backend ref:** `QUICKSTART.md`
- **Full plan:** `LANE_A_SUMMARY.md`
- **Spec:** `docs/SPEC_v0.md`
- **PRD:** `PRD.md`
