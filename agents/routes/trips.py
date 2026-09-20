"""Trips offered by shoppers (via the SMS agent). Feeds the `trip` signal in
recommendations -- "you're already going to Trader Joe's at 5pm"."""

import asyncpg
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, AwareDatetime
from datetime import datetime

from deps import get_conn

router = APIRouter()


class TripIn(BaseModel):
    shopper_id: str
    store: str
    depart_at: datetime  # naive treated as UTC


@router.post("/trips", status_code=201)
async def create_trip(payload: TripIn, conn: asyncpg.Connection = Depends(get_conn)):
    person = await conn.fetchrow("SELECT id FROM app_people WHERE id = $1", payload.shopper_id)
    if not person:
        raise HTTPException(404, "person not found")
    # One live trip per shopper keeps the signal honest.
    await conn.execute(
        "UPDATE trips SET status = 'done' WHERE shopper_id = $1 AND status IN ('open','shopping')",
        payload.shopper_id,
    )
    row = await conn.fetchrow(
        "INSERT INTO trips (shopper_id, store, depart_at) VALUES ($1, $2, $3) RETURNING id",
        payload.shopper_id, payload.store, payload.depart_at,
    )
    return {"id": str(row["id"])}
