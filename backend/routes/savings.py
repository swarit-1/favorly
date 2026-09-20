"""Personal savings meter routes."""

from fastapi import APIRouter, HTTPException
from uuid import UUID
from datetime import datetime, timedelta

from db.client import get_supabase_client
from shared.contracts.savings import (
    PersonalSavings,
    RequesterSavings,
    CarrierSavings,
    compute_requester_savings,
    compute_carrier_savings,
)

router = APIRouter(prefix="/savings", tags=["savings"])


@router.get("/{user_id}", response_model=PersonalSavings)
async def get_personal_savings(user_id: UUID):
    """
    Get personal savings/earnings for a user.

    Computes:
    - Requester view: "fees avoided" this month vs delivery-app pricing
    - Carrier view: "earned in perks + bulk savings" this month

    Returns both views combined in PersonalSavings.
    """
    supabase = get_supabase_client()

    try:
        # Get the user to find their circle
        user_response = supabase.table("users").select("circle_id").eq("id", str(user_id)).execute()
        if not user_response.data:
            raise HTTPException(status_code=404, detail="User not found")

        circle_id = user_response.data[0]["circle_id"]

        # Compute requester savings (based on settlements this month)
        requester_savings = None
        has_requester_data = False

        # Query settlements where user is requester (this month)
        now = datetime.now()
        month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

        settlements_response = (
            supabase.table("settlements")
            .select("subtotal, tax_share, total, created_at")
            .eq("requester_id", str(user_id))
            .gte("created_at", month_start.isoformat())
            .execute()
        )

        if settlements_response.data:
            has_requester_data = True
            total_subtotal = 0.0
            total_tax = 0.0
            total_paid = 0.0
            items_count = 0

            for settlement in settlements_response.data:
                total_subtotal += float(settlement.get("subtotal", 0))
                total_tax += float(settlement.get("tax_share", 0))
                total_paid += float(settlement.get("total", 0))
                items_count += 1

            requester_savings = compute_requester_savings(
                subtotal=total_subtotal,
                tax=total_tax,
                favorly_total=total_paid,
                items_count=items_count,
            )
            # Update trip count
            requester_savings.trips_used_this_month = items_count

        # Compute carrier savings (based on trips run this month)
        carrier_savings = None
        has_carrier_data = False

        # Query trips where user is shopper (this month)
        trips_response = (
            supabase.table("trips")
            .select("id")
            .eq("shopper_id", str(user_id))
            .gte("created_at", month_start.isoformat())
            .eq("status", "done")
            .execute()
        )

        trips_completed = len(trips_response.data) if trips_response.data else 0

        # Query ledger for dollars carried (all-time or this month)
        ledger_response = (
            supabase.table("ledger_rows")
            .select("dollars_carried, trips_run")
            .eq("member_id", str(user_id))
            .execute()
        )

        if ledger_response.data:
            ledger = ledger_response.data[0]
            dollars_carried = float(ledger.get("dollars_carried", 0))
            trips_run = int(ledger.get("trips_run", 0))

            if trips_run > 0 or dollars_carried > 0:
                has_carrier_data = True
                # Use this month's trips, but all-time dollars (conservative estimate)
                carrier_savings = compute_carrier_savings(
                    trips_carried=trips_completed or trips_run,
                    dollars_carried=dollars_carried,
                )

        return PersonalSavings(
            requester_savings=requester_savings,
            carrier_savings=carrier_savings,
            has_requester_data=has_requester_data,
            has_carrier_data=has_carrier_data,
        )

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
