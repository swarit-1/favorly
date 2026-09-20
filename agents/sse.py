"""Minimal in-process pub/sub for SSE (§11 events push). Supabase Realtime
replaces this outright (§15) if/when this runs against Supabase with logical
replication enabled on edges/claims/intros -- kept here so the service is
self-contained without that dependency.
"""

import asyncio

_subscribers: set[asyncio.Queue] = set()


def subscribe() -> asyncio.Queue:
    q: asyncio.Queue = asyncio.Queue()
    _subscribers.add(q)
    return q


def unsubscribe(q: asyncio.Queue):
    _subscribers.discard(q)


async def publish(event: str, data: dict):
    payload = {"event": event, "data": data}
    for q in list(_subscribers):
        await q.put(payload)
