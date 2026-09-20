"""Write endpoints. Idempotent on source_key. Returns immediately;
extraction is async -- never make the caller wait on a model call.
"""

from datetime import datetime, timezone

import asyncpg
from fastapi import APIRouter, Depends, HTTPException

import edges as edges_mod
import sse
import worker
from deps import get_conn
from models import EventIn, FavorIn

router = APIRouter()


@router.post("/events", status_code=202)
async def create_event(payload: EventIn, conn: asyncpg.Connection = Depends(get_conn)):
    if payload.source_key:
        existing = await conn.fetchrow("SELECT id FROM events WHERE source_key = $1", payload.source_key)
        if existing:
            return {"event_id": str(existing["id"])}

    person = await conn.fetchrow("SELECT id FROM people WHERE id = $1", payload.person_id)
    if not person:
        raise HTTPException(404, "person not found")

    occurred_at = payload.occurred_at or datetime.now(timezone.utc)
    row = await conn.fetchrow(
        "INSERT INTO events (person_id, kind, body, occurred_at, source_key) "
        "VALUES ($1, $2, $3, $4, $5) RETURNING id",
        payload.person_id, payload.kind, payload.body, occurred_at, payload.source_key,
    )
    event_id = str(row["id"])

    if payload.kind in ("message", "favor_logged"):
        await worker.enqueue_event(event_id, payload.person_id, payload.body)

    return {"event_id": event_id}


@router.post("/favors", status_code=202)
async def create_favor(payload: FavorIn, conn: asyncpg.Connection = Depends(get_conn)):
    """Sugar over /events that writes the favor edge directly."""
    giver = await conn.fetchrow("SELECT id FROM people WHERE id = $1", payload.giver_id)
    receiver = await conn.fetchrow("SELECT id FROM people WHERE id = $1", payload.receiver_id)
    if not giver or not receiver:
        raise HTTPException(404, "giver or receiver not found")

    event_row = await conn.fetchrow(
        "INSERT INTO events (person_id, kind, body) VALUES ($1, 'favor_logged', $2) RETURNING id",
        payload.giver_id, payload.description,
    )
    event_id = str(event_row["id"])

    await edges_mod.write_edge(conn, payload.giver_id, payload.receiver_id, "favor", event_id=event_id)
    await sse.publish("edge_created", {"src": payload.giver_id, "dst": payload.receiver_id, "kind": "favor"})

    await worker.enqueue_event(event_id, payload.giver_id, payload.description)

    return {"event_id": event_id}
