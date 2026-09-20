"""Favorly FastAPI application."""

import os
import logging
from contextlib import asynccontextmanager
from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.openapi.utils import get_openapi
from supabase import create_client, Client

from shared.contracts import models

# Load environment variables from .env
load_dotenv()

# Configure logging to print to stdout
logging.basicConfig(
    level=logging.INFO,
    format='%(levelname)s:     %(message)s',
)


# ============================================================================
# SUPABASE CLIENT
# ============================================================================

def get_supabase_client() -> Client:
    """Get Supabase client (anon key for user-facing operations)."""
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_KEY")
    if not url or not key:
        raise RuntimeError("SUPABASE_URL and SUPABASE_KEY must be set")
    return create_client(url, key)


def get_supabase_admin_client() -> Client:
    """Get Supabase admin client (service role key for backend operations)."""
    url = os.getenv("SUPABASE_URL")
    service_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not service_key:
        # Fall back to anon key if service role not available
        key = os.getenv("SUPABASE_KEY")
        if not url or not key:
            raise RuntimeError("SUPABASE_URL and SUPABASE_KEY must be set")
        return create_client(url, key)
    return create_client(url, service_key)


# ============================================================================
# LIFESPAN EVENTS
# ============================================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Handle startup and shutdown events."""
    # Startup
    print("\n🚀 Starting Favorly backend...")
    try:
        supabase = get_supabase_client()
        # Test connection
        response = supabase.table("users").select("*").limit(1).execute()
        print("✅ Supabase connected")
        print("\n✅ All systems ready!")

        # Log all registered routes
        print("\n📡 Registered routes:")
        for route in app.routes:
            if hasattr(route, 'path'):
                methods = getattr(route, 'methods', ['N/A'])
                print(f"  - {route.path} [{methods}]")
    except Exception as e:
        print(f"\n❌ Startup failed: {e}")
        raise

    yield

    # Shutdown
    print("\n🛑 Shutting down...")
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
def get_allowed_origins() -> list[str]:
    """Get CORS allowed origins from environment or default based on environment."""
    cors_origins = os.getenv("CORS_ALLOWED_ORIGINS")
    if cors_origins:
        return [origin.strip() for origin in cors_origins.split(",")]
    # Default: allow all origins in development, none in production
    env = os.getenv("ENVIRONMENT", "development")
    if env == "development":
        return ["*"]
    return []


app.add_middleware(
    CORSMiddleware,
    allow_origins=get_allowed_origins(),
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
# ROUTES
# ============================================================================

from routes import auth, trips, requests, users, merged_list, vision, experiences, messages, notifications, savings, storm, insurance, unlocks
from routes.linq_webhook import router as linq_router

print("\n📡 Registering routers...")
app.include_router(auth.router)
print("✅ Auth router registered")
app.include_router(trips.router)
print("✅ Trips router registered")
app.include_router(requests.router)
print("✅ Requests router registered")
app.include_router(users.router)
print("✅ Users router registered")
app.include_router(merged_list.router)
print("✅ Merged list router registered")
app.include_router(vision.router)
print("✅ Vision router registered")
app.include_router(experiences.router)
print("✅ Experiences router registered")
app.include_router(messages.router)
print("✅ Messages router registered")
app.include_router(notifications.router)
print("✅ Notifications router registered")
app.include_router(savings.router)
print("✅ Savings router registered")
app.include_router(storm.router)
print("✅ Storm mode router registered")
app.include_router(insurance.router)
print("✅ Insurance router registered")
app.include_router(unlocks.router)
print("✅ Unlocks router registered")
app.include_router(linq_router)  # Linq agent: inbound texts -> matching -> reply
print("✅ Linq router registered\n")

@app.post("/trips", tags=["trips"])
async def create_trip(trip: dict):
    """Create a new trip."""
    return {"status": "stub", "message": "POST /trips not implemented yet"}


@app.get("/trips/{trip_id}", tags=["trips"])
async def get_trip(trip_id: str):
    """Get trip details."""
    return {"status": "stub", "message": "GET /trips/{trip_id} not implemented yet"}


@app.patch("/trips/{trip_id}/status", tags=["trips"])
async def update_trip_status(trip_id: str, status_update: dict):
    """Update trip status (open → shopping → settling → done)."""
    return {"status": "stub", "message": "PATCH /trips/{trip_id}/status not implemented yet"}


@app.post("/trips/{trip_id}/requests", tags=["requests"])
async def create_request(trip_id: str, request_data: dict):
    """Create a request (attach items to a trip)."""
    return {"status": "stub", "message": "POST /trips/{trip_id}/requests not implemented yet"}


@app.patch("/requests/{request_id}", tags=["requests"])
async def update_request(request_id: str, update_data: dict):
    """Accept or decline a request."""
    return {"status": "stub", "message": "PATCH /requests/{request_id} not implemented yet"}


@app.post("/parses", tags=["parses"])
async def create_parse(parse_data: dict):
    """Create a parse (text, photo, or voice list)."""
    return {"status": "stub", "message": "POST /parses not implemented yet"}


@app.patch("/parses/{parse_id}/confirm", tags=["parses"])
async def confirm_parse(parse_id: str, confirmation_data: dict):
    """Confirm parsed items before submitting."""
    return {"status": "stub", "message": "PATCH /parses/{parse_id}/confirm not implemented yet"}


@app.get("/trips/{trip_id}/merged-list", tags=["merged-list"])
async def get_merged_list(trip_id: str):
    """Get merged, aisle-ordered list for shopper."""
    return {"status": "stub", "message": "GET /trips/{trip_id}/merged-list not implemented yet"}


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
async def handoff_trip(trip_id: str, handoff_data: dict | None = None):
    """Confirm delivery, mark trip done, update ledger."""
    return {"status": "stub", "message": "POST /trips/{trip_id}/handoff not implemented yet"}


@app.get("/circles/{circle_id}/ledger", tags=["ledger"])
async def get_circle_ledger(circle_id: str):
    """Get circle member ledger."""
    return {"status": "stub", "message": "GET /circles/{circle_id}/ledger not implemented yet"}


# ============================================================================
# CUSTOM OPENAPI SCHEMA (for TypeScript generation)
# ============================================================================

def get_openapi_servers() -> list[dict]:
    """Get OpenAPI server URLs from environment."""
    servers = []

    # Add development server
    dev_server = os.getenv("DEV_SERVER_URL", "http://localhost:8000")
    if dev_server:
        servers.append({"url": dev_server, "description": "Development"})

    # Add production server if configured
    prod_server = os.getenv("PROD_SERVER_URL")
    if prod_server:
        servers.append({"url": prod_server, "description": "Production"})

    # If no servers configured, default to localhost
    if not servers:
        servers.append({"url": "http://localhost:8000", "description": "Development"})

    return servers


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

    # Add server URLs from environment
    openapi_schema["servers"] = get_openapi_servers()

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
