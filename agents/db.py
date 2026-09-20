"""asyncpg connection pool + small helpers."""

from pathlib import Path
from typing import Optional
import asyncpg

from config import settings

_pool: Optional[asyncpg.Pool] = None


async def init_pool() -> asyncpg.Pool:
    global _pool
    if _pool is None:
        # One connection per serverless instance: they multiply, and Supabase's
        # pooler has a finite budget.
        max_size = 2 if settings.SERVERLESS else 10
        _pool = await asyncpg.create_pool(
            settings.DATABASE_URL, min_size=1, max_size=max_size)
    return _pool


async def close_pool():
    global _pool
    if _pool is not None:
        await _pool.close()
        _pool = None


def pool() -> asyncpg.Pool:
    if _pool is None:
        raise RuntimeError("DB pool not initialized — call init_pool() at startup")
    return _pool


async def apply_schema():
    """Idempotent: runs schema.sql. Safe to call every startup."""
    schema_path = Path(__file__).parent / "schema.sql"
    sql = schema_path.read_text()
    async with pool().acquire() as conn:
        await conn.execute(sql)


def vector_literal(embedding: list[float]) -> str:
    """pgvector accepts a string literal like '[0.1,0.2,...]' cast to ::vector."""
    return "[" + ",".join(f"{x:.8f}" for x in embedding) + "]"
