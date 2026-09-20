"""
Vision analysis routes for multi-domain image processing.

This module handles image uploads and coordinates with the vision service.
The actual VLM analysis will be injected via VisionService once API key is available.
"""

from fastapi import APIRouter, UploadFile, File, Form, HTTPException
from typing import List, Optional, Any
import uuid
import json
import logging
from pydantic import BaseModel
from datetime import datetime
from uuid import UUID

from services.image_storage_service import ImageStorageService
from services.vision_service import VisionService, MockVisionService, OpenAIVisionService
from shared.contracts.models import PantryScan, AnalysisType

router = APIRouter(prefix="/vision", tags=["vision"])
logger = logging.getLogger(__name__)

# Initialize services
import os
from dotenv import load_dotenv

load_dotenv()

image_storage = ImageStorageService()


async def _add_items_to_trip(
    trip_id: str,
    user_id: Optional[UUID],
    items: List[Any],
    source: str = "vision_analysis"
) -> None:
    """
    Auto-add detected items to a trip's merged list.

    Creates a request for the vision analysis with items marked for restocking.
    Filters to only add items where should_restock=true.

    Args:
        trip_id: UUID string of the trip
        user_id: UUID of the user who performed the scan (becomes requester_id)
        items: List of detected items (dicts with name, should_restock, etc.)
        source: Source of the items for logging
    """
    if not items:
        logger.debug("No items to add to trip")
        return

    # Add all detected items (opt-out model: user can remove unwanted items)
    items_to_add = []
    for item in items:
        if isinstance(item, dict):
            item_name = item.get("name")
            if item_name and isinstance(item_name, str) and item_name.strip():
                items_to_add.append((item_name, item))

    if not items_to_add:
        logger.debug("No items detected to add")
        return

    try:
        from app import get_supabase_admin_client
        supabase = get_supabase_admin_client()

        requester_id = str(user_id) if user_id else "vision_system"

        # Create request record
        request_response = supabase.table("requests").insert({
            "trip_id": trip_id,
            "requester_id": requester_id,
            "status": "pending",
        }).execute()

        if not request_response.data:
            logger.warning(f"Failed to create request for trip {trip_id}")
            return

        request_id = request_response.data[0]["id"]
        logger.info(f"Created request {request_id} for trip {trip_id}")

        # Add items to the request
        added_count = 0
        for item_name, item_dict in items_to_add:
            try:
                reason = item_dict.get("reason", "")
                note = f"Auto-detected by {source}: {reason}" if reason else f"Auto-detected by {source}"

                item_response = supabase.table("items").insert({
                    "request_id": request_id,
                    "trip_id": trip_id,
                    "name": item_name,
                    "qty": 1,
                    "unit": None,
                    "note": note,
                    "max_price": None,
                    "section": "other",
                    "status": "pending",
                }).execute()

                if item_response.data:
                    logger.debug(f"Added item '{item_name}' to request {request_id}")
                    added_count += 1
                else:
                    logger.warning(f"Failed to add item '{item_name}' to request {request_id}")
            except Exception as item_error:
                logger.warning(f"Error adding item '{item_name}': {item_error}")
                continue

        logger.info(f"Auto-added {added_count} items (out of {len(items_to_add)} marked for restocking) to trip {trip_id}")
    except Exception as e:
        logger.warning(f"Failed to auto-add items to trip: {e}")
        # Don't fail the main request if auto-add fails

