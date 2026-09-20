"""Favorly FastAPI application."""

import json
import os
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from decimal import Decimal

import asyncpg
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.openapi.utils import get_openapi
from supabase import create_client, Client

from shared.contracts import models
from services import trellis_client
import db as db_migrate
from deps import get_conn

# Load environment variables from .env
load_dotenv()


# ============================================================================
# SUPABASE CLIENT
# ============================================================================

def get_supabase_client() -> Client:
    """Get Supabase client."""
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_KEY")
    if not url or not key:
        raise RuntimeError("SUPABASE_URL and SUPABASE_KEY must be set")
    return create_client(url, key)


# ============================================================================
# LIFESPAN EVENTS
# ============================================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Handle startup and shutdown events."""
    # Startup
    print("\n🚀 Starting Favorly backend...")
    try:
        applied = await db_migrate.apply_schema()
        print("✅ Schema applied (schema.sql)" if applied else "ℹ️  DATABASE_URL not set, skipping schema apply")

        supabase = get_supabase_client()
        # Test connection
        response = supabase.table("users").select("*").limit(1).execute()
        print("✅ Supabase connected")
        print("\n✅ All systems ready!")
    except Exception as e:
        print(f"\n❌ Startup failed: {e}")
        raise

    yield

    # Shutdown
    print("\n🛑 Shutting down...")
    await db_migrate.close_pool()
    print("✅ Shutdown complete")


# ============================================================================
# FASTAPI APP
# ============================================================================

app = FastAPI(
    title="Favorly API",
    description="Neighbor-to-neighbor errand coordination",
    version="0.1.0",
    lifespan=lifespan,
)


# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # For demo; restrict in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ============================================================================
# HEALTH CHECK
# ============================================================================

@app.get("/health", tags=["health"])
async def health_check():
    """Health check endpoint."""
    try:
        supabase = get_supabase_client()
        supabase.table("users").select("*").limit(1).execute()
        return {"status": "ok", "supabase": "connected"}
    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={"status": "error", "supabase": str(e)},
        )


# ============================================================================
# TRIPS
# ============================================================================

def _row_to_trip(row: asyncpg.Record) -> dict:
    caps = row["caps"]
    if isinstance(caps, str):
        caps = json.loads(caps)
    return {
        "id": str(row["id"]),
        "shopper_id": str(row["shopper_id"]),
        "circle_id": str(row["circle_id"]),
        "store": row["store"],
        "depart_at": row["depart_at"],
        "caps": caps,
        "status": row["status"],
        "created_at": row["created_at"],
    }


@app.post("/trips", tags=["trips"], status_code=201)
async def create_trip(trip: dict, conn: asyncpg.Connection = Depends(get_conn)):
    """Create a new trip."""
    shopper_id = trip.get("shopper_id")
    circle_id = trip.get("circle_id")
    store = trip.get("store")
    depart_at_raw = trip.get("depart_at")
    if not (shopper_id and circle_id and store and depart_at_raw):
        raise HTTPException(422, "shopper_id, circle_id, store, and depart_at are required")

    try:
        # asyncpg needs a real (naive) datetime for this project's `timestamp
        # without time zone` columns -- JSON only has strings, and a tz-aware
        # datetime is rejected against a tz-naive column.
        depart_at = datetime.fromisoformat(depart_at_raw.replace("Z", "+00:00")).replace(tzinfo=None)
    except ValueError:
        raise HTTPException(422, f"depart_at is not a valid ISO 8601 timestamp: {depart_at_raw}")

    caps = models.TripCaps(**trip.get("caps", {})).model_dump(mode="json")
    row = await conn.fetchrow(
        "INSERT INTO trips (shopper_id, circle_id, store, depart_at, caps) "
        "VALUES ($1, $2, $3, $4, $5::jsonb) RETURNING *",
        shopper_id, circle_id, store, depart_at, json.dumps(caps),
    )
    return _row_to_trip(row)


