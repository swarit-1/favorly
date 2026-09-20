"""Shared FastAPI dependencies."""

import asyncpg

import db


async def get_conn() -> asyncpg.Connection:
    async with db.pool().acquire() as conn:
        yield conn
