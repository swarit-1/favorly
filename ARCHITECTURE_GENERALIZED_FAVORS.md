# Favorly v2+: Generalized Favor Platform

**Vision:** Extend Favorly from "neighbor grocery delivery" to "neighbor-to-neighbor help for ANY favor."

Same core loop: **Post need → Capture requests → Match preferences → Fulfill → Track reciprocity**

But now it works for:
- 🛒 **Grocery shopping** (existing)
- 🚗 **Errand runs** (pharmacy, gas, returns)
- 🏗️ **Home repairs** (painting, furniture fix, installation)
- 🧹 **Household tasks** (cleaning, organizing, yard work)
- 📚 **Services** (tutoring, pet-sitting, tech help)
- 🚚 **Logistics** (moving, pickup)

---

## Part 1: Conceptual Mapping (Food → Generic Favors)

### Current Food Model (v0/v1)

```
Trip = shopper goes to store
  ↓
Request = typed/photo list of food items
  ↓
Items = {name, brand, size, qty, price}
  ↓
Preferences = brand, type, size (for foods)
  ↓
Substitution = shelf photo → alternatives → user picks one
  ↓
Settlement = receipt split → Venmo
```

### Generalized Model (v2+)

```
Favor = person offering to do a task (store run, home repair, tutoring)
  ↓
Request = need for a task/service/item (paint wall, buy milk, teach math)
  ↓
Need Item = {service_type, description, specs, requester_budget, deadline, preferences}
  ↓
Preferences = domain-specific (for paint: color, finish; for tutoring: subject, age group; for groceries: brand)
  ↓
Adjustment = photo of issue → AI suggests solutions → user picks one
  ↓
Settlement = split payment/reciprocity → records ledger
```

### Key Abstraction: Favor Domains

Instead of hard-coding for "grocery shopping", define configurable **domains**:

```
Domain = {
  id: "grocery_shopping",
  name: "Grocery Shopping",
  intake_formats: ["text", "photo", "voice"],  // How user describes need
  need_detection: ["pantry_vision"],  // Photo analysis type
  item_schema: {  // What fields describe a need item?
    name: string,
    qty: number,
    brand: string,
    size: string,
    max_price: number
  },
  preference_categories: ["brand", "type", "size", "dietary"],
  adjustment_type: "substitution",  // What happens if item unavailable?
  settlement_type: "split_receipt",  // How to divide cost?
  store_support: true  // Is this domain location-based?
}

Domain = {
  id: "home_repair",
  name: "Home Repair & Maintenance",
  intake_formats: ["text", "photo", "voice", "checklist"],
  need_detection: ["damage_detection", "maintenance_scan"],  // Photo analysis
  item_schema: {
    task: string,  // "Paint bedroom wall", "Fix cabinet hinge"
    description: string,  // More details
    materials_needed: [string],  // "Paint", "Primer", "Brushes"
    estimated_hours: number,
    budget: number,
    deadline: date,
    difficulty: enum  // "easy", "medium", "hard"
  },
  preference_categories: ["skill_level", "material_brand", "time_availability"],
  adjustment_type: "rescope",  // Adjust scope if can't do full task
  settlement_type: "hourly_rate_or_reciprocity",
  store_support: false  // Could be true if buying materials at store
}

Domain = {
  id: "tutoring",
  name: "Tutoring & Teaching",
  intake_formats: ["text", "voice", "form"],
  need_detection: ["skill_assessment"],  // Maybe video of student?
  item_schema: {
    subject: string,  // "Math", "Python", "Spanish"
    level: string,  // "Elementary", "High School", "College"
    hours_needed: number,
    student_age: number,
    learning_style: string,  // "Visual", "Hands-on", "Lecture"
    deadline: date,
    budget_per_hour: number
  },
  preference_categories: ["tutor_background", "teaching_style", "language"],
  adjustment_type: "scope",  // Can we meet fewer hours? Different topic?
  settlement_type: "hourly_rate",
  store_support: false
}
```

---

## Part 2: Generalized Data Model

### Core Schema (Domain-Agnostic)

