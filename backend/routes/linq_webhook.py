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
"""

from __future__ import annotations

from fastapi import APIRouter, BackgroundTasks, Request

from agent.handlers import handle_message
from agent.linq_client import notify, send_reply
from agent.store import store

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
    reply, notifications = handle_message(store, sender, text)
    await send_reply(reply, chat_id=chat_id, to=sender)
    for phone, message in notifications:
        await notify(phone, message)
