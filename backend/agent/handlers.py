"""Conversation logic: parsed intent + store + matching engine → reply text.

Pure functions over the AgentStore so everything is unit-testable without
Linq or Claude. Returns (reply, notifications) where notifications are
proactive messages to other members' phones.
"""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Optional
from uuid import UUID

from matching import rank_trips_for_ask, recommend_asks_for_trip
from shared.contracts.models import Trip, TripStatus

from .nlu import ParsedIntent, parse_message
from .store import AgentStore, FavorAsk, Profile

Notification = tuple[str, str]  # (phone, text)

HELP_TEXT = (
    "Hey, I'm the Favorly agent for your circle. You can text me things like:\n"
    "• \"Can someone grab me oat milk and eggs?\" — ask a favor\n"
    "• \"I'm going to Trader Joe's at 3\" — offer a run\n"
    "• \"What should I pick up?\" — favors matched to you\n"
    "• \"Status\" — open runs and your asks\n"
    "• \"Call me Sam\" — set your name"
)


def handle_message(store: AgentStore, phone: str, text: str, now: Optional[datetime] = None) -> tuple[str, list[Notification]]:
    now = now or datetime.now()
    first_contact = phone not in store.profiles
    profile = store.user_for_phone(phone)
    parsed = parse_message(text, now)

    if first_contact:
        reply, notes = _dispatch(store, phone, profile, parsed, now)
        welcome = (
            f"👋 Welcome to Favorly — you're in the {store.circle.name} circle as "
            f"{profile.user.name} (text \"call me <name>\" to change that).\n\n"
        )
        return welcome + reply, notes
    return _dispatch(store, phone, profile, parsed, now)


def _dispatch(store: AgentStore, phone: str, profile: Profile, parsed: ParsedIntent, now: datetime) -> tuple[str, list[Notification]]:

    if parsed.intent == "set_name" and parsed.name:
        store.rename(phone, parsed.name)
        return f"Got it — you're {store.profiles[phone].user.name} now. 👋", []
    if parsed.intent == "ask_favor" and parsed.items:
        return _handle_ask(store, profile, parsed, now)
    if parsed.intent == "offer_trip" and parsed.store:
        return _handle_trip(store, profile, parsed, now)
    if parsed.intent == "get_recommendations":
        return _handle_recommendations(store, profile, now), []
    if parsed.intent == "status":
        return _handle_status(store, profile, now), []
    return HELP_TEXT, []


# ---------------------------------------------------------------------------

def _fmt_time(dt: datetime) -> str:
    return dt.strftime("%I:%M %p").lstrip("0").lower()


def _fmt_items(ask: FavorAsk) -> str:
    parts = []
    for it in ask.items:
        qty = f"{it.qty}x " if it.qty > 1 else ""
        note = f" ({it.note})" if it.note else ""
        parts.append(f"{qty}{it.name}{note}")
    return ", ".join(parts)


def _phone_of(store: AgentStore, user_id: UUID) -> Optional[str]:
    for p in store.profiles.values():
        if p.user.id == user_id and p.phone:
            return p.phone
    return None


def _handle_ask(store: AgentStore, profile: Profile, parsed: ParsedIntent, now: datetime) -> tuple[str, list[Notification]]:
    ask = store.create_ask(profile.user.id, parsed.items)
    candidates = [
        (t, store.requester_count(t.id))
        for t in store.open_trips()
        if t.shopper_id != profile.user.id
    ]
    ranked = rank_trips_for_ask([it.section for it in ask.items], candidates, now)

    if ranked:
        trip, score = ranked[0]
        store.attach_ask_to_trip(ask, trip)
        shopper = store.name_of(trip.shopper_id)
        reply = (
            f"You're in luck — {shopper} is heading to {trip.store} at "
            f"{_fmt_time(trip.depart_at)} (match score {score:.2f}). "
            f"I added {_fmt_items(ask)} to their run. "
            f"You'll settle up via Venmo after the receipt."
        )
        notifications = []
        shopper_phone = _phone_of(store, trip.shopper_id)
        if shopper_phone:
            notifications.append((
                shopper_phone,
                f"New favor on your {trip.store} run: {profile.user.name} needs "
                f"{_fmt_items(ask)}. Reply \"what should I pick up\" for your full list.",
            ))
        return reply, notifications

    return (
        f"No open runs match right now, so I posted your ask: {_fmt_items(ask)}. "
        f"The moment a neighbor offers a matching trip I'll attach it and let you know.",
        [],
    )