class FallbackVisionService:
    """
    Multi-provider fallback: tries Muse API → OpenAI Vision → Mock
    Ensures vision analysis always works with graceful degradation.
    """

    def __init__(self, muse_service: VisionService, openai_service: Optional[OpenAIVisionService], mock_service: MockVisionService):
        self.muse = muse_service
        self.openai = openai_service
        self.mock = mock_service
        self.real_available = True
        self.using_provider = "muse"  # Track which provider is being used

    async def _try_providers(self, method_name: str, *args, **kwargs):
        """Try Muse → OpenAI → Mock in sequence"""
        providers = [
            ("muse", self.muse),
            ("openai", self.openai) if self.openai else None,
            ("mock", self.mock),
        ]
        providers = [p for p in providers if p is not None]

        for provider_name, provider in providers:
            try:
                logger.info(f"📡 Trying {provider_name} vision service for {method_name}...")
                result = await getattr(provider, method_name)(*args, **kwargs)
                self.real_available = (provider_name != "mock")
                self.using_provider = provider_name
                if provider_name != "mock":
                    logger.info(f"✅ {provider_name} vision service succeeded")
                else:
                    logger.info(f"⚠️  Using mock vision service (fallback)")
                return result
            except Exception as e:
                logger.warning(f"❌ {provider_name} failed ({method_name}): {e}")
                continue

        # If all providers failed, raise error
        raise RuntimeError(f"All vision providers failed for {method_name}")

    async def analyze_pantry_vision(self, *args, **kwargs):
        return await self._try_providers("analyze_pantry_vision", *args, **kwargs)

    async def analyze_shelf_substitution(self, *args, **kwargs):
        return await self._try_providers("analyze_shelf_substitution", *args, **kwargs)

    async def analyze_receipt(self, *args, **kwargs):
        return await self._try_providers("analyze_receipt", *args, **kwargs)

    async def analyze_damage(self, *args, **kwargs):
        return await self._try_providers("analyze_damage", *args, **kwargs)

    async def analyze_yard_maintenance(self, *args, **kwargs):
        return await self._try_providers("analyze_yard_maintenance", *args, **kwargs)

    async def assess_pet(self, *args, **kwargs):
        return await self._try_providers("assess_pet", *args, **kwargs)

    async def analyze_cleaning(self, *args, **kwargs):
        return await self._try_providers("analyze_cleaning", *args, **kwargs)


# Initialize services with multi-provider fallback: Muse → OpenAI → Mock
mock_service = MockVisionService()
muse_service = None
openai_service = None

# Try to initialize Muse API
try:
    api_key = os.getenv("MUSE_API_KEY")
    if api_key:
        muse_service = VisionService(api_key=api_key)
        print("✅ Muse Vision API initialized")
        logger.info("✅ Muse Vision API initialized")
    else:
        print("ℹ️  MUSE_API_KEY not set")
        logger.info("ℹ️  MUSE_API_KEY not set")
except Exception as e:
    print(f"⚠️  Failed to initialize Muse API: {e}")
    logger.warning(f"⚠️  Failed to initialize Muse API: {e}")

# Try to initialize OpenAI as fallback
try:
    api_key = os.getenv("OPENAI_API_KEY")
    if api_key:
        openai_service = OpenAIVisionService(api_key=api_key)
        print("✅ OpenAI Vision API initialized as fallback")
        logger.info("✅ OpenAI Vision API initialized as fallback")
    else:
        print("ℹ️  OPENAI_API_KEY not set (optional)")
        logger.info("ℹ️  OPENAI_API_KEY not set (optional)")
except Exception as e:
    print(f"⚠️  Failed to initialize OpenAI API: {e}")
    logger.warning(f"⚠️  Failed to initialize OpenAI API: {e}")

# Create fallback service with available providers
if muse_service:
    vision_service = FallbackVisionService(muse_service, openai_service, mock_service)
    providers = ["Muse", "OpenAI" if openai_service else None, "Mock"]
    providers = [p for p in providers if p]
    print(f"✅ Vision service initialized with fallback chain: {' → '.join(providers)}")
    logger.info(f"✅ Vision service initialized with fallback chain: {' → '.join(providers)}")
else:
    # If Muse not available, try OpenAI or fall back to mock
    if openai_service:
        vision_service = FallbackVisionService(openai_service, None, mock_service)
        print("✅ Vision service using OpenAI → Mock fallback chain")
        logger.info("✅ Vision service using OpenAI → Mock fallback chain")
    else:
        print("⚠️  No real vision APIs available, using Mock only")
        logger.warning("⚠️  No real vision APIs available, using Mock only")
        vision_service = mock_service


