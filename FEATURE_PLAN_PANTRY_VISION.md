# Favorly v1: Pantry Vision & Smart Shopping Preferences

**Feature Goal:** Enable users to photograph their fridge/pantry and automatically generate shopping list suggestions. Learn user preferences (brands, sizes, types) and surface smarter requests based on consumption patterns and store availability.

---

## 1. Executive Summary

**The Problem:**
- Users spend 5+ minutes manually typing shopping lists for every trip
- Requesters have no way to express "I like Organic Valley milk" vs "any milk" vs "lactose-free"
- With product varieties (20 SKUs of yogurt), shoppers face endless substitution friction
- No signal on what people actually consume regularly

**The Solution (3-Part):**
1. **Pantry Vision** — Photo of your fridge/pantry → VLM detects products → auto-fills request with what you're low on
2. **Preference Learning** — Track what brands/sizes/types you pick when offered substitutes → build a preference profile
3. **Smart Store Matching** — When posting a trip to Store A, surface "popular with you" items in stock there + warn when your preferred brands are rare at that store

**Value Proposition:**
- Request entry time: 5 min → 30 seconds (tap photo, accept suggestions, done)
- Substitution friction: Shopper sees "Charlie prefers Organic Valley milk" vs guessing
- Better trip matching: Requesters say "going to Trader Joe's? I need their yogurt" instead of "milk" (implicit store preference)
- Serendipity: "You bought almond butter twice last month; TJ's has a sale" → enables smart trip suggestions

---

## 2. Three Core Capabilities

### 2.1 Pantry Vision (Photo → Auto-List)

**User Flow:**
1. User taps "Scan fridge" in request creation screen
2. Takes 2–4 quick photos of fridge/pantry shelves
3. VLM processes all photos → returns structured list: `{name, qty, brand, size, status: 'have'|'low'|'empty'}`
4. User reviews, edits, marks which items they want to request
5. System auto-calculates: "You photographed Organic Valley milk (full), Dannon yogurt (low), no cheese" → suggests "add Greek yogurt to your request"

**Technical Implementation:**
- Multi-image VLM prompt: "Analyze these fridge photos. For each product, identify: name, brand, size, visible quantity (full/half/low/empty), expiration date if visible"
- Structured output schema:
  ```json
  {
    "detected_items": [
      {
        "name": "Milk",
        "brand": "Organic Valley",
        "size": "Half gallon",
        "status": "half",
        "expiration": "2026-09-28",
        "confidence": 0.95,
        "image_index": 0
      },
      ...
    ],
    "low_or_empty": ["Milk", "Yogurt", "Cheese"],
    "inventory_summary": "Fridge: 12 items, about 40% full"
  }
  ```
- Frontend: Photo carousel with item overlay annotations (VLM-tagged products highlighted)
- User selects which detected items to request (checkbox per item)
- Optional: Generate smart suggestion: "You're low on: Milk, Yogurt. Want to add these to your request?"

---

### 2.2 Preference Learning (Substitution → Profile)

**What We're Learning:**
Every time a user accepts a substitution, we capture preference signal:
```
Original request: "Yogurt"
Offered alternatives: [Fage, Dannon, Chobani, store brand]
User picked: "Fage (Greek)"
→ Preference signal: user prefers Greek yogurt, brand=Fage
```

Over time (3–5 substitutions in the category), we infer:
- Preferred brand(s)
- Preferred type (Greek yogurt vs regular vs skyr)
- Price sensitivity (if they always pick budget option vs premium)
- Dietary flags (gluten-free, organic, non-GMO if pattern emerges)

**Data Model:**

```sql
-- New table: user_preferences
CREATE TABLE user_preferences (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  category TEXT,  -- "yogurt", "milk", "cheese", "bread", etc.
  preferred_brand TEXT,
  preferred_type TEXT,  -- "Greek", "Icelandic", "regular", etc.
  preferred_size TEXT,  -- "large", "individual", "6-pack", etc.
  confidence NUMERIC(3,2),  -- 0.0-1.0, based on # times picked
  price_tier TEXT,  -- "budget", "mid", "premium"
  last_updated TIMESTAMP,
  created_at TIMESTAMP,
  UNIQUE(user_id, category, preferred_brand)
);

-- New table: substitution_feedback
CREATE TABLE substitution_feedback (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  original_item_id UUID NOT NULL REFERENCES items(id),
  offered_alternatives JSONB,  -- [{name, brand, price}, ...]
  selected_alternative JSONB,  -- {name, brand, price, category}
  feedback_timestamp TIMESTAMP,
  created_at TIMESTAMP
);
```

