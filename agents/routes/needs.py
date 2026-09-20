"""Posting something you need help with, and getting recommendations back."""

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query

import edges as edges_mod
import recommendations
import sse
import worker
from deps import get_conn
from models import FavorReviewIn, NeedClaimIn, NeedIn, RecommendationsOut

router = APIRouter()


@router.post("/needs", status_code=201)
async def create_need(payload: NeedIn, conn: asyncpg.Connection = Depends(get_conn)):
    """Post something you need help with."""
    person = await conn.fetchrow("SELECT id FROM app_people WHERE id = $1", payload.person_id)
    if not person:
        raise HTTPException(404, "person not found")

    # The need text is also an event, so extraction can mine grocery-relevant
    # signal from it the same way it does any other message.
    event_row = await conn.fetchrow(
        "INSERT INTO events (person_id, kind, body) VALUES ($1, 'message', $2) RETURNING id",
        payload.person_id, payload.body,
    )
    event_id = str(event_row["id"])

    row = await conn.fetchrow(
        "INSERT INTO needs (person_id, body, event_id) VALUES ($1, $2, $3) "
        "RETURNING id, status, created_at",
        payload.person_id, payload.body, event_id,
    )
    await worker.enqueue_event(event_id, payload.person_id, payload.body)
    await sse.publish("need_posted", {"need_id": str(row["id"]), "person_id": payload.person_id})

    return {"id": str(row["id"]), "status": row["status"], "created_at": row["created_at"]}


@router.get("/needs")
async def list_needs(
    status: str = Query(default="open"),
    conn: asyncpg.Connection = Depends(get_conn),
):
    rows = await conn.fetch(
        "SELECT n.id, n.person_id, n.body, n.status, n.claimed_by, n.created_at, p.display_name "
        "FROM needs n JOIN app_people p ON p.id = n.person_id "
        "WHERE n.status = $1 ORDER BY n.created_at DESC",
        status,
    )
    return {
        "needs": [
            {
                "id": str(r["id"]), "body": r["body"], "status": r["status"],
                "posted_by": {"id": str(r["person_id"]), "display_name": r["display_name"]},
                "claimed_by": str(r["claimed_by"]) if r["claimed_by"] else None,
                "created_at": r["created_at"],
            }
            for r in rows
        ]
    }


@router.get("/people/{person_id}/recommendations", response_model=RecommendationsOut)
async def get_recommendations(
    person_id: str,
    limit: int = Query(default=10, ge=1, le=50),
    conn: asyncpg.Connection = Depends(get_conn),
):
    """Favors this person should consider doing. The graph retrieves and scores
    candidates; the model decides which to surface and how to frame them.
    `decided_by` says which path produced the result."""
    person = await conn.fetchrow("SELECT id FROM app_people WHERE id = $1", person_id)
    if not person:
        raise HTTPException(404, "person not found")
    return await recommendations.suggest_favors(conn, person_id, limit)


@router.post("/needs/{need_id}/claim")
async def claim_need(need_id: str, payload: NeedClaimIn, conn: asyncpg.Connection = Depends(get_conn)):
    """One-sided: whoever decides to help claims it."""
    need = await conn.fetchrow("SELECT * FROM needs WHERE id = $1", need_id)
    if not need:
        raise HTTPException(404, "need not found")
    if need["status"] != "open":
        raise HTTPException(409, f"need is already {need['status']}")
    if str(need["person_id"]) == payload.person_id:
        raise HTTPException(422, "you can't claim your own need")

    await conn.execute(
        "UPDATE needs SET status = 'claimed', claimed_by = $1 WHERE id = $2",
        payload.person_id, need_id,
    )
    await sse.publish("need_claimed", {"need_id": need_id, "claimed_by": payload.person_id})
    return {"id": need_id, "status": "claimed", "claimed_by": payload.person_id}