```sql
-- Favors (like Trips, but for any task)
CREATE TABLE favors (
  id UUID PRIMARY KEY,
  offerer_id UUID NOT NULL REFERENCES users(id),
  circle_id UUID NOT NULL REFERENCES circles(id),
  domain_id TEXT NOT NULL,  -- "grocery_shopping", "home_repair", "tutoring"
  title TEXT,  -- "Grocery run to Whole Foods", "Paint living room", "Python tutoring"
  description TEXT,
  status TEXT DEFAULT 'open',  -- 'open' | 'in_progress' | 'settling' | 'done'
  
  -- Domain-specific config (stored as JSONB for flexibility)
  domain_config JSONB,  -- store name (grocery), location/room (repair), meeting place (tutoring)
  caps JSONB,  -- max_requesters, max_per_person, max_hours, etc.
  
  created_at TIMESTAMP,
  started_at TIMESTAMP,
  completed_at TIMESTAMP
);

-- Requests (like current Requests, but for any domain)
CREATE TABLE requests (
  id UUID PRIMARY KEY,
  favor_id UUID NOT NULL REFERENCES favors(id),
  requester_id UUID NOT NULL REFERENCES users(id),
  status TEXT DEFAULT 'pending',  -- 'pending' | 'accepted' | 'declined'
  
  -- Domain-specific items (e.g., foods, repair tasks, tutoring sessions)
  items JSONB,  -- [{name, qty, specs, max_price, deadline}, ...]
  
  request_json JSONB,  -- Raw request data for flexibility
  intake_source TEXT,  -- 'manual' | 'pantry_vision' | 'damage_detection' | 'voice'
  
  created_at TIMESTAMP,
  created_at TIMESTAMP
);

-- Merged list (like current merged list, but generalized)
CREATE TABLE favor_merged_lists (
  id UUID PRIMARY KEY,
  favor_id UUID NOT NULL REFERENCES favors(id),
  merged_items JSONB,  -- Aggregated items across all requests, ranked by priority
  total_estimated_cost NUMERIC(10,2),
  total_estimated_time NUMERIC(8,2),
  created_at TIMESTAMP
);

-- Preferences (domain-specific preference profiles)
CREATE TABLE user_preferences (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  domain_id TEXT NOT NULL,  -- "grocery_shopping", "home_repair", etc.
  category TEXT,  -- "brand" (grocery), "material_brand" (repair), "teaching_style" (tutoring)
  preference_key TEXT,  -- "Fage" (brand), "Sherwin-Williams" (material), "Hands-on" (style)
  preference_value TEXT,  -- Flexible for different types
  confidence NUMERIC(3,2),  -- 0.0-1.0
  
  UNIQUE(user_id, domain_id, category, preference_key)
);

-- Adjustments (like Substitutions, but for any domain)
CREATE TABLE favor_adjustments (
  id UUID PRIMARY KEY,
  request_item_id UUID,  -- Link to specific item in request
  favor_id UUID NOT NULL REFERENCES favors(id),
  
  adjustment_type TEXT,  -- "substitution" (grocery), "rescope" (repair), "alternative_time" (tutoring)
  original_need JSONB,  -- Original request
  offered_alternatives JSONB,  -- [{option1}, {option2}, ...]
  user_selected JSONB,  -- What user picked
  
  created_at TIMESTAMP
);

-- Need detection results (photos → detected needs)
CREATE TABLE need_detections (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  domain_id TEXT NOT NULL,  -- "pantry_vision", "damage_detection", "maintenance_scan"
  photo_refs JSONB,  -- Image paths in storage
  vlm_analysis JSONB,  -- VLM output
  detected_items JSONB,  -- Parsed needs
  
  status TEXT DEFAULT 'pending_review',  -- 'pending_review' | 'accepted' | 'rejected'
  created_at TIMESTAMP
);

-- Domain configurations (allow admins to add new favor types)
CREATE TABLE favor_domains (
  id TEXT PRIMARY KEY,  -- "grocery_shopping", "home_repair", etc.
  name TEXT,
  description TEXT,
  intake_formats JSONB,  -- ["text", "photo", "voice"]
  detection_methods JSONB,  -- ["pantry_vision", "damage_detection"]
  item_schema JSONB,  -- JSON schema for items in this domain
  preference_categories JSONB,  -- Available preference types
  adjustment_type TEXT,  -- How to handle unavailability
  settlement_type TEXT,  -- "split_receipt", "hourly_rate", "reciprocity"
  icon TEXT,  -- For UI
  enabled BOOLEAN DEFAULT true,
  created_at TIMESTAMP
);

-- Store/location preferences (now generalized to any location-based domain)
CREATE TABLE location_preferences (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  domain_id TEXT NOT NULL,  -- "grocery_shopping", "home_repair" (if local)
  location TEXT,  -- "Trader Joe's", "Local Paint Store", "Bob's Repair Shop"
  preference_score NUMERIC(3,2),
  notes TEXT,
  last_used TIMESTAMP,
  UNIQUE(user_id, domain_id, location)
);
```

