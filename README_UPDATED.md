# Favorly — Updated Stack (Supabase + Flutter)

**A neighbor posts "I'm going shopping at 3." Neighbors attach requests. One trip carries the whole building.**

---

## 📖 Documentation Index

**Start with these (in order):**

1. **[START_HERE.md](START_HERE.md)** ⭐ **← BEGIN HERE**
   - 20-minute quick setup
   - Supabase project creation
   - Backend & Flutter initialization
   - 4 simple steps to running code

2. **[SETUP_SUPABASE.md](SETUP_SUPABASE.md)**
   - Detailed Supabase walkthrough
   - Database schema setup
   - Environment variables
   - Troubleshooting

3. **[IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)**
   - Full 24-hour timeline
   - Lane breakdown (A: Backend, B: AI, C: Flutter, D: Demo)
   - Success criteria
   - Parallel work structure

4. **[QUICKSTART.md](QUICKSTART.md)**
   - Backend API reference
   - Supabase client usage
   - Flutter integration examples
   - Common issues & fixes

5. **[UPDATED_ARCHITECTURE.md](UPDATED_ARCHITECTURE.md)**
   - Architecture comparison (MongoDB → Supabase, Next.js → Flutter)
   - What stayed the same (API, models)
   - What changed (database, frontend)
   - Migration path if needed

6. **[CHANGES_SUMMARY.md](CHANGES_SUMMARY.md)**
   - Stack update summary
   - Why Supabase + Flutter
   - What you get vs. old stack
   - Timeline comparison

7. **[DELIVERY_SUMMARY.md](DELIVERY_SUMMARY.md)**
   - What's been delivered
   - What's ready vs. what's next
   - Project structure
   - Verification checklist

8. **[PRD.md](PRD.md)**
   - Product requirements
   - Core loop (24-minute demo)
   - Feature requirements
   - Success criteria

9. **[docs/SPEC_v0.md](docs/SPEC_v0.md)**
   - Engineering specification
   - Data models (Pydantic)
   - Database schema
   - API routes
   - Matching algorithms

---

## 🚀 Quick Start (20 minutes)

```bash
# 1. Follow SETUP_SUPABASE.md (5 min)
# Create Supabase project and database

# 2. Backend setup (5 min)
cd backend
cp .env.example .env
# Edit .env with Supabase credentials
uv sync
python -m uvicorn app:app --reload

# 3. Flutter setup (5 min)
flutter create favorly_mobile
cd favorly_mobile
flutter pub add supabase flutter_appauth go_router
flutter run

# 4. Verify (5 min)
# ✅ Backend at http://localhost:8000
# ✅ Flutter app runs
```

---

## 📊 What's Delivered

### ✅ Backend (FastAPI + Supabase)
- 15 Pydantic models (frozen)
- 14 API routes + WebSocket (stubs)
- 10 Supabase tables + indexes
- Supabase Auth integration
- Realtime WebSocket manager
- Model validation tests
- Complete documentation

### ✅ Frontend (Flutter - Ready to Build)
- Flutter project scaffolding
- Supabase Flutter SDK integration
- 7 main screens to implement
- Complete API documentation
- Code examples

### ✅ Documentation
- 9 complete guides
- Architecture diagrams
- Implementation timeline
- API reference
- Setup instructions

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────┐
│         Flutter Mobile (iOS/Android)        │
│  • Login screen (Supabase Auth)             │
│  • Trip creation, request entry             │
│  • Merged list view, substitution chooser   │
│  • Settlement screen, ledger view           │
│  • Real-time updates (Supabase Realtime)    │
└──────────────────┬──────────────────────────┘
                   │ REST + WebSocket
                   ↓
┌─────────────────────────────────────────────┐
│       FastAPI Backend (Python 3.11)         │
│  • 14 REST endpoints                        │
│  • WebSocket for realtime                   │
│  • Pydantic models (frozen)                 │
│  • 15 total models                          │
└──────────────────┬──────────────────────────┘
                   │ SQL queries
                   ↓
