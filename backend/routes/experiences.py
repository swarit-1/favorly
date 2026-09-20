"""Experience ratings and member compatibility routes."""

from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel, Field
from typing import List, Optional
from uuid import UUID
from datetime import datetime

from db.client import get_supabase_client
from shared.contracts.models import ExperienceRating, MemberCompatibility
from shared.timestamps import parse_timestamp

router = APIRouter(prefix="/experiences", tags=["experiences"])


# ============================================================================
# REQUEST/RESPONSE MODELS
# ============================================================================

class SubmitRatingRequest(BaseModel):
    """Request body for submitting an experience rating."""
    trip_id: UUID
    circle_id: UUID
    rated_by_id: UUID
    rated_id: UUID
    overall_rating: int = Field(ge=1, le=5)
    reliability_rating: Optional[int] = Field(None, ge=1, le=5)
    accuracy_rating: Optional[int] = Field(None, ge=1, le=5)
    communication_rating: Optional[int] = Field(None, ge=1, le=5)
    comment: Optional[str] = None


# ============================================================================
# ENDPOINTS
# ============================================================================

@router.post("", response_model=ExperienceRating)
async def submit_experience_rating(request: SubmitRatingRequest):
    """
    Submit an experience rating after a trip.

    One person rates another person for a specific trip.
    The UNIQUE constraint on (trip_id, rated_by_id, rated_id) prevents duplicate ratings.
    """
    supabase = get_supabase_client()

    try:
        # Insert the experience rating
        rating_data = {
            "trip_id": str(request.trip_id),
            "circle_id": str(request.circle_id),
            "rated_by_id": str(request.rated_by_id),
            "rated_id": str(request.rated_id),
            "overall_rating": request.overall_rating,
            "reliability_rating": request.reliability_rating,
            "accuracy_rating": request.accuracy_rating,
            "communication_rating": request.communication_rating,
            "comment": request.comment,
        }

        response = supabase.table("experience_ratings").insert(rating_data).execute()

        if not response.data:
            raise HTTPException(status_code=400, detail="Failed to create experience rating")

        rating = response.data[0]
        return ExperienceRating(
            id=rating["id"],
            trip_id=rating["trip_id"],
            circle_id=rating["circle_id"],
            rated_by_id=rating["rated_by_id"],
            rated_id=rating["rated_id"],
            overall_rating=rating["overall_rating"],
            reliability_rating=rating.get("reliability_rating"),
            accuracy_rating=rating.get("accuracy_rating"),
            communication_rating=rating.get("communication_rating"),
            comment=rating.get("comment"),
            created_at=parse_timestamp(rating["created_at"]),
        )
    except HTTPException:
        raise
    except Exception as e:
        # Check if it's a unique constraint violation (duplicate rating)
        error_msg = str(e)
        if "unique" in error_msg.lower():
            raise HTTPException(
                status_code=409,
                detail="You have already rated this person for this trip"
            )
        raise HTTPException(status_code=400, detail=str(e))


@router.get("", response_model=List[ExperienceRating])
async def get_experiences(
    rated_id: Optional[UUID] = None,
    rated_by_id: Optional[UUID] = None,
    trip_id: Optional[UUID] = None,
):
    """
    Get experience ratings with optional filters.

    - rated_id: Get all ratings about a specific person
    - rated_by_id: Get all ratings given by a specific person
    - trip_id: Get all ratings for a specific trip
    """
    supabase = get_supabase_client()

    try:
        query = supabase.table("experience_ratings").select("*")

        if rated_id:
            query = query.eq("rated_id", str(rated_id))
        if rated_by_id:
            query = query.eq("rated_by_id", str(rated_by_id))
        if trip_id:
            query = query.eq("trip_id", str(trip_id))

        response = query.execute()

        ratings = []
        for rating in response.data:
            ratings.append(ExperienceRating(
                id=rating["id"],
                trip_id=rating["trip_id"],
                circle_id=rating["circle_id"],
                rated_by_id=rating["rated_by_id"],
                rated_id=rating["rated_id"],
                overall_rating=rating["overall_rating"],
                reliability_rating=rating.get("reliability_rating"),
                accuracy_rating=rating.get("accuracy_rating"),
                communication_rating=rating.get("communication_rating"),
                comment=rating.get("comment"),
                created_at=parse_timestamp(rating["created_at"]),
            ))
        return ratings
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/members/{member_id}/recommendations")
async def get_member_recommendations(
    member_id: UUID,
    circle_id: UUID,
    limit: int = 3,
):
    """
    Get top recommended partners for a member in a circle.

    Uses the member_compatibility_cache table to return members
    this person works best with, sorted by compatibility score.
    """
    supabase = get_supabase_client()

    try:
        # Query the cache table for high-compatibility scores
        # Include both member_id_1 and member_id_2 columns since
        # canonical ordering means either could be our member
        response = supabase.table("member_compatibility_cache").select("*").eq(
            "circle_id", str(circle_id)
        ).execute()

        # Filter and sort recommendations
        recommendations = []
        for compat in response.data:
            # Check both columns to find the other member
            if str(member_id) == str(compat["member_id_1"]):
                other_member_id = compat["member_id_2"]
            elif str(member_id) == str(compat["member_id_2"]):
                other_member_id = compat["member_id_1"]
            else:
                continue  # This compatibility record doesn't involve this member

            recommendations.append({
                "member_id": other_member_id,
                "compatibility_score": float(compat["score"]),
                "trips_worked_together": compat["trips_worked_together"],
                "average_rating": float(compat["average_rating"]) if compat["average_rating"] else None,
            })

        # Sort by score descending, return top N
        recommendations.sort(key=lambda x: x["compatibility_score"], reverse=True)
        return recommendations[:limit]
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/refresh-compatibility")
async def refresh_compatibility_cache(circle_id: Optional[UUID] = None):
    """
    Refresh the member compatibility cache.

    This should be called after each trip completes to recompute
    compatibility scores based on new experience ratings.

    - If circle_id is provided, only refresh that circle's cache
    - If circle_id is None, refresh all circles
    """
    supabase = get_supabase_client()

    try:
        # Call the PostgreSQL function to refresh the cache
        # The function signature is: refresh_member_compatibility(p_circle_id UUID DEFAULT NULL)
        if circle_id:
            response = supabase.rpc(
                "refresh_member_compatibility",
                {"p_circle_id": str(circle_id)}
            ).execute()
        else:
            response = supabase.rpc("refresh_member_compatibility").execute()

        return {"status": "ok", "message": "Compatibility cache refreshed"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