@router.post("/needs/{need_id}/fulfill")
async def fulfill_need(need_id: str, conn: asyncpg.Connection = Depends(get_conn)):
    """Marks it done and writes the favor edge -- which is what makes the next
    recommendation to the person who was helped say "they helped you before"."""
    need = await conn.fetchrow("SELECT * FROM needs WHERE id = $1", need_id)
    if not need:
        raise HTTPException(404, "need not found")
    if need["status"] != "claimed":
        raise HTTPException(409, f"need is {need['status']}, expected claimed")

    helper_id, needer_id = str(need["claimed_by"]), str(need["person_id"])
    event_row = await conn.fetchrow(
        "INSERT INTO events (person_id, kind, body) VALUES ($1, 'favor_logged', $2) RETURNING id",
        helper_id, f"helped with: {need['body']}",
    )
    await edges_mod.write_edge(conn, helper_id, needer_id, "favor", event_id=str(event_row["id"]))
    await conn.execute(
        "UPDATE needs SET status = 'fulfilled', resolved_at = now() WHERE id = $1", need_id,
    )
    await sse.publish("edge_created", {"src": helper_id, "dst": needer_id, "kind": "favor"})

    return {"id": need_id, "status": "fulfilled", "favor_logged": True}


@router.post("/needs/{need_id}/review")
async def review_need(
    need_id: str,
    payload: FavorReviewIn,
    conn: asyncpg.Connection = Depends(get_conn),
):
    """Rate a finished favor, optionally with a comment.

    Re-submitting replaces your own review rather than stacking another row.
    The comment is also written to the event log, so extraction can mine it
    for grocery-relevant signal the way it does any other message -- a review
    saying "she always remembers I'm gluten free" is a claim waiting to happen.
    """
    need = await conn.fetchrow("SELECT * FROM needs WHERE id = $1", need_id)
    if not need:
        raise HTTPException(404, "need not found")
    if need["status"] != "fulfilled":
        raise HTTPException(409, f"need is {need['status']}, expected fulfilled")

    reviewer = await conn.fetchrow(
        "SELECT id FROM app_people WHERE id = $1", payload.reviewer_id)
    if not reviewer:
        raise HTTPException(404, "reviewer not found")

    comment = (payload.comment or "").strip() or None

    row = await conn.fetchrow(
        "INSERT INTO favor_reviews (need_id, reviewer_id, rating, comment) "
        "VALUES ($1, $2, $3, $4) "
        "ON CONFLICT (need_id, reviewer_id) DO UPDATE "
        "  SET rating = EXCLUDED.rating, comment = EXCLUDED.comment, created_at = now() "
        "RETURNING id, rating, comment, created_at",
        need_id, payload.reviewer_id, payload.rating, comment,
    )

    if comment:
        event_row = await conn.fetchrow(
            "INSERT INTO events (person_id, kind, body) VALUES ($1, 'message', $2) "
            "RETURNING id",
            payload.reviewer_id, comment,
        )
        await worker.enqueue_event(str(event_row["id"]), payload.reviewer_id, comment)

    await sse.publish("favor_reviewed", {"need_id": need_id, "rating": payload.rating})

    return {
        "id": str(row["id"]),
        "need_id": need_id,
        "rating": row["rating"],
        "comment": row["comment"],
        "created_at": row["created_at"],
    }


@router.get("/needs/{need_id}/review")
async def get_review(
    need_id: str,
    reviewer_id: str = Query(...),
    conn: asyncpg.Connection = Depends(get_conn),
):
    """Your own review of this favor, if you left one."""
    row = await conn.fetchrow(
        "SELECT id, rating, comment, created_at FROM favor_reviews "
        "WHERE need_id = $1 AND reviewer_id = $2",
        need_id, reviewer_id,
    )
    if not row:
        raise HTTPException(404, "no review yet")
    return {
        "id": str(row["id"]),
        "need_id": need_id,
        "rating": row["rating"],
        "comment": row["comment"],
        "created_at": row["created_at"],
    }
