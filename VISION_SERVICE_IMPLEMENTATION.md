# Meta Muse Integration for Multi-Domain Image Analysis

**Status:** Meta Muse Spark via Meta Model API is the primary VLM (as per PRD)

This document shows how to use Meta Muse for all image processing needs across Favorly's domains.

---

## 1. Architecture Overview

### Single VLM Service, Domain-Specific Prompts

```python
# services/vision_service.py

from typing import List, Dict, Any
from anthropic import Anthropic
import base64
import json

class VisionService:
    """
    Universal vision processing using Meta Muse via Anthropic SDK
    
    Supports:
    - Grocery: Pantry detection, shelf substitution, receipt splitting
    - Home Repair: Damage detection, material identification
    - Yard Work: Maintenance need detection, overgrowth assessment
    - Pet Sitting: Pet behavior analysis, setup assessment
    - Cleaning: Clutter detection, organizing needs
    """
    
    def __init__(self, api_key: str):
        self.client = Anthropic(api_key=api_key)
        self.model = "claude-3-5-sonnet-20241022"  # Meta Muse via Anthropic
    
    async def analyze_images(
        self,
        image_paths: List[str],
        prompt: str,
        structured_output_schema: Optional[Dict] = None
    ) -> Dict[str, Any]:
        """
        Generic image analysis wrapper
        
        Args:
            image_paths: List of image file paths or URLs
            prompt: Domain-specific analysis prompt
            structured_output_schema: JSON schema for structured output (optional)
        
        Returns:
            Parsed JSON response from VLM
        """
        # Convert images to base64
        image_content = await self._prepare_images(image_paths)
        
        # Build message with images + prompt
        message_content = image_content + [
            {
                "type": "text",
                "text": prompt
            }
        ]
        
        # Call VLM
        response = self.client.messages.create(
            model=self.model,
            max_tokens=2048,
            messages=[
                {
                    "role": "user",
                    "content": message_content
                }
            ]
        )
        
        # Extract and parse JSON from response
        response_text = response.content[0].text
        
        try:
            # Try to find JSON in response (VLM might wrap it in markdown)
            json_start = response_text.find('{')
            json_end = response_text.rfind('}') + 1
            json_str = response_text[json_start:json_end]
            return json.loads(json_str)
        except (json.JSONDecodeError, ValueError):
            # If not JSON, return as-is
            return {"raw_response": response_text}
    
    async def _prepare_images(self, image_paths: List[str]) -> List[Dict]:
        """Convert image paths to base64 for API"""
        image_content = []
        
        for path in image_paths:
            if path.startswith('http'):
                # URL-based image
                image_content.append({
                    "type": "image",
                    "source": {
                        "type": "url",
                        "url": path
                    }
                })
            else:
                # Local file - convert to base64
                with open(path, 'rb') as f:
                    image_data = base64.standard_b64encode(f.read()).decode('utf-8')
                    ext = path.split('.')[-1].lower()
                    media_type = f"image/{ext}" if ext != 'jpg' else "image/jpeg"
                    
                    image_content.append({
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": media_type,
                            "data": image_data
                        }
                    })
        
        return image_content


# Initialize service
vision_service = VisionService(api_key=os.getenv("ANTHROPIC_API_KEY"))
```

---

## 2. Domain-Specific Implementations

### 2.1 Grocery: Pantry Vision