---

## Part 3: Multi-Domain Need Detection

### Generic VLM Analysis Pattern

Instead of just "pantry vision", we have **domain-specific analyzers**:

```python
# services/need_detection_service.py

class NeedDetectionService:
    """Universal need detection across domains"""
    
    async def analyze_photos(
        self,
        user_id: str,
        domain_id: str,
        photos: List[UploadFile]
    ) -> NeedDetectionResult:
        """
        Dispatch to domain-specific analyzer
        """
        domain = await db.get_domain_config(domain_id)
        
        if domain_id == "grocery_shopping":
            return await self._detect_pantry_needs(photos, domain)
        elif domain_id == "home_repair":
            return await self._detect_damage_needs(photos, domain)
        elif domain_id == "yard_work":
            return await self._detect_maintenance_needs(photos, domain)
        else:
            raise ValueError(f"Unknown domain: {domain_id}")
    
    async def _detect_pantry_needs(
        self, 
        photos: List[UploadFile], 
        domain: Dict
    ) -> NeedDetectionResult:
        """Analyze fridge/pantry photos"""
        prompt = """
        Analyze these fridge/pantry photos. For each product:
        - Name, brand, size
        - Visible quantity (full/half/low/empty)
        - Expiration date if visible
        
        Identify items that are low or empty.
        
        Return JSON: {
          detected_items: [{name, brand, size, status, expiration}, ...],
          low_or_empty: [names],
          summary: "..."
        }
        """
        return await self._call_vlm_analysis(photos, prompt, domain)
    
    async def _detect_damage_needs(
        self, 
        photos: List[UploadFile], 
        domain: Dict
    ) -> NeedDetectionResult:
        """Analyze home damage/repair photos"""
        prompt = """
        Analyze these photos for home repair/maintenance needs.
        
        For each identified issue:
        - Type of damage/maintenance needed
        - Severity (minor/moderate/major)
        - Estimated difficulty (easy/medium/hard)
        - Likely materials needed
        - Approximate time to fix
        - Safety concerns if any
        
        Return JSON: {
          detected_issues: [
            {
              issue_type: "Cracked paint", 
              severity: "minor",
              difficulty: "easy",
              materials: ["paint", "primer", "brush"],
              estimated_hours: 2,
              safety_concerns: false
            },
            ...
          ],
          summary: "..."
        }
        """
        return await self._call_vlm_analysis(photos, prompt, domain)
    
    async def _detect_maintenance_needs(
        self, 
        photos: List[UploadFile], 
        domain: Dict
    ) -> NeedDetectionResult:
        """Analyze yard/garden/outdoor maintenance"""
        prompt = """
        Analyze these outdoor/yard photos for maintenance needs.
        
        Identify:
        - Overgrown areas (weeds, grass height, trimming needed)
        - Dead plants/trees that need removal
        - Clearing needed
        - Seasonal maintenance (fall leaves, snow prep)
        - Structural issues (fence, deck, pavers)
        
        Return JSON: {
          maintenance_tasks: [
            {
              task: "Trim overgrown hedge",
              area: "Front yard, west side",
              urgency: "moderate",
              estimated_hours: 3,
              tools_needed: ["hedge trimmer", "rake"]
            },
            ...
          ],
          summary: "..."
        }
        """
        return await self._call_vlm_analysis(photos, prompt, domain)
    
    async def _call_vlm_analysis(
        self, 
        photos: List[UploadFile], 
        prompt: str, 
        domain: Dict
    ) -> NeedDetectionResult:
        """Generic VLM call with domain-specific prompt"""
        storage_paths = await upload_images_to_supabase(photos)
        
        # Call Meta Muse or fallback VLM
        analysis = await meta_muse.analyze_images(
            storage_paths, 
            prompt,
            structured_output_schema=domain.get("output_schema")
        )
        
        # Save detection result
        detection = await db.create_need_detection(
            user_id=user_id,
            domain_id=domain.id,
            photo_refs=storage_paths,
            vlm_analysis=analysis,
            detected_items=analysis.get("detected_items")
        )
        
        return detection
```

