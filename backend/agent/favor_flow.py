"""v2 inbound SMS routing: any favor in, the right neighbor out.

Order of operations per message (PRD v2 P1.5/P3):
1. Fast path, no LLM: if the text is a short reply ("2", "yes", "done"),
   fetch this person's conversation state from Trellis and act on it.
   State is derived from the database, never process memory -- the one
   allowed in-memory bit is the remembered right_sized rewrite.
2. Rule parse. Grocery-verb asks, trips, status, recs, set_name go to the
   existing sync handlers -- zero change to the grocery loop.
3. Everything else goes to Trellis POST /needs/intake and branches on scope.
4. Fire-and-forget event log for profile mining.

Trellis never sees a phone; phones stay in backend `users.phone`.
"""

from __future__ import annotations

import asyncio
import os
import re
from datetime import datetime
from typing import Optional

from services import trellis_client as trellis

from .handlers import HELP_TEXT, Notification, handle_message
from .nlu import ParsedIntent, parse_rules
from .store import AgentStore, Profile

# ---------------------------------------------------------------------------
# Templates. House style: no em or en dashes, no scores, no gendered guesses.
# ---------------------------------------------------------------------------

ACK = "{title}, {when_text}. Finding the right neighbor."
ACK_NO_WHEN = "{title}. Finding the right neighbor."
WAIT = "Asked {helper}. I will text you as soon as they answer."
DECLINE_TO_ASKER = "{helper} can't make it today. Want me to ask {next}? Reply YES, or pick a number."
DECLINE_TO_ASKER_NO_NEXT = "{helper} can't make it today. Reply EVERYONE and I will ask the whole building."
DECLINE_ACK = "All good, thanks for answering. I will ask someone else."
DONE_FIRST = "Done. That was your first favor together. Your building just got a little closer."
DONE_HELPER = "Done. Thanks for showing up for {other}."
DONE_ASKER = "Done. {other} came through for you."
NOBODY = "Nobody has told me they have {item} yet. Want me to ask the whole building? Reply EVERYONE."
NOBODY_GENERIC = "Nobody fits just yet. Want me to ask the whole building? Reply EVERYONE."
BROADCAST_OK = "Okay, I asked the whole building. I will text you when someone steps up."
CANCELLED = "Cancelled. Text me whenever you need a hand."
OFFER_NOTED = "Noted. I will remember that."
POSTED_FALLBACK = "Posted. I will text you when someone picks it up."

_YES_RE = re.compile(r"^(yes|y|yep|yeah|sure|ok|okay|i can|happy to)\b", re.IGNORECASE)
_NO_RE = re.compile(r"^(no|n|nope|can'?t|cannot|not today|sorry)\b", re.IGNORECASE)
_DIGIT_RE = re.compile(r"^[1-5]$")
_EVERYONE_RE = re.compile(r"^(everyone|all|anyone)\b", re.IGNORECASE)
_CANCEL_RE = re.compile(r"^(cancel|never ?mind|forget it)\b", re.IGNORECASE)
_DONE_RE = re.compile(
    r"^(done|all done|finished|returned|got it back|all set|thanks,? done)\b", re.IGNORECASE
)
_RIGHT_SIZED_YES_RE = re.compile(r"^(yes|y|sure|ok|okay|do that)\b", re.IGNORECASE)
# Grocery verbs keep the errand regression on the untouched sync path.
_GROCERY_VERB_RE = re.compile(r"\b(grab|pick ?up|buy|bring)\b", re.IGNORECASE)

_SHORT_REPLY_RE = re.compile(
    r"^(yes|y|yep|yeah|sure|ok|okay|i can|happy to|no|n|nope|can'?t|cannot|not today|sorry|"
    r"[1-5]|everyone|all|anyone|cancel|never ?mind|forget it|done|all done|finished|returned|"
    r"got it back|all set|thanks,? done|do that)[.!]?$",
    re.IGNORECASE,
)