**Workflow:**
1. Shopper snapshots shelf → VLM returns 3–4 candidates for "yogurt"
2. Requester sees: [Fage $8.99] [Dannon $5.49] [Chobani $6.99] [Store brand $3.99]
3. Requester taps "Fage" → system logs `substitution_feedback` row
4. After 3+ picks of Fage, system upserts `user_preferences` with brand=Fage, confidence=0.75
5. Next trip: shopper's VLM substitution prompt includes "Charlie prefers Fage yogurt (75% confidence)" → when shelf is out, VLM prioritizes Fage alternatives

---

### 2.3 Smart Store Matching & Trip Advisories

**Capability 1: Preference-Aware Substitution Hints**

When shopper posts trip to Store A:
- System queries: "What do my requesters prefer? What's available at this store?"
- Example: Trip to Trader Joe's posted
  - Charlie's profile: prefers Fage yogurt (75%), organic milk (80%)
  - TJ's inventory: has Fage (yes), has organic milk (yes)
  - Alert to shopper: "Charlie's usual preferences are well-stocked at TJ's"

**Capability 2: Trip Recommendation**

When Requester sees list of upcoming trips, highlight store-preference matches:
- Charlie sees 3 upcoming trips: [Trader Joe's] [Whole Foods] [Safeway]
- At each store, surface "Popular items in stock for you":
  - TJ's: Fage, Organic Valley milk, Almond butter ✓ in stock
  - Whole Foods: Fage, Organic Valley ✓ in stock
  - Safeway: Store brand yogurt (Fage not usually in stock)
- Charlie can now say "going to TJ's? I'd love [yogurt, milk]" instead of generic "dairy"

**Capability 3: Build-In Store Preference**

```sql
CREATE TABLE store_preferences (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  store_id UUID NOT NULL REFERENCES stores(id),  -- "Trader Joe's", "Whole Foods", etc.
  preference_score NUMERIC(3,2),  -- derived from: past trips, successful substitutions at this store
  notes TEXT,  -- user's own note: "they have better yogurt selection", "closer to me"
  last_shopped_at TIMESTAMP,
  created_at TIMESTAMP
);
```

**Derivation:**
- Whenever a trip completes at Store X and Charlie requests items successfully → increment store preference score for Store X
- When substitutions go smoothly at Store X → boost score
- When Charlie rejects items or items are out of stock at Store X → reduce score
- Display: "You've had great luck at Trader Joe's (4.5 stars based on your 8 trips)"

---

## 3. Integrated User Flows

### Flow A: Request Creation (Requester POV)

**Status Quo (v0):**
```
Tap "Add my list" → Manual text input → Type "milk, yogurt, bread" → Review → Submit
Time: 2–5 minutes
```

**New Flow (v1):**
```
Tap "Add my list"
  ↓
[Option A: Scan Fridge] ← NEW
  Take 2–4 quick photos
  VLM: "Detected milk (low), yogurt (empty), cheese (full)"
  Toggle items to request: [✓ milk] [✓ yogurt] [ cheese]
  Optional: Edit quantities, add notes
  Submit
  Time: 1 minute
  ↓
OR [Option B: Smart Suggestions] ← NEW
  "Based on your preferences & recent requests:"
  Suggested items: [Fage yogurt — you love this] [Organic Valley milk — bestseller for you]
  Toggle to add or skip
  ↓
OR [Option C: Manual (v0 behavior)]
  Type freely
  ↓
[View preferences overlay on each item]
  "Fage yogurt (80% of your yogurt choices)" ← shows your brand preference
  If shopper posts trip to store, cross-check: "Fage usually available at TJ's ✓"
```

### Flow B: Substitution with Preferences (Shopper POV)

**Status Quo (v0):**
```
Shopper snaps shelf: "yogurt section (no Fage)"
VLM returns: [Dannon $5.49] [Chobani $6.99] [Store brand $3.99]
Shopper has NO IDEA which Charlie prefers
Guess wrong → Charlie declines substitute → back to square one
```

**New Flow (v1):**
```
Shopper snaps shelf: "yogurt section (no Fage)"
VLM returns: [Dannon $5.49] [Chobani $6.99] [Store brand $3.99]
  + Charlie's preference layer:
    "Charlie's usual brand (Fage) not found.
     Best alternatives:
     [✓ Chobani $6.99] — Charlie picked this 40% of the time when Fage unavailable
     [ Dannon $5.49]
     [ Store brand $3.99]"
Shopper taps Chobani → high likelihood Charlie accepts
Requester gets prompt: "Original: Fage. Available: Chobani. Accept? [✓ Yes] [✗ No]"
Charlie taps Yes → substitution accepted, preference confidence updated (now 0.80)
```

### Flow C: Store Trip Advisory (Requester POV)

**Status Quo (v0):**
```
New trip posted: "Whole Foods at 5pm"
Requester sees: Store name, time, caps
Requester requests: generic items → some hit, some miss depending on store inventory
```

**New Flow (v1):**
```
New trip posted: "Whole Foods at 5pm"
Requester taps to view details
  ↓
[Store preference badge]
  "Your track record at Whole Foods: ★★★★☆ (4 stars, 8 successful trips)"
  "Your frequent items in stock: Fage yogurt ✓, Organic Valley milk ✓"
  ↓
[Smart suggestion]
  "Want to add your usual dairy items?"
  Suggested: [✓ Fage yogurt] [✓ Organic Valley milk] [ Other]
  ↓
Requester toggles on → auto-populated request with quantities based on consumption history
Time: 30 seconds
```

---

## 4. Data Model Additions

### New Tables

```sql
-- Preference tracking
CREATE TABLE user_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  category TEXT NOT NULL,  -- "yogurt", "milk", "bread", etc.
  preferred_brand TEXT,
  preferred_type TEXT,
  preferred_size TEXT,
  price_tier TEXT,  -- "budget" | "mid" | "premium"
  confidence NUMERIC(3,2) DEFAULT 0.0,  -- 0.0-1.0
  last_updated TIMESTAMP DEFAULT now(),
  created_at TIMESTAMP DEFAULT now(),
  UNIQUE(user_id, category, preferred_brand)
);

-- Pantry snapshots (for future analytics)
CREATE TABLE pantry_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  snapshot_date DATE DEFAULT today(),
  detected_items JSONB,  -- VLM output: [{name, brand, size, status, expiration}, ...]
  image_refs JSONB,  -- [{image_id, storage_path}, ...]
  created_at TIMESTAMP DEFAULT now()
);

-- Substitution feedback (learning signal)
CREATE TABLE substitution_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  original_request TEXT,  -- "Yogurt"
  offered_alternatives JSONB,  -- [{name, brand, price}, ...]
  selected_alternative JSONB,  -- {name, brand, price}
  feedback_timestamp TIMESTAMP,
  created_at TIMESTAMP DEFAULT now()
);

-- Store preferences (user's track record)
CREATE TABLE store_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  store TEXT NOT NULL,  -- "Trader Joe's", "Whole Foods", etc.
  total_trips INT DEFAULT 0,
  successful_requests INT DEFAULT 0,  -- requests fulfilled as-is (no substitutions needed)
  substitution_acceptance_rate NUMERIC(3,2),  -- % of offered substitutions accepted
  preference_score NUMERIC(3,2),  -- derived: (successful_requests * 0.7 + substitution_acceptance_rate * 0.3)
  last_shopped_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT now(),
  UNIQUE(user_id, store)
);

-- Consumption hints (optional, for v1.1: trip advisor)
CREATE TABLE consumption_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  category TEXT,  -- "yogurt", "milk", "bread"
  quantity_avg NUMERIC(5,2),  -- e.g., "1.2" cartons per week
  frequency_days INT,  -- e.g., every 7 days
  last_bought TIMESTAMP,
  created_at TIMESTAMP DEFAULT now()
);
```

### Updated Tables

**items table** - Add preference context:
```sql
ALTER TABLE items ADD COLUMN user_preferred_brand TEXT;  -- denormalized from preferences for fast lookup
ALTER TABLE items ADD COLUMN brand TEXT;  -- parse from VLM request parsing
ALTER TABLE items ADD COLUMN category TEXT;  -- e.g., "yogurt", "milk" for preference matching
```

**requests table** - Add source tracking:
```sql
ALTER TABLE requests ADD COLUMN intake_source TEXT DEFAULT 'manual';  -- 'manual' | 'pantry_vision' | 'smart_suggestion'
ALTER TABLE requests ADD COLUMN pantry_snapshot_id UUID REFERENCES pantry_snapshots(id);
```

---

## 5. Technical Architecture

### Backend Services

#### 5.1 Pantry Vision Service
```python
# routes/pantry_vision.py

@router.post("/pantry-scan")
async def scan_pantry(
    user_id: str,
    images: List[UploadFile]  # 2-4 fridge/pantry photos
) -> PantryVisionResponse:
    """
    1. Upload images to Supabase Storage
    2. Call VLM with multi-image prompt
    3. Parse structured output
    4. Save pantry_snapshot
    5. Return detected items for user confirmation
    """
    storage_paths = await upload_images_to_supabase(images)
    
    vlm_prompt = """Analyze these fridge/pantry photos. For each visible product, 
    identify: product name, brand, size, visible quantity (full/half/low/empty), 
    expiration date if visible. Return as JSON."""
    
    visions = await meta_muse.analyze_images(storage_paths, vlm_prompt)
    
    snapshot = await db.create_pantry_snapshot(
        user_id=user_id,
        detected_items=visions["detected_items"],
        image_refs=storage_paths
    )
    
    return {
        "snapshot_id": snapshot.id,
        "detected_items": visions["detected_items"],
        "low_or_empty": visions["low_or_empty"],
        "suggestions": generate_smart_suggestions(user_id, visions)
    }

@router.post("/requests/{trip_id}/from-pantry")
async def create_request_from_pantry(
    user_id: str,
    trip_id: str,
    snapshot_id: str,
    selected_items: List[str]  # User-selected product names
) -> Request:
    """Convert pantry scan into actual request"""
    snapshot = await db.get_pantry_snapshot(snapshot_id)
    selected = [i for i in snapshot.detected_items if i["name"] in selected_items]
    
    items = [
        Item(
            name=i["name"],
            brand=i["brand"],
            qty=infer_quantity(i["status"], category=infer_category(i["name"])),
            category=infer_category(i["name"]),
            source="pantry_vision"
        )
        for i in selected
    ]
    
    request = await db.create_request(trip_id, user_id, items)
    return request
```

#### 5.2 Preference Engine
```python
# services/preference_engine.py

async def log_substitution_feedback(
    user_id: str,
    item_id: str,
    original: str,
    alternatives: List[Dict],
    selected: Dict
) -> None:
    """Record substitution choice → update preference profile"""
    
    await db.create_substitution_feedback(
        user_id=user_id,
        item_id=item_id,
        original_request=original,
        offered_alternatives=alternatives,
        selected_alternative=selected
    )
    
    category = infer_category(selected["name"])
    brand = selected.get("brand")
    
    # Upsert preference (incremental learning)
    await db.upsert_user_preference(
        user_id=user_id,
        category=category,
        preferred_brand=brand,
        confidence=await calculate_confidence(user_id, category, brand)
    )

async def calculate_confidence(user_id: str, category: str, brand: str) -> float:
    """
    Confidence = (times_selected / times_offered) in this category
    E.g., user picked Fage 3 times out of 5 yogurt substitutions → 0.60
    """
    feedback = await db.get_substitution_feedback(user_id, category)
    selected_count = sum(1 for f in feedback if f["selected_alternative"]["brand"] == brand)
    return min(selected_count / len(feedback), 1.0) if feedback else 0.0

async def get_user_preferences(user_id: str) -> Dict[str, UserPreference]:
    """Return all learned preferences for a user"""
    prefs = await db.get_user_preferences(user_id)
    return {p.category: p for p in prefs}
```

#### 5.3 Store Preference Tracker
```python
# services/store_preferences.py

async def update_store_preference_on_trip_complete(
    user_id: str,
    trip_id: str,
    store: str
) -> None:
    """
    Increment store preference after trip settles:
    - +1 total_trips
    - +1 successful_requests for each request that required 0 substitutions
    - Track substitution_acceptance_rate
    - Recalculate preference_score
    """
    trip = await db.get_trip(trip_id)
    requests = await db.get_requests_for_trip(trip_id, requester_id=user_id)
    
    successful = sum(
        1 for req in requests 
        if all(item.status != "substituted" for item in req.items)
    )
    
    store_pref = await db.get_or_create_store_preference(user_id, store)
    
    await db.update_store_preference(
        store_pref.id,
        total_trips=store_pref.total_trips + 1,
        successful_requests=store_pref.successful_requests + successful,
        substitution_acceptance_rate=calculate_acceptance_rate(requests),
        preference_score=calculate_preference_score(
            successful / len(requests) if requests else 0,
            calculate_acceptance_rate(requests)
        ),
        last_shopped_at=now()
    )

def calculate_preference_score(success_rate: float, substitution_rate: float) -> float:
    """
    Weighted score: items you got as-requested (70%) + smooth substitutions (30%)
    Higher = better experience at that store
    """
    return success_rate * 0.7 + substitution_rate * 0.3
```

#### 5.4 Smart Suggestion Engine
```python
# services/smart_suggestions.py

async def suggest_items_for_trip(
    user_id: str,
    trip_id: str
) -> List[SuggestionItem]:
    """
    When user views an upcoming trip:
    1. Get store name
    2. Get user's preference profile
    3. Get store's inventory (or inferred from past availability)
    4. Rank items by: (preference_confidence * 0.6) + (in_stock_likelihood * 0.4)
    5. Return top 5–8 suggestions
    """
    trip = await db.get_trip(trip_id)
    preferences = await get_user_preferences(user_id)
    store = trip.store
    
    suggestions = []
    for category, pref in preferences.items():
        # Infer: "did this brand usually exist at this store?"
        in_stock_likelihood = await infer_in_stock_likelihood(store, pref.preferred_brand)
        
        score = pref.confidence * 0.6 + in_stock_likelihood * 0.4
        
        suggestions.append(SuggestionItem(
            name=f"{pref.preferred_brand} {category}",
            category=category,
            confidence=pref.confidence,
            in_stock_likelihood=in_stock_likelihood,
            rank_score=score,
            note=f"You pick {pref.preferred_brand} {pref.confidence*100:.0f}% of the time"
        ))
    
    return sorted(suggestions, key=lambda s: s.rank_score, reverse=True)[:8]

async def infer_in_stock_likelihood(store: str, brand: str) -> float:
    """
    Query historical data: how often does this store carry this brand?
    E.g., Trader Joe's always has Fage (0.99), Safeway rarely has Fage (0.30)
    Use substitution_feedback + store_inventory patterns
    """
    historical = await db.query_historical_availability(store, brand)
    if not historical:
        return 0.5  # Unknown: neutral guess
    return historical["available_count"] / historical["total_trips"]
```

### Frontend Integration

#### 5.5 Flutter Screens

**Pantry Vision Scanner:**
```dart
class PantryVisionScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text("Scan Your Fridge")),
      body: Column(
        children: [
          // Photo carousel (2-4 images)
          PhotoCarousel(onPhotosSelected: (photos) {
            ref.read(pantryProvider).scanPantry(photos);
          }),
          
          // VLM-parsed results with overlay annotations
          PantryResultsList(
            items: ref.watch(pantryProvider).detectedItems,
            onToggle: (item, selected) {
              // User checks/unchecks items to include in request
            }
          ),
          
          // Smart suggestions ("You're low on...")
          SuggestionsCard(
            suggestions: ref.watch(pantryProvider).suggestions
          ),
          
          PillButton(
            label: "Add to Request",
            onPressed: () => createRequestFromPantry()
          )
        ]
      )
    );
  }
}
```

**Request Creation with Smart Suggestions:**
```dart
class AddRequestScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(tripProvider);
    
    return Scaffold(
      body: Column(
        children: [
          // Three paths to request creation
          SegmentedButton(
            options: [
              ("Scan Fridge", PantryVisionScreen()),
              ("Smart Suggestions", SmartSuggestionsScreen()),
              ("Manual", ManualRequestForm())
            ]
          ),
          
          // Preference overlay on each item
          if (selectedItems.isNotEmpty)
            ItemsWithPreferences(
              items: selectedItems,
              userPreferences: ref.watch(preferencesProvider),
              storePreferences: ref.watch(storePreferencesProvider(trip.store))
            )
        ]
      )
    );
  }
}
```

**Substitution Flow with Preference Hints:**
```dart
class SubstitutionPrompt extends StatelessWidget {
  final String originalItem;
  final List<Alternative> alternatives;
  final UserPreference? userPreference;
  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Column(
        children: [
          Text("$originalItem out of stock"),
          if (userPreference != null)
            InfoBanner(
              text: "You prefer ${userPreference.preferredBrand} (${(userPreference.confidence*100).toInt()}%)"
            ),
          
          // Rank alternatives by preference match
          ...alternatives
            .sortByPreferenceMatch(userPreference)
            .map((alt) => AlternativeCard(
              alternative: alt,
              isPreferred: alt.brand == userPreference?.preferredBrand,
              onSelect: () => acceptSubstitution(alt)
            ))
        ]
      )
    );
  }
}
```

---

## 6. Implementation Roadmap

### Phase 1 (Weeks 1–2): Foundation
- [ ] Add new tables to Supabase schema
- [ ] Build `PantryVisionService` (VLM integration for multi-image analysis)
- [ ] Build `PreferenceEngine` (log feedback, calculate confidence)
- [ ] Add pantry scanner UI (photo carousel + results)

### Phase 2 (Weeks 3–4): Integration
- [ ] Wire pantry vision into request creation flow
- [ ] Update substitution prompt to show preference hints
- [ ] Log substitution feedback → update preference profile
- [ ] Build preference profile view (what the system learned about you)

### Phase 3 (Weeks 5–6): Smart Recommendations
- [ ] Build `StorePreferenceTracker` (update on trip completion)
- [ ] Build `SmartSuggestionEngine` (item recommendations per trip)
- [ ] Add smart suggestions UI to request creation
- [ ] Add store preference badge to trip cards

### Phase 4 (Weeks 7–8): Polish & Analytics
- [ ] Consumption history inference (optional)
- [ ] Trip advisor: "Based on your history at Trader Joe's..." (optional)
- [ ] Analytics dashboard: "Your top brands", "Stores you love", etc. (optional)
- [ ] End-to-end testing with real users

---

## 7. Addressing Product Varieties

**The Core Challenge:**
When a shopper scans a shelf and finds "Fage out of stock", there are 15 yogurt SKUs. How do we rank alternatives smartly?

**Solution Stack:**

### Layer 1: User Preference (Primary Signal)
```
User's preference profile: {
  category: "yogurt",
  preferred_brand: "Fage",
  preferred_type: "Greek",
  preferred_size: "32 oz",
  confidence: 0.85
}

VLM-detected alternatives on shelf:
- Fage (out of stock)
- Chobani (Greek, 32 oz) ← matches 2/3 attributes
- Dannon (regular, 6-pack) ← matches 0/3
- Skyr (Icelandic, 4-pack) ← matches type (Greek-like), size mismatch
- Store brand (Greek, 32 oz) ← matches 2/3, but no brand preference

Ranking:
  1. Chobani (Greek, 32 oz) — 67% attribute match + seen in previous substitutions
  2. Skyr (Icelandic, 32 oz) — similar type, but uncommon for this user
  3. Store brand (Greek, 32 oz) — attribute match, but price-conscious brand
  4. Dannon — low match, skip unless necessary
```

### Layer 2: Substitution History (Learning)
```
Substitution log for this user:
- 5 yogurt substitutions total
- Picked Chobani 2 times (40%)
- Picked Skyr 1 time (20%)
- Picked store brand 2 times (40%) ← when price-capped

Context: "Last time, Charlie was at $3.99 cap and picked store brand.
This time, cap is $6.99, so Chobani ($5.99) is likely better pick."
```

### Layer 3: Variety Disambiguation (VLM+Human)
```
If ambiguity remains (e.g., 3 Fage products in stock: regular/greek/icelandic):
  Shopper's VLM gets hint: "Charlie prefers Greek yogurt"
  → VLM prioritizes Fage Greek in alternatives
  → Shopper sees "[✓ Fage Greek] [ Fage Regular] [ Fage Icelandic]"
  Shopper taps Fage Greek → zero friction
```

### Data Model for Tracking Varieties

```sql
CREATE TABLE product_varieties (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  product_name TEXT,  -- "Yogurt"
  category TEXT,
  variety_type TEXT,  -- "style" | "size" | "brand"
  variety_value TEXT,  -- "Greek", "32 oz", "Fage"
  times_selected INT DEFAULT 0,
  times_offered INT DEFAULT 0,
  last_selected_at TIMESTAMP,
  created_at TIMESTAMP
);
```

**Smart Ranking Algorithm:**
```python
def rank_alternatives(
    alternatives: List[Product],
    user_preference: UserPreference,
    substitution_history: List[Substitution],
    user_budget: float
) -> List[Product]:
    """
    Rank yogurt alternatives by:
    1. Brand match (40%) — does brand = user's preferred?
    2. Type match (30%) — does type = user's preferred?
    3. Size match (20%) — does size = user's preferred?
    4. Price (10%) — is price within cap?
    """
    
    def score_product(product):
        brand_match = 1.0 if product.brand == user_preference.brand else 0.0
        type_match = 0.8 if product.type == user_preference.type else 0.3
        size_match = 1.0 if product.size == user_preference.size else 0.6
        price_match = 1.0 if product.price <= user_budget else 0.0
        
        # Historical pick rate as tiebreaker
        historical_pick_rate = get_pick_rate(substitution_history, product)
        
        return (
            brand_match * 0.40 +
            type_match * 0.30 +
            size_match * 0.20 +
            price_match * 0.10 +
            historical_pick_rate * 0.05
        )
    
    return sorted(alternatives, key=score_product, reverse=True)
```

---

## 8. Store Preferences Deep Dive

### 8.1 Why Store Preferences Matter

**Problem:** "I'm going to Whole Foods"
- Current: Requester says "milk" → shopper guesses which milk
- Better: Requester says "Organic Valley milk (which Whole Foods always has)"

**Problem:** "Which store should I go to for my circle?"
- Current: No signal
- Better: "You have an 4.8-star track record at Trader Joe's, 3.2 at Safeway"

### 8.2 Preference Score Derivation

```
Store Preference Score = (successful_requests_rate * 0.7) + (substitution_acceptance_rate * 0.3)

Example (Charlie's history at Trader Joe's):
- 10 total trips as requester
- 8 of those: got items as-requested (80% successful_requests_rate)
- 2 of those: needed substitutions, accepted them (100% acceptance_rate)
→ Score = (0.80 * 0.7) + (1.00 * 0.3) = 0.56 + 0.30 = 0.86 / 1.0 = 4.3 / 5 stars
```

### 8.3 Store Inventory Inference

For each store, build a lightweight "brand availability map":
```
Trader Joe's:
  - Yogurt: Fage (yes, 95%), Chobani (rare, 20%), Store brand (yes, 100%)
  - Milk: Organic Valley (yes, 90%), Store brand (yes, 100%), Lactaid (yes, 60%)
  - Bread: TJ's own brand (yes, 100%), Ezekiel (yes, 40%), Sourdough (yes, 70%)

Whole Foods:
  - Yogurt: Fage (yes, 100%), Chobani (yes, 100%), Store brand (yes, 100%)
  - Milk: Organic Valley (yes, 100%), Lactaid (yes, 90%), Lacto-free (yes, 80%)
  - Bread: Multiple local bakeries (yes, 100%), Ezekiel (yes, 90%), Mass-market (rare)

Safeway:
  - Yogurt: Store brand (yes, 100%), Dannon (yes, 90%), Fage (rare, 15%)
  - Milk: Store brand (yes, 100%), Lactaid (yes, 100%), Organic Valley (no, 0%)
  - Bread: Wonder (yes, 100%), Sara Lee (yes, 95%), Artisan (yes, 30%)
```

**How to Build It:**
1. **Implicit Feedback:** Every time substitution occurs, log it as "Brand X not in stock at Store Y"
2. **Explicit Feedback:** After trip, shopper can note "checked but not found" items
3. **External Data:** Integrate with store APIs (if available) or use 3P data (e.g., Instacart inventory snapshots)

**Usage in Substitution Flow:**
```
Shopper at Safeway scans: "yogurt (no Fage)"
System queries: "Is Fage ever in stock at Safeway?" → No (15% from history)
System rank: [Dannon] [Store brand] [Chobani] — don't suggest Fage
Shopper sees: "Fage rarely in stock here. Best match: Dannon $5.49"
Less friction, higher acceptance
```

---

## 9. API Endpoint Spec (Summary)

```
POST /pantry/scan
  Input: {user_id, images: [binary]}
  Output: {snapshot_id, detected_items, suggestions}

POST /requests/{trip_id}/from-pantry
  Input: {user_id, snapshot_id, selected_items: ["Milk", "Yogurt"]}
  Output: Request object

GET /users/{user_id}/preferences
  Output: {category: UserPreference, ...}

POST /substitutions/{item_id}/feedback
  Input: {user_id, original, alternatives, selected}
  Output: {accepted, preference_updated}

GET /trips/{trip_id}/suggestions
  Input: {user_id}
  Output: [SuggestionItem, ...]

GET /users/{user_id}/stores/preferences
  Output: {store_name: {score, total_trips, success_rate}, ...}

GET /stores/{store_id}/inventory-map
  Output: {brand: {category: in_stock_rate}, ...}
```

---

## 10. Key Metrics to Track

1. **Request Creation Time:** Avg time from "Add my list" → submitted
   - Goal: Reduce from 5 min → 1 min with pantry vision
2. **Substitution Acceptance Rate:** % of offered substitutions accepted
   - Goal: Increase from 60% → 80%+ with preference hints
3. **Store Preference Correlation:** Do high-pref-score stores have higher satisfaction?
4. **Preference Accuracy:** % of suggestions accepted by user
   - Goal: 70%+ first-try acceptance
5. **Consumption Prediction Accuracy:** (Future) How well do we predict what users need?

---

## 11. Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| VLM hallucination ("VLM sees milk in empty fridge") | Always user-confirms. VLM low-confidence items flagged for review. |
| Privacy concerns ("Why does the app scan my fridge?") | Privacy-first UX: photos never leave device until user opts in. Explicit consent. Local processing if possible. |
| Preference profile stale | Decay old preferences over time (e.g., 6-month halflife). Always allow manual override. |
| Store inventory data outdated | Use substitution feedback as realtime update signal. Manual "not in stock" from shopper. |
| Cold start (new users have no preference history) | Suggest popular items for their circle. A/B test suggestions. Fallback to generic. |
| Brand lock-in (only suggesting one brand) | Diversity: after 3+ picks of brand X, also suggest adjacent brands. Encourage experimentation. |

---

## 12. Success Criteria (v1)

- [ ] Pantry vision reduces request creation time from 5 min → <2 min
- [ ] 70%+ of VLM-suggested items make it into final request
- [ ] Substitution acceptance rate increases from 60% → 75%+
- [ ] Users can articulate their preference profile ("I prefer Fage yogurt")
- [ ] Store preference scores correlate with user satisfaction (qualitative)
- [ ] No privacy incidents (photos handled securely)
- [ ] System gracefully handles cold-start users (new accounts)

---

## 13. Future Extensions (v1.1+)

1. **Trip Advisor:** "Based on your history, Trader Joe's is ideal this week" (predict demand + inventory match)
2. **Consumption Forecasting:** "You buy milk every 7 days; next TJ's trip in 6 days — add milk?"
3. **Bulk Insights:** Circle-level: "Everyone loves TJ's; that's why it fills up first"
4. **Seasonal Patterns:** "Summer: 3x more frozen berries; winter: comfort foods"
5. **Store Notifications:** "TJ's just restocked organic Valley milk (usually out)" → push to interested users
6. **Collaborative Filtering:** "Users like you also buy almond butter when they buy Greek yogurt"

---

## 14. Conclusion

This feature transforms Favorly from a **coordination tool** into a **smart shopping assistant**.

**Core Insight:** The preference + store data you collect turns every substitution into a learning opportunity. Over 20–30 trips, you move from generic "milk" requests to "Organic Valley half-gallon (prefers Trader Joe's, historically 90% stocked there)."

**The magic:** Requesters spend 1 minute setting up, shoppers spend 30 seconds deciding substitutions, and trust increases because everyone gets what they actually want.