### Example: Damage Detection (Home Repair)

**User Flow:**
1. Requester: "I need my bathroom repaired"
2. Photos → VLM analyzes: "Cracked tile (moderate), water damage (major), mold (safety concern)"
3. System surfaces:
   - "⚠️ This looks like a major job; recommend professional contractor, not a favor"
   - Or: "This looks manageable! Cracked tile easy, water damage needs inspection"
4. Requester confirms which issues to post
5. Favor created: "Bathroom repair (cracked tile + water inspection)"

---

## Part 4: Domain Configuration System

**The Key:** Make it dead-simple to add new favor types without code changes.

### Admin Panel: Add New Domain

```python
# API to add domain dynamically
@router.post("/admin/domains")
async def create_domain(domain_spec: DomainSpec):
    """
    Admin creates new favor domain:
    - Name, description, icon
    - Intake formats (text, photo, voice, form)
    - Detection methods (VLM analysis types)
    - Item schema (JSON schema for needs)
    - Settlement strategy
    """
    domain = await db.create_favor_domain(domain_spec)
    
    # Index in available_domains for app
    await cache.set(f"domain:{domain.id}", domain)
    
    return domain

# Example payloads:

# Add "Pet Sitting"
{
  "id": "pet_sitting",
  "name": "Pet Sitting & Pet Care",
  "intake_formats": ["text", "form"],
  "item_schema": {
    "pet_type": "string",  // "dog", "cat", "bird"
    "pet_name": "string",
    "duration": "number",  // hours
    "special_needs": "string",  // dietary, behavioral
    "medicines": ["string"],  // medications to administer
  },
  "preference_categories": ["pet_experience", "care_style"],
  "adjustment_type": "rescope",  // Can you watch for fewer hours?
  "settlement_type": "hourly_rate",
  "icon": "🐕"
}

# Add "Cleaning & Organizing"
{
  "id": "cleaning",
  "name": "Cleaning & Organizing",
  "intake_formats": ["text", "photo"],
  "detection_methods": ["clutter_detection"],  // Photo analysis
  "item_schema": {
    "room": "string",  // "bedroom", "kitchen"
    "task_type": "string",  // "deep_clean", "organize", "declutter"
    "square_footage": "number",
    "special_requirements": "string",
    "products_to_use": ["string"],  // user preferences
  },
  "preference_categories": ["cleaning_products", "organization_style"],
  "settlement_type": "hourly_rate",
  "icon": "🧹"
}
```

---

## Part 5: Preference Learning Across Domains

### Domain-Specific Preferences

```python
# Grocery: Prefers Organic Valley milk
UserPreference(
  domain_id="grocery_shopping",
  category="brand",
  preference_key="milk_brand",
  preference_value="Organic Valley",
  confidence=0.85
)

# Home Repair: Prefers Sherwin-Williams paint
UserPreference(
  domain_id="home_repair",
  category="material_brand",
  preference_key="paint_brand",
  preference_value="Sherwin-Williams",
  confidence=0.70
)

# Tutoring: Prefers hands-on teaching style
UserPreference(
  domain_id="tutoring",
  category="teaching_style",
  preference_key="approach",
  preference_value="hands_on",
  confidence=0.80
)

# Pet Sitting: Prefers experienced with large dogs
UserPreference(
  domain_id="pet_sitting",
  category="pet_experience",
  preference_key="dog_size",
  preference_value="large_dogs",
  confidence=0.90
)
```

### Learning Flow (Universal)

```python
# When adjustment happens (substitution, rescope, etc.)
async def log_adjustment_feedback(
    user_id: str,
    favor_id: str,
    domain_id: str,
    adjustment: Adjustment
):
    """
    Log: What did user prefer? What was offered? What did they pick?
    """
    await db.create_adjustment_feedback(
        user_id=user_id,
        domain_id=domain_id,
        original=adjustment.original_need,
        offered=adjustment.offered_alternatives,
        selected=adjustment.user_selected
    )
    
    # Update preference profile
    await preference_engine.update_from_feedback(
        user_id=user_id,
        domain_id=domain_id,
        feedback=adjustment
    )
    
    # Example: Repair domain
    # User originally wanted: "Paint wall with Behr paint"
    # Offered: [Sherwin-Williams, Benjamin Moore, Behr, Store brand]
    # Selected: Sherwin-Williams
    # → Inference: "This user is willing to switch from Behr to Sherwin-Williams"
    #   (Maybe Behr wasn't available, or offerer recommended SW)
    #   Confidence increase for Sherwin-Williams: 0.70
```