def _ack(need: dict) -> str:
    title = need.get("title") or "Got it"
    when = need.get("when_text")
    if when:
        return ACK.format(title=title, when_text=when)
    return ACK_NO_WHEN.format(title=title)


def _matches_reply(helpers: list[dict]) -> str:
    count_word = {1: "One neighbor who fits:", 2: "Two neighbors who fit:", 3: "Three neighbors who fit:"}
    lines = [count_word.get(len(helpers), "Three neighbors who fit:")]
    for h in helpers[:3]:
        first = h.get("person", {}).get("first_name") or h.get("person", {}).get("display_name", "A neighbor")
        where = h.get("where") or "in the building"
        tie = (h.get("tie_label") or "").lower()
        header = f"{h.get('rank')}. {first} · {where}" + (f" · {tie}" if tie else "")
        lines.append("")
        lines.append(header)
        reason = h.get("reason") or h.get("headline") or ""
        if reason:
            lines.append(reason)
    lines.append("")
    n = min(len(helpers), 3)
    digits = {1: "1", 2: "1 or 2", 3: "1, 2 or 3"}[n]
    lines.append(f"Reply {digits} and I will ask them. Or reply EVERYONE.")
    return "\n".join(lines)


def _invite_text(pending: dict) -> str:
    asker = pending.get("asker") or {}
    first = asker.get("first_name") or "A neighbor"
    floor = asker.get("floor")
    mutual = pending.get("mutual_first_name")
    title = (pending.get("title") or "a small favor").lower()
    when = pending.get("when_text")
    bits = f"{first}"
    if floor is not None:
        bits += f" on floor {floor}"
    if mutual:
        bits += f", a friend of {mutual},"
    line = f"{bits} is hoping for a hand: {title}"
    if when:
        line += f", {when}"
    return line + ". Up for it? Reply YES or NO. No pressure either way."


def _accept_helper_text(asker_first: str, unit: Optional[str], spark: Optional[str]) -> str:
    where = f"{asker_first} is in {unit}. " if unit else ""
    tail = f" {spark}" if spark else ""
    return f"You are on. {where}Text DONE here when it is wrapped up.{tail}"


def _accept_asker_text(helper_first: str, unit: Optional[str], spark: Optional[str]) -> str:
    where = f" They are in {unit}." if unit else ""
    tail = f" {spark}" if spark else ""
    return f"{helper_first} is in.{where}{tail}"


# ---------------------------------------------------------------------------
# Phone lookup: backend-only. Trellis never sees these.
# ---------------------------------------------------------------------------

def _phone_for_person(store: AgentStore, person_id: str) -> Optional[str]:
    for p in store.profiles.values():
        if str(p.user.id) == str(person_id) and p.phone:
            return p.phone
    if not (os.getenv("SUPABASE_URL") and os.getenv("SUPABASE_SERVICE_ROLE_KEY")):
        return None
    try:
        from db.client import get_supabase_client

        rows = (
            get_supabase_client().table("users").select("phone")
            .eq("id", str(person_id)).limit(1).execute().data
        )
        return (rows[0].get("phone") or None) if rows else None
    except Exception as e:
        print(f"[favor_flow] phone lookup failed: {e}", flush=True)
        return None


# ---------------------------------------------------------------------------
# The fast path: short replies interpreted against database-derived state.
# ---------------------------------------------------------------------------