```python
# services/pantry_vision_service.py

async def scan_pantry(
    user_id: str,
    images: List[UploadFile]
) -> Dict:
    """
    Analyze fridge/pantry photos to detect products and quantities
    """
    # Save uploaded images temporarily
    image_paths = await save_temp_images(images)
    
    prompt = """
    Analyze these fridge/pantry photos carefully. For each visible product, identify:
    
    1. Product name (e.g., "Milk", "Greek Yogurt", "Bread")
    2. Brand name if visible (e.g., "Organic Valley", "Fage", "Trader Joe's")
    3. Size/quantity if visible (e.g., "Half gallon", "32 oz", "6-pack")
    4. Visible quantity level (full/3/4 full/half/1/4 full/low/empty)
    5. Expiration date if clearly visible
    6. Any notable details (organic label, specialty item, etc.)
    
    Then provide:
    - List of items that are LOW or EMPTY (priority items to restock)
    - Overall inventory assessment (e.g., "About 40% full, mostly fresh")
    - Any items past expiration or close to it
    
    Return as JSON:
    {
      "detected_items": [
        {
          "name": "Milk",
          "brand": "Organic Valley",
          "size": "Half gallon",
          "status": "half",
          "expiration": "2026-09-28",
          "confidence": 0.95,
          "notes": "Organic label visible"
        },
        ...
      ],
      "low_or_empty": ["Milk", "Yogurt"],
      "inventory_summary": "About 40% full, mostly fresh produce and dairy",
      "expiration_warnings": ["Deli turkey (expires 2026-09-20)"],
      "recommendations": ["Consider restocking milk soon", "Use deli turkey by end of week"]
    }
    """
    
    result = await vision_service.analyze_images(image_paths, prompt)
    
    # Save pantry snapshot
    snapshot = await db.create_pantry_snapshot(
        user_id=user_id,
        detected_items=result.get("detected_items", []),
        image_refs=image_paths,
        raw_vlm_output=result
    )
    
    return {
        "snapshot_id": snapshot.id,
        "detected_items": result.get("detected_items", []),
        "low_or_empty": result.get("low_or_empty", []),
        "summary": result.get("inventory_summary", ""),
        "recommendations": result.get("recommendations", [])
    }


async def analyze_shelf_for_substitution(
    image_path: str,
    original_item: str,
    user_preferences: Dict
) -> Dict:
    """
    Shopper snaps shelf → analyze available options
    """
    prompt = f"""
    The shopper is looking for "{original_item}" but it's out of stock.
    
    Analyze this shelf photo and identify all available alternatives that could substitute.
    
    For each alternative product visible, provide:
    1. Product name and brand
    2. Size/quantity
    3. Approximate price if visible on shelf tag
    4. Key attributes (type, flavor, style)
    5. How similar it is to the original (1-10 scale)
    
    User's preference context:
    {json.dumps(user_preferences)}
    
    Rank alternatives from best to worst match based on the user's preferences.
    
    Return JSON:
    {
      "original_request": "{original_item}",
      "available_alternatives": [
        {
          "name": "Chobani Greek Yogurt",
          "brand": "Chobani",
          "size": "32 oz",
          "price": "$6.99",
          "attributes": {
            "type": "Greek",
            "flavor": "Plain",
            "dairy_type": "Regular"
          },
          "similarity_score": 8,
          "match_reasoning": "Same type (Greek) and size (32oz) as preferred brand, just different brand"
        },
        ...
      ],
      "no_stock_warning": false,
      "notes": "All alternatives are in the dairy aisle section"
    }
    """
    
    result = await vision_service.analyze_images([image_path], prompt)
    return result
```

### 2.2 Home Repair: Damage Detection