def _handle_trip(store: AgentStore, profile: Profile, parsed: ParsedIntent, now: datetime) -> tuple[str, list[Notification]]:
    depart_at = now.replace(second=0, microsecond=0) + timedelta(
        minutes=parsed.depart_minutes_from_now or 60
    )
    trip = store.create_trip(profile.user.id, parsed.store, depart_at)

    pending = store.pending_asks(exclude_user=profile.user.id)
    recs = recommend_asks_for_trip(
        [(str(a.id), [it.section for it in a.items]) for a in pending],
        trip,
        store.requester_count(trip.id),
        now,
    )

    notifications: list[Notification] = []
    matched_lines: list[str] = []
    asks_by_id = {str(a.id): a for a in pending}
    for ask_id, score in recs:
        ask = asks_by_id[ask_id]
        store.attach_ask_to_trip(ask, trip)
        requester = store.name_of(ask.user_id)
        matched_lines.append(f"• {requester}: {_fmt_items(ask)}")
        requester_phone = _phone_of(store, ask.user_id)
        if requester_phone:
            notifications.append((
                requester_phone,
                f"Good news — {profile.user.name} is going to {trip.store} at "
                f"{_fmt_time(depart_at)} and I attached your ask ({_fmt_items(ask)}).",
            ))

    reply = f"Logged your {trip.store} run at {_fmt_time(depart_at)}."
    if matched_lines:
        reply += " I matched these favors to it:\n" + "\n".join(matched_lines)
        reply += "\nText \"what should I pick up\" before you leave for the final list."
    else:
        reply += " No pending favors match yet — I'll add any that come in before you leave."
    return reply, notifications


def _handle_recommendations(store: AgentStore, profile: Profile, now: datetime) -> str:
    my_trip = next(
        (t for t in store.open_trips() if t.shopper_id == profile.user.id), None
    )

    if my_trip:
        lines = [f"Your {my_trip.store} run at {_fmt_time(my_trip.depart_at)}:"]
        attached = store.trip_items_for_shopper(my_trip.id)
        if attached:
            lines.append("On your list:")
            for requester, item in sorted(attached, key=lambda p: p[1].section.value):
                qty = f"{item.qty}x " if item.qty > 1 else ""
                note = f" ({item.note})" if item.note else ""
                lines.append(f"• {qty}{item.name}{note} — {requester} [{item.section.value}]")
        pending = store.pending_asks(exclude_user=profile.user.id)
        recs = recommend_asks_for_trip(
            [(str(a.id), [it.section for it in a.items]) for a in pending],
            my_trip,
            store.requester_count(my_trip.id),
            now,
        )
        asks_by_id = {str(a.id): a for a in pending}
        if recs:
            lines.append("Also a good fit for this run:")
            for ask_id, score in recs[:3]:
                ask = asks_by_id[ask_id]
                lines.append(
                    f"• {store.name_of(ask.user_id)} needs {_fmt_items(ask)} "
                    f"(match {score:.2f})"
                )
        if len(lines) == 1:
            lines.append("Nothing attached yet — I'll match favors as they come in.")
        return "\n".join(lines)

    # No trip of their own: surface what they *could* do for neighbors.
    pending = store.pending_asks(exclude_user=profile.user.id)
    open_trips = [t for t in store.open_trips() if t.shopper_id != profile.user.id]
    if not pending and not open_trips:
        return (
            "Nothing needs doing right now. If you're heading out, text me "
            "\"I'm going to <store> at <time>\" and I'll match neighbors' favors to your run."
        )
    lines = ["Here's how you could help right now:"]
    for ask in sorted(pending, key=lambda a: a.created_at)[:5]:
        sections = ", ".join(sorted({it.section.value for it in ask.items}))
        lines.append(f"• {store.name_of(ask.user_id)} needs {_fmt_items(ask)} [{sections}]")
    if pending:
        lines.append(
            "Text \"I'm going to <store>\" and I'll attach the ones that fit your run."
        )
    for t in open_trips:
        lines.append(
            f"• {store.name_of(t.shopper_id)} is running to {t.store} at "
            f"{_fmt_time(t.depart_at)} — you can still add asks to it."
        )
    return "\n".join(lines)


def _handle_status(store: AgentStore, profile: Profile, now: datetime) -> str:
    lines = []
    trips = store.open_trips()
    if trips:
        lines.append("Open runs:")
        for t in trips:
            n = store.requester_count(t.id)
            lines.append(
                f"• {store.name_of(t.shopper_id)} → {t.store} at {_fmt_time(t.depart_at)} "
                f"({n}/{t.caps.max_requesters} requesters)"
            )
    my_asks = [a for a in store.asks.values() if a.user_id == profile.user.id]
    if my_asks:
        lines.append("Your pending asks:")
        lines.extend(f"• {_fmt_items(a)}" for a in my_asks)
    return "\n".join(lines) if lines else "All quiet — no open runs or pending favors."
