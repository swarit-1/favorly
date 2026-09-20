"""Linq webhook: inbound texts → intent → matching → reply.

Register with scripts/register_linq_webhook.py (target_url = <public URL>/webhooks/linq).
Payload shape (message.received, docs.linqapp.com):
{
  "event_type": "message.received",
  "data": {
    "chat": {"id": "...", "is_group": false},
    "direction": "inbound",
    "sender_handle": {"handle": "+1202...", "service": "iMessage"},
    "parts": [{"type": "text", "value": "..."}]
  }
}

Every message is also mirrored into the Trellis graph service (best-effort,
fire-and-forget): people upsert on contact, asks become needs, offered runs
become trips, and trip-matched asks are claimed by the shopper. Trellis's
person-aware ranking (reciprocity, mutuals, fit, affinity) is blended into
"what should I pick up?" replies as the "why you" lines.
"""

from __future__ import annotations

from fastapi import APIRouter, BackgroundTasks, Request

from agent.favor_flow import handle_inbound
from agent.linq_client import notify, send_reply
from agent.store import store
from services import trellis_client as trellis

router = APIRouter(tags=["linq-agent"])


@router.post("/webhooks/linq")
async def linq_webhook(request: Request, background: BackgroundTasks):
    payload = await request.json()
    if payload.get("event_type") != "message.received":
        return {"status": "ignored"}

    data = payload.get("data", {})
    if data.get("direction") != "inbound":
        return {"status": "ignored"}

    sender = (data.get("sender_handle") or {}).get("handle")
    chat_id = (data.get("chat") or {}).get("id")
    text = " ".join(
        p.get("value", "") for p in data.get("parts", []) if p.get("type") == "text"
    ).strip()
    if not sender or not text:
        return {"status": "ignored"}

    # Reply asynchronously so the webhook ACKs fast.
    background.add_task(_process, sender, chat_id, text)
    return {"status": "ok"}


async def _process(sender: str, chat_id: str | None, text: str) -> None:
    replies, notifications = await handle_inbound(store, sender, text)
    if replies:
        # First reply (the ack) goes out immediately; the drained grocery
        # events may append "why you" lines to it.
        first = replies[0]
        try:
            first = await _sync_trellis(first)
        except Exception as e:  # Trellis drift must never block the reply
            print(f"[trellis-sync] skipped: {e}", flush=True)
        await send_reply(first, chat_id=chat_id, to=sender)
        for extra in replies[1:]:
            await send_reply(extra, chat_id=chat_id, to=sender)
    for phone, message in notifications:
        await notify(phone, message)


async def _sync_trellis(reply: str) -> str:
    """Forward the drained handler events to Trellis; append its person-aware
    reasons when the user asked for recommendations. Any Trellis failure is
    swallowed, so the SMS flow never depends on it.

    Since the Supabase-identity rework, Trellis has no POST /people — only
    people with a real `users` row exist there. SMS-only texters therefore
    can't be mirrored; their needs FK-fail server-side and are skipped."""
    for event in store.drain_events():
        kind = event[0]
        if kind == "ask":
            _, ask, matched_trip, raw_text = event
            if ask.trellis_need_id is None:  # intake may have created it already
                ask.trellis_need_id = await trellis.post_need(ask.user_id, raw_text)
            if matched_trip and ask.trellis_need_id:
                await trellis.claim_need(ask.trellis_need_id, matched_trip.shopper_id)
        elif kind == "trip":
            _, trip, attached_asks = event
            await trellis.post_trip(trip.shopper_id, trip.store, trip.depart_at)
            for ask in attached_asks:
                if ask.trellis_need_id:
                    await trellis.claim_need(ask.trellis_need_id, trip.shopper_id)
        elif kind == "recs":
            profile = event[1]
            favors = await trellis.get_recommendations(profile.user.id)
            if favors:
                lines = ["", "🧠 Why you (from your favor graph):"]
                lines += [f"• {f['reason']}" for f in favors[:3] if f.get("reason")]
                if len(lines) > 2:
                    reply += "\n".join(lines)
    return reply