---

## Part 6: Merged List → Merged Work Plan

**Current (Grocery):**
```
Merged List (Shopper View):
- Produce: Bananas (Bob, $2), Apples (Charlie, $3)
- Dairy: Milk (Bob, $4), Yogurt (Charlie, $5)
Total: Bob $6, Charlie $8
```

**Generalized (Home Repair):**
```
Merged Work Plan (Fixer View):
Task 1: Cracked tile (Ana's request, moderate, ~2 hours)
  - Materials: Grout, replacement tile, adhesive
  - Estimated cost: $30
  - Preference: Ana prefers Sherwin-Williams grout

Task 2: Water damage inspection (Bob's request, major, ~1 hour inspection)
  - Materials: None (inspection only)
  - Estimated cost: $0 (sweat equity)
  - Preference: Bob wants licensed inspector if needed

Task 3: Paint living room (Charlie's request, easy, ~3 hours)
  - Materials: Sherwin-Williams paint, primer, brushes
  - Estimated cost: $80
  - Preference: Charlie wants matte finish, "Soft White" color

Total work: 6 hours (3 tasks)
Estimated cost: $110 (split or reciprocity tracking)
```

---

## Part 7: Settlement → Flexible Payment Models

**Current (Grocery):**
- Venmo split based on receipt items

**Generalized:**

### Option A: Hourly Rate (Service-Based)
```
Favor: Home Repair (3 tasks, 6 hours)
Offerer rate: $25/hour
Total: $150
Split by hours spent per task:
- Ana's tile: 2 hours = $50
- Bob's inspection: 1 hour = $25
- Charlie's paint: 3 hours = $75
Venmo links generated
```

### Option B: Reciprocity (Barter)
```
Favor: Home Repair
Offerer: Alex (did 2 hours of work on Charlie's bathroom)
Offerer cap: "Up to $50 in reciprocal favors"

Charlie's ledger:
- Owes Alex: 2 hours of help (value ~$50)
- Has 3 hours available time for helping others

Later: Charlie helps Alex move boxes
- Logs: 1.5 hours of helping
- Ledger updates: Alex owes Charlie 0.5 hours

Circle dashboard shows: "Alex helped everyone 15 hours. Circle has helped Alex 8 hours. Alex is owed 7 hours of reciprocal help."
```

### Option C: Hybrid (Mixed Settlement)
```
Favor: Home Repair + Grocery Run
- Home repair: $100 (hourly rate paid via Venmo)
- Grocery run: $30 (split receipt, no cash if home repair credit applied)
- Net: Requester pays $70; home repair offerer credits $30 toward reciprocal favors
```

---

## Part 8: Smart Matching Across Domains

### "Who should do this favor?"

**Current (v1):** Any circle member can run a grocery trip

**Generalized:** Match offerer skills to favor type

```python
async def find_best_offerers(favor: Favor) -> List[OfferMatch]:
    """
    For favor: "Paint living room"
    
    Rank circle members by:
    1. Domain experience: Have they done home repair before? (skill signal)
    2. Successful history: How often did requesters accept their work?
    3. Preference alignment: Do they like the paint brand/finish?
    4. Availability: Free this weekend?
    5. Location: Close to requester?
    
    Return ranked list
    """
    domain_id = favor.domain_id
    
    # Get all circle members
    circle_members = await db.get_circle_members(favor.circle_id)
    
    matches = []
    for member in circle_members:
        # Domain experience signal
        past_favors = await db.get_user_favors(member.id, domain_id)
        domain_skill = calculate_domain_skill(past_favors)
        
        # Track record in this domain
        acceptance_rate = calculate_acceptance_rate(past_favors)
        
        # Preference alignment (does offerer prefer the same materials?)
        preference_alignment = calculate_preference_overlap(
            member.id,
            domain_id,
            favor.domain_config
        )
        
        # Availability
        availability_score = check_availability(member.id, favor.timeline)
        
        # Distance (if location-based)
        distance = calculate_distance(member.location, favor.location)
        
        # Composite score
        score = (
            domain_skill * 0.30 +
            acceptance_rate * 0.25 +
            preference_alignment * 0.20 +
            availability_score * 0.15 +
            (1.0 / (1.0 + distance_km / 5.0)) * 0.10  # Closer = higher score
        )
        
        matches.append(OfferMatch(member, score))
    
    return sorted(matches, key=lambda m: m.score, reverse=True)
```

