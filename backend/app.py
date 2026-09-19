"""Favorly FastAPI application."""

import os
import json
from contextlib import asynccontextmanager
from fastapi import FastAPI, WebSocket, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.openapi.utils import get_openapi

# Internal imports
from db.mongo_client import get_mongo_client, close_mongo_client, init_collections, get_db
from auth.firebase_auth import init_firebase, get_current_user
from realtime.websocket_manager import manager
from shared.contracts import models

# Import routes (will be created next)
# from routes import trips, requests as request_routes, parses, merged_list, substitutions, receipts, handoff, ledger


# ============================================================================
# LIFESPAN EVENTS
# ============================================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Handle startup and shutdown events."""
    # Startup
    print("\n🚀 Starting Favorly backend...")
    try:
        init_firebase()
        await get_mongo_client()
        await init_collections()
        print("\n✅ All systems ready!")
    except Exception as e:
        print(f"\n❌ Startup failed: {e}")
        raise

    yield

    # Shutdown
    print("\n🛑 Shutting down...")
    await close_mongo_client()
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
    db = await get_db()
    try:
        await db.command("ping")
        return {"status": "ok", "mongodb": "connected"}
    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={"status": "error", "mongodb": str(e)},
        )


# ============================================================================
# WEBSOCKET REALTIME
# ============================================================================

@app.websocket("/ws/trips/{trip_id}")
async def websocket_trip_updates(websocket: WebSocket, trip_id: str):
    """
    WebSocket endpoint for real-time trip updates.

    Subscribes to changes in: trips, items, substitution_prompts, settlements
    related to this trip_id.
    """
    await manager.connect(websocket, trip_id)
    try:
        # Send welcome message
        await websocket.send_json({
            "type": "connected",
            "trip_id": trip_id,
            "message": "Connected to trip updates",
        })

        # Keep connection alive
        while True:
            # Wait for any message from client (ping, etc.)
            data = await websocket.receive_text()
            if data == "ping":
                await websocket.send_json({"type": "pong"})

    except Exception as e:
        print(f"WebSocket error: {e}")
    finally:
        manager.disconnect(websocket, trip_id)


# ============================================================================
# STUB ROUTES (will be implemented in routes/ modules)
# ============================================================================

@app.post("/trips", tags=["trips"])
async def create_trip(trip: dict, current_user: dict = Depends(get_current_user)):
    """Create a new trip."""
    return {"status": "stub", "message": "POST /trips not implemented yet"}


@app.get("/trips/{trip_id}", tags=["trips"])
async def get_trip(trip_id: str):
    """Get trip details."""
    return {"status": "stub", "message": "GET /trips/{trip_id} not implemented yet"}


@app.patch("/trips/{trip_id}/status", tags=["trips"])
async def update_trip_status(
    trip_id: str,
    status_update: dict,
    current_user: dict = Depends(get_current_user),
):
    """Update trip status (open → shopping → settling → done)."""
    return {"status": "stub", "message": "PATCH /trips/{trip_id}/status not implemented yet"}


@app.post("/trips/{trip_id}/requests", tags=["requests"])
async def create_request(
    trip_id: str,
    request_data: dict,
    current_user: dict = Depends(get_current_user),
):
    """Create a request (attach items to a trip)."""
    return {"status": "stub", "message": "POST /trips/{trip_id}/requests not implemented yet"}


@app.patch("/requests/{request_id}", tags=["requests"])
async def update_request(
    request_id: str,
    update_data: dict,
    current_user: dict = Depends(get_current_user),
):
    """Accept or decline a request."""
    return {"status": "stub", "message": "PATCH /requests/{request_id} not implemented yet"}


@app.post("/parses", tags=["parses"])
async def create_parse(
    parse_data: dict,
    current_user: dict = Depends(get_current_user),
):
    """Create a parse (text, photo, or voice list)."""
    return {"status": "stub", "message": "POST /parses not implemented yet"}


@app.patch("/parses/{parse_id}/confirm", tags=["parses"])
async def confirm_parse(
    parse_id: str,
    confirmation_data: dict,
    current_user: dict = Depends(get_current_user),
):
    """Confirm parsed items before submitting."""
    return {"status": "stub", "message": "PATCH /parses/{parse_id}/confirm not implemented yet"}


@app.get("/trips/{trip_id}/merged-list", tags=["merged-list"])
async def get_merged_list(trip_id: str):
    """Get merged, aisle-ordered list for shopper."""
    return {"status": "stub", "message": "GET /trips/{trip_id}/merged-list not implemented yet"}


@app.post("/trips/{trip_id}/substitutions", tags=["substitutions"])
async def create_substitution_prompt(
    trip_id: str,
    substitution_data: dict,
    current_user: dict = Depends(get_current_user),
):
    """Create a substitution prompt (shopper found shelf photo)."""
    return {"status": "stub", "message": "POST /trips/{trip_id}/substitutions not implemented yet"}


@app.patch("/substitutions/{substitution_id}", tags=["substitutions"])
async def respond_to_substitution(
    substitution_id: str,
    response_data: dict,
    current_user: dict = Depends(get_current_user),
):
    """Requester chooses a substitute or skips."""
    return {"status": "stub", "message": "PATCH /substitutions/{substitution_id} not implemented yet"}


@app.post("/trips/{trip_id}/receipts", tags=["receipts"])
async def create_receipt(
    trip_id: str,
    receipt_data: dict,
    current_user: dict = Depends(get_current_user),
):
    """Upload and parse receipt."""
    return {"status": "stub", "message": "POST /trips/{trip_id}/receipts not implemented yet"}


@app.patch("/receipts/{receipt_id}/assignments", tags=["receipts"])
async def update_receipt_assignments(
    receipt_id: str,
    assignments_data: dict,
    current_user: dict = Depends(get_current_user),
):
    """Confirm receipt line assignments."""
    return {"status": "stub", "message": "PATCH /receipts/{receipt_id}/assignments not implemented yet"}


@app.post("/trips/{trip_id}/handoff", tags=["handoff"])
async def handoff_trip(
    trip_id: str,
    handoff_data: dict | None = None,
    current_user: dict = Depends(get_current_user),
):
    """Confirm delivery, mark trip done, update ledger."""
    return {"status": "stub", "message": "POST /trips/{trip_id}/handoff not implemented yet"}


@app.get("/circles/{circle_id}/ledger", tags=["ledger"])
async def get_circle_ledger(circle_id: str):
    """Get circle member ledger."""
    return {"status": "stub", "message": "GET /circles/{circle_id}/ledger not implemented yet"}


# ============================================================================
# CUSTOM OPENAPI SCHEMA (for easy TypeScript generation)
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