```python
# services/damage_detection_service.py

async def analyze_damage(
    images: List[UploadFile],
    room_or_area: str = None
) -> Dict:
    """
    Analyze photos of home damage/repair needs
    """
    image_paths = await save_temp_images(images)
    
    prompt = f"""
    Analyze these photos for home repair and maintenance needs.
    Area/Room: {room_or_area or "Not specified"}
    
    For EACH identifiable issue, provide:
    1. Type of damage/issue (e.g., "Cracked drywall", "Water damage", "Peeling paint")
    2. Location in room if identifiable
    3. Severity assessment: minor/moderate/major
    4. Estimated difficulty to fix: easy/medium/hard
    5. Estimated time to complete: hours
    6. Materials likely needed (with typical products)
    7. Tools likely needed
    8. Safety concerns if any (structural, mold, electrical, etc.)
    9. Whether professional help is recommended
    10. Urgency: low (can wait months) / medium (within weeks) / high (within days)
    
    Return JSON:
    {
      "damage_assessment": [
        {
          "issue_type": "Cracked drywall",
          "location": "Living room wall, right of window",
          "severity": "moderate",
          "difficulty": "medium",
          "estimated_hours": 2.5,
          "materials": [
            {"name": "Drywall patch kit", "typical_cost": "$15-25"},
            {"name": "Joint compound", "typical_cost": "$10-15"},
            {"name": "Sandpaper (120/180 grit)", "typical_cost": "$5"},
            {"name": "Primer", "typical_cost": "$15"},
            {"name": "Paint (matching)", "typical_cost": "$20-40"}
          ],
          "tools": ["Putty knife", "Sandpaper block", "Paint roller", "Brush"],
          "safety_concerns": false,
          "professional_recommended": false,
          "urgency": "medium",
          "notes": "Standard drywall repair, no structural concerns"
        },
        {
          "issue_type": "Water stain on ceiling",
          "location": "Master bedroom, corner",
          "severity": "major",
          "difficulty": "hard",
          "estimated_hours": 0.5,
          "materials": [],
          "tools": ["Flashlight"],
          "safety_concerns": true,
          "professional_recommended": true,
          "urgency": "high",
          "notes": "Indicates potential roof or plumbing leak. Recommend inspection before repair."
        }
      ],
      "overall_assessment": "Two issues: cracked drywall (moderate, DIY-able) and water damage (major, needs professional inspection)",
      "total_diy_hours": 2.5,
      "total_estimated_material_cost": "$65-95",
      "professional_inspection_recommended": true,
      "priority_order": ["Water damage inspection (urgent)", "Drywall repair (can wait 1-2 weeks)"]
    }
    """
    
    result = await vision_service.analyze_images(image_paths, prompt)
    
    # Save detection
    detection = await db.create_need_detection(
        user_id=current_user_id,
        domain_id="home_repair",
        photo_refs=image_paths,
        vlm_analysis=result,
        detected_items=result.get("damage_assessment", [])
    )
    
    return {
        "detection_id": detection.id,
        "issues": result.get("damage_assessment", []),
        "overall_assessment": result.get("overall_assessment", ""),
        "total_hours": result.get("total_diy_hours", 0),
        "estimated_cost": result.get("total_estimated_material_cost", ""),
        "professional_recommended": result.get("professional_inspection_recommended", False)
    }
```

### 2.3 Grocery: Receipt Splitting

```python
# services/receipt_splitting_service.py

async def analyze_receipt(
    receipt_image: UploadFile,
    merged_list_items: List[Dict]
) -> Dict:
    """
    Analyze receipt photo and assign line items to requesters
    """
    image_path = await save_temp_image(receipt_image)
    
    # Convert merged list to readable format for VLM context
    merged_list_text = "\n".join([
        f"- {item['name']} ({item['requester']})"
        for item in merged_list_items
    ])
    
    prompt = f"""
    Analyze this receipt photo and extract all line items.
    
    For each line item, provide:
    1. Item name
    2. Quantity
    3. Price per unit
    4. Total price for that line
    5. Category (produce, dairy, meat, pantry, household, personal care, etc.)
    
    Then match each line item to the merged shopping list below.
    The people who requested items were:
    {merged_list_text}
    
    Provide your best match for each receipt line to the requesters.
    If ambiguous, list multiple possible matches.
    
    Calculate:
    - Subtotal (items only)
    - Tax
    - Total
    
    Return JSON:
    {
      "line_items": [
        {
          "item_name": "Organic Milk Half Gal",
          "quantity": 1,
          "unit_price": 4.99,
          "line_total": 4.99,
          "category": "dairy",
          "matched_to": "Bob",
          "confidence": 0.95,
          "notes": "Matches 'milk' in Bob's list"
        },
        {
          "item_name": "Fage Greek Yogurt 32oz",
          "quantity": 1,
          "unit_price": 7.99,
          "line_total": 7.99,
          "category": "dairy",
          "matched_to": "Charlie",
          "confidence": 0.90,
          "notes": "Matches 'yogurt' in Charlie's list"
        }
      ],
      "subtotal": 12.98,
      "tax": 1.04,
      "total": 14.02,
      "summary_by_requester": {
        "Bob": {
          "items": ["Organic Milk Half Gal"],
          "subtotal": 4.99,
          "tax_share": 0.40,
          "total_owed": 5.39
        },
        "Charlie": {
          "items": ["Fage Greek Yogurt 32oz"],
          "subtotal": 7.99,
          "tax_share": 0.64,
          "total_owed": 8.63
        }
      },
      "ambiguous_items": [],
      "unmatched_items": []
    }
    """
    
    result = await vision_service.analyze_images([image_path], prompt)
    
    # Save receipt analysis
    receipt = await db.create_receipt(
        trip_id=trip_id,
        image_ref=image_path,
        vlm_analysis=result,
        line_items=result.get("line_items", []),
        summary_by_requester=result.get("summary_by_requester", {})
    )
    
    return {
        "receipt_id": receipt.id,
        "line_items": result.get("line_items", []),
        "settlement": result.get("summary_by_requester", {}),
        "total": result.get("total", 0),
        "ambiguous_items": result.get("ambiguous_items", [])
    }
```

