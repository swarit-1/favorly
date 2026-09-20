"""
Vision analysis routes for multi-domain image processing.

This module handles image uploads and coordinates with the vision service.
The actual VLM analysis will be injected via VisionService once API key is available.
"""

from fastapi import APIRouter, UploadFile, File, Form, HTTPException
from typing import List, Optional
import uuid
import json
import logging
from pydantic import BaseModel
from datetime import datetime

from services.image_storage_service import ImageStorageService
from services.vision_service import VisionService, MockVisionService

router = APIRouter(prefix="/vision", tags=["vision"])
logger = logging.getLogger(__name__)

# Initialize services
image_storage = ImageStorageService()
vision_service = MockVisionService()  # Will replace with real VisionService when API key available


class AnalysisResponse(BaseModel):
    """Generic response for all vision analyses"""
    analysis_id: str
    domain_type: str
    detected_items: dict
    summary: str
    image_refs: List[str]
    analyzed_at: str
    is_placeholder: bool = True  # Mark as placeholder until real VLM is available


@router.post("/grocery/pantry-scan")
async def scan_pantry(
    files: List[UploadFile] = File(...),
):
    """
    Scan fridge/pantry photos for product detection

    Returns:
    - detected_items: List of products found with quantities
    - low_or_empty: Items that are low or empty
    - suggestions: Smart suggestions based on detected items
    """
    try:
        # Upload images
        image_refs = await image_storage.upload_images(
            files=files,
            user_id="demo_user",  # Placeholder
            domain="grocery_shopping"
        )

        # Analyze (placeholder until API key available)
        analysis_result = await vision_service.analyze_pantry_vision(
            image_refs=image_refs,
            user_id="demo_user"
        )

        return AnalysisResponse(
            analysis_id=str(uuid.uuid4()),
            domain_type="grocery_shopping",
            detected_items=analysis_result["detected_items"],
            summary=analysis_result["summary"],
            image_refs=image_refs,
            analyzed_at=datetime.utcnow().isoformat(),
            is_placeholder=True,
        )

    except Exception as e:
        logger.error(f"Error in pantry scan: {e}")
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
            detected_items=analysis_result["alternatives"],
            summary=f"Found {len(analysis_result.get('alternatives', []))} alternatives for {original_item}",
            image_refs=[image_ref],
            analyzed_at=datetime.utcnow().isoformat(),
            is_placeholder=True,
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
    return {
        "status": "ok",
        "vision_service": "mock" if isinstance(vision_service, MockVisionService) else "real",
        "image_storage": "ready",
    }
