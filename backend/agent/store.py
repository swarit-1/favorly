"""In-memory state for the Linq agent.

Mirrors the demo store used by the Flutter app: one circle, members, open
trips, requests, plus a *pending favor pool* for asks that arrive when no
matching trip is open. Swap for Supabase later without changing handlers.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Optional
from uuid import UUID, uuid4

from shared.contracts.models import (
    Circle,
    Request,
    Item,
    StoreSection,
    Trip,
    TripStatus,
    User,
)
from matching import assign_section

_SEED_PATH = Path(__file__).resolve().parent.parent / "seed" / "demo_circle.json"


@dataclass
class AskItem:
    name: str
    qty: int = 1
    note: Optional[str] = None
    section: StoreSection = StoreSection.OTHER


@dataclass
class FavorAsk:
    """A favor request not yet attached to any trip."""

    user_id: UUID
    items: list[AskItem]
    id: UUID = field(default_factory=uuid4)
    created_at: datetime = field(default_factory=datetime.utcnow)
    matched_trip_id: Optional[UUID] = None
    trellis_need_id: Optional[str] = None  # mirror in the Trellis needs pool


@dataclass
class Profile:
    user: User
    phone: str


class AgentStore:
    def __init__(self) -> None:
        seed = json.loads(_SEED_PATH.read_text())
        self.circle = Circle(**seed["circle"])
        self.profiles: dict[str, Profile] = {}  # phone -> Profile
        self.trips: dict[UUID, Trip] = {}
        self.requests: dict[UUID, Request] = {}
        self.asks: dict[UUID, FavorAsk] = {}
        # last agent prompt per phone, for yes/no follow-ups: (kind, payload)
        self.pending_action: dict[str, tuple[str, dict]] = {}
        # integration events for the webhook to forward (e.g. to Trellis);
        # handlers append, the webhook drains after each message
        self.events: list[tuple] = []

    def drain_events(self) -> list[tuple]:
        drained, self.events = self.events, []
        return drained

    # -- users ---------------------------------------------------------------

    def user_for_phone(self, phone: str) -> Profile:
        """Look up by phone. Delegates to the phone-to-person identity bridge
        (backend/agent/identity.py): in-memory cache, then users.phone in
        Supabase, then LINQ_USER_PHONES env resolution, then auto-provision.
        Without Supabase env (tests) it falls back to a random in-memory UUID."""
        from . import identity

        return identity.resolve(self, phone)

    def rename(self, phone: str, name: str) -> None:
        self.profiles[phone].user.name = name.strip().title()

    def name_of(self, user_id: UUID) -> str:
        for p in self.profiles.values():
            if p.user.id == user_id:
                return p.user.name
        return "someone"

    # -- trips & requests ------------------------------------------------------

    def open_trips(self) -> list[Trip]:
        return [t for t in self.trips.values() if t.status is TripStatus.OPEN]

    def requester_count(self, trip_id: UUID) -> int:
        return len({r.requester_id for r in self.requests.values() if r.trip_id == trip_id})

    def create_trip(self, shopper_id: UUID, store: str, depart_at: datetime) -> Trip:
        trip = Trip(
            shopper_id=shopper_id,
            circle_id=self.circle.id,
            store=store,
            depart_at=depart_at,
        )
        self.trips[trip.id] = trip
        return trip

    def attach_ask_to_trip(self, ask: FavorAsk, trip: Trip) -> Request:
        request = Request(trip_id=trip.id, requester_id=ask.user_id)
        request.items = [
            Item(
                request_id=request.id,
                trip_id=trip.id,
                name=it.name,
                qty=it.qty,
                note=it.note,
                section=it.section,
            )
            for it in ask.items
        ]
        self.requests[request.id] = request
        ask.matched_trip_id = trip.id
        self.asks.pop(ask.id, None)
        return request

    # -- favor asks -------------------------------------------------------------

    def create_ask(self, user_id: UUID, items: list[dict]) -> FavorAsk:
        ask_items = [
            AskItem(
                name=i["name"],
                qty=int(i.get("qty") or 1),
                note=i.get("note"),
                section=assign_section(i["name"]),
            )
            for i in items
        ]
        ask = FavorAsk(user_id=user_id, items=ask_items)
        self.asks[ask.id] = ask
        return ask

    def pending_asks(self, exclude_user: Optional[UUID] = None) -> list[FavorAsk]:
        return [
            a
            for a in self.asks.values()
            if a.matched_trip_id is None and a.user_id != exclude_user
        ]

    def trip_items_for_shopper(self, trip_id: UUID) -> list[tuple[str, Item]]:
        """(requester name, item) pairs attached to a trip."""
        out: list[tuple[str, Item]] = []
        for r in self.requests.values():
            if r.trip_id == trip_id:
                requester = self.name_of(r.requester_id)
                out.extend((requester, item) for item in r.items)
        return out


# Singleton used by the webhook route.
store = AgentStore()
