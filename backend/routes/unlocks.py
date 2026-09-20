"""Collective unlocks and circle-wide milestone routes."""

from fastapi import APIRouter, HTTPException
from uuid import UUID
from datetime import datetime

from db.client import get_supabase_client
from shared.contracts.unlocks import (
    CircleUnlockStatus,
    CircleUnlock,
    compute_unlock_progress,
    UNLOCK_TIERS,
)

router = APIRouter(prefix="/unlocks", tags=["unlocks"])


@router.get("/status/{circle_id}", response_model=CircleUnlockStatus)
async def get_unlock_status(circle_id: UUID):
    """
    Get collective unlock progress for a circle.

    Counts all settlements (completed favors) this month and returns progress
    toward next milestone plus list of claimed rewards.
    """
    supabase = get_supabase_client()

    try:
        # Get this month's favor count (settlements)
        now = datetime.now()
        month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

        settlements_response = (
            supabase.table("settlements")
            .select("id")
            .gte("created_at", month_start.isoformat())
            .execute()
        )

        favors_this_month = len(settlements_response.data) if settlements_response.data else 0

        # Get claimed unlocks for this circle
        unlocks_response = (
            supabase.table("circle_unlocks")
            .select("*")
            .eq("circle_id", str(circle_id))
            .execute()
        )

        claimed_unlocks = []
        claimed_types = []
        if unlocks_response.data:
            for unlock in unlocks_response.data:
                claimed_unlocks.append(
                    CircleUnlock(
                        id=unlock["id"],
                        circle_id=unlock["circle_id"],
                        unlock_type=unlock["unlock_type"],
                        reward_description=unlock["reward_description"],
                        favors_at_unlock=unlock["favors_at_unlock"],
                        claimed_at=unlock["claimed_at"],
                    )
                )
                claimed_types.append(unlock["unlock_type"])

        # Compute progress
        progress = compute_unlock_progress(favors_this_month, str(circle_id), claimed_types)

        return CircleUnlockStatus(
            circle_id=str(circle_id),
            favors_this_month=progress["favors_this_month"],
            progress_percentage=progress["progress_percentage"],
            next_milestone_threshold=progress["next_milestone_threshold"],
            next_milestone_description=progress["next_milestone_description"],
            next_milestone_favors_remaining=progress[
                "next_milestone_favors_remaining"
            ],
            claimed_unlocks=claimed_unlocks,
            available_unlocks=progress["available_unlocks"],
        )

    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/claim/{circle_id}")
async def claim_unlock(circle_id: UUID, unlock_type: str):
    """
    Claim an available unlock for a circle.

    Only callable if the circle has reached the threshold for that unlock
    and hasn't already claimed it.
    """
    supabase = get_supabase_client()

    try:
        # Verify circle exists
        circle_response = (
            supabase.table("circles").select("id").eq("id", str(circle_id)).execute()
        )
        if not circle_response.data:
            raise HTTPException(status_code=404, detail="Circle not found")

        # Check if already claimed
        existing_response = (
            supabase.table("circle_unlocks")
            .select("id")
            .eq("circle_id", str(circle_id))
            .eq("unlock_type", unlock_type)
            .execute()
        )
        if existing_response.data:
            raise HTTPException(
                status_code=409,
                detail=f"Unlock {unlock_type} already claimed for this circle",
            )

        # Find the tier
        tier = None
        for t in UNLOCK_TIERS:
            if t.unlock_type.value == unlock_type:
                tier = t
                break
        if not tier:
            raise HTTPException(status_code=400, detail="Invalid unlock type")

        # Count current favors
        now = datetime.now()
        month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

        settlements_response = (
            supabase.table("settlements")
            .select("id")
            .gte("created_at", month_start.isoformat())
            .execute()
        )
        favors_this_month = (
            len(settlements_response.data) if settlements_response.data else 0
        )

        # Verify threshold met
        if favors_this_month < tier.threshold:
            raise HTTPException(
                status_code=400,
                detail=f"Circle must have {tier.threshold} favors to claim this unlock (current: {favors_this_month})",
            )

        # Insert the claimed unlock
        unlock_id = f"unlock_{circle_id}_{unlock_type}"
        insert_response = supabase.table("circle_unlocks").insert(
            {
                "id": unlock_id,
                "circle_id": str(circle_id),
                "unlock_type": unlock_type,
                "reward_description": tier.reward_description,
                "favors_at_unlock": favors_this_month,
                "claimed_at": now.isoformat(),
            }
        ).execute()

        if not insert_response.data:
            raise HTTPException(status_code=500, detail="Failed to claim unlock")

        return {
            "success": True,
            "unlock_type": unlock_type,
            "reward_description": tier.reward_description,
            "claimed_at": now.isoformat(),
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
