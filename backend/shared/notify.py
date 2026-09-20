"""Notification utilities for fan-out notifications on trip events."""

from uuid import UUID
from supabase import Client


def write_notification(
    supabase: Client,
    user_id: UUID,
    trip_id: UUID | None,
    kind: str,
    title: str,
    body: str,
) -> None:
    """Write a notification to the database.

    Args:
        supabase: Supabase client with service role
        user_id: User to notify
        trip_id: Associated trip (optional)
        kind: Notification type (new_message, trip_departed, request_accepted, item_substituted)
        title: Short notification title
        body: Notification body text
    """
    supabase.table("notifications").insert({
        "user_id": str(user_id),
        "trip_id": str(trip_id) if trip_id else None,
        "kind": kind,
        "title": title,
        "body": body,
    }).execute()
