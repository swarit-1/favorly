"""Read endpoints. No give_balance -- not an oversight.

There is no POST /people any more. Identity is Supabase Auth: a person exists
because they have an auth account and a `users` profile row, both created at
signup by the errand-coordination backend. This service reads them through the
`app_people` view and never mints an identity of its own.
"""

import asyncpg
from fastapi import APIRouter, Depends, HTTPException

from deps import get_conn

router = APIRouter()


@router.get("/people/{person_id}/profile")
async def get_profile(person_id: str, conn: asyncpg.Connection = Depends(get_conn)):
    person = await conn.fetchrow("SELECT id, display_name FROM app_people WHERE id = $1", person_id)
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
