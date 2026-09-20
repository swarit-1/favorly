"""Message routes for live chat in trips."""

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel

from db.client import get_supabase_client
from shared.notify import write_notification

router = APIRouter(prefix="/messages", tags=["messages"])


class MessageRequest(BaseModel):
    """Send a message."""
    body: str


class Message(BaseModel):
    """A message in a trip."""
    id: UUID
    trip_id: UUID
    sender_id: UUID
    sender_name: str
    body: str
    created_at: datetime


@router.post("/{trip_id}")
async def send_message(trip_id: UUID, req: MessageRequest) -> Message:
    """Send a message to a trip.

    Inserts the message and fan-outs notifications to all other members of the trip.
    """
    supabase = get_supabase_client()

    # Validate that the trip exists and the user is part of it
    trip_response = supabase.table("trips").select("*").eq("id", str(trip_id)).execute()
    if not trip_response.data:
        raise HTTPException(status_code=404, detail="Trip not found")

    trip = trip_response.data[0]

    # Get the authenticated user
    user = supabase.auth.get_user()
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated")

    sender_id = user.id

    # Verify user is part of the trip's circle
    circle_response = supabase.table("users").select("*").eq("id", str(sender_id)).execute()
    if not circle_response.data:
        raise HTTPException(status_code=404, detail="User not found")

    user_data = circle_response.data[0]
    if user_data["circle_id"] != trip["circle_id"]:
        raise HTTPException(status_code=403, detail="Not part of this trip's circle")

    # Get sender's name
    sender_name = user_data.get("name", "Unknown")

    # Insert the message
    message_response = supabase.table("messages").insert({
        "trip_id": str(trip_id),
        "sender_id": str(sender_id),
        "body": req.body,
    }).execute()

    if not message_response.data:
        raise HTTPException(status_code=500, detail="Failed to create message")

    message_data = message_response.data[0]

    # Fan-out notifications to all other circle members
    circle_members = supabase.table("users").select("id").eq(
        "circle_id", trip["circle_id"]
    ).execute()

    for member in circle_members.data or []:
        if member["id"] != str(sender_id):
            write_notification(
                supabase,
                UUID(member["id"]),
                trip_id,
                "new_message",
                title=f"New message from {sender_name}",
                body=req.body[:100],  # First 100 chars
            )

    return Message(
        id=UUID(message_data["id"]),
        trip_id=UUID(message_data["trip_id"]),
        sender_id=UUID(message_data["sender_id"]),
        sender_name=sender_name,
        body=message_data["body"],
        created_at=datetime.fromisoformat(message_data["created_at"]),
    )


@router.get("/{trip_id}")
async def get_messages(
    trip_id: UUID,
    limit: int = 50,
    before: datetime | None = None,
) -> list[Message]:
    """Fetch message history for a trip.

    Returns up to `limit` messages, newest first. If `before` is specified,
    only returns messages before that timestamp.
    """
    supabase = get_supabase_client()

    # Verify the trip exists
    trip_response = supabase.table("trips").select("*").eq("id", str(trip_id)).execute()
    if not trip_response.data:
        raise HTTPException(status_code=404, detail="Trip not found")

    trip = trip_response.data[0]

    # Verify the user is part of the trip's circle
    user = supabase.auth.get_user()
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated")

    circle_response = supabase.table("users").select("*").eq("id", str(user.id)).execute()
    if not circle_response.data or circle_response.data[0]["circle_id"] != trip["circle_id"]:
        raise HTTPException(status_code=403, detail="Not part of this trip's circle")

    # Build query
    query = supabase.table("messages").select(
        "*, users(name)"
    ).eq("trip_id", str(trip_id))

    if before:
        query = query.lt("created_at", before.isoformat())

    messages_response = query.order("created_at", desc=True).limit(limit).execute()

    result = []
    for msg in messages_response.data or []:
        sender_name = "Unknown"
        if msg.get("users"):
            sender_name = msg["users"].get("name", "Unknown")

        result.append(Message(
            id=UUID(msg["id"]),
            trip_id=UUID(msg["trip_id"]),
            sender_id=UUID(msg["sender_id"]),
            sender_name=sender_name,
            body=msg["body"],
            created_at=datetime.fromisoformat(msg["created_at"]),
        ))

    return list(reversed(result))  # Return oldest first for UI