---

## Part 9: Adjustment Strategies (Domain-Specific)

### Substitution (Grocery)
```
Can't find: Fage yogurt
Offered: [Chobani, Dannon, Store brand]
User picks: Chobani
→ Accepted, move on
```

### Rescope (Home Repair)
```
Original: "Paint living room + bedroom"
Offerer assessment: "Too much time; can only do living room this weekend"
Alternative: "Do living room, reschedule bedroom for next weekend"
User accepts: Partial fulfillment + future favor
→ Split settlement: pay for living room, owe favor for bedroom
```

### Alternative Time (Tutoring)
```
Original: "Monday 5pm session"
Tutor: Not available Monday
Alternative: "Tuesday 5pm or Saturday 10am?"
Student picks: Saturday 10am
→ Accepted, time changed
```

### Alternative Skill Level (Pet Sitting)
```
Original: "Need someone experienced with anxious dogs"
Offerer: "I'm experienced with dogs, but anxious ones are new to me"
Alternative: "Can you do it? I can provide behavior tips, or recommend someone better?"
Requester pick: "Let's try it, with tips"
→ Accepted, preference learning: "Requester willing to take risk"
```

---

## Part 10: Real-World Examples

### Example 1: Grocery Shopping (Existing)

```
Timeline:
- Monday: Alex posts "Whole Foods run Wednesday 5pm"
- Requester Bob: Takes pantry photo → VLM detects low milk
- Bob's request: "Organic Valley milk (half gallon), Bob prefers this brand (85% confidence)"
- Wednesday: Alex sees merged list, notes preference hint
- At store: Alex sees Organic Valley sold out
  - VLM suggests: [Straus Family dairy $7.99] [Kalona milk $6.99] [Store brand $4.99]
  - Hint: "Bob prefers Organic Valley but has accepted Straus before"
  - Alex picks Straus
- Bob gets notification: "Alex got you Straus instead (similar quality, same price)"
- Settlement: Split receipt via Venmo
```

### Example 2: Home Repair (New Domain)

```
Timeline:
- Monday: Carlos posts "Anyone good at drywall repair? Kitchen wall needs fixing"
- Requester Sam: Takes photo of damage
  - VLM detects: "Large hole, ~6 inches, moderate damage, 2–3 hour fix"
  - System suggests: "This looks like medium difficulty; you need patching compound, sandpaper, primer, paint"
- Sam's request: "Drywall patch + paint (I like matte white finishes)"
- System suggests: "Maria has done 3 drywall repairs, all accepted. She likes Benjamin Moore paint."
  - Maria's profile: Domain skill = 0.85, Acceptance rate = 0.98, Available this weekend = yes
- Carlos sees ranked list: Maria is #1 match
- Carlos: "Sounds good, Saturday afternoon?"
- Adjustment phase:
  - Maria assesses: "Paint color + primer will be $35, 2.5 hours labor"
  - Settlement: $35 materials + 2.5 hours @ $20/hr = $85 total
  - Sam can pay $85 Venmo OR offer reciprocal favor (I'll help you move next month)
```

### Example 3: Tutoring (New Domain)

```
Timeline:
- Sunday: Marcus posts "Looking for Python tutoring for 10-year-old"
- Requester Lee: Fills out form
  - Child's skill level: Beginner
  - Goals: "Understand loops and conditionals"
  - Learning style: "Hands-on, building projects"
  - Time: "Thursday 4–5pm, ongoing (4 weeks)"
- System matches: "Dr. Keisha teaches Python to kids, 5+ years experience, hands-on style"
  - Domain skill = 0.95, Preference alignment = 0.90
- Keisha suggests adjustment:
  - "4pm–5pm is tight for hands-on projects; can we do 4–5:30pm?"
  - Lee agrees
- Adjustment: Alternative time (5:30pm instead of 5pm)
- Settlement: $30/hour × 4 weeks = $120 (Venmo or reciprocity: "Lee helps Keisha prep for conference" = $120 value)
```

### Example 4: Yard Work (New Domain)

