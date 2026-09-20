"""
Vision service with multi-provider fallback: Muse API → OpenAI → Mock.

Supports grocery detection (pantry scans, shelf substitution, receipt analysis).
Other domains use mock responses until implemented.
"""

import logging
import json
import os
import base64
from typing import List, Dict, Optional
from datetime import datetime
import httpx
from openai import AsyncOpenAI

logger = logging.getLogger(__name__)


class VisionService:
    """
    Real vision service using Meta's Muse Vision API.
    Focuses on grocery domain, with other domains returning mock data.
    """

    def __init__(self, api_key: Optional[str] = None):
        self.api_key = api_key or os.getenv("MUSE_API_KEY")
        if not self.api_key:
            raise RuntimeError("MUSE_API_KEY must be set in environment or passed to VisionService")

        self.client = httpx.AsyncClient()
        # Meta Muse API endpoint
        # Official: https://api.meta.ai/v1
        self.api_base_url = os.getenv("MUSE_API_BASE_URL", "https://api.meta.ai/v1")
        # Best model for vision/multimodal: muse-spark-1.3
        self.model = os.getenv("MUSE_MODEL", "muse-spark-1.3")

    async def _load_image_as_base64(self, image_path: str) -> str:
        """Load image file and convert to base64"""
        try:
            with open(image_path, "rb") as image_file:
                return base64.standard_b64encode(image_file.read()).decode("utf-8")
        except Exception as e:
            logger.error(f"Failed to load image {image_path}: {e}")
            raise

    async def _get_image_media_type(self, image_path: str) -> str:
        """Determine media type from file extension"""
        ext = image_path.split(".")[-1].lower()
        media_types = {
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "png": "image/png",
            "gif": "image/gif",
            "webp": "image/webp",
        }
        return media_types.get(ext, "image/jpeg")

    async def _analyze_image_with_prompt(
        self,
        image_paths: List[str],
        prompt: str,
    ) -> Dict:
        """Send images to Meta Muse Vision API with prompt"""
        print(f"🔄 Analyzing {len(image_paths)} image(s) with Meta Muse...")
        logger.info(f"🔄 Analyzing {len(image_paths)} image(s) with Meta Muse...")

        # Prepare images for Muse Spark API (OpenAI-compatible format)
        images = []
        for image_path in image_paths:
            try:
                image_data = await self._load_image_as_base64(image_path)
                media_type = await self._get_image_media_type(image_path)
                # Muse Spark uses OpenAI-compatible format: {"type": "image_url", "image_url": {"url": "data:..."}}
                images.append({
                    "type": "image_url",
                    "image_url": {
                        "url": f"data:{media_type};base64,{image_data}",
                    },
                })
            except Exception as e:
                logger.warning(f"Could not load image {image_path}, skipping: {e}")
                continue

        # Build request for Muse Spark API (OpenAI-compatible format)
        request_body = {
            "model": self.model,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        *images,
                        {
                            "type": "text",
                            "text": prompt,
                        },
                    ],
                }
            ],
            "max_tokens": 2048,
            "temperature": 0.7,
        }

        try:
            print(f"📡 Calling Meta Muse API ({self.model}) with {len(images)} image(s)...")
            headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
            }

            # Meta Muse Spark API endpoint (OpenAI-compatible)
            muse_endpoint = f"{self.api_base_url}/chat/completions"

            print(f"🔗 Endpoint: {muse_endpoint}")
            print(f"🤖 Model: {self.model}")
            print(f"📝 Prompt length: {len(prompt)} chars")
            print(f"⚙️  Max tokens: {request_body.get('max_tokens', 2048)}")
            logger.info(f"🔗 Endpoint: {muse_endpoint}")
            logger.info(f"🤖 Model: {self.model}")
            logger.debug(f"📝 Prompt: {prompt[:200]}...")  # Log first 200 chars of prompt

            response = await self.client.post(
                muse_endpoint,
                json=request_body,
                headers=headers,
                timeout=60.0,
            )

            if response.status_code != 200:
                error_detail = response.text
                print(f"❌ Muse API error (status {response.status_code}): {error_detail}")
                logger.error(f"❌ Muse API error: {error_detail}")
                raise RuntimeError(f"Muse API returned {response.status_code}: {error_detail}")

            response_data = response.json()
            print(f"📦 Raw Muse response: {json.dumps(response_data, indent=2)[:200]}...")

            # Handle OpenAI-compatible response format from Muse Spark
            response_text = ""
            if isinstance(response_data, dict):
                # OpenAI format: {"choices": [{"message": {"content": "..."}}]}
                if "choices" in response_data and isinstance(response_data["choices"], list):
                    response_text = response_data["choices"][0].get("message", {}).get("content") or ""
                # Alternative format: {"content": "..."}
                elif "content" in response_data:
                    response_text = response_data.get("content") or ""
                # Fallback
                else:
                    response_text = json.dumps(response_data)
            else:
                response_text = str(response_data)

            # Handle null/empty response from API (not a valid response)
            if not response_text or response_text.strip() == "":
                finish_reason = response_data.get('choices', [{}])[0].get('finish_reason', 'unknown')
                logger.warning(f"Muse API returned empty content (finish_reason: {finish_reason}) - treating as API failure")
                raise RuntimeError(f"Muse API returned no content (finish_reason: {finish_reason}) - may have hit token limit or API issue")

            if response_text:
                print(f"✅ Muse response received ({len(response_text)} chars)")
                logger.info(f"✅ Muse response received ({len(response_text)} chars)")

            # Try to extract JSON from response
            try:
                json_start = response_text.find("{")
                json_end = response_text.rfind("}") + 1
                if json_start != -1 and json_end > json_start:
                    json_str = response_text[json_start:json_end]
                    result = json.loads(json_str)
                    print(f"✅ JSON parsed successfully: {list(result.keys())}")
                    logger.info(f"✅ JSON parsed successfully: {list(result.keys())}")
                    # Valid JSON response - return it even if low_or_empty is empty
                    # (means no items need restocking, which is a valid result)
                    return result
            except (json.JSONDecodeError, ValueError) as parse_error:
                print(f"⚠️ Failed to parse JSON: {parse_error}")
                logger.warning(f"⚠️ Failed to parse JSON: {parse_error}")
                # Invalid JSON is an API failure - let this raise
                raise RuntimeError(f"Muse API returned invalid JSON: {parse_error}")

            # If we got here, response_text exists but no JSON found
            raise RuntimeError(f"Muse API returned non-JSON response: {response_text[:100]}")
        except Exception as e:
            print(f"❌ Muse API error: {e}")
            logger.error(f"❌ Muse API error: {e}", exc_info=True)
            raise

    async def analyze_pantry_vision(
        self,
        image_refs: List[str],
        user_id: str,
    ) -> Dict:
        """Analyze pantry photos for all items and restocking needs"""
        prompt = """Analyze this pantry/fridge photo and detect ALL visible items.

For EVERY item you can see, provide:
1. Exact product name and brand (e.g., "Organic Valley Milk", "Fage Greek Yogurt")
2. Specific size if visible (e.g., "Half gallon", "32 oz", "1 loaf")
3. Current status (full/mostly_full/half/low/nearly_empty/empty)
4. Whether it should be restocked (yes/no) - YES if less than half full or empty
5. Confidence level (0-1)

Return specific product names only - NOT generic categories.

Return ONLY valid JSON:
{
  "detected_items": [
    {
      "name": "Organic Valley Milk Half Gallon",
      "brand": "Organic Valley",
      "status": "low",
      "should_restock": true,
      "reason": "Only about 1/4 full",
      "confidence": 0.92
    },
    {
      "name": "Fage Greek Yogurt 32oz",
      "brand": "Fage",
      "status": "full",
      "should_restock": false,
      "reason": "Recently purchased",
      "confidence": 0.95
    }
  ],
  "summary": "Detected X items, Y need restocking",
  "expiration_warnings": [],
  "recommendations": []
}
"""
        return await self._analyze_image_with_prompt(image_refs, prompt)

    async def analyze_shelf_substitution(
        self,
        image_ref: str,
        original_item: str,
        user_preferences: Dict,
        user_id: str,
    ) -> Dict:
        """Analyze shelf for substitution options"""
        prompt = f"""
The shopper is looking for "{original_item}" but it's out of stock.

Analyze this shelf photo and identify all available alternatives that could substitute.

For each alternative product visible, provide:
1. Product name and brand
2. Size/quantity
3. Approximate price if visible on shelf tag
4. Key attributes (type, flavor, style)
5. How similar it is to the original (1-10 scale)

User preferences: {json.dumps(user_preferences)}

Rank alternatives from best to worst match based on the user's preferences.

Return ONLY valid JSON (no markdown, no code blocks):
{{
  "original_request": "{original_item}",
  "alternatives": [
    {{
      "name": "Chobani Greek Yogurt",
      "brand": "Chobani",
      "size": "32 oz",
      "price": "$6.99",
      "similarity_score": 8,
      "match_reasoning": "Same type (Greek) and size"
    }}
  ],
  "no_stock_warning": false,
  "notes": "All alternatives are in the dairy aisle"
}}
"""
        return await self._analyze_image_with_prompt([image_ref], prompt)

    async def analyze_receipt(
        self,
        image_ref: str,
        merged_list: List[Dict],
        trip_id: str,
        user_id: str,
    ) -> Dict:
        """Analyze receipt and assign line items"""
        merged_list_text = "\n".join([
            f"- {item.get('name', item)} ({item.get('requester', 'unknown')})"
            for item in merged_list
        ])

        prompt = f"""
Analyze this receipt photo and extract all line items.

For each line item, provide:
1. Item name
2. Quantity
3. Price per unit
4. Total price for that line
5. Category (produce, dairy, meat, pantry, household, personal care, etc.)

Then match each line item to the merged shopping list below:
{merged_list_text}

Return ONLY valid JSON (no markdown, no code blocks):
{{
  "line_items": [
    {{
      "item_name": "Organic Milk Half Gal",
      "quantity": 1,
      "unit_price": 4.99,
      "line_total": 4.99,
      "category": "dairy",
      "matched_to": "requester_name",
      "confidence": 0.95
    }}
  ],
  "subtotal": 0.0,
  "tax": 0.0,
  "total": 0.0,
  "summary_by_requester": {{}},
  "ambiguous_items": [],
  "unmatched_items": []
}}
"""
        return await self._analyze_image_with_prompt([image_ref], prompt)

    async def analyze_damage(
        self,
        image_refs: List[str],
        room_or_area: Optional[str],
        user_id: str,
    ) -> Dict:
        """Analyze home damage/repair needs"""
        raise NotImplementedError("Home repair vision analysis not yet implemented. Use mock data.")

    async def analyze_yard_maintenance(
        self,
        image_refs: List[str],
        user_id: str,
    ) -> Dict:
        """Analyze yard for maintenance needs"""
        raise NotImplementedError("Yard maintenance vision analysis not yet implemented. Use mock data.")

    async def assess_pet(
        self,
        image_refs: List[str],
        pet_info: Dict,
        user_id: str,
    ) -> Dict:
        """Assess pet and home setup for pet sitting"""
        raise NotImplementedError("Pet assessment vision analysis not yet implemented. Use mock data.")

    async def analyze_cleaning(
        self,
        image_refs: List[str],
        room_type: Optional[str],
        user_id: str,
    ) -> Dict:
        """Analyze cleaning and organizing needs"""
        raise NotImplementedError("Cleaning analysis vision analysis not yet implemented. Use mock data.")


