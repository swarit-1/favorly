"""Intent parsing for inbound texts.

Primary parsing has moved to Trellis POST /needs/intake (see favor_flow.py);
this module remains as the Trellis-unreachable fallback. Its LLM path runs on
Meta Muse (set MUSE_API_KEY -- same env vars and endpoint as the vision
service). Final fallback: deterministic rules, so the whole flow works with
no keys at all.
"""

from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional

INTENTS = {"ask_favor", "offer_trip", "get_recommendations", "status", "set_name", "help"}


@dataclass
class ParsedIntent:
    intent: str
    items: list[dict] = field(default_factory=list)  # {name, qty, note}
    store: Optional[str] = None
    depart_minutes_from_now: Optional[int] = None
    name: Optional[str] = None  # for set_name


_SCHEMA = {
    "type": "object",
    "properties": {
        "intent": {
            "type": "string",
            "enum": sorted(INTENTS),
            "description": (
                "ask_favor: user wants someone to pick something up for them. "
                "offer_trip: user announces they are going to a store and can carry favors. "
                "get_recommendations: user asks which favors they should do / what to pick up "
                "for neighbors. status: user asks what's currently open (trips, their asks). "
                "set_name: user tells the agent their name. help: greeting or anything else."
            ),
        },
        "items": {
            "type": "array",
            "description": "Concrete items the user wants picked up (ask_favor only).",
            "items": {
                "type": "object",
                "properties": {
                    "name": {"type": "string", "description": "Item name, lowercase, no quantity words"},
                    "qty": {"type": "integer", "description": "Quantity, default 1"},
                    "note": {"type": ["string", "null"], "description": "Brand/size/ripeness hints"},
                },
                "required": ["name", "qty", "note"],
                "additionalProperties": False,
            },
        },
        "store": {
            "type": ["string", "null"],
            "description": "Store name if mentioned (offer_trip, or a preference on ask_favor)",
        },
        "depart_minutes_from_now": {
            "type": ["integer", "null"],
            "description": "Minutes until departure, if the user gave a time ('at 3pm', 'in 20'). Null if unknown.",
        },
        "name": {"type": ["string", "null"], "description": "User's name (set_name only)"},
    },
    "required": ["intent", "items", "store", "depart_minutes_from_now", "name"],
    "additionalProperties": False,
}

_SYSTEM = """You parse text messages sent to Favorly, a neighbor favor-running app.
Neighbors text this agent to (a) ask for favors — small pickups they want someone to
grab for them, (b) announce a store trip they're about to make, or (c) ask which favors
they should complete for others.

Extract the intent and fields per the schema. Rules:
- "can someone grab me X and Y" / "i need X" / "pick up X for me" → ask_favor with items.
- "I'm going to <store> at 3" / "heading to <store>" / "making a Costco run" → offer_trip.
- "what should I pick up?" / "any favors for me to do?" / "recommend favors" → get_recommendations.
- "what's going on" / "any open trips" / "status" → status.
- "call me Sam" / "I'm Sam" → set_name.
- Normalize item names: lowercase, singular quantity words removed ("2 dozen eggs" →
  name "eggs", qty 2, note "dozen"). Keep brand/variant in the name ("oat milk").
- Time: compute minutes from now using the current local time given in the message
  context. "at 3" with current time 1:30pm → 90. Ambiguous bare hours are the next
  occurrence of that hour. If no time is given, use null."""


def parse_message(text: str, now: Optional[datetime] = None) -> ParsedIntent:
    now = now or datetime.now()
    if os.getenv("MUSE_API_KEY"):
        try:
            return _parse_with_muse(text, now)
        except Exception as exc:  # any API failure → deterministic fallback
            print(f"[nlu] Muse parse failed ({exc}); using rule fallback")
    return parse_rules(text, now)


# ---------------------------------------------------------------------------
# Meta Muse path (OpenAI-compatible chat completions -- same env vars and
# endpoint shape as the vision service, see backend/services/vision_service.py)
# ---------------------------------------------------------------------------

