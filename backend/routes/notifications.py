"""Notification routes for real-time updates."""

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel

from db.client import get_supabase_client

router = APIRouter(prefix="/notifications", tags=["notifications"])


class Notification(BaseModel):
    """A user notification."""
    id: UUID
    user_id: UUID
    trip_id: UUID | None
    kind: str
    title: str
    body: str
    read: bool
    created_at: datetime


@router.get("")
async def get_notifications() -> list[Notification]:
    """Fetch user's unread notifications."""
    supabase = get_supabase_client()

    user = supabase.auth.get_user()
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated")

    notif_response = supabase.table("notifications").select(
        "*"
    ).eq("user_id", str(user.id)).eq("read", False).order(
        "created_at", desc=True
    ).execute()

    result = []
    for notif in notif_response.data or []:
        result.append(Notification(
            id=UUID(notif["id"]),
            user_id=UUID(notif["user_id"]),
            trip_id=UUID(notif["trip_id"]) if notif.get("trip_id") else None,
            kind=notif["kind"],
            title=notif["title"],
            body=notif["body"],
            read=notif["read"],
            created_at=datetime.fromisoformat(notif["created_at"]),
        ))

    return result


@router.patch("/{notification_id}/read")
async def mark_notification_read(notification_id: UUID) -> Notification:
    """Mark a single notification as read."""
    supabase = get_supabase_client()

    user = supabase.auth.get_user()
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated")

    # Verify ownership
    notif_response = supabase.table("notifications").select(
        "*"
    ).eq("id", str(notification_id)).execute()

    if not notif_response.data:
        raise HTTPException(status_code=404, detail="Notification not found")

    notif = notif_response.data[0]
    if notif["user_id"] != str(user.id):
        raise HTTPException(status_code=403, detail="Not your notification")

    # Update
    update_response = supabase.table("notifications").update(
        {"read": True}
    ).eq("id", str(notification_id)).execute()

    if not update_response.data:
        raise HTTPException(status_code=500, detail="Failed to update notification")

    updated = update_response.data[0]
    return Notification(
        id=UUID(updated["id"]),
        user_id=UUID(updated["user_id"]),
        trip_id=UUID(updated["trip_id"]) if updated.get("trip_id") else None,
        kind=updated["kind"],
        title=updated["title"],
        body=updated["body"],
        read=updated["read"],
        created_at=datetime.fromisoformat(updated["created_at"]),
    )


@router.patch("/read-all")
async def mark_all_notifications_read() -> dict[str, int]:
    """Mark all user's unread notifications as read."""
    supabase = get_supabase_client()

    user = supabase.auth.get_user()
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated")

    # Get count of unread
    count_response = supabase.table("notifications").select(
        "id", count="exact"
    ).eq("user_id", str(user.id)).eq("read", False).execute()

    count = count_response.count or 0

    # Update all to read
    if count > 0:
        supabase.table("notifications").update(
            {"read": True}
        ).eq("user_id", str(user.id)).eq("read", False).execute()

    return {"marked_read": count}
