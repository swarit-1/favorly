"""Trellis -- Agent & Graph Service.

Owns the event log, the grocery-favor graph, extraction of grocery-relevant
signal (dietary/mobility/budget/preference), and reciprocity tracking. It is
the only thing that writes to this database. Scoped deliberately: no
introductions/matchmaking.

Algorithm and response contract: docs/AGENT_API_PRD.md
Config lives in the repo-root .env (python-dotenv walks up to find it).
"""

import logging
from contextlib import asynccontextmanager

import asyncpg
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

import db
import canonicalization
import worker
from config import settings
from routes import admin, events, graph, helpers, needs, people, stream, trips

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("trellis")


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info(
        "Starting Trellis agent + graph service (MOCK_LLM=%s, serverless=%s)",
        settings.MOCK_LLM, settings.SERVERLESS,
    )
    await db.init_pool()

    # Applying the schema is a startup job, not a per-request one. On a
    # persistent host it runs once; on serverless it would run on every cold
    # start, so it is skipped and left to a deploy step.
    if not settings.SERVERLESS:
        await db.apply_schema()

    async with db.pool().acquire() as conn:
        await canonicalization.seed_vocabulary(conn)

    # No background tasks on serverless -- worker.enqueue_event extracts inline
    # instead. See worker.py.
    if not settings.SERVERLESS:
        worker.start_workers()

    logger.info("Trellis ready.")

    yield

    if not settings.SERVERLESS:
        worker.stop_workers()
    await db.close_pool()
    logger.info("Trellis shut down.")


app = FastAPI(
    title="Trellis Agent & Graph Service",
    description="Event log, grocery-favor graph, extraction, reciprocity tracking.",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(events.router)
app.include_router(trips.router)
app.include_router(needs.router)
app.include_router(helpers.router)
app.include_router(people.router)
app.include_router(graph.router)
app.include_router(admin.router)
app.include_router(stream.router)


@app.exception_handler(asyncpg.exceptions.DataError)
async def malformed_parameter(request: Request, exc: asyncpg.exceptions.DataError):
    """A malformed id (typically a truncated UUID from an unset shell variable)
    is the caller's mistake, not a server fault -- say so instead of 500ing."""
    return JSONResponse(status_code=422, content={"detail": f"invalid parameter: {exc}"})


@app.get("/health")
async def health():
    try:
        async with db.pool().acquire() as conn:
            await conn.fetchval("SELECT 1")
        return {"status": "ok", "mock_llm": settings.MOCK_LLM}
    except Exception as e:
        return {"status": "error", "detail": str(e)}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app:app", host="0.0.0.0", port=settings.PORT, reload=settings.ENVIRONMENT == "development")