async def _fast_path(
    store: AgentStore, phone: str, profile: Profile, text: str,
) -> Optional[tuple[list[str], list[Notification]]]:
    stripped = text.strip()
    if not _SHORT_REPLY_RE.match(stripped):
        return None

    person_id = str(profile.user.id)
    state = await trellis.state(person_id)

    pending = (state or {}).get("pending_invite")
    if pending and _YES_RE.match(stripped):
        return await _accept_invite(store, profile, pending)
    if pending and _NO_RE.match(stripped):
        return await _decline_invite(store, profile, pending)

    open_ask = (state or {}).get("open_ask")
    if open_ask:
        shortlist = open_ask.get("shortlist") or []
        if shortlist and (_DIGIT_RE.match(stripped) or _shortlist_by_name(shortlist, stripped)):
            entry = _shortlist_by_name(shortlist, stripped)
            if entry is None:
                idx = int(stripped)
                entry = next((s for s in shortlist if s.get("rank") == idx), None)
                if entry is None and 1 <= idx <= len(shortlist):
                    entry = shortlist[idx - 1]
            if entry is None:
                return (["That number is not on the list. Reply 1, 2 or 3, or a first name."], [])
            return await _send_invite(store, profile, open_ask, entry)
        if _EVERYONE_RE.match(stripped):
            await trellis.broadcast(open_ask["need_id"])
            return ([BROADCAST_OK], [])
        if _CANCEL_RE.match(stripped):
            await trellis.cancel(open_ask["need_id"])
            return ([CANCELLED], [])
        if shortlist and _YES_RE.match(stripped):
            declined = any(s.get("invite_status") == "declined" for s in shortlist)
            nxt = next(
                (s for s in shortlist if s.get("invite_status") is None), None,
            )
            if declined and nxt:
                return await _send_invite(store, profile, open_ask, nxt)

    remembered = store.pending_action.get(phone)
    if remembered and remembered[0] == "right_sized" and _RIGHT_SIZED_YES_RE.match(stripped):
        store.pending_action.pop(phone, None)
        return await _post_right_sized(store, profile, remembered[1]["text"])

    active = (state or {}).get("active_favor")
    if active and _DONE_RE.match(stripped):
        return await _fulfill(store, profile, active)

    return None


def _shortlist_by_name(shortlist: list[dict], text: str) -> Optional[dict]:
    lowered = text.strip().lower().rstrip(".!")
    for s in shortlist:
        if (s.get("first_name") or "").lower() == lowered:
            return s
    return None


async def _send_invite(
    store: AgentStore, profile: Profile, open_ask: dict, entry: dict,
) -> tuple[list[str], list[Notification]]:
    need_id = open_ask["need_id"]
    helper_id = entry["person_id"]
    result = await trellis.invite(need_id, helper_id)
    if result is None:
        return (["Hmm, I could not reach them just now. Try again in a minute."], [])
    helper_first = entry.get("first_name") or "them"

    notifications: list[Notification] = []
    helper_phone = _phone_for_person(store, helper_id)
    helper_state = await trellis.state(helper_id)
    pending = (helper_state or {}).get("pending_invite") or {
        "asker": {"first_name": profile.user.name.split()[0]},
        "title": open_ask.get("title"),
        "when_text": None,
    }
    invite_msg = _invite_text(pending)
    if helper_phone:
        notifications.append((helper_phone, invite_msg))
    else:
        _maybe_autoaccept(store, profile, need_id, helper_id, helper_first)

    return ([WAIT.format(helper=helper_first)], notifications)


def _maybe_autoaccept(
    store: AgentStore, profile: Profile, need_id: str, helper_id: str, helper_first: str,
) -> None:
    """3.4: a phoneless seeded persona can only answer in the app. With
    DEMO_AUTOACCEPT_SECONDS set, they accept after that delay."""
    delay = os.getenv("DEMO_AUTOACCEPT_SECONDS")
    if not delay:
        return

    async def _later():
        try:
            await asyncio.sleep(float(delay))
            result = await trellis.respond_invite(need_id, helper_id, True)
            if result is None:
                return
            print(f"[demo] auto-accept for seeded persona {helper_first}", flush=True)
            asker_state = await trellis.state(str(profile.user.id))
            active = (asker_state or {}).get("active_favor") or {}
            other = active.get("other") or {}
            msg = _accept_asker_text(
                other.get("first_name") or helper_first, other.get("unit"), active.get("spark"),
            )
            from .linq_client import notify

            if profile.phone:
                await notify(profile.phone, msg)
        except Exception as e:
            print(f"[demo] auto-accept failed: {e}", flush=True)

    asyncio.get_event_loop().create_task(_later())


