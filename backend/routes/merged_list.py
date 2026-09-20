"""Merged list route - aggregates all items from all requests for a trip."""

from fastapi import APIRouter, HTTPException
from typing import List, Dict
from uuid import UUID
from datetime import datetime
from decimal import Decimal
import os
from supabase import create_client, Client

from shared.contracts.models import (
    MergedList,
    MergedListRow,
    Item,
    ItemStatus,
    StoreSection,
    STORE_SECTION_ORDER,
    User,
    RequestStatus,
)

router = APIRouter(prefix="/trips", tags=["merged_list"])


def get_supabase_client() -> Client:
    """Get Supabase client."""
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")
    return create_client(url, key)


@router.get("/{trip_id}/merged-list", response_model=MergedList)
async def get_merged_list(trip_id: UUID):
    """Get merged list for a trip (accepted items aggregated by section)."""
    supabase = get_supabase_client()

    try:
        # Get all accepted requests for this trip
        requests_response = supabase.table("requests").select("*").eq("trip_id", str(trip_id)).eq("status", RequestStatus.ACCEPTED.value).execute()

        merged_list_rows: Dict[StoreSection, List[MergedListRow]] = {
            section: [] for section in STORE_SECTION_ORDER
        }
        totals_by_requester: Dict[UUID, Decimal] = {}

        for request_data in requests_response.data:
            requester_id = request_data["requester_id"]

            # Get requester user
            user_response = supabase.table("users").select("*").eq("id", requester_id).execute()
            if not user_response.data:
                continue

            user_data = user_response.data[0]
            requester = User(
                id=user_data["id"],
                circle_id=user_data["circle_id"],
                name=user_data["name"],
                venmo_handle=user_data.get("venmo_handle"),
                created_at=datetime.fromisoformat(user_data["created_at"]),
            )

            # Get items for this request
            items_response = supabase.table("items").select("*").eq("request_id", request_data["id"]).execute()

            running_total = totals_by_requester.get(requester_id, Decimal("0.00"))

            for item_data in items_response.data:
                item = Item(
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
                    created_at=datetime.fromisoformat(item_data["created_at"]),
                )

                # Calculate running total and cap
                max_price = Decimal(str(item.max_price)) if item.max_price else Decimal("5.00")
                running_total += max_price
                cap = Decimal("40.00")  # Default cap
                over_cap = running_total > cap

                # Get trip caps if different
                trip_response = supabase.table("trips").select("caps").eq("id", str(trip_id)).execute()
                if trip_response.data:
                    caps_data = trip_response.data[0]["caps"]
                    cap = Decimal(str(caps_data.get("max_dollars_per_person", "40.00")))

                section = StoreSection(item.section) if isinstance(item.section, str) else item.section
                merged_list_rows[section].append(MergedListRow(
                    item=item,
                    requester=requester,
                    running_total=running_total,
                    cap=cap,
                    over_cap=over_cap,
                ))

            totals_by_requester[requester_id] = running_total

        return MergedList(
            trip_id=trip_id,
            sections=merged_list_rows,
            totals_by_requester=totals_by_requester,
        )
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
