"""Read endpoints. No give_balance -- not an oversight."""

import uuid

import asyncpg
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from deps import get_conn

router = APIRouter()


class PersonIn(BaseModel):
    display_name: str
    phone: str | None = None
    # Pass this equal to the backend's users.id when the two services share a
    # Supabase project, so every person_id/giver_id/receiver_id the backend
    # already has resolves here directly (see agents/schema.sql). Omit it for
    # a standalone person (e.g. demo/dev use outside the merged setup).
    id: str | None = None


@router.post("/people", status_code=201)
async def create_person(payload: PersonIn, conn: asyncpg.Connection = Depends(get_conn)):
    """Not part of the frozen §11 surface, but people have to come from somewhere --
    normally the backend (on user signup) or the texting service (on first
    inbound SMS) registers them here."""
    person_id = payload.id or str(uuid.uuid4())
    row = await conn.fetchrow(
        "INSERT INTO people (id, display_name, phone) VALUES ($1, $2, $3) "
        "ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name "
        "RETURNING id",
        person_id, payload.display_name, payload.phone,
    )
    return {"id": str(row["id"])}


@router.get("/people/{person_id}/profile")
async def get_profile(person_id: str, conn: asyncpg.Connection = Depends(get_conn)):
    person = await conn.fetchrow("SELECT id, display_name FROM people WHERE id = $1", person_id)
    if not person:
        raise HTTPException(404, "person not found")

    claims = await conn.fetch(
        "SELECT kind, raw_label, confidence FROM claims "
        "WHERE person_id = $1 AND superseded_by IS NULL ORDER BY confidence DESC",
        person_id,
    )
    connections = await conn.fetchrow(
        "SELECT COUNT(*) AS n FROM ("
        "  SELECT dst_id AS id FROM edges WHERE src_id = $1"
        "  UNION SELECT src_id AS id FROM edges WHERE dst_id = $1"
        ") AS neighbors",
        person_id,
    )

    return {
        "display_name": person["display_name"],
        "claims": [{"kind": c["kind"], "raw_label": c["raw_label"], "confidence": c["confidence"]} for c in claims],
        "connection_count": connections["n"],
    }
