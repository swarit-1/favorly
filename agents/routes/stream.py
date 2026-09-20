"""Events push. SSE emitting claim_extracted, edge_created, extraction_complete.
Avoids polling; the frontend animates off this.

If this ever runs against Supabase with logical replication enabled, prefer
subscribing to postgres_changes directly and delete this endpoint.
"""

import asyncio
import json

from fastapi import APIRouter
from fastapi.responses import StreamingResponse

import sse

router = APIRouter()


@router.get("/stream")
async def stream():
    async def event_source():
        q = sse.subscribe()
        try:
            while True:
                payload = await q.get()
                yield f"event: {payload['event']}\ndata: {json.dumps(payload['data'], default=str)}\n\n"
        except asyncio.CancelledError:
            pass
        finally:
            sse.unsubscribe(q)

    return StreamingResponse(event_source(), media_type="text/event-stream")