@app.get("/trips/{trip_id}", tags=["trips"])
async def get_trip(trip_id: str, conn: asyncpg.Connection = Depends(get_conn)):
    """Get trip details."""
    row = await conn.fetchrow("SELECT * FROM trips WHERE id = $1", trip_id)
    if not row:
        raise HTTPException(404, "trip not found")
    return _row_to_trip(row)


@app.get("/circles/{circle_id}/trips", tags=["trips"])
async def list_circle_trips(circle_id: str, conn: asyncpg.Connection = Depends(get_conn)):
    """List trips for a circle, most recent first -- what the Trips tab renders."""
    rows = await conn.fetch(
        "SELECT * FROM trips WHERE circle_id = $1 ORDER BY created_at DESC", circle_id,
    )
    return {"trips": [_row_to_trip(r) for r in rows]}


@app.patch("/trips/{trip_id}/status", tags=["trips"])
async def update_trip_status(trip_id: str, status_update: dict, conn: asyncpg.Connection = Depends(get_conn)):
    """Update trip status (open → shopping → settling → done)."""
    new_status = status_update.get("status")
    if new_status not in {s.value for s in models.TripStatus}:
        raise HTTPException(422, f"invalid status: {new_status}")
    row = await conn.fetchrow(
        "UPDATE trips SET status = $1 WHERE id = $2 RETURNING *", new_status, trip_id,
    )
    if not row:
        raise HTTPException(404, "trip not found")
    return _row_to_trip(row)


# ============================================================================
# REQUESTS + ITEMS
# ============================================================================

@app.post("/trips/{trip_id}/requests", tags=["requests"], status_code=201)
async def create_request(trip_id: str, request_data: dict, conn: asyncpg.Connection = Depends(get_conn)):
    """Create a request (attach items to a trip)."""
    requester_id = request_data.get("requester_id")
    items = request_data.get("items", [])
    if not requester_id or not items:
        raise HTTPException(422, "requester_id and at least one item are required")

    trip = await conn.fetchrow("SELECT id FROM trips WHERE id = $1", trip_id)
    if not trip:
        raise HTTPException(404, "trip not found")

    request_row = await conn.fetchrow(
        "INSERT INTO requests (trip_id, requester_id) VALUES ($1, $2) RETURNING id",
        trip_id, requester_id,
    )
    request_id = request_row["id"]

    item_ids = []
    for item in items:
        item_row = await conn.fetchrow(
            "INSERT INTO items (request_id, trip_id, name, qty, unit, note, max_price, section) "
            "VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id",
            request_id, trip_id, item["name"], item.get("qty", 1), item.get("unit"),
            item.get("note"), item.get("max_price"), item.get("section", "other"),
        )
        item_ids.append(str(item_row["id"]))

    return {"request_id": str(request_id), "item_ids": item_ids}


@app.patch("/requests/{request_id}", tags=["requests"])
async def update_request(request_id: str, update_data: dict, conn: asyncpg.Connection = Depends(get_conn)):
    """Accept or decline a request."""
    new_status = update_data.get("status")
    if new_status not in {s.value for s in models.RequestStatus}:
        raise HTTPException(422, f"invalid status: {new_status}")
    row = await conn.fetchrow(
        "UPDATE requests SET status = $1 WHERE id = $2 RETURNING *", new_status, request_id,
    )
    if not row:
        raise HTTPException(404, "request not found")
    return {"id": str(row["id"]), "trip_id": str(row["trip_id"]),
            "requester_id": str(row["requester_id"]), "status": row["status"]}