def _parse_with_muse(text: str, now: datetime) -> ParsedIntent:
    import httpx

    base_url = os.getenv("MUSE_API_BASE_URL", "https://api.meta.ai/v1")
    model = os.getenv("MUSE_MODEL", "muse-spark-1.3")
    system = (
        _SYSTEM
        + "\nReturn ONLY a JSON object matching this schema, no prose:\n"
        + json.dumps(_SCHEMA)
    )
    response = httpx.post(
        f"{base_url}/chat/completions",
        headers={
            "Authorization": f"Bearer {os.environ['MUSE_API_KEY']}",
            "Content-Type": "application/json",
        },
        json={
            "model": model,
            "messages": [
                {"role": "system", "content": system},
                {
                    "role": "user",
                    "content": (
                        f"Current local time: {now.strftime('%A %I:%M %p')}\n"
                        f"Message: {text}"
                    ),
                },
            ],
            "max_tokens": 1024,
            "temperature": 0.2,
        },
        timeout=4.0,
    )
    response.raise_for_status()
    content = response.json()["choices"][0]["message"]["content"] or ""
    start, end = content.find("{"), content.rfind("}") + 1
    if start == -1 or end <= start:
        raise ValueError("no JSON object in Muse response")
    payload = json.loads(content[start:end])
    intent = payload.get("intent") if payload.get("intent") in INTENTS else "help"
    return ParsedIntent(
        intent=intent,
        items=[i for i in (payload.get("items") or []) if i.get("name")],
        store=payload.get("store"),
        depart_minutes_from_now=payload.get("depart_minutes_from_now"),
        name=payload.get("name"),
    )


# ---------------------------------------------------------------------------
# Rule-based fallback
# ---------------------------------------------------------------------------

_TRIP_RE = re.compile(
    r"\b(?:going|heading|headed|driving|on my way|running)\s+(?:out\s+)?to\s+(?P<store>[\w' ]+?)(?=\s+(?:at|in|around|by)\b|[.,!]|$)",
    re.IGNORECASE,
)
_RUN_RE = re.compile(r"\bmaking an?\s+(?P<store>[\w' ]+?)\s+run\b", re.IGNORECASE)
_AT_TIME_RE = re.compile(r"\bat\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b", re.IGNORECASE)
_IN_TIME_RE = re.compile(r"\bin\s+(\d{1,3})\s*(min|mins|minutes|hr|hrs|hours?)\b", re.IGNORECASE)
_NAME_RE = re.compile(r"\b(?:call me|i'?m|my name is|this is)\s+([A-Za-z]+)\b", re.IGNORECASE)
_QTY_RE = re.compile(r"^(\d+|a couple(?: of)?|a few|a dozen)\s+(.*)$", re.IGNORECASE)

_ASK_LEADINS = [
    r"can (?:some(?:one|body)|anyone|you) (?:please )?(?:grab|get|pick up|buy|bring)( me)?",
    r"(?:please )?(?:grab|get|pick up|buy|bring) me",
    r"i (?:need|want|could use)",
    r"pick up",
]
_REC_HINTS = [
    "recommend", "what should i", "what can i pick up", "what can i grab",
    "favors for me", "any favors", "what do i need to do", "what do i need to complete",
    "my list", "who needs", "what does everyone need",
]
_STATUS_HINTS = ["status", "what's open", "whats open", "open trips", "any trips", "what's going on"]

# A "store" that starts with a verb is not a store: "I'm going to need help
# moving a couch" must not become a trip to "Need Help Moving A Couch".
_STORE_VERB_RE = re.compile(
    r"^(?:need|help|be|have|get|do|make|move|build|borrow|ask|go|try|see)\b",
    re.IGNORECASE,
)


def _plausible_store(raw: str) -> bool:
    return not _STORE_VERB_RE.match(raw.strip()) and len(raw.strip().split()) <= 4