class OpenAIVisionService:
    """
    OpenAI Vision API service (GPT-4V fallback).
    Used when Muse API fails.
    """

    def __init__(self, api_key: Optional[str] = None):
        self.api_key = api_key or os.getenv("OPENAI_API_KEY")
        if not self.api_key:
            raise RuntimeError("OPENAI_API_KEY must be set to use OpenAI fallback")
        self.client = AsyncOpenAI(api_key=self.api_key)
        self.model = "gpt-4-vision"

    async def _load_image_as_base64(self, image_path: str) -> str:
        """Load image file and convert to base64"""
        try:
            with open(image_path, "rb") as image_file:
                return base64.standard_b64encode(image_file.read()).decode("utf-8")
        except Exception as e:
            logger.error(f"Failed to load image {image_path}: {e}")
            raise

    async def _analyze_with_prompt(self, image_refs: List[str], prompt: str) -> Dict:
        """Send images to OpenAI Vision API with prompt"""
        logger.info(f"📡 Calling OpenAI Vision API (GPT-4V) with {len(image_refs)} image(s)...")
        print(f"📡 Calling OpenAI Vision API (GPT-4V) with {len(image_refs)} image(s)...")

        # Prepare images for OpenAI Vision API
        content = [{"type": "text", "text": prompt}]
        for image_path in image_refs:
            try:
                image_data = await self._load_image_as_base64(image_path)
                content.append({
                    "type": "image_url",
                    "image_url": {
                        "url": f"data:image/jpeg;base64,{image_data}",
                    },
                })
            except Exception as e:
                logger.warning(f"Could not load image {image_path}: {e}")
                continue

        try:
            response = await self.client.chat.completions.create(
                model="gpt-4-vision",
                messages=[{"role": "user", "content": content}],
                max_tokens=2048,
                temperature=0.7,
            )

            response_text = response.choices[0].message.content or ""
            if not response_text or not response_text.strip():
                raise RuntimeError("OpenAI API returned empty response")

            logger.info(f"✅ OpenAI Vision API response received ({len(response_text)} chars)")
            print(f"✅ OpenAI Vision API response received ({len(response_text)} chars)")

            # Parse JSON from response
            try:
                result = json.loads(response_text)
                # Valid JSON response - return it even if low_or_empty is empty
                return result
            except json.JSONDecodeError:
                logger.warning("OpenAI response was not valid JSON, attempting to extract...")
                # Try to extract JSON from response
                start_idx = response_text.find("{")
                end_idx = response_text.rfind("}") + 1
                if start_idx >= 0 and end_idx > start_idx:
                    try:
                        return json.loads(response_text[start_idx:end_idx])
                    except json.JSONDecodeError as e:
                        raise RuntimeError(f"Could not parse OpenAI response as JSON: {e}")
                raise RuntimeError("Could not find JSON in OpenAI response")

        except Exception as e:
            logger.error(f"OpenAI Vision API error: {e}")
            raise

    async def analyze_pantry_vision(self, image_refs: List[str], user_id: str) -> Dict:
        """Analyze pantry with OpenAI Vision"""
        prompt = """Analyze this pantry/fridge photo and detect ALL visible items.

For EVERY item you can see, provide:
1. Exact product name and brand (e.g., "Organic Valley Milk", "Fage Greek Yogurt")
2. Specific size if visible (e.g., "Half gallon", "32 oz", "1 loaf")
3. Current status (full/mostly_full/half/low/nearly_empty/empty)
4. Whether it should be restocked (yes/no) - YES if less than half full or empty
5. Confidence level (0-1)

Return specific product names only - NOT generic categories.

Return ONLY valid JSON:
{
  "detected_items": [
    {
      "name": "Organic Valley Milk Half Gallon",
      "brand": "Organic Valley",
      "status": "low",
      "should_restock": true,
      "reason": "Only about 1/4 full",
      "confidence": 0.92
    },
    {
      "name": "Fage Greek Yogurt 32oz",
      "brand": "Fage",
      "status": "full",
      "should_restock": false,
      "reason": "Recently purchased",
      "confidence": 0.95
    }
  ],
  "summary": "Detected X items, Y need restocking",
  "expiration_warnings": [],
  "recommendations": []
}"""
        return await self._analyze_with_prompt(image_refs, prompt)

    async def analyze_shelf_substitution(self, image_ref: str, original_item: str, user_preferences: Dict, user_id: str) -> Dict:
        """Analyze shelf for alternatives with OpenAI Vision"""
        prompt = f"""The shopper is looking for "{original_item}" but it's out of stock.
Analyze this shelf photo and identify alternatives. User preferences: {json.dumps(user_preferences)}

Return JSON with alternatives ranked by match."""
        result = await self._analyze_with_prompt([image_ref], prompt)
        return {"alternatives": result.get("alternatives", [])}

    async def analyze_receipt(self, image_ref: str, merged_list: List[Dict], trip_id: str, user_id: str) -> Dict:
        """Analyze receipt with OpenAI Vision"""
        prompt = f"""Extract all line items from this receipt.
Return JSON with line_items array and total."""
        result = await self._analyze_with_prompt([image_ref], prompt)
        return {"line_items": result.get("line_items", []), "total": result.get("total", 0)}

    async def analyze_damage(self, image_refs: List[str], room_or_area: Optional[str], user_id: str) -> Dict:
        """Analyze damage with OpenAI Vision"""
        raise NotImplementedError("Home repair analysis not implemented for OpenAI fallback")

    async def analyze_yard_maintenance(self, image_refs: List[str], user_id: str) -> Dict:
        """Analyze yard with OpenAI Vision"""
        raise NotImplementedError("Yard maintenance analysis not implemented for OpenAI fallback")

    async def assess_pet(self, image_refs: List[str], pet_info: Dict, user_id: str) -> Dict:
        """Assess pet with OpenAI Vision"""
        raise NotImplementedError("Pet assessment not implemented for OpenAI fallback")

    async def analyze_cleaning(self, image_refs: List[str], room_type: Optional[str], user_id: str) -> Dict:
        """Analyze cleaning needs with OpenAI Vision"""
        raise NotImplementedError("Cleaning analysis not implemented for OpenAI fallback")