@app.post("/parses", tags=["parses"])
async def create_parse(parse_data: dict):
    """Create a parse (text, photo, or voice list)."""
    # Forward raw text to Trellis (see services/trellis_client.py). A request
    # like "need a drill this weekend" is plumbing here and judgment there --
    # this backend never interprets it, it just logs the event (spec §1).
    user_id = parse_data.get("user_id")
    source = parse_data.get("source")
    raw_ref = parse_data.get("raw_ref")
    if user_id and source == "text" and raw_ref:
        await trellis_client.log_event(user_id, raw_ref)

    return {"status": "stub", "message": "POST /parses not implemented yet"}


@app.patch("/parses/{parse_id}/confirm", tags=["parses"])
async def confirm_parse(parse_id: str, confirmation_data: dict):
    """Confirm parsed items before submitting."""
    return {"status": "stub", "message": "PATCH /parses/{parse_id}/confirm not implemented yet"}


@app.get("/trips/{trip_id}/merged-list", tags=["merged-list"])
async def get_merged_list(trip_id: str, conn: asyncpg.Connection = Depends(get_conn)):
    """Get merged, aisle-ordered list for shopper: accepted items only, grouped
    by section, each tagged with requester + running total vs their cap."""
    trip = await conn.fetchrow("SELECT caps FROM trips WHERE id = $1", trip_id)
    if not trip:
        raise HTTPException(404, "trip not found")
    caps = json.loads(trip["caps"]) if isinstance(trip["caps"], str) else trip["caps"]
    cap_per_person = Decimal(str(caps.get("max_dollars_per_person", 0)))

    rows = await conn.fetch(
        "SELECT i.id, i.name, i.qty, i.unit, i.note, i.max_price, i.section, i.status, "
        "       r.requester_id, u.name AS requester_name "
        "FROM items i "
        "JOIN requests r ON r.id = i.request_id "
        "JOIN users u ON u.id = r.requester_id "
        "WHERE i.trip_id = $1 AND r.status = 'accepted' "
        "ORDER BY i.section, i.created_at",
        trip_id,
    )

    sections: dict[str, list[dict]] = {}
    running_totals: dict[str, Decimal] = {}
    for r in rows:
        requester_id = str(r["requester_id"])
        running_totals.setdefault(requester_id, Decimal("0"))
        if r["max_price"] is not None:
            running_totals[requester_id] += r["max_price"]
        sections.setdefault(r["section"], []).append({
            "item": {
                "id": str(r["id"]), "name": r["name"], "qty": r["qty"], "unit": r["unit"],
                "note": r["note"], "max_price": r["max_price"], "status": r["status"],
            },
            "requester_id": requester_id,
            "requester_name": r["requester_name"],
            "running_total": running_totals[requester_id],
            "cap": cap_per_person,
            "over_cap": running_totals[requester_id] > cap_per_person,
        })

    return {
        "trip_id": trip_id,
        "sections": sections,
        "totals_by_requester": {k: v for k, v in running_totals.items()},
    }


@app.post("/trips/{trip_id}/substitutions", tags=["substitutions"])
async def create_substitution_prompt(trip_id: str, substitution_data: dict):
    """Create a substitution prompt (shopper found shelf photo)."""
    return {"status": "stub", "message": "POST /trips/{trip_id}/substitutions not implemented yet"}


@app.patch("/substitutions/{substitution_id}", tags=["substitutions"])
async def respond_to_substitution(substitution_id: str, response_data: dict):
    """Requester chooses a substitute or skips."""
    return {"status": "stub", "message": "PATCH /substitutions/{substitution_id} not implemented yet"}


@app.post("/trips/{trip_id}/receipts", tags=["receipts"])
async def create_receipt(trip_id: str, receipt_data: dict):
    """Upload and parse receipt."""
    return {"status": "stub", "message": "POST /trips/{trip_id}/receipts not implemented yet"}


@app.patch("/receipts/{receipt_id}/assignments", tags=["receipts"])
async def update_receipt_assignments(receipt_id: str, assignments_data: dict):
    """Confirm receipt line assignments."""
    return {"status": "stub", "message": "PATCH /receipts/{receipt_id}/assignments not implemented yet"}


