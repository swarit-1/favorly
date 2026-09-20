"""User and circle management routes."""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List
from uuid import UUID
from datetime import datetime
import os
from supabase import create_client, Client

from shared.contracts.models import User, Circle

router = APIRouter(prefix="/users", tags=["users"])


def get_supabase_client() -> Client:
    """Get Supabase client."""
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")
    return create_client(url, key)


@router.get("/{user_id}", response_model=User)
async def get_user(user_id: UUID):
    """Get a user by ID."""
    supabase = get_supabase_client()

    try:
        user_response = supabase.table("users").select("*").eq("id", str(user_id)).execute()
        if not user_response.data:
            raise HTTPException(status_code=404, detail="User not found")

        user_data = user_response.data[0]
        return User(
            id=user_data["id"],
            circle_id=user_data["circle_id"],
            name=user_data["name"],
            venmo_handle=user_data.get("venmo_handle"),
            created_at=datetime.fromisoformat(user_data["created_at"]),
        )
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

        users = []
        for user_data in users_response.data:
            users.append(User(
                id=user_data["id"],
                circle_id=user_data["circle_id"],
                name=user_data["name"],
                venmo_handle=user_data.get("venmo_handle"),
                created_at=datetime.fromisoformat(user_data["created_at"]),
            ))
        return users
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
            created_at=datetime.fromisoformat(circle_data["created_at"]),
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
