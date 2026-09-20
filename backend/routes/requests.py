"""Request management routes."""

from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel
from typing import List, Optional
from uuid import UUID
from datetime import datetime

from db.client import get_supabase_client
from shared.contracts.models import Request as RequestModel, RequestStatus, Item, ItemStatus, StoreSection
from shared.timestamps import parse_timestamp

router = APIRouter(prefix="/requests", tags=["requests"])


class CreateItemRequest(BaseModel):
    """Create item request."""
    name: str
    qty: int = 1
    unit: Optional[str] = None
    note: Optional[str] = None
    max_price: Optional[float] = None
    section: Optional[str] = StoreSection.OTHER.value


class CreateRequestRequest(BaseModel):
    """Create request with items."""
    items: List[CreateItemRequest]


class UpdateRequestStatusRequest(BaseModel):
    """Update request status."""
    status: RequestStatus


@router.post("/{trip_id}", response_model=RequestModel)
async def create_request(trip_id: UUID, req: CreateRequestRequest, authorization: str = Header(None)):
    """Create a request for a trip."""
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing authorization header")

    supabase = get_supabase_client()
    requester_id = authorization.split("User-")[-1] if "User-" in authorization else authorization

    try:
        # Create request
        request_response = supabase.table("requests").insert({
            "trip_id": str(trip_id),
            "requester_id": requester_id,
            "status": RequestStatus.PENDING.value,
        }).execute()

        if not request_response.data:
            raise HTTPException(status_code=500, detail="Failed to create request")

        request_data = request_response.data[0]
        request_id = request_data["id"]

        # Create items
        items = []
        for item_req in req.items:
            item_response = supabase.table("items").insert({
                "request_id": request_id,
                "trip_id": str(trip_id),
                "name": item_req.name,
                "qty": item_req.qty,
                "unit": item_req.unit,
                "note": item_req.note,
                "max_price": item_req.max_price,
                "section": item_req.section,
                "status": ItemStatus.PENDING.value,
            }).execute()

            if item_response.data:
                item_data = item_response.data[0]
                items.append(Item(
                    id=item_data["id"],
                    request_id=request_id,
                    trip_id=item_data["trip_id"],
                    name=item_data["name"],
                    qty=item_data["qty"],
                    unit=item_data["unit"],
                    note=item_data["note"],
                    max_price=item_data["max_price"],
                    section=item_data["section"],
                    status=ItemStatus(item_data["status"]),
                    substitute_of=item_data.get("substitute_of"),
                    actual_price=item_data.get("actual_price"),
                    created_at=parse_timestamp(item_data["created_at"]),
                ))

        return RequestModel(
            id=request_id,
            trip_id=request_data["trip_id"],
            requester_id=request_data["requester_id"],
            status=RequestStatus(request_data["status"]),
            items=items,
            created_at=parse_timestamp(request_data["created_at"]),
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/{request_id}", response_model=RequestModel)
async def get_request(request_id: UUID):
    """Get a request by ID."""
    supabase = get_supabase_client()

    try:
        request_response = supabase.table("requests").select("*").eq("id", str(request_id)).execute()
        if not request_response.data:
            raise HTTPException(status_code=404, detail="Request not found")

        request_data = request_response.data[0]

        # Get items
        items_response = supabase.table("items").select("*").eq("request_id", str(request_id)).execute()
        items = []
        for item_data in items_response.data:
            items.append(Item(
                id=item_data["id"],
                request_id=item_data["request_id"],
                trip_id=item_data["trip_id"],
                name=item_data["name"],
                qty=item_data["qty"],
                unit=item_data["unit"],
                note=item_data["note"],
                max_price=item_data["max_price"],
                section=item_data["section"],
                status=ItemStatus(item_data["status"]),
                substitute_of=item_data.get("substitute_of"),
                actual_price=item_data.get("actual_price"),
                created_at=parse_timestamp(item_data["created_at"]),
            ))

        return RequestModel(
            id=request_data["id"],
            trip_id=request_data["trip_id"],
            requester_id=request_data["requester_id"],
            status=RequestStatus(request_data["status"]),
            items=items,
            created_at=parse_timestamp(request_data["created_at"]),
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/trip/{trip_id}", response_model=List[RequestModel])
async def list_requests_by_trip(trip_id: UUID):
    """List all requests for a trip."""
    supabase = get_supabase_client()

    try:
        requests_response = supabase.table("requests").select("*").eq("trip_id", str(trip_id)).execute()

        requests = []
        for request_data in requests_response.data:
            # Get items for this request
            items_response = supabase.table("items").select("*").eq("request_id", request_data["id"]).execute()
            items = []
            for item_data in items_response.data:
                items.append(Item(
                    id=item_data["id"],
                    request_id=item_data["request_id"],
                    trip_id=item_data["trip_id"],
                    name=item_data["name"],
                    qty=item_data["qty"],
                    unit=item_data["unit"],
                    note=item_data["note"],
                    max_price=item_data["max_price"],
                    section=item_data["section"],
                    status=ItemStatus(item_data["status"]),
                    substitute_of=item_data.get("substitute_of"),
                    actual_price=item_data.get("actual_price"),
                    created_at=parse_timestamp(item_data["created_at"]),
                ))

            requests.append(RequestModel(
                id=request_data["id"],
                trip_id=request_data["trip_id"],
                requester_id=request_data["requester_id"],
                status=RequestStatus(request_data["status"]),
                items=items,
                created_at=parse_timestamp(request_data["created_at"]),
            ))

        return requests
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.patch("/{request_id}/status", response_model=RequestModel)
async def update_request_status(request_id: UUID, req: UpdateRequestStatusRequest):
    """Update request status."""
    supabase = get_supabase_client()

    try:
        # Update status
        update_response = supabase.table("requests").update({
            "status": req.status.value,
        }).eq("id", str(request_id)).execute()

        if not update_response.data:
            raise HTTPException(status_code=404, detail="Request not found")

        request_data = update_response.data[0]

        # Get items
        items_response = supabase.table("items").select("*").eq("request_id", str(request_id)).execute()
        items = []
        for item_data in items_response.data:
            items.append(Item(
                id=item_data["id"],
                request_id=item_data["request_id"],
                trip_id=item_data["trip_id"],
                name=item_data["name"],
                qty=item_data["qty"],
                unit=item_data["unit"],
                note=item_data["note"],
                max_price=item_data["max_price"],
                section=item_data["section"],
                status=ItemStatus(item_data["status"]),
                substitute_of=item_data.get("substitute_of"),
                actual_price=item_data.get("actual_price"),
                created_at=parse_timestamp(item_data["created_at"]),
            ))

        return RequestModel(
            id=request_data["id"],
            trip_id=request_data["trip_id"],
            requester_id=request_data["requester_id"],
            status=RequestStatus(request_data["status"]),
            items=items,
            created_at=parse_timestamp(request_data["created_at"]),
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
