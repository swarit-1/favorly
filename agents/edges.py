"""Favor edges: append-only, decayed, weighted by kind. give_balance
(reciprocity) lives here and is never exposed by any route."""

import asyncpg

from config import settings

_DECAY_SQL = "EXP(-EXTRACT(EPOCH FROM (now() - created_at)) / $__decay__)"


def weight_for_kind(kind: str) -> float:
    return settings.EDGE_WEIGHTS.get(kind, 0.5)


async def write_edge(
    conn: asyncpg.Connection, src_id: str, dst_id: str, kind: str,
    event_id: str | None = None, weight: float | None = None,
    created_at=None,
) -> str:
    w = weight if weight is not None else weight_for_kind(kind)
    row = await conn.fetchrow(
        "INSERT INTO edges (src_id, dst_id, kind, weight, event_id, created_at) "
        "VALUES ($1, $2, $3, $4, $5, COALESCE($6, now())) "
        "ON CONFLICT (src_id, dst_id, kind, event_id) DO NOTHING "
        "RETURNING id",
        src_id, dst_id, kind, w, event_id, created_at,
    )
    if row is None:
        existing = await conn.fetchrow(
            "SELECT id FROM edges WHERE src_id=$1 AND dst_id=$2 AND kind=$3 "
            "AND event_id IS NOT DISTINCT FROM $4",
            src_id, dst_id, kind, event_id,
        )
        return str(existing["id"]) if existing else ""
    return str(row["id"])


async def all_edges_decayed(conn: asyncpg.Connection) -> list[dict]:
    # `knows` and `neighbor` are structural, not events -- they do not decay.
    decay = _DECAY_SQL.replace("$__decay__", "$1")
    sql = (
        "SELECT src_id, dst_id, kind, "
        f"SUM(weight * CASE WHEN kind IN ('favor','co_occurrence') THEN {decay} ELSE 1 END) AS strength "
        "FROM edges GROUP BY src_id, dst_id, kind"
    )
    rows = await conn.fetch(sql, settings.EDGE_DECAY_SECONDS)
    return [dict(r) for r in rows]


async def give_balance(conn: asyncpg.Connection, person_id: str) -> float:
    """Favors given minus received, decayed. Internal only -- never returned by
    the API, never rendered. Kept because surfacing it would turn helping into
    a scoreboard; it exists for burnout detection if that gets built."""
    decay = settings.EDGE_DECAY_SECONDS
    given = await conn.fetchrow(
        f"SELECT COALESCE(SUM(weight * {_DECAY_SQL.replace('$__decay__', '$2')}), 0) AS s "
        "FROM edges WHERE src_id = $1 AND kind = 'favor'",
        person_id, decay,
    )
    received = await conn.fetchrow(
        f"SELECT COALESCE(SUM(weight * {_DECAY_SQL.replace('$__decay__', '$2')}), 0) AS s "
        "FROM edges WHERE dst_id = $1 AND kind = 'favor'",
        person_id, decay,
    )
    return float(given["s"]) - float(received["s"])