┌─────────────────────────────────────────────┐
│   Supabase (PostgreSQL + Services)          │
│  • 10 tables + 1 cache table                │
│  • Auth (magic link, Google)                │
│  • Storage (images)                         │
│  • Realtime (auto-sync)                     │
│  • One dashboard, one login                 │
└─────────────────────────────────────────────┘
```

---

## 📋 Development Phases

### H0–H2: Setup ✅ Done
- Pydantic models (15)
- Supabase schema (10 tables)
- FastAPI app (14 routes)
- Documentation (complete)

### H2–H8: Parallel Build
- **Lane B:** VisionService (LLM parsing)
- **Lane C:** Flutter screens
- **Lane D:** Demo data + images

### H8–H14: Real Integration
- Real Muse Spark API
- Flutter calls real backend
- Cached responses for demo beats

### H14–H18: Matching + Settlement
- Receipt line assignment algorithm
- Settlement calculation
- Venmo deep-link generation

### H18–H24: Demo
- 3 phones end-to-end test
- Cached fallbacks verified
- Polish + rehearsals

---

## 💾 Stack Summary

| Layer | Tech | Why |
|-------|------|-----|
| Frontend | Flutter 3.x (Dart) | Native iOS/Android, single codebase |
| Backend | FastAPI (Python 3.11) | Pydantic models, async, performant |
| Database | Supabase (PostgreSQL) | One dashboard, built-in auth + storage + realtime |
| Auth | Supabase Auth | Magic link, Google OAuth, JWT |
| Storage | Supabase Storage | S3-backed, built-in |
| Realtime | Supabase Realtime | Postgres NOTIFY/LISTEN, automatic |
| VLM | Meta Muse Spark + OpenAI | Structured output, fallback chain |

---

## 📁 Project Structure

```
favorly/
├── START_HERE.md ⭐ BEGIN HERE
├── SETUP_SUPABASE.md
├── IMPLEMENTATION_PLAN.md
├── QUICKSTART.md
├── UPDATED_ARCHITECTURE.md
├── CHANGES_SUMMARY.md
├── DELIVERY_SUMMARY.md
├── README_UPDATED.md ← You are here
├── PRD.md
│
├── docs/
│   └── SPEC_v0.md
│
└── backend/
    ├── app.py
    ├── requirements.txt
    ├── .env.example
    ├── .gitignore
    ├── shared/contracts/
    │   └── models.py ← 15 Pydantic models (frozen)
    ├── db/
    │   └── supabase_client.py (NEW)
    ├── auth/
    │   └── supabase_auth.py (NEW)
    ├── realtime/
    │   └── websocket_manager.py
    ├── routes/ ← 14 endpoints
    ├── storage/
    ├── seed/
    │   ├── demo_circle.json
    │   └── seed_demo.py
    └── tests/
        └── test_contracts.py
```

---

## ✅ Before You Start

- [ ] Read `START_HERE.md` (5 min)
- [ ] Have Supabase account (free at supabase.com)
- [ ] Have Flutter SDK installed (flutter.dev)
- [ ] Have Python 3.11+ installed
- [ ] Have 20 minutes for setup

---

## 🎯 Success = Full Loop in 3 Phones

**Demo beat (2.5 minutes):**

1. Phone A posts "Trader Joe's at 3" (voice)
2. Phone B types list; Phone C photographs handwritten list
3. Both parse → A sees merged aisle-ordered list
4. A snaps shelf photo → C picks substitute live
5. A snaps receipt → B & C see itemized splits with Venmo links
6. Handoff photo → ledger updates

**Every beat < 20 seconds. All with cached fallbacks.**

---

## 📞 Need Help?

1. **Setup issues?** → `SETUP_SUPABASE.md` troubleshooting
2. **API questions?** → `QUICKSTART.md` reference
3. **Architecture?** → `UPDATED_ARCHITECTURE.md`
4. **Timeline/planning?** → `IMPLEMENTATION_PLAN.md`
5. **Everything?** → `START_HERE.md` step-by-step

---

## 🎉 Ready!

**Next step:** Open `START_HERE.md` and follow the 4 steps.

All frozen contracts are ready. Lanes B, C, and D can start immediately.

---

**Stack:** Supabase + Flutter + FastAPI
**Status:** ✅ Ready for 24-hour sprint
**Delivered:** Complete documentation + backend contracts
