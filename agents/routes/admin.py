"""Demo control. The difference between a smooth demo and a frozen one."""

import asyncpg
from fastapi import APIRouter, Depends, HTTPException

import canonicalization
import extraction
import graph_metrics
import seed_data
from deps import get_conn
from models import SeedIn, TickIn

router = APIRouter(prefix="/admin")


@router.post("/seed")
async def admin_seed(payload: SeedIn, conn: asyncpg.Connection = Depends(get_conn)):
    result = await seed_data.seed(conn, payload.scenario)
    return result


@router.post("/demo-history")
async def admin_demo_history(conn: asyncpg.Connection = Depends(get_conn)):
    """Build a dense favor web (neighbors, claims, favors, open needs) so the
    reciprocity/mutual/fit signals have something to fire on.

    Additive -- unlike /admin/seed it truncates nothing, so it is safe to run
    against a shared database where other people's rows must survive.
    """
    return await seed_data.build_demo_history(conn)


@router.post("/reset")
async def admin_reset(conn: asyncpg.Connection = Depends(get_conn)):
    await seed_data.reset(conn)
    return {"status": "reset"}


@router.post("/reextract")
async def admin_reextract(conn: asyncpg.Connection = Depends(get_conn)):
    """Drop every claim and replay extraction over the existing event log.

    This is what the append-only event log buys you: switching MOCK_LLM=0 (or
    changing the extraction prompt) makes old claims stale -- mock embeddings
    aren't comparable to real ones -- so rebuild rather than migrate. Events,
    people, and favor edges are untouched.
    """
    events = await conn.fetch(
        "SELECT id, person_id, body FROM events WHERE kind IN ('message', 'favor_logged') "
        "ORDER BY occurred_at ASC"
    )
    claims_written = 0
    try:
        # One transaction: a failure part-way (an API error mid-replay) must
        # not leave the graph wiped. Either the whole rebuild lands or nothing
        # changes.
        async with conn.transaction():
            await conn.execute("TRUNCATE TABLE claims CASCADE")
            await conn.execute("TRUNCATE TABLE canonical_labels CASCADE")
            canonicalization._vocab_cache.clear()
            await canonicalization.seed_vocabulary(conn)

            for e in events:
                ids = await extraction.process_event(
                    conn, str(e["id"]), str(e["person_id"]), e["body"])
                claims_written += len(ids)
    except Exception as exc:
        canonicalization._vocab_cache.clear()  # cache no longer matches the rolled-back DB
        raise HTTPException(
            503, f"replay failed and was rolled back, claims left untouched: {exc}")

    return {"events_replayed": len(events), "claims_written": claims_written}


@router.post("/tick")
async def admin_tick(payload: TickIn, conn: asyncpg.Connection = Depends(get_conn)):
    """Refresh decay-derived topology (give_balance, degree). Useful to call
    after backdating edges in a demo so the graph reflects current decay."""
    for _ in range(max(payload.steps, 1)):
        await graph_metrics.recompute_all(conn)
    return {"steps": payload.steps}