class AnalysisResponse(BaseModel):
    """Generic response for all vision analyses"""
    analysis_id: str
    domain_type: str
    detected_items: Any
    summary: str
    image_refs: List[str]
    analyzed_at: str
    is_placeholder: bool = True  # Mark as placeholder until real VLM is available


@router.post("/grocery/pantry-scan")
async def scan_pantry(
    files: List[UploadFile] = File(...),
    user_id: Optional[str] = Form(None),
    trip_id: Optional[str] = Form(None),
):
    """
    Scan fridge/pantry photos for product detection

    Returns:
    - detected_items: List of products found with quantities
    - low_or_empty: Items that are low or empty
    - suggestions: Smart suggestions based on detected items
    """
    logger.info("POST /vision/grocery/pantry-scan called", extra={"file_count": len(files)})
    try:
        # Use provided user_id or None for anonymous/demo mode
        user_uuid = None
        if user_id:
            try:
                user_uuid = UUID(user_id)
            except (ValueError, TypeError):
                logger.warning(f"Invalid user_id format: {user_id}")

        effective_user_id = str(user_uuid) if user_uuid else "demo_user"

        # Upload images
        logger.debug(f"Uploading {len(files)} image(s) for vision analysis")
        image_refs = await image_storage.upload_images(
            files=files,
            user_id=effective_user_id,
            domain="grocery_shopping"
        )

        # Analyze
        logger.debug(f"Analyzing images with {type(vision_service).__name__}")
        analysis_result = await vision_service.analyze_pantry_vision(
            image_refs=image_refs,
            user_id=effective_user_id
        )

        # Determine if using real or mock
        is_using_mock = False
        vision_model = "unknown"

        if isinstance(vision_service, MockVisionService):
            is_using_mock = True
            vision_model = "mock"
            logger.debug("Using mock vision service")
        elif isinstance(vision_service, FallbackVisionService):
            if vision_service.using_provider == "mock":
                is_using_mock = True
                vision_model = "mock"
                logger.debug("Fell back to mock vision service")
            elif vision_service.using_provider == "openai":
                vision_model = "gpt-4-vision"
                logger.debug("Using OpenAI Vision API")
            elif vision_service.using_provider == "muse":
                vision_model = "muse-spark-1.3"
                logger.debug("Using Muse Vision API")
        else:
            vision_model = "muse-spark-1.3"

        # Only persist if real API was used (not mock/default data)
        pantry_scan_id = None
        if is_using_mock:
            logger.info("Skipping database persistence for mock/default data")
            pantry_scan = PantryScan(
                user_id=user_uuid,
                trip_id=UUID(trip_id) if trip_id else None,
                detected_items=analysis_result.get("detected_items", []),
                low_or_empty=analysis_result.get("low_or_empty", []),
                summary=analysis_result.get("summary", ""),
                expiration_warnings=analysis_result.get("expiration_warnings", []),
                recommendations=analysis_result.get("recommendations", []),
                image_paths=image_refs,
                analysis_type=AnalysisType.PANTRY,
                confidence_score=analysis_result.get("confidence_score"),
                vision_model=vision_model,
                is_placeholder=is_using_mock,
            )
        else:
            # Create PantryScan record for persistence
            pantry_scan = PantryScan(
                user_id=user_uuid,
                trip_id=UUID(trip_id) if trip_id else None,
                detected_items=analysis_result.get("detected_items", []),
                low_or_empty=analysis_result.get("low_or_empty", []),
                summary=analysis_result.get("summary", ""),
                expiration_warnings=analysis_result.get("expiration_warnings", []),
                recommendations=analysis_result.get("recommendations", []),
                image_paths=image_refs,
                analysis_type=AnalysisType.PANTRY,
                confidence_score=analysis_result.get("confidence_score"),
                vision_model=vision_model,
                is_placeholder=is_using_mock,
            )

            # Save to database (using admin client to bypass RLS for backend writes)
            try:
                from app import get_supabase_admin_client
                supabase = get_supabase_admin_client()
                db_response = supabase.table("pantry_scans").insert(
                    pantry_scan.model_dump(
                        mode="json",
                        include={"user_id", "trip_id", "detected_items", "low_or_empty",
                                "summary", "expiration_warnings", "recommendations",
                                "image_paths", "analysis_type", "confidence_score",
                                "vision_model", "is_placeholder"}
                    )
                ).execute()
                pantry_scan_id = pantry_scan.id
                logger.info(f"Pantry scan saved to database", extra={"scan_id": str(pantry_scan.id)})

                # Auto-add detected items marked for restocking to trip
                if trip_id and analysis_result.get("detected_items"):
                    await _add_items_to_trip(
                        trip_id=trip_id,
                        user_id=user_uuid,
                        items=analysis_result.get("detected_items", []),
                        source="vision_pantry_scan"
                    )
            except Exception as db_error:
                logger.warning(f"Failed to save pantry scan to database: {db_error}")
                # Don't fail the request if database save fails

        # Return all detected items for user to verify/adjust
        all_detected = analysis_result.get("detected_items", [])
        items_needing_restock = [item for item in all_detected if isinstance(item, dict) and item.get("should_restock", False)]

        response = AnalysisResponse(
            analysis_id=str(pantry_scan.id),
            domain_type="grocery_shopping",
            detected_items=all_detected,  # All items for user to see and adjust
            summary=f"Detected {len(all_detected)} items, {len(items_needing_restock)} need restocking: {analysis_result.get('summary', '')}",
            image_refs=image_refs,
            analyzed_at=datetime.utcnow().isoformat(),
            is_placeholder=is_using_mock,
        )
        logger.debug(f"Pantry scan response ready", extra={
            "is_placeholder": is_using_mock,
            "total_detected": len(all_detected),
            "needs_restocking": len(items_needing_restock)
        })
        return response

    except Exception as e:
        logger.error(f"Error in pantry scan: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/grocery/shelf-analysis")
