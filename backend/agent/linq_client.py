"""Thin client for the Linq partner API (iMessage/RCS/SMS).

Docs: https://docs.linqapp.com — quickstart + v3 messages endpoints.
Without LINQ_API_KEY set, replies are printed to the console so the whole
flow can be exercised locally (curl the webhook, read the reply in logs).
"""

from __future__ import annotations

import os
from typing import Optional

import httpx

BASE_URL = os.getenv("LINQ_BASE_URL", "https://api.linqapp.com")


def _headers() -> dict:
    return {
        "Authorization": f"Bearer {os.environ['LINQ_API_KEY']}",
        "Content-Type": "application/json",
    }


def _valid_chat_id(chat_id: Optional[str]) -> bool:
    try:
        import uuid
        return bool(chat_id) and bool(uuid.UUID(chat_id))
    except ValueError:
        return False


async def send_reply(text: str, chat_id: Optional[str] = None, to: Optional[str] = None) -> None:
    """Reply in an existing chat when we have its id, else start/reuse one by number."""
    if not _valid_chat_id(chat_id):
        chat_id = None  # Linq requires UUID chat ids; fall back to the number
    if not os.getenv("LINQ_API_KEY"):
        print(f"[linq:dry-run] reply to {chat_id or to}:\n{text}\n", flush=True)
        return

    async with httpx.AsyncClient(base_url=BASE_URL, timeout=15) as client:
        if chat_id:
            resp = await client.post(
                f"/api/partner/v3/chats/{chat_id}/messages",
                headers=_headers(),
                json={"message": {"parts": [{"type": "text", "value": text}]}},
            )
        else:
            resp = await client.post(
                "/api/partner/v3/messages",
                headers=_headers(),
                json={"to": [to], "message": {"parts": [{"type": "text", "value": text}]}},
            )
        if resp.status_code >= 400:
            print(f"[linq] send failed {resp.status_code}: {resp.text}", flush=True)


async def notify(phone: str, text: str) -> None:
    """Proactive outbound message (e.g. 'your favor got matched')."""
    await send_reply(text, to=phone)
