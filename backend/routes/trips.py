"""Trip management routes."""

from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel
from typing import List, Optional
from uuid import UUID
from datetime import datetime
from decimal import Decimal

from db.client import get_supabase_client
from shared.contracts.models import Trip, TripCaps, TripStatus, Item, Request as RequestModel, User, RequestStatus, StoreSection
from shared.timestamps import parse_timestamp
from shared.notify import write_notification

router = APIRouter(prefix="/trips", tags=["trips"])


class CreateTripRequest(BaseModel):
    """Create trip request."""
    store: str
    depart_at: datetime
    caps: Optional[TripCaps] = None


class UpdateTripStatusRequest(BaseModel):
    """Update trip status."""
    status: TripStatus


class TripSuggestion(BaseModel):
    """A request that fits this trip."""
    request_id: str
    trip_id: str
    requester_name: str
    items: List[str]
    score: float
    nudge: str


@router.post("", response_model=Trip)
async def create_trip(req: CreateTripRequest, authorization: str = Header(None)):
    """Create a new trip."""
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing authorization header")

    supabase = get_supabase_client()
    user_id = authorization.split("User-")[-1] if "User-" in authorization else authorization

    try:
        # Get user to get circle_id
        user_response = supabase.table("users").select("*").eq("id", user_id).execute()
        if not user_response.data:
            raise HTTPException(status_code=404, detail="User not found")

        circle_id = user_response.data[0]["circle_id"]

        # Create trip
        caps = req.caps or TripCaps()
        trip_response = supabase.table("trips").insert({
            "shopper_id": user_id,
            "circle_id": circle_id,
            "store": req.store,
            "depart_at": req.depart_at.isoformat(),
            "caps": caps.model_dump(),
            "status": TripStatus.OPEN.value,
        }).execute()

        if not trip_response.data:
            raise HTTPException(status_code=500, detail="Failed to create trip")

        trip_data = trip_response.data[0]
        return Trip(
            id=trip_data["id"],
            shopper_id=trip_data["shopper_id"],
            circle_id=trip_data["circle_id"],
            store=trip_data["store"],
            depart_at=parse_timestamp(trip_data["depart_at"]),
            caps=TripCaps(**trip_data["caps"]),
            status=TripStatus(trip_data["status"]),
            created_at=parse_timestamp(trip_data["created_at"]),
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/{trip_id}", response_model=Trip)
async def get_trip(trip_id: UUID):
    """Get a trip by ID."""
    supabase = get_supabase_client()

    try:
        trip_response = supabase.table("trips").select("*").eq("id", str(trip_id)).execute()
        if not trip_response.data:
            raise HTTPException(status_code=404, detail="Trip not found")

        trip_data = trip_response.data[0]
        return Trip(
            id=trip_data["id"],
            shopper_id=trip_data["shopper_id"],
            circle_id=trip_data["circle_id"],
            store=trip_data["store"],
            depart_at=parse_timestamp(trip_data["depart_at"]),
            caps=TripCaps(**trip_data["caps"]),
            status=TripStatus(trip_data["status"]),
            created_at=parse_timestamp(trip_data["created_at"]),
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/circle/{circle_id}", response_model=List[Trip])
async def list_trips_by_circle(circle_id: UUID):
    """List trips in a circle."""
    supabase = get_supabase_client()

    try:
        trips_response = supabase.table("trips").select("*").eq("circle_id", str(circle_id)).order("created_at", desc=True).execute()

        trips = []
        for trip_data in trips_response.data:
            trips.append(Trip(
                id=trip_data["id"],
                shopper_id=trip_data["shopper_id"],
                circle_id=trip_data["circle_id"],
                store=trip_data["store"],
                depart_at=parse_timestamp(trip_data["depart_at"]),
                caps=TripCaps(**trip_data["caps"]),
                status=TripStatus(trip_data["status"]),
                created_at=parse_timestamp(trip_data["created_at"]),
            ))
        return trips
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.patch("/{trip_id}/status", response_model=Trip)
async def update_trip_status(trip_id: UUID, req: UpdateTripStatusRequest):
    """Update trip status."""
    supabase = get_supabase_client()

    try:
        # Get the trip first to get circle_id
        trip_response = supabase.table("trips").select("*").eq("id", str(trip_id)).execute()
        if not trip_response.data:
            raise HTTPException(status_code=404, detail="Trip not found")

        trip_data_before = trip_response.data[0]

        # Update status
        update_response = supabase.table("trips").update({
            "status": req.status.value,
        }).eq("id", str(trip_id)).execute()

        if not update_response.data:
            raise HTTPException(status_code=404, detail="Trip not found")

        trip_data = update_response.data[0]

        # Fan-out notifications on status change to "shopping"
        if req.status == TripStatus.SHOPPING:
            circle_id = trip_data["circle_id"]
            shopper_id = trip_data["shopper_id"]
            store = trip_data["store"]

            # Get all requesters (users with pending/accepted requests in this trip)
            requests_response = supabase.table("requests").select(
                "requester_id"
            ).eq("trip_id", str(trip_id)).in_("status", ["pending", "accepted"]).execute()

            for request_data in requests_response.data or []:
                requester_id = request_data["requester_id"]
                if requester_id != shopper_id:  # Don't notify yourself
                    write_notification(
                        supabase,
                        UUID(requester_id),
                        trip_id,
                        "trip_departed",
                        title=f"Shopping trip to {store} started",
                        body="Your shopper is heading to the store now",
                    )

        return Trip(
            id=trip_data["id"],
            shopper_id=trip_data["shopper_id"],
            circle_id=trip_data["circle_id"],
            store=trip_data["store"],
            depart_at=parse_timestamp(trip_data["depart_at"]),
            caps=TripCaps(**trip_data["caps"]),
            status=TripStatus(trip_data["status"]),
            created_at=parse_timestamp(trip_data["created_at"]),
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/{trip_id}/suggestions", response_model=List[TripSuggestion])
async def get_trip_suggestions(trip_id: UUID, limit: int = 5):
    """Pending requests in this circle that score well against this trip."""
    supabase = get_supabase_client()

    trip_response = supabase.table("trips").select("*").eq("id", str(trip_id)).execute()
    if not trip_response.data:
        raise HTTPException(status_code=404, detail="Trip not found")
    trip_data = trip_response.data[0]
    trip = Trip(
        id=trip_data["id"], shopper_id=trip_data["shopper_id"],
        circle_id=trip_data["circle_id"], store=trip_data["store"],
        depart_at=parse_timestamp(trip_data["depart_at"]),
        caps=TripCaps(**trip_data["caps"]),
        status=TripStatus(trip_data["status"]),
        created_at=parse_timestamp(trip_data["created_at"]),
    )

    # All open trips in this circle (including this one)
    all_trips = supabase.table("trips").select("id, shopper_id") \
        .eq("circle_id", str(trip.circle_id)) \
        .eq("status", TripStatus.OPEN.value) \
        .execute()

    # Get all trip IDs except the current one
    trip_ids = [t["id"] for t in (all_trips.data or []) if t["id"] != str(trip_id)]

    # Get shopper IDs (to exclude their own requests)
    trip_shoppers = {t["id"]: t["shopper_id"] for t in (all_trips.data or [])}

    if not trip_ids:
        return []

    # Pending requests on those trips
    requests_resp = supabase.table("requests").select("id, trip_id, requester_id") \
        .in_("trip_id", trip_ids) \
        .eq("status", RequestStatus.PENDING.value).execute()

    if not requests_resp.data:
        return []

    # Exclude requests from the current trip's shopper
    requests_resp.data = [
        r for r in requests_resp.data
        if r["requester_id"] != str(trip.shopper_id)
    ]

    if not requests_resp.data:
        return []

    requester_ids = list({r["requester_id"] for r in requests_resp.data})
    users_resp = supabase.table("users").select("id, name").in_("id", requester_ids).execute()
    name_by_id = {u["id"]: u["name"] for u in (users_resp.data or [])}

    request_ids = [r["id"] for r in requests_resp.data]
    items_resp = supabase.table("items").select("request_id, name, section") \
        .in_("request_id", request_ids).execute()

    items_by_request: dict[str, list] = {}
    names_by_request: dict[str, list[str]] = {}
    for item in (items_resp.data or []):
        rid = item["request_id"]
        items_by_request.setdefault(rid, []).append(StoreSection(item["section"]))
        names_by_request.setdefault(rid, []).append(item["name"])

    from matching.engine import recommend_asks_for_trip
    asks = [(r["id"], items_by_request.get(r["id"], [StoreSection.OTHER])) for r in requests_resp.data]
    scored = recommend_asks_for_trip(asks, trip, current_requesters=0)

    results = []
    for ask_id, score in scored[:limit]:
        req = next(r for r in requests_resp.data if r["id"] == ask_id)
        requester_name = name_by_id.get(req["requester_id"], "A neighbor")
        item_list = names_by_request.get(ask_id, [])
        summary = ", ".join(item_list[:3]) + (f" +{len(item_list)-3} more" if len(item_list) > 3 else "")
        if score >= 0.8:
            nudge = f"Perfect match — {requester_name} needs {summary} from {trip.store}."
        elif score >= 0.6:
            nudge = f"Good fit — {summary} is likely at {trip.store}."
        else:
            nudge = f"Possible pickup — {summary} might be on your route."
        results.append(TripSuggestion(
            request_id=ask_id, trip_id=req["trip_id"],
            requester_name=requester_name, items=item_list,
            score=score, nudge=nudge,
        ))
    return results