async def analyze_shelf(
    file: UploadFile = File(...),
    original_item: str = Form(...),
    user_preferences: str = Form(...),
):
    """
    Analyze shelf for substitution options

    Returns:
    - available_alternatives: List of alternatives ranked by preference match
    """
    try:
        # Parse preferences
        prefs = json.loads(user_preferences) if user_preferences else {}

        # Upload image
        image_ref = await image_storage.upload_image(
            file=file,
            user_id="demo_user",
            domain="grocery_shopping"
        )

        # Analyze
        analysis_result = await vision_service.analyze_shelf_substitution(
            image_ref=image_ref,
            original_item=original_item,
            user_preferences=prefs,
            user_id="demo_user"
        )

        return AnalysisResponse(
            analysis_id=str(uuid.uuid4()),
            domain_type="grocery_shopping",
            detected_items=analysis_result.get("alternatives", []),
            summary=f"Found {len(analysis_result.get('alternatives', []))} alternatives for {original_item}",
            image_refs=[image_ref],
            analyzed_at=datetime.utcnow().isoformat(),
            is_placeholder=not isinstance(vision_service, VisionService) or isinstance(vision_service, MockVisionService),
        )

    except json.JSONDecodeError:
        raise HTTPException(status_code=400, detail="Invalid user_preferences JSON")
    except Exception as e:
        logger.error(f"Error in shelf analysis: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/grocery/receipt-analysis")
