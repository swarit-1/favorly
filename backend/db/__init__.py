"""Raw Postgres access for schema migration. Supabase's Python client talks
REST (PostgREST), which can't run arbitrary DDL -- so schema.sql is applied
over a direct asyncpg connection using DATABASE_URL (the same connection
string Supabase shows under Settings -> Database), separate from the
SUPABASE_URL/SUPABASE_KEY client used for normal reads/writes.
"""

import os
from pathlib import Path
from typing import Optional
import asyncpg

_pool: Optional[asyncpg.Pool] = None


async def init_pool() -> Optional[asyncpg.Pool]:
    global _pool
    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        return None
    if _pool is None:
        _pool = await asyncpg.create_pool(database_url, min_size=1, max_size=5)
    return _pool


async def close_pool():
    global _pool
    if _pool is not None:
        await _pool.close()
        _pool = None


def pool() -> asyncpg.Pool:
    """Accessor for routes -- assumes init_pool()/apply_schema() already ran
    at startup. Raises if DATABASE_URL wasn't set."""
    if _pool is None:
        raise RuntimeError("DB pool not initialized -- is DATABASE_URL set?")
    return _pool


async def apply_schema() -> bool:
    """Idempotent: CREATE TABLE IF NOT EXISTS throughout. Safe to run every
    startup. No-op if DATABASE_URL isn't set (falls back to whatever already
    exists in the project -- e.g. tables created by hand in the dashboard)."""
    pool = await init_pool()
    if pool is None:
        return False
    schema_path = Path(__file__).parent.parent / "schema.sql"
    sql = schema_path.read_text()
    async with pool.acquire() as conn:
        await conn.execute(sql)
    return True