```
Timeline:
- Saturday AM: David posts "Anyone free to help with fall cleanup? Lots of leaves"
- Requester Nina: Takes 3 photos of yard
  - VLM detects: "Moderate leaf accumulation (~30% coverage), no dead branches, gutters need clearing"
  - System suggests: "This looks like 3–4 hour job; need rake, wheelbarrow, maybe gutter tools"
- Nina's request: "Leaf cleanup + gutter clearing"
- System suggests: "Jamie has done 7 yard jobs, all positive. Available Saturday."
  - Jamie's profile: Domain skill = 0.88, Acceptance = 1.0
- Jamie accepts, Saturday afternoon
- Adjustment phase:
  - Jamie assesses: "Leaves bad, but gutters look clear. Just leaves + mulching."
  - Rescope: "Can do leaves and mulch for 3 hours, not gutter work (wasn't actually needed)"
  - Settlement: 3 hours @ $25/hr = $75 (originally Nina said "up to 4 hours = $100")
  - Nina happy to pay less, Jamie happy to finish early
```

---

## Part 11: Ledger & Reciprocity (Universal)

### Current Ledger (Grocery Only)
```
Charlie:
- Trips run: 2
- Favors received: 4
- Money carried: $120
```

### Generalized Ledger (All Domains)

```
Charlie's Favor Ledger:
═════════════════════════════════════════════════════════════
FAVORS OFFERED (Charlie helping others):
  ✓ Grocery run (Whole Foods) - Alex, Bob - 1 trip
  ✓ Home repair (drywall patch) - Sam - 2.5 hours
  ✓ Tutoring (Python) - Lee's kid - 8 hours
  ✓ Yard work (leaf cleanup) - Nina - 3 hours
  
  Total: 1 trip + 13.5 hours of service = ~$340 value

FAVORS RECEIVED (Others helping Charlie):
  ✓ Grocery run (Trader Joe's) - Maria - 1 trip
  ✓ Home repair (paint living room) - Carlos - 3 hours ($75 paid)
  ✓ Pet sitting (2 evenings) - David - 2 × 2 hours ($40 paid)
  
  Total: 1 trip + 4 hours of service = ~$115 value

BALANCE: Charlie has helped circle 13.5 hours, received 4 hours
  → Circle owes Charlie 9.5 hours of reciprocal help
  → Charlie can "cash in" for: Home repairs, tutoring, yard work, pet sitting, etc.

CROSS-DOMAIN PREFERENCES:
  - Loves working with Sam (drywall was fun!)
  - Prefers not to do home repair (does tutoring instead)
  - Available for grocery runs weekends only
═════════════════════════════════════════════════════════════
```

---

## Part 12: UI/UX Changes

### Old UX (Grocery Only)
```
Bottom nav: [Trips] [Circle] [You]
  ↓
Tabs show only grocery-related actions
```

### New UX (Multi-Domain)

```
Bottom nav: [Favors] [Circle] [You]

Home Screen:
  "What do you need help with?"
  [🛒 Grocery] [🏗️ Home Repair] [📚 Tutoring] [🐕 Pet Sitting] [🧹 Cleaning] [+More]
  
  OR
  
  "Who needs help?"
  Active favors this week:
  [Maria: "Grocery run, Wednesday 5pm"]
  [Sam: "Drywall repair, Saturday"]
  [Lee: "Python tutoring, Thursday"]
  [Nina: "Yard cleanup, Saturday"]

Offer a Favor Screen:
  Domain selector (Grocery, Home Repair, Tutoring, etc.)
  Time/location picker
  Caps/requirements form
  
Request a Favor Screen:
  Domain selector
  Intake method: [Scan/photo] [Type] [Voice] [Form]
  Specify needs
  Set budget/time constraints
  
My Favors Screen:
  Grouped by domain + status
  Ledger showing: "You've helped 13.5 hours, owe 2 hours"
  Reciprocity tracker
```

---

## Part 13: Implementation Phases

### Phase 0 (Weeks 1–2): Generalization Foundation
- [ ] Refactor data model (Trip → Favor, generic schema)
- [ ] Create `favor_domains` table + admin API
- [ ] Build domain configuration system
- [ ] Migrate existing "grocery_shopping" domain to new model

### Phase 1 (Weeks 3–4): Multi-Domain Need Detection
- [ ] Add "home_repair" domain config
- [ ] Build VLM damage detection (`_detect_damage_needs`)
- [ ] Build VLM maintenance detection (`_detect_maintenance_needs`)
- [ ] Wire into request creation flow