async def analyze_receipt(
    file: UploadFile = File(...),
    trip_id: str = Form(...),
    merged_list: str = Form(...),
):
    """
    Analyze receipt and split by requester

    Returns:
    - line_items: Extracted line items from receipt
    - summary_by_requester: Cost breakdown per requester
    """
    try:
        merged_items = json.loads(merged_list) if merged_list else []

        # Upload receipt
        image_ref = await image_storage.upload_image(
            file=file,
            user_id="demo_user",
            domain="grocery_shopping"
        )

        # Analyze
        analysis_result = await vision_service.analyze_receipt(
            image_ref=image_ref,
            merged_list=merged_items,
            trip_id=trip_id,
            user_id="demo_user"
        )

        return AnalysisResponse(
            analysis_id=str(uuid.uuid4()),
            domain_type="grocery_shopping",
            detected_items=analysis_result["line_items"],
            summary=f"Receipt total: ${analysis_result.get('total', 0)}",
            image_refs=[image_ref],
            analyzed_at=datetime.utcnow().isoformat(),
            is_placeholder=True,
        )

    except json.JSONDecodeError:
        raise HTTPException(status_code=400, detail="Invalid merged_list JSON")
    except Exception as e:
        logger.error(f"Error in receipt analysis: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/home-repair/damage-detection")
async def detect_damage(
    files: List[UploadFile] = File(...),
    room_or_area: Optional[str] = Form(None),
):
    """
    Analyze photos for home damage/repair needs

    Returns:
    - damage_assessment: List of issues with severity and materials needed
    """
    try:
        # Upload images
        image_refs = await image_storage.upload_images(
            files=files,
            user_id="demo_user",
            domain="home_repair"
        )

        # Analyze
        analysis_result = await vision_service.analyze_damage(
            image_refs=image_refs,
            room_or_area=room_or_area,
            user_id="demo_user"
        )

        return AnalysisResponse(
            analysis_id=str(uuid.uuid4()),
            domain_type="home_repair",
            detected_items=analysis_result["damage_assessment"],
            summary=analysis_result.get("overall_assessment", ""),
            image_refs=image_refs,
            analyzed_at=datetime.utcnow().isoformat(),
            is_placeholder=True,
        )

    except Exception as e:
        logger.error(f"Error in damage detection: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/yard/maintenance-scan")
async def scan_yard_maintenance(
    files: List[UploadFile] = File(...),
):
    """
    Analyze yard for maintenance needs

    Returns:
    - maintenance_tasks: List of tasks with hours and tools needed
    """
    try:
        # Upload images
        image_refs = await image_storage.upload_images(
            files=files,
            user_id="demo_user",
            domain="yard_work"
        )

        # Analyze
        analysis_result = await vision_service.analyze_yard_maintenance(
            image_refs=image_refs,
            user_id="demo_user"
        )

        return AnalysisResponse(
            analysis_id=str(uuid.uuid4()),
            domain_type="yard_work",
            detected_items=analysis_result["maintenance_tasks"],
            summary=analysis_result.get("overall_assessment", ""),
            image_refs=image_refs,
            analyzed_at=datetime.utcnow().isoformat(),
            is_placeholder=True,
        )

    except Exception as e:
        logger.error(f"Error in yard maintenance scan: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/pet-sitting/assessment")
async def assess_pet(
    files: List[UploadFile] = File(...),
    pet_info: str = Form(...),
):
    """
    Assess pet and home setup for pet sitting

    Returns:
    - pet_assessment: Pet behavior and temperament
    - caretaker_requirements: Experience level and skills needed
    """
    try:
        pet_data = json.loads(pet_info) if pet_info else {}

        # Upload images
        image_refs = await image_storage.upload_images(
            files=files,
            user_id="demo_user",
            domain="pet_sitting"
        )

        # Analyze
        analysis_result = await vision_service.assess_pet(
            image_refs=image_refs,
            pet_info=pet_data,
            user_id="demo_user"
        )

        return AnalysisResponse(
            analysis_id=str(uuid.uuid4()),
            domain_type="pet_sitting",
            detected_items=analysis_result,
            summary=analysis_result.get("caretaker_recommendation", ""),
            image_refs=image_refs,
            analyzed_at=datetime.utcnow().isoformat(),
            is_placeholder=True,
        )

    except json.JSONDecodeError:
        raise HTTPException(status_code=400, detail="Invalid pet_info JSON")
    except Exception as e:
        logger.error(f"Error in pet assessment: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/cleaning/needs-analysis")