### 2.4 Yard Work: Maintenance Detection

```python
# services/yard_maintenance_service.py

async def analyze_yard_condition(
    images: List[UploadFile]
) -> Dict:
    """
    Analyze yard photos for maintenance needs
    """
    image_paths = await save_temp_images(images)
    
    prompt = """
    Analyze these yard/outdoor photos for maintenance needs.
    
    For each identifiable maintenance task, provide:
    1. Task type (e.g., "Leaf cleanup", "Trim overgrown hedge", "Remove dead tree")
    2. Location in yard if identifiable
    3. Severity/urgency (low/medium/high)
    4. Estimated work hours
    5. Tools needed
    6. Safety concerns if any
    7. Seasonal context (fall cleanup, spring prep, etc.)
    8. Priority ranking
    
    Also provide:
    - Overall yard assessment
    - Total estimated hours for all tasks
    - Tools needed (consolidated list)
    - Any specialized equipment rental needed
    - Recommended task order
    
    Return JSON:
    {
      "maintenance_tasks": [
        {
          "task_type": "Leaf cleanup and mulching",
          "location": "Front yard and driveway",
          "severity": "moderate",
          "estimated_hours": 3.5,
          "tools": ["Rake", "Leaf blower", "Wheelbarrow", "Shovel"],
          "safety_concerns": false,
          "seasonal_context": "Fall cleanup",
          "priority": 1,
          "notes": "Moderate leaf accumulation, walkable area"
        },
        {
          "task_type": "Trim overgrown hedge",
          "location": "East fence line",
          "severity": "moderate",
          "estimated_hours": 2,
          "tools": ["Hedge trimmer", "Pruning saw", "Rake"],
          "safety_concerns": false,
          "seasonal_context": "Late summer/fall maintenance",
          "priority": 2,
          "notes": "Hedge is about 20% overgrown"
        },
        {
          "task_type": "Check and clear gutters",
          "location": "Roof gutters (all sides)",
          "severity": "medium",
          "estimated_hours": 1,
          "tools": ["Ladder", "Gloves", "Bucket"],
          "safety_concerns": true,
          "seasonal_context": "Fall preparation",
          "priority": 3,
          "notes": "Heights involved; recommend safety harness"
        }
      ],
      "overall_assessment": "Typical fall maintenance: leaf cleanup (priority), hedge trimming, gutter prep",
      "total_estimated_hours": 6.5,
      "tools_needed": ["Rake", "Leaf blower", "Wheelbarrow", "Shovel", "Hedge trimmer", "Ladder"],
      "equipment_rental_needed": false,
      "recommended_task_order": ["Leaf cleanup", "Hedge trim", "Gutter check"],
      "best_conditions": "Dry weather, cool temperature",
      "estimated_material_cost": "$0 (cleanup only, no purchasing)"
    }
    """
    
    result = await vision_service.analyze_images(image_paths, prompt)
    
    detection = await db.create_need_detection(
        user_id=current_user_id,
        domain_id="yard_work",
        photo_refs=image_paths,
        vlm_analysis=result,
        detected_items=result.get("maintenance_tasks", [])
    )
    
    return {
        "detection_id": detection.id,
        "tasks": result.get("maintenance_tasks", []),
        "assessment": result.get("overall_assessment", ""),
        "total_hours": result.get("total_estimated_hours", 0),
        "tools_needed": result.get("tools_needed", []),
        "recommended_order": result.get("recommended_task_order", [])
    }
```

### 2.5 Pet Sitting: Behavior & Setup Assessment

