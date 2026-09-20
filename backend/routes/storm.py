"""Storm mode routes for event-triggered generosity surges."""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional
from datetime import datetime
from uuid import UUID

from db.client import get_supabase_client

router = APIRouter(prefix="/storm", tags=["storm"])


class StormStatus(BaseModel):
    """Current storm mode status."""

    active: bool
    storm_type: Optional[str] = None  # "snowstorm", "thunderstorm", etc.
    severity: Optional[str] = None  # "advisory", "warning", "emergency"
    message: Optional[str] = None
    expires_at: Optional[datetime] = None
    karma_multiplier: int = 1


@router.get("/status/{circle_id}", response_model=StormStatus)
async def get_storm_status(circle_id: UUID):
    """Get current storm mode status for a circle."""
    supabase = get_supabase_client()

    try:
        circle_response = (
            supabase.table("circles")
            .select("storm_mode_active, storm_mode_expires_at, storm_karma_multiplier")
            .eq("id", str(circle_id))
            .execute()
        )

        if not circle_response.data:
            raise HTTPException(status_code=404, detail="Circle not found")

        circle = circle_response.data[0]
        active = circle.get("storm_mode_active", False)
        expires_at = circle.get("storm_mode_expires_at")
        multiplier = circle.get("storm_karma_multiplier", 1)

        # Check if storm window has expired
        if active and expires_at:
            expires_dt = datetime.fromisoformat(expires_at.replace("Z", "+00:00"))
            if datetime.now(expires_dt.tzinfo) > expires_dt:
                # Storm mode has expired, deactivate it
                await deactivate_storm_mode(circle_id)
                active = False
                multiplier = 1

        return StormStatus(
            active=active,
            storm_type="snowstorm" if active else None,
            severity="warning" if active else None,
            message=f"{7} neighbors covered before the storm" if active else None,
            expires_at=expires_at,
            karma_multiplier=multiplier,
        )

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/activate/{circle_id}", response_model=StormStatus)
async def activate_storm_mode(circle_id: UUID):
    """Activate storm mode for a circle (admin/demo action)."""
    supabase = get_supabase_client()

    try:
        # Storm mode lasts for 4 hours
        from datetime import timedelta

        expires_at = datetime.now() + timedelta(hours=4)

        response = (
            supabase.table("circles")
            .update({
                "storm_mode_active": True,
                "storm_mode_expires_at": expires_at.isoformat(),
                "storm_karma_multiplier": 2,
            })
            .eq("id", str(circle_id))
            .execute()
        )

        if not response.data:
            raise HTTPException(status_code=404, detail="Circle not found")

        return StormStatus(
            active=True,
            storm_type="snowstorm",
            severity="warning",
            message="7 neighbors covered before the storm",
            expires_at=expires_at,
            karma_multiplier=2,
        )

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/deactivate/{circle_id}", response_model=StormStatus)
async def deactivate_storm_mode(circle_id: UUID):
    """Deactivate storm mode for a circle."""
    supabase = get_supabase_client()

    try:
        response = (
            supabase.table("circles")
            .update({
                "storm_mode_active": False,
                "storm_mode_expires_at": None,
                "storm_karma_multiplier": 1,
            })
            .eq("id", str(circle_id))
            .execute()
        )

        if not response.data:
            raise HTTPException(status_code=404, detail="Circle not found")

        return StormStatus(active=False, karma_multiplier=1)

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