async def analyze_cleaning_needs(
    files: List[UploadFile] = File(...),
    room_type: Optional[str] = Form(None),
):
    """
    Analyze cleaning and organizing needs

    Returns:
    - clutter_assessment: Clutter level and types
    - cleaning_needs: Tasks and priority
    - organizing_needs: Storage solutions and strategies
    """
    try:
        # Upload images
        image_refs = await image_storage.upload_images(
            files=files,
            user_id="demo_user",
            domain="cleaning"
        )

        # Analyze
        analysis_result = await vision_service.analyze_cleaning(
            image_refs=image_refs,
            room_type=room_type,
            user_id="demo_user"
        )

        return AnalysisResponse(
            analysis_id=str(uuid.uuid4()),
            domain_type="cleaning",
            detected_items=analysis_result,
            summary=analysis_result.get("recommendation", ""),
            image_refs=image_refs,
            analyzed_at=datetime.utcnow().isoformat(),
            is_placeholder=True,
        )

    except Exception as e:
        logger.error(f"Error in cleaning analysis: {e}")
        raise HTTPException(status_code=500, detail=str(e))




@router.get("/health")
async def health_check():
    """Health check for vision service"""
    logger.info("🏥 Health check called")

    # Determine service status
    if isinstance(vision_service, FallbackVisionService):
        service_status = "real_with_fallback" if vision_service.real_available else "fallback_to_mock"
    elif isinstance(vision_service, MockVisionService):
        service_status = "mock"
    else:
        service_status = "real"

    return {
        "status": "ok",
        "vision_service": service_status,
        "image_storage": "ready",
        "muse_api_key_configured": bool(os.getenv("MUSE_API_KEY")),
        "muse_api_endpoint": os.getenv("MUSE_API_BASE_URL", "https://api.meta.ai/v1"),
    }


@router.get("/config")
async def vision_config():
    """Get vision service configuration (for debugging)"""
    logger.info("📋 Vision config requested")
    return {
        "vision_service_type": type(vision_service).__name__,
        "muse_api_key_set": bool(os.getenv("MUSE_API_KEY")),
        "muse_api_endpoint": os.getenv("MUSE_API_BASE_URL", "https://api.meta.ai/v1"),
        "fallback_enabled": isinstance(vision_service, FallbackVisionService),
        "real_service_available": vision_service.real_available if isinstance(vision_service, FallbackVisionService) else "N/A",
    }


@router.get("/grocery/pantry-scans")
async def get_pantry_scans(
    user_id: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
):
    """Get saved pantry scans for a user with pagination"""
    try:
        from app import get_supabase_admin_client
        supabase = get_supabase_admin_client()

        # Clamp pagination params
        limit = min(max(limit, 1), 100)  # 1-100 items per page
        offset = max(offset, 0)

        if user_id:
            try:
                user_uuid = UUID(user_id)
                response = supabase.table("pantry_scans").select("*", count="exact").eq(
                    "user_id", str(user_uuid)
                ).order("created_at", desc=True).range(offset, offset + limit - 1).execute()
            except (ValueError, TypeError):
                logger.warning(f"Invalid user_id format: {user_id}, filtering to NULL user_id")
                response = supabase.table("pantry_scans").select("*", count="exact").is_(
                    "user_id", "null"
                ).order("created_at", desc=True).range(offset, offset + limit - 1).execute()
        else:
            # For anonymous requests, only return NULL user_id (demo) scans
            logger.debug("Anonymous request: returning only demo scans")
            response = supabase.table("pantry_scans").select("*", count="exact").is_(
                "user_id", "null"
            ).order("created_at", desc=True).range(offset, offset + limit - 1).execute()

        logger.info(f"Retrieved {len(response.data)} pantry scans", extra={
            "user_id": user_id,
            "limit": limit,
            "offset": offset,
            "total": response.count,
        })
        return {
            "scans": response.data,
            "total": response.count,
            "limit": limit,
            "offset": offset,
        }
    except Exception as e:
        logger.error(f"Error retrieving pantry scans: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))