```python
# services/pet_assessment_service.py

async def analyze_pet_and_setup(
    images: List[UploadFile],
    pet_info: Dict  # {name, breed, age, known_issues}
) -> Dict:
    """
    Analyze pet photos and home setup for pet sitting needs
    """
    image_paths = await save_temp_images(images)
    
    pet_context = f"""
    Pet information:
    - Name: {pet_info.get('name')}
    - Breed: {pet_info.get('breed')}
    - Age: {pet_info.get('age')}
    - Known issues/behaviors: {pet_info.get('known_issues', 'None noted')}
    """
    
    prompt = f"""
    {pet_context}
    
    Analyze these photos of the pet and home setup.
    
    ABOUT THE PET:
    1. Observable behavior/temperament from photos (calm, energetic, anxious, friendly, wary, etc.)
    2. Physical condition assessment (health observations)
    3. Estimated care difficulty level (easy/moderate/challenging)
    4. Special handling notes (if any obvious needs)
    5. Exercise/activity level assessment
    
    ABOUT THE HOME SETUP:
    1. Crate/bed location and accessibility
    2. Food/water bowl location and setup
    3. Toy and enrichment items observed
    4. Potential hazards or concerns
    5. Yard/outdoor area assessment if visible
    6. Emergency supplies or medications visible
    7. Overall safety and accessibility for caretaker
    
    EXPERIENCE RECOMMENDATIONS:
    1. Minimum experience level recommended (beginner/intermediate/experienced)
    2. Special skills or knowledge needed
    3. Physical requirements (strength, mobility, allergies)
    4. Time commitment per day
    5. Any concerning behaviors to watch for
    
    Return JSON:
    {
      "pet_assessment": {
        "observable_behavior": "Friendly and energetic, seems well-socialized",
        "physical_condition": "Healthy looking, good coat condition, no obvious health issues",
        "care_difficulty": "moderate",
        "special_handling": "Appears to jump on people; may need redirection training",
        "exercise_level": "high - frequent bathroom breaks and play needed"
      },
      "setup_assessment": {
        "crate_location": "Living room corner, easily accessible",
        "food_setup": "Two stainless steel bowls in kitchen, right side of fridge",
        "toys": ["Tennis balls", "Rope toy", "Kong toy"],
        "potential_hazards": ["Loose electrical cord near water bowl", "Trash can not secured"],
        "yard_access": "Fenced backyard, gate has broken latch - supervision needed",
        "emergency_supplies": "First aid kit visible on kitchen shelf",
        "safety_score": 7,
        "safety_notes": "Generally safe with minor fixes (secure trash, fix gate latch)"
      },
      "caretaker_requirements": {
        "experience_level": "intermediate",
        "required_skills": ["Leash training", "Boundary setting", "Bathroom routine management"],
        "physical_requirements": "Moderate strength (40+ lb dog), ability to supervise outdoor time",
        "time_per_day": "Minimum 3-4 hours (morning walk, afternoon play, evening walk)",
        "behavioral_concerns": ["Jumping on people - use 'sit' command", "May test boundaries"],
        "red_flags": "Watch for: excessive barking (stress), refusal to eat (unusual), limping (pain)"
      },
      "caretaker_recommendation": "Good match for intermediate caretakers who are active and patient. Not suitable for very young kids or elderly without help.",
      "preparation_needed": "Brief walk before caretaker arrives to burn energy"
    }
    """
    
    result = await vision_service.analyze_images(image_paths, prompt)
    
    detection = await db.create_need_detection(
        user_id=current_user_id,
        domain_id="pet_sitting",
        photo_refs=image_paths,
        vlm_analysis=result,
        detected_items={
            "pet_assessment": result.get("pet_assessment"),
            "setup_assessment": result.get("setup_assessment"),
            "caretaker_requirements": result.get("caretaker_requirements")
        }
    )
    
    return {
        "detection_id": detection.id,
        "pet_assessment": result.get("pet_assessment", {}),
        "setup_assessment": result.get("setup_assessment", {}),
        "caretaker_requirements": result.get("caretaker_requirements", {}),
        "recommendation": result.get("caretaker_recommendation", ""),
        "safety_score": result.get("setup_assessment", {}).get("safety_score", 0)
    }
```

### 2.6 Cleaning: Clutter Detection