class MockVisionService:
    """
    Mock vision service for development/testing.
    Returns realistic placeholder responses without calling actual VLM.
    """

    async def analyze_pantry_vision(
        self,
        image_refs: List[str],
        user_id: str,
    ) -> Dict:
        """Mock pantry detection"""
        return {
            "detected_items": [
                {
                    "name": "Milk",
                    "brand": "Organic Valley",
                    "size": "Half gallon",
                    "status": "half",
                    "expiration": "2026-09-28",
                    "confidence": 0.95,
                },
                {
                    "name": "Greek Yogurt",
                    "brand": "Fage",
                    "size": "32 oz",
                    "status": "empty",
                    "confidence": 0.92,
                },
                {
                    "name": "Bread",
                    "brand": "Trader Joe's",
                    "size": "1 loaf",
                    "status": "low",
                    "confidence": 0.88,
                },
            ],
            "low_or_empty": ["Greek Yogurt", "Bread"],
            "summary": "Pantry is 40% full. Milk half remaining, yogurt and bread need restocking.",
        }

    async def analyze_shelf_substitution(
        self,
        image_ref: str,
        original_item: str,
        user_preferences: Dict,
        user_id: str,
    ) -> Dict:
        """Mock shelf substitution detection"""
        return {
            "original_request": original_item,
            "alternatives": [
                {
                    "name": "Chobani Greek Yogurt",
                    "brand": "Chobani",
                    "size": "32 oz",
                    "price": "$6.99",
                    "similarity_score": 8,
                    "match_reasoning": "Same type (Greek), similar price",
                },
                {
                    "name": "Dannon Yogurt",
                    "brand": "Dannon",
                    "size": "32 oz",
                    "price": "$5.49",
                    "similarity_score": 6,
                    "match_reasoning": "Regular yogurt, budget-friendly",
                },
                {
                    "name": "Skyr",
                    "brand": "Siggi's",
                    "size": "4-pack",
                    "price": "$7.49",
                    "similarity_score": 7,
                    "match_reasoning": "Icelandic yogurt, similar nutrition",
                },
            ],
            "no_stock_warning": False,
        }

    async def analyze_receipt(
        self,
        image_ref: str,
        merged_list: List[Dict],
        trip_id: str,
        user_id: str,
    ) -> Dict:
        """Mock receipt splitting"""
        return {
            "line_items": [
                {
                    "item_name": "Organic Milk Half Gal",
                    "quantity": 1,
                    "unit_price": 4.99,
                    "line_total": 4.99,
                    "matched_to": "Bob",
                    "confidence": 0.95,
                },
                {
                    "item_name": "Fage Greek Yogurt 32oz",
                    "quantity": 1,
                    "unit_price": 7.99,
                    "line_total": 7.99,
                    "matched_to": "Charlie",
                    "confidence": 0.90,
                },
                {
                    "item_name": "Whole Wheat Bread",
                    "quantity": 1,
                    "unit_price": 3.49,
                    "line_total": 3.49,
                    "matched_to": "Bob",
                    "confidence": 0.85,
                },
            ],
            "subtotal": 16.47,
            "tax": 1.32,
            "total": 17.79,
            "summary_by_requester": {
                "Bob": {"subtotal": 8.48, "tax_share": 0.68, "total": 9.16},
                "Charlie": {"subtotal": 7.99, "tax_share": 0.64, "total": 8.63},
            },
        }

    async def analyze_damage(
        self,
        image_refs: List[str],
        room_or_area: Optional[str],
        user_id: str,
    ) -> Dict:
        """Mock damage detection"""
        return {
            "damage_assessment": [
                {
                    "issue_type": "Cracked drywall",
                    "location": "Living room wall",
                    "severity": "moderate",
                    "difficulty": "medium",
                    "estimated_hours": 2.5,
                    "materials": [
                        {"name": "Drywall patch kit", "cost": "$20"},
                        {"name": "Joint compound", "cost": "$12"},
                        {"name": "Paint", "cost": "$30"},
                    ],
                    "professional_recommended": False,
                    "urgency": "medium",
                },
            ],
            "overall_assessment": "Moderate drywall repair needed. Can be DIY.",
            "total_diy_hours": 2.5,
            "total_estimated_cost": "$62-75",
        }

    async def analyze_yard_maintenance(
        self,
        image_refs: List[str],
        user_id: str,
    ) -> Dict:
        """Mock yard maintenance detection"""
        return {
            "maintenance_tasks": [
                {
                    "task_type": "Leaf cleanup",
                    "location": "Front yard",
                    "severity": "moderate",
                    "estimated_hours": 3,
                    "tools": ["Rake", "Wheelbarrow", "Leaf blower"],
                    "priority": 1,
                },
                {
                    "task_type": "Trim overgrown hedge",
                    "location": "East fence",
                    "severity": "moderate",
                    "estimated_hours": 2,
                    "tools": ["Hedge trimmer", "Rake"],
                    "priority": 2,
                },
            ],
            "overall_assessment": "Fall cleanup needed: leaves and light trimming",
            "total_estimated_hours": 5,
        }

    async def assess_pet(
        self,
        image_refs: List[str],
        pet_info: Dict,
        user_id: str,
    ) -> Dict:
        """Mock pet assessment"""
        return {
            "pet_assessment": {
                "observable_behavior": "Friendly, energetic, well-socialized",
                "physical_condition": "Healthy, good coat",
                "care_difficulty": "moderate",
                "exercise_level": "high",
            },
            "caretaker_requirements": {
                "experience_level": "intermediate",
                "required_skills": ["Leash training", "Boundary setting"],
                "physical_requirements": "Moderate strength",
                "time_per_day": "3-4 hours",
            },
            "caretaker_recommendation": "Good for intermediate caretakers who are active",
        }

    async def analyze_cleaning(
        self,
        image_refs: List[str],
        room_type: Optional[str],
        user_id: str,
    ) -> Dict:
        """Mock cleaning analysis"""
        return {
            "clutter_assessment": {
                "clutter_level": "moderate",
                "clutter_types": ["Clothes", "Papers", "Misc items"],
                "floor_accessibility": "70%",
            },
            "cleaning_needs": {
                "dust_level": "moderate",
                "tasks": ["Vacuum", "Dust surfaces", "Wipe desk"],
                "priority_order": ["Vacuum", "Dust", "Wipe surfaces"],
            },
            "organizing_needs": {
                "strategy": "Zone-based",
                "storage_needed": ["Desk organizer", "Under-bed bins"],
            },
            "time_estimate": {
                "total_combined": "4-5 hours",
            },
            "recommendation": "Standard bedroom refresh combining cleaning and light organizing",
        }
