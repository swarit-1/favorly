"""Guaranteed-fill insurance routes."""

from fastapi import APIRouter, HTTPException
from uuid import UUID
from datetime import datetime, timedelta

from db.client import get_supabase_client
from shared.contracts.insurance import (
    InsuranceStatus,
    GuaranteedRequest,
    check_insurance_eligibility,
)

router = APIRouter(prefix="/insurance", tags=["insurance"])


@router.get("/status/{user_id}", response_model=InsuranceStatus)
async def get_insurance_status(user_id: UUID):
    """
    Get insurance eligibility status for a user.

    A user qualifies for guaranteed-fill insurance by carrying 3+ times in the current month.
    When active, the building guarantees to fulfill any requests not covered within 48 hours.
    """
    supabase = get_supabase_client()

    try:
        # Query trips completed this month by this user as shopper
        now = datetime.now()
        month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

        trips_response = (
            supabase.table("trips")
            .select("id")
            .eq("shopper_id", str(user_id))
            .gte("created_at", month_start.isoformat())
            .eq("status", "done")
            .execute()
        )

        trips_carried = len(trips_response.data) if trips_response.data else 0
        active = check_insurance_eligibility(trips_carried)

        return InsuranceStatus(
            user_id=str(user_id),
            active=active,
            trips_carried_this_month=trips_carried,
            expires_at=(now + timedelta(days=1)) if active else None,
        )

    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/check-eligible/{user_id}")
async def check_eligible(user_id: UUID):
    """Check if a specific user qualifies for insurance (3+ carries this month)."""
    supabase = get_supabase_client()

    try:
        now = datetime.now()
        month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

        trips_response = (
            supabase.table("trips")
            .select("id")
            .eq("shopper_id", str(user_id))
            .gte("created_at", month_start.isoformat())
            .eq("status", "done")
            .execute()
        )

        trips_carried = len(trips_response.data) if trips_response.data else 0
        active = check_insurance_eligibility(trips_carried)

        return {
            "user_id": str(user_id),
            "eligible": active,
            "trips_carried": trips_carried,
            "required_trips": 3,
        }

    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/guaranteed-requests/{circle_id}")
async def get_guaranteed_requests(circle_id: UUID):
    """
    Get all outstanding guaranteed requests for a circle.

    These are requests that haven't been filled by neighbors within 48h,
    so the building's insurance kicks in to fulfill them.
    """
    supabase = get_supabase_client()

    try:
        # Query guaranteed_requests table where filled_at is null (still pending)
        requests_response = (
            supabase.table("guaranteed_requests")
            .select("*")
            .eq("circle_id", str(circle_id))
            .is_("filled_at", "null")  # Still pending
            .lte("guarantee_deadline", datetime.now().isoformat())  # Past deadline
            .execute()
        )

        guaranteed_requests = []
        if requests_response.data:
            for req in requests_response.data:
                guaranteed_requests.append(
                    GuaranteedRequest(
                        id=req["id"],
                        requester_id=req["requester_id"],
                        request_items=req.get("request_items", "{}"),
                        guarantee_deadline=req["guarantee_deadline"],
                        filled_by=req.get("filled_by"),
                        filled_at=req.get("filled_at"),
                        coverage_cost=float(req.get("coverage_cost", 0)),
                        created_at=req["created_at"],
                    )
                )

        return {"circle_id": str(circle_id), "guaranteed_requests": guaranteed_requests}

    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