```python
# services/cleaning_detection_service.py

async def analyze_cleaning_needs(
    images: List[UploadFile],
    room_type: str = None
) -> Dict:
    """
    Analyze room photos for cleaning and organizing needs
    """
    image_paths = await save_temp_images(images)
    
    prompt = f"""
    Analyze these photos of a room needing cleaning and/or organizing.
    Room type: {room_type or "Not specified"}
    
    CLUTTER ASSESSMENT:
    1. Clutter level (minimal/moderate/severe)
    2. Types of clutter identified (clothes, papers, dishes, general items)
    3. Floor accessibility (% of floor visible)
    4. Surface clutter (tables, shelves, counters)
    5. Specific problem areas
    
    CLEANING NEEDS:
    1. Dust/dirt level (minimal/moderate/heavy)
    2. Specific cleaning tasks needed (vacuum, mop, wipe surfaces, etc.)
    3. Bathroom needs if visible (tile, fixtures, mirrors)
    4. Kitchen needs if visible (appliances, counters, sink)
    5. Trash/recycling needs
    
    ORGANIZING NEEDS:
    1. Suggested organization strategy (by type, by zone, other)
    2. Storage solutions needed (bins, shelves, hangers)
    3. Items for donate/discard
    4. Space reclamation opportunities
    
    DIFFICULTY & TIME:
    1. Estimated time (light cleaning, normal, deep clean)
    2. Difficulty level (simple, moderate, complex)
    3. Special equipment needed (steam cleaner, pressure washer, etc.)
    4. Physical demands (ladder work, heavy lifting, etc.)
    
    Return JSON:
    {
      "clutter_assessment": {
        "clutter_level": "moderate",
        "clutter_types": ["clothes on chair", "papers on desk", "books on floor"],
        "floor_accessibility": "70% visible",
        "surface_clutter": {
          "desk": "High - papers, cups, misc items",
          "bed": "Medium - clothes pile",
          "nightstand": "High - books, glasses, items"
        },
        "problem_areas": ["Desk area", "Closet overflowing"]
      },
      "cleaning_needs": {
        "dust_level": "moderate",
        "tasks": ["Vacuum floor", "Dust surfaces", "Wipe desk", "Clean mirrors"],
        "specific_issues": ["Sticky spots on desk", "Dust bunnies under bed"],
        "priority_order": ["Vacuum", "Dust", "Wipe surfaces", "Final sweep"]
      },
      "organizing_needs": {
        "strategy": "Zone-based organization: work zone (desk), sleep zone (bed), storage zone (closet)",
        "storage_needed": ["Desk organizer", "Under-bed storage bins", "Shelf organizer"],
        "items_to_discard": "About 20-30% of items on desk could be removed",
        "space_recovery": "Clearing desk would free up significant work space"
      },
      "time_estimate": {
        "light_cleaning": "1-2 hours",
        "deep_clean": "3-4 hours",
        "organizing": "2-3 additional hours",
        "total_combined": "4-5 hours for complete refresh"
      },
      "difficulty": "moderate",
      "special_equipment": "Vacuum with attachments, microfiber cloths, trash bags",
      "physical_demands": "Light - mostly standing and bending, no heavy lifting",
      "recommendation": "Standard bedroom refresh; combination of cleaning and light organizing. Good DIY project or professional cleaner task."
    }
    """
    
    result = await vision_service.analyze_images(image_paths, prompt)
    
    detection = await db.create_need_detection(
        user_id=current_user_id,
        domain_id="cleaning",
        photo_refs=image_paths,
        vlm_analysis=result,
        detected_items=result.get("cleaning_needs", {})
    )
    
    return {
        "detection_id": detection.id,
        "clutter": result.get("clutter_assessment", {}),
        "cleaning": result.get("cleaning_needs", {}),
        "organizing": result.get("organizing_needs", {}),
        "time_estimate": result.get("time_estimate", {}),
        "difficulty": result.get("difficulty", ""),
        "recommendation": result.get("recommendation", "")
    }
```

---

## 3. Setup & Configuration

### Environment

```bash
# .env
ANTHROPIC_API_KEY=sk-ant-...  # Your Anthropic API key for Meta Muse access
```

### Installation

```bash
# requirements.txt
anthropic>=0.25.0
python-dotenv>=1.0.0
```

### Python

```python
# initialization
import os
from dotenv import load_dotenv

load_dotenv()

# VisionService will use ANTHROPIC_API_KEY from environment
vision_service = VisionService(api_key=os.getenv("ANTHROPIC_API_KEY"))
```

---

## 4. API Routes (FastAPI)