### Phase 2 (Weeks 5–6): Cross-Domain Preferences & Matching
- [ ] Generalize preference engine (domain-aware)
- [ ] Build smart offerer matching algorithm
- [ ] Add preference hints to adjustments (all domains)
- [ ] Build "Who should do this favor?" ranking

### Phase 3 (Weeks 7–8): Multi-Domain Settlement
- [ ] Support hourly rate settlement
- [ ] Build reciprocity ledger (cross-domain tracking)
- [ ] Add reciprocity UI to ledger screen
- [ ] Support hybrid payment (hourly + reciprocity mix)

### Phase 4 (Weeks 9–10): New Domains (Pet Sitting, Tutoring)
- [ ] Add "pet_sitting" domain + detection
- [ ] Add "tutoring" domain + skill matching
- [ ] Add "cleaning" domain + clutter detection
- [ ] Build domain-specific adjustment flows

### Phase 5 (Weeks 11–12): Analytics & Polish
- [ ] Consumption/demand forecasting (any domain)
- [ ] Skill confidence scoring per user + domain
- [ ] Cross-domain recommendation engine
- [ ] Community insights ("Most popular favors in your circle")

---

## Part 14: Risk & Considerations

| Risk | Mitigation |
|------|-----------|
| Scope creep (too many domains) | Start with 3–4 domains; validate before adding more |
| Safety (non-vetted handyman doing repairs) | Skill rating + reviews; encourage insurance; maybe verify credentials for risky domains |
| Privacy (photos of home condition) | Explicit consent; photos auto-delete after settlement; no sharing with offers. |
| Disputes (what if repair isn't good?) | Ratings/reviews; requester can rate offerer; escalation to circle admins |
| Over-reliance on reciprocity (what if someone never returns favor?) | Track reciprocity debt; nudge with reminders; optional: allow cash conversion of reciprocity hours |
| Cold start (new domain, no preferences yet) | Suggest based on circle's favorite offerers; A/B test suggestions; fallback to "generalist" matches |

---

## Part 15: Why This Generalization Matters

**Current (v0):** "I need milk"
- Favorly is a grocery app
- Useful for neighbors who shop

**Generalized (v2+):** "I need help"
- Could be milk, paint, tutoring, moving, pet sitting, etc.
- Favorly becomes a universal "neighbor barter platform"
- Same core loop, infinite domains
- Same trust ledger, now tracks all kinds of help

**Network Effect:**
- Every domain solved → more types of help available
- More help available → more people join
- More people → more demand → positive loop

**Competitive Moat:**
- Favorly's ledger + trust system = hard to copy
- Grocery-only = local optimization; multi-domain = network optimization

---

## Part 16: Example Domain: Pet Sitting

```yaml
id: pet_sitting
name: Pet Care & Sitting
icon: 🐕
intake_formats:
  - form: Pet type, name, age, special needs, medications
  - photo: Photos of setup (crate, food, bed, toys)
  - text: "Need dog walker Tuesday 5pm, Fido eats at 6pm"

detection_methods:
  - pet_behavior_assessment: Analyze pet photos for behavior signals
  - special_needs_detector: Does pet need medication? Anxiety? Dietary needs?

item_schema:
  pet_type: enum  # "dog" | "cat" | "bird" | "other"
  pet_name: string
  pet_age: number
  special_needs: string  # "anxious", "elderly", "requires meds"
  medications: array  # [{name, time, instructions}]
  duration_hours: number
  food_schedule: object  # {time: portion}
  additional_instructions: string

preference_categories:
  - pet_experience: "Has worked with [large dogs] [anxious pets] [senior pets]"
  - care_style: "Prefers [play-based] [calm/quiet] [exercise-heavy]"
  - availability: "Prefers [evening] [daytime] [overnight]"

adjustment_type: rescope  # Can you sit for fewer hours? Different times?
settlement_type: hourly_rate
```

---

## Summary

This generalization:

1. **Unifies the core loop:** Post → Request → Adjust → Settle, works for ANY favor
2. **Enables infinite domains:** Add grocery, home repair, tutoring, pet sitting, moving, cleaning, yard work, etc.
3. **Shares infrastructure:** Same preference engine, same ledger, same matching algorithm
4. **Builds network effects:** Every domain solved attracts more users
5. **Maintains trust:** Reciprocity ledger tracks all help across all domains

The key insight: **The coordination problem isn't specific to groceries.** It's universal. Generalize the platform, and you've built a tool for any kind of neighbor-to-neighbor help.
