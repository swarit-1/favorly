"""User and circle management routes."""

from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from typing import List
from uuid import UUID
from datetime import datetime

from db.client import get_supabase_client
from shared.contracts.models import User, Circle, ProfileUpdate, Address, ShopperRole
from shared.timestamps import parse_timestamp
from auth.dependencies import get_current_user_id

router = APIRouter(prefix="/users", tags=["users"])


def _row_to_user(user_data: dict) -> User:
    """Convert a database row to a User model."""
    address = None
    if any([user_data.get(f"address_{field}") for field in ["unit", "floor", "buzzer", "notes"]]):
        address = Address(
            unit=user_data.get("address_unit"),
            floor=user_data.get("address_floor"),
            buzzer=user_data.get("address_buzzer"),
            notes=user_data.get("address_notes"),
        )

    return User(
        id=user_data["id"],
        circle_id=user_data["circle_id"],
        name=user_data["name"],
        venmo_handle=user_data.get("venmo_handle"),
        bio=user_data.get("bio"),
        photo_url=user_data.get("photo_url"),
        role=ShopperRole(user_data.get("role", "both")),
        address=address,
        dietary=user_data.get("dietary", []) or [],
        preferred_stores=user_data.get("preferred_stores", []) or [],
        availability=user_data.get("availability", []) or [],
        created_at=parse_timestamp(user_data["created_at"]),
        updated_at=parse_timestamp(user_data["updated_at"]) if user_data.get("updated_at") else None,
    )


@router.get("/{user_id}", response_model=User)
async def get_user(user_id: UUID):
    """Get a user by ID."""
    supabase = get_supabase_client()

    try:
        user_response = supabase.table("users").select("*").eq("id", str(user_id)).execute()
        if not user_response.data:
            raise HTTPException(status_code=404, detail="User not found")

        return _row_to_user(user_response.data[0])
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/circle/{circle_id}", response_model=List[User])
async def get_circle_members(circle_id: UUID):
    """Get all users in a circle."""
    supabase = get_supabase_client()

    try:
        users_response = supabase.table("users").select("*").eq("circle_id", str(circle_id)).execute()
        return [_row_to_user(user_data) for user_data in users_response.data]
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.patch("/{user_id}", response_model=User)
async def update_profile(
    user_id: UUID,
    profile_update: ProfileUpdate,
    current_user_id: UUID = Depends(get_current_user_id),
):
    """
    Update a user's profile.

    Only the authenticated user can update their own profile.
    Partial updates: only provided fields are updated.
    """
    # Verify the user is updating their own profile
    if current_user_id != user_id:
        raise HTTPException(status_code=403, detail="Cannot update another user's profile")

    supabase = get_supabase_client()

    try:
        # Build update dictionary with only non-None fields
        update_data = {}
        if profile_update.bio is not None:
            update_data["bio"] = profile_update.bio
        if profile_update.photo_url is not None:
            update_data["photo_url"] = profile_update.photo_url
        if profile_update.role is not None:
            update_data["role"] = profile_update.role.value
        if profile_update.dietary is not None:
            update_data["dietary"] = profile_update.dietary
        if profile_update.preferred_stores is not None:
            update_data["preferred_stores"] = profile_update.preferred_stores
        if profile_update.availability is not None:
            update_data["availability"] = profile_update.availability

        # Handle address separately (it's a nested object)
        if profile_update.address is not None:
            update_data["address_unit"] = profile_update.address.unit
            update_data["address_floor"] = profile_update.address.floor
            update_data["address_buzzer"] = profile_update.address.buzzer
            update_data["address_notes"] = profile_update.address.notes

        # Always update the updated_at timestamp
        update_data["updated_at"] = datetime.utcnow().isoformat()

        # Execute the update
        response = (
            supabase.table("users")
            .update(update_data)
            .eq("id", str(user_id))
            .execute()
        )

        if not response.data:
            raise HTTPException(status_code=404, detail="User not found")

        return _row_to_user(response.data[0])
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/circles/{invite_code}", response_model=Circle)
async def get_circle_by_invite_code(invite_code: str):
    """Get a circle by invite code."""
    supabase = get_supabase_client()

    try:
        circle_response = supabase.table("circles").select("*").eq("invite_code", invite_code).execute()
        if not circle_response.data:
            raise HTTPException(status_code=404, detail="Circle not found")

        circle_data = circle_response.data[0]
        return Circle(
            id=circle_data["id"],
            name=circle_data["name"],
            invite_code=circle_data["invite_code"],
            created_at=parse_timestamp(circle_data["created_at"]),
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