```python
# routes/vision.py

from fastapi import APIRouter, UploadFile, File, Form
from typing import List, Optional

router = APIRouter(prefix="/vision", tags=["vision"])

@router.post("/grocery/pantry-scan")
async def scan_pantry(
    files: List[UploadFile] = File(...),
    current_user_id: str = Depends(get_current_user)
):
    """Scan fridge/pantry for product detection"""
    result = await pantry_vision_service.scan_pantry(current_user_id, files)
    return result

@router.post("/grocery/shelf-analysis")
async def analyze_shelf(
    file: UploadFile = File(...),
    original_item: str = Form(...),
    user_preferences: str = Form(...)
):
    """Analyze shelf for substitution options"""
    prefs = json.loads(user_preferences)
    result = await pantry_vision_service.analyze_shelf_for_substitution(
        file, original_item, prefs
    )
    return result

@router.post("/grocery/receipt-analysis")
async def analyze_receipt(
    file: UploadFile = File(...),
    trip_id: str = Form(...),
    merged_list: str = Form(...)
):
    """Split receipt among requesters"""
    list_items = json.loads(merged_list)
    result = await receipt_splitting_service.analyze_receipt(file, list_items)
    return result

@router.post("/home-repair/damage-detection")
async def detect_damage(
    files: List[UploadFile] = File(...),
    room_or_area: Optional[str] = Form(None),
    current_user_id: str = Depends(get_current_user)
):
    """Analyze home damage and repair needs"""
    result = await damage_detection_service.analyze_damage(files, room_or_area)
    return result

@router.post("/yard/maintenance-scan")
async def scan_yard(
    files: List[UploadFile] = File(...),
    current_user_id: str = Depends(get_current_user)
):
    """Analyze yard for maintenance needs"""
    result = await yard_maintenance_service.analyze_yard_condition(files)
    return result

@router.post("/pet-sitting/assessment")
async def assess_pet(
    files: List[UploadFile] = File(...),
    pet_info: str = Form(...),
    current_user_id: str = Depends(get_current_user)
):
    """Assess pet and home setup for pet sitting"""
    info = json.loads(pet_info)
    result = await pet_assessment_service.analyze_pet_and_setup(files, info)
    return result

@router.post("/cleaning/needs-analysis")
async def analyze_cleaning(
    files: List[UploadFile] = File(...),
    room_type: Optional[str] = Form(None),
    current_user_id: str = Depends(get_current_user)
):
    """Analyze cleaning and organizing needs"""
    result = await cleaning_detection_service.analyze_cleaning_needs(files, room_type)
    return result
```

---

## 5. Error Handling & Fallbacks

```python
# services/vision_service.py (enhanced)

class VisionServiceWithFallback(VisionService):
    """
    Vision service with fallback strategies
    """
    
    async def analyze_images_with_fallback(
        self,
        image_paths: List[str],
        prompt: str,
        fallback_response: Optional[Dict] = None
    ) -> Dict:
        """
        Try primary VLM, fall back to cached response if needed
        """
        try:
            return await self.analyze_images(image_paths, prompt)
        except Exception as e:
            logger.error(f"VLM analysis failed: {e}")
            
            if fallback_response:
                logger.info("Using fallback response")
                return fallback_response
            
            # Return structured error
            return {
                "error": str(e),
                "status": "analysis_failed",
                "manual_review_required": True
            }
    
    async def analyze_with_retries(
        self,
        image_paths: List[str],
        prompt: str,
        max_retries: int = 2
    ) -> Dict:
        """Retry logic for transient failures"""
        for attempt in range(max_retries):
            try:
                return await self.analyze_images(image_paths, prompt)
            except Exception as e:
                if attempt < max_retries - 1:
                    logger.warning(f"Attempt {attempt + 1} failed, retrying...")
                    await asyncio.sleep(2 ** attempt)  # Exponential backoff
                else:
                    raise
```

---

## 6. Caching Analyzed Results