def parse_rules(text: str, now: Optional[datetime] = None) -> ParsedIntent:
    now = now or datetime.now()
    lowered = text.lower().strip()

    m = _NAME_RE.search(text)
    if m and len(lowered.split()) <= 5:
        return ParsedIntent(intent="set_name", name=m.group(1))

    trip = _TRIP_RE.search(text) or _RUN_RE.search(text)
    if trip and not _plausible_store(trip.group("store")):
        trip = None
    if trip:
        # str.title() would capitalize after apostrophes ("Trader Joe'S")
        store_name = " ".join(
            w if w[:1].isupper() else w.capitalize()
            for w in trip.group("store").strip().split()
        )
        return ParsedIntent(
            intent="offer_trip",
            store=store_name,
            depart_minutes_from_now=_extract_minutes(text, now),
        )

    if any(h in lowered for h in _REC_HINTS):
        return ParsedIntent(intent="get_recommendations")
    if any(h in lowered for h in _STATUS_HINTS):
        return ParsedIntent(intent="status")

    for leadin in _ASK_LEADINS:
        m = re.search(leadin + r"\s+(?P<rest>.+)", lowered)
        if m:
            items = _split_items(m.group("rest"))
            if items:
                note = _preference_note(lowered)
                if note:
                    for item in items:
                        item["note"] = item["note"] or note
                return ParsedIntent(intent="ask_favor", items=items)

    return ParsedIntent(intent="help")


_PREFERENCE_RE = re.compile(
    r"\b(i (?:like|prefer|love)\b[^.?!]*|not (?:really |too )?picky[^.?!]*|any brand[^.?!]*)",
    re.IGNORECASE,
)


def _preference_note(text: str) -> str | None:
    """Pull a preference clause ('I like salty or sweet, not picky') into the note."""
    m = _PREFERENCE_RE.search(text)
    return m.group(1).strip(" ,") if m else None


def _split_items(rest: str) -> list[dict]:
    rest = re.split(r"[.?!]", rest)[0]
    rest = re.sub(r"^to\s+(?:get|grab|pick up|buy|have)\s+", "", rest)  # "need to get snacks"
    rest = re.sub(r"\bfrom\s+[\w' ]+$", "", rest)  # "eggs from trader joe's"
    parts = re.split(r",|\band\b|\+|&", rest)
    items = []
    for part in parts:
        name = part.strip(" .!?")
        if not name or name in {"me", "please", "thanks", "thank you"}:
            continue
        qty, note = 1, None
        m = _QTY_RE.match(name)
        if m:
            qty_word, name = m.group(1).lower(), m.group(2).strip()
            if qty_word.isdigit():
                qty = int(qty_word)
            elif "dozen" in qty_word:
                qty, note = 1, "dozen"
            elif "couple" in qty_word:
                qty = 2
            elif "few" in qty_word:
                qty = 3
        name = re.sub(r"^(some|a|an|the)\s+", "", name)
        if name:
            items.append({"name": name, "qty": qty, "note": note})
    return items


def _extract_minutes(text: str, now: datetime) -> Optional[int]:
    m = _IN_TIME_RE.search(text)
    if m:
        n = int(m.group(1))
        return n * 60 if m.group(2).lower().startswith(("hr", "hour")) else n

    m = _AT_TIME_RE.search(text)
    if m:
        hour = int(m.group(1))
        minute = int(m.group(2) or 0)
        meridiem = (m.group(3) or "").lower()
        if meridiem == "pm" and hour < 12:
            hour += 12
        elif not meridiem:
            # bare hour → next occurrence of that hour (12h clock)
            candidates = [hour % 24, (hour + 12) % 24]
            future = [
                h for h in candidates
                if (h, minute) > (now.hour, now.minute)
            ]
            hour = min(future) if future else min(candidates)
        base = now.replace(second=0, microsecond=0)
        target = base.replace(hour=hour % 24, minute=minute)
        delta = (target - base).total_seconds() / 60
        if delta < 0:
            delta += 24 * 60
        return round(delta)
    return None
