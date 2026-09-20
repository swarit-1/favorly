"""Trip management routes."""

from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel
from typing import List, Optional
from uuid import UUID
from datetime import datetime
from decimal import Decimal
import os
from supabase import create_client, Client

from shared.contracts.models import Trip, TripCaps, TripStatus, Item, Request as RequestModel, User
from shared.timestamps import parse_timestamp

router = APIRouter(prefix="/trips", tags=["trips"])


def get_supabase_client() -> Client:
    """Get Supabase client."""
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")
    return create_client(url, key)


class CreateTripRequest(BaseModel):
    """Create trip request."""
    store: str
    depart_at: datetime
    caps: Optional[TripCaps] = None


class UpdateTripStatusRequest(BaseModel):
    """Update trip status."""
    status: TripStatus


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
        # Update status
        update_response = supabase.table("trips").update({
            "status": req.status.value,
        }).eq("id", str(trip_id)).execute()

        if not update_response.data:
            raise HTTPException(status_code=404, detail="Trip not found")

        trip_data = update_response.data[0]
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