```python
# services/vision_cache.py

class VisionCache:
    """Cache VLM analysis results to reduce API calls"""
    
    async def get_cached_analysis(
        self,
        image_hash: str,
        domain_id: str
    ) -> Optional[Dict]:
        """Check if we've already analyzed this image"""
        return await db.get_vision_cache(image_hash, domain_id)
    
    async def cache_analysis(
        self,
        image_hash: str,
        domain_id: str,
        result: Dict
    ):
        """Store analysis for future use"""
        await db.create_vision_cache(image_hash, domain_id, result)
    
    async def analyze_with_cache(
        self,
        image_paths: List[str],
        domain_id: str,
        prompt: str
    ) -> Dict:
        """Analyze with caching layer"""
        # Hash images for cache lookup
        image_hash = hashlib.md5(
            ''.join(image_paths).encode()
        ).hexdigest()
        
        # Check cache
        cached = await self.get_cached_analysis(image_hash, domain_id)
        if cached:
            logger.info("Using cached analysis")
            return cached
        
        # Fresh analysis
        result = await vision_service.analyze_images(image_paths, prompt)
        await self.cache_analysis(image_hash, domain_id, result)
        
        return result
```

---

## 7. Cost Optimization

### Token Counting

```python
# Meta Muse via Anthropic uses token-based pricing
# Input tokens (images + text prompt)
# Output tokens (response)

# Example costs per domain (rough estimates):
# Pantry vision: 1 image → ~500 tokens → ~$0.02
# Shelf analysis: 1 image → ~400 tokens → ~$0.015
# Receipt splitting: 1 image → ~800 tokens → ~$0.03
# Damage detection: 3 images → ~1500 tokens → ~$0.05
# Yard maintenance: 3 images → ~1500 tokens → ~$0.05

# Batching optimizations:
# - Combine multiple images in single call when possible
# - Cache frequently analyzed templates
# - Use lower-resolution images for initial assessment
```

### Image Compression

```python
# services/vision_service.py (enhanced)

async def compress_image_for_vlm(
    image_path: str,
    max_width: int = 1024,
    max_height: int = 1024
) -> str:
    """Compress images while retaining detail for VLM"""
    from PIL import Image
    
    img = Image.open(image_path)
    
    # Resize while maintaining aspect ratio
    img.thumbnail((max_width, max_height), Image.Resampling.LANCZOS)
    
    # Save compressed
    compressed_path = image_path.replace('.jpg', '_compressed.jpg')
    img.save(compressed_path, quality=85, optimize=True)
    
    return compressed_path
```

---

## 8. Monitoring & Logging

```python
# services/vision_metrics.py

class VisionMetrics:
    """Track VLM usage and performance"""
    
    async def log_vision_call(
        self,
        domain_id: str,
        image_count: int,
        input_tokens: int,
        output_tokens: int,
        success: bool,
        latency_ms: float
    ):
        """Log metrics for monitoring"""
        await db.create_vision_metric({
            "domain_id": domain_id,
            "image_count": image_count,
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "success": success,
            "latency_ms": latency_ms,
            "timestamp": now()
        })
    
    async def get_cost_summary(
        self,
        domain_id: Optional[str] = None,
        days: int = 7
    ) -> Dict:
        """Get cost breakdown by domain"""
        metrics = await db.get_vision_metrics(domain_id, days)
        
        # Anthropic pricing: ~$0.003 per 1K input, $0.015 per 1K output
        total_cost = sum(
            (m["input_tokens"] * 0.003 + m["output_tokens"] * 0.015) / 1000
            for m in metrics
        )
        
        return {
            "total_calls": len(metrics),
            "successful_calls": sum(1 for m in metrics if m["success"]),
            "total_tokens": sum(m["input_tokens"] + m["output_tokens"] for m in metrics),
            "estimated_cost": total_cost,
            "avg_latency_ms": sum(m["latency_ms"] for m in metrics) / len(metrics)
        }
```

---

## Summary

**Meta Muse Integration Pattern:**

```python
# 1. Initialize once
vision_service = VisionService(api_key=os.getenv("ANTHROPIC_API_KEY"))

# 2. For any domain, write domain-specific prompt
prompt = "Analyze this [grocery/repair/yard/pet/cleaning] and return JSON: {...}"

# 3. Call VLM
result = await vision_service.analyze_images(image_paths, prompt)

# 4. Parse structured JSON response
# 5. Use result for request creation, matching, settlement

# Same pattern works for all 5+ domains!
```

**Why Meta Muse is Perfect:**

✅ Multi-image support (pantry scan = 4 photos at once)
✅ Structured output (return JSON schema)
✅ OpenAI-compatible API (via Anthropic SDK)
✅ Vision understanding across domains (food, damage, pets, cleaning all work)
✅ Cost-effective (~$0.02–$0.05 per analysis)
✅ Reliable fallback strategy (demo caching)