@app.post("/trips/{trip_id}/handoff", tags=["handoff"])
async def handoff_trip(trip_id: str, handoff_data: dict | None = None,
                         conn: asyncpg.Connection = Depends(get_conn)):
    """Confirm delivery, mark trip done, update ledger."""
    trip = await conn.fetchrow("SELECT id, shopper_id, store, circle_id FROM trips WHERE id = $1", trip_id)
    if not trip:
        raise HTTPException(404, "trip not found")

    shopper_id = str(trip["shopper_id"])
    requester_rows = await conn.fetch(
        "SELECT DISTINCT requester_id FROM requests WHERE trip_id = $1 AND status = 'accepted'",
        trip_id,
    )
    requester_ids = [str(r["requester_id"]) for r in requester_rows]

    # A completed handoff is a real favor -- the strongest edge signal the
    # Trellis graph has (spec §6). One favor per requester actually helped.
    for requester_id in requester_ids:
        await trellis_client.log_favor(shopper_id, requester_id, f"{trip['store']} run")

    await conn.execute("UPDATE trips SET status = 'done' WHERE id = $1", trip_id)

    await conn.execute(
        "INSERT INTO ledger_events (circle_id, user_id, type, value, trip_id) VALUES ($1, $2, 'trip_run', 1, $3)",
        trip["circle_id"], shopper_id, trip_id,
    )
    for requester_id in requester_ids:
        await conn.execute(
            "INSERT INTO ledger_events (circle_id, user_id, type, value, trip_id) "
            "VALUES ($1, $2, 'favor_received', 1, $3)",
            trip["circle_id"], requester_id, trip_id,
        )

    return {"status": "done", "favors_logged": len(requester_ids)}


@app.get("/circles/{circle_id}/ledger", tags=["ledger"])
async def get_circle_ledger(circle_id: str, conn: asyncpg.Connection = Depends(get_conn)):
    """Get circle member ledger. Counts only for now -- dollars_carried needs
    settlements (receipt splitting), which isn't implemented yet."""
    rows = await conn.fetch(
        "SELECT u.id, u.name, "
        "  COALESCE(SUM(CASE WHEN le.type = 'trip_run' THEN 1 ELSE 0 END), 0) AS trips_run, "
        "  COALESCE(SUM(CASE WHEN le.type = 'favor_received' THEN 1 ELSE 0 END), 0) AS favors_received "
        "FROM users u "
        "LEFT JOIN ledger_events le ON le.user_id = u.id "
        "WHERE u.circle_id = $1 "
        "GROUP BY u.id, u.name "
        "ORDER BY u.name",
        circle_id,
    )
    return {
        "rows": [
            {"user_id": str(r["id"]), "name": r["name"], "trips_run": r["trips_run"],
             "favors_received": r["favors_received"], "dollars_carried": "0.00"}
            for r in rows
        ],
    }


# ============================================================================
# CUSTOM OPENAPI SCHEMA (for TypeScript generation)
# ============================================================================

def custom_openapi():
    """Generate OpenAPI schema."""
    if app.openapi_schema:
        return app.openapi_schema

    openapi_schema = get_openapi(
        title="Favorly API",
        version="0.1.0",
        description="Neighbor-to-neighbor errand coordination",
        routes=app.routes,
    )

    # Add server URLs
    openapi_schema["servers"] = [
        {"url": "http://localhost:8000", "description": "Development"},
        {"url": "https://favorly-api.fly.dev", "description": "Production"},
    ]

    app.openapi_schema = openapi_schema
    return app.openapi_schema


app.openapi = custom_openapi


# ============================================================================
# MAIN
# ============================================================================

if __name__ == "__main__":
    import uvicorn

    port = int(os.getenv("PORT", 8000))
    uvicorn.run(
        "app:app",
        host="0.0.0.0",
        port=port,
        reload=os.getenv("ENVIRONMENT") == "development",
    )