async def _accept_invite(
    store: AgentStore, profile: Profile, pending: dict,
) -> tuple[list[str], list[Notification]]:
    need_id = pending["need_id"]
    helper_id = str(profile.user.id)
    result = await trellis.respond_invite(need_id, helper_id, True)
    if result is None:
        return (["Hmm, something went sideways. Try YES again in a minute."], [])

    helper_state = await trellis.state(helper_id)
    active = (helper_state or {}).get("active_favor") or {}
    other = active.get("other") or {}
    asker_first = other.get("first_name") or (pending.get("asker") or {}).get("first_name") or "your neighbor"
    spark = active.get("spark")
    reply = _accept_helper_text(asker_first, other.get("unit"), spark)

    notifications: list[Notification] = []
    asker_id = (pending.get("asker") or {}).get("id")
    if asker_id:
        asker_phone = _phone_for_person(store, asker_id)
        if asker_phone:
            asker_state = await trellis.state(str(asker_id))
            a_active = (asker_state or {}).get("active_favor") or {}
            a_other = a_active.get("other") or {}
            helper_first = a_other.get("first_name") or profile.user.name.split()[0]
            notifications.append((
                asker_phone,
                _accept_asker_text(helper_first, a_other.get("unit"), a_active.get("spark")),
            ))
    return ([reply], notifications)


async def _decline_invite(
    store: AgentStore, profile: Profile, pending: dict,
) -> tuple[list[str], list[Notification]]:
    need_id = pending["need_id"]
    helper_id = str(profile.user.id)
    result = await trellis.respond_invite(need_id, helper_id, False)
    if result is None:
        return (["Hmm, something went sideways. Try again in a minute."], [])

    notifications: list[Notification] = []
    asker_id = (pending.get("asker") or {}).get("id")
    helper_first = profile.user.name.split()[0]
    if asker_id:
        asker_phone = _phone_for_person(store, asker_id)
        if asker_phone:
            nxt = result.get("next")
            if nxt:
                next_first = (nxt.get("person") or {}).get("first_name") or "the next neighbor"
                msg = DECLINE_TO_ASKER.format(helper=helper_first, next=next_first)
            else:
                msg = DECLINE_TO_ASKER_NO_NEXT.format(helper=helper_first)
            notifications.append((asker_phone, msg))
    return ([DECLINE_ACK], notifications)


async def _fulfill(
    store: AgentStore, profile: Profile, active: dict,
) -> tuple[list[str], list[Notification]]:
    need_id = active["need_id"]
    result = await trellis.fulfill(need_id)
    if result is None:
        return (["Hmm, I could not mark that done just now. Try again in a minute."], [])

    other = active.get("other") or {}
    other_first = other.get("first_name") or "your neighbor"
    my_first = profile.user.name.split()[0]
    first_time = bool(result.get("first_favor_together"))

    if first_time:
        reply = DONE_FIRST
        counterpart_msg = DONE_FIRST
    elif active.get("role") == "helper":
        reply = DONE_HELPER.format(other=other_first)
        counterpart_msg = DONE_ASKER.format(other=my_first)
    else:
        reply = DONE_ASKER.format(other=other_first)
        counterpart_msg = DONE_HELPER.format(other=my_first)

    notifications: list[Notification] = []
    other_id = other.get("id")
    if other_id:
        other_phone = _phone_for_person(store, other_id)
        if other_phone:
            notifications.append((other_phone, counterpart_msg))
    return ([reply], notifications)


# ---------------------------------------------------------------------------
# Intake: parse + scope check on Trellis, then reply.
# ---------------------------------------------------------------------------

async def _post_right_sized(
    store: AgentStore, profile: Profile, text: str,
) -> tuple[list[str], list[Notification]]:
    result = await trellis.intake(str(profile.user.id), text, confirm_right_sized=True)
    if result is None or not result.get("need"):
        return ([POSTED_FALLBACK], [])
    return await _ok_branch(store, profile, result["need"])


async def _ok_branch(
    store: AgentStore, profile: Profile, need: dict,
) -> tuple[list[str], list[Notification]]:
    replies = [_ack(need)]
    ranked = await trellis.helpers(need["id"], limit=3)
    helpers = (ranked or {}).get("helpers") or []
    if helpers:
        replies.append(_matches_reply(helpers))
    else:
        item = (need.get("requires") or [None])[0]
        replies.append(NOBODY.format(item=f"a {item}") if item else NOBODY_GENERIC)
    return (replies, [])


def _route_to_grocery(parsed: ParsedIntent, text: str) -> bool:
    if parsed.intent in ("offer_trip", "status", "get_recommendations", "set_name"):
        return True
    if parsed.intent == "ask_favor" and parsed.items and _GROCERY_VERB_RE.search(text):
        return True
    return False


async def handle_inbound(
    store: AgentStore, phone: str, text: str, now: Optional[datetime] = None,
) -> tuple[list[str], list[Notification]]:
    now = now or datetime.now()
    profile = store.user_for_phone(phone)

    # 1. Fast path: short replies against database-derived state.
    fast = await _fast_path(store, phone, profile, text)
    if fast is not None:
        return fast

    # 2. Grocery loop, untouched (the rule parse is reused so no LLM call
    # delays the reply).
    parsed = parse_rules(text, now)
    if _route_to_grocery(parsed, text):
        reply, notes = handle_message(store, phone, text, now, parsed=parsed)
        return ([reply], notes)

    # 3. Everything else: Trellis intake.
    person_id = str(profile.user.id)
    result = await trellis.intake(person_id, text)
    if result is None:
        # Trellis unreachable: today's local parse + reply.
        reply, notes = handle_message(store, phone, text, now)
        return ([reply], notes)

    intent, scope = result.get("intent"), result.get("scope")
    out: tuple[list[str], list[Notification]]
    if intent == "offer_help":
        out = ([OFFER_NOTED], [])
    elif intent == "not_a_favor":
        out = ([HELP_TEXT], [])
    elif scope == "ok" and result.get("need"):
        need = result["need"]
        if need.get("category") == "errand" and need.get("items"):
            out = _errand_bridge(store, phone, profile, need, text, now)
        else:
            out = await _ok_branch(store, profile, need)
    elif scope in ("too_big", "needs_pro"):
        scope_reply = result.get("scope_reply") or "That one is bigger than a single favor."
        right_sized = result.get("right_sized")
        if right_sized:
            store.pending_action[phone] = ("right_sized", {"text": right_sized})
            out = ([f"{scope_reply} Reply YES to post that, or tell me again in your own words."], [])
        else:
            out = ([scope_reply], [])
    elif scope in ("not_ok", "unclear"):
        out = ([result.get("scope_reply") or "What do you need a hand with?"], [])
    else:
        reply, notes = handle_message(store, phone, text, now)
        out = ([reply], notes)

    # 4. Fire-and-forget: the raw text feeds profile extraction.
    try:
        asyncio.get_event_loop().create_task(trellis.log_event(person_id, text))
    except RuntimeError:
        await trellis.log_event(person_id, text)
    return out


def _errand_bridge(
    store: AgentStore, phone: str, profile: Profile, need: dict, text: str, now: datetime,
) -> tuple[list[str], list[Notification]]:
    """An errand parsed by Trellis still uses the existing trip matching.
    The store ask carries the Trellis need id so _sync_trellis does not post
    a duplicate need."""
    from .handlers import _handle_ask

    parsed = ParsedIntent(
        intent="ask_favor",
        items=[
            {"name": i.get("name"), "qty": int(i.get("qty") or 1), "note": i.get("note")}
            for i in need["items"] if i.get("name")
        ],
    )
    reply, notes = _handle_ask(store, profile, parsed, now, text)
    for event in store.events:
        if event[0] == "ask" and event[1].trellis_need_id is None:
            event[1].trellis_need_id = need["id"]
    return ([reply], notes)
