"""The favor-network visualization endpoints.

`GET /graph` is the map: who is connected to whom, how strongly, in what
community. `since` lets the frontend animate deltas instead of redrawing.
`GET /graph/thread/{a}/{b}` is one pair of that map, expanded.
"""

from datetime import datetime
from typing import Optional

import asyncpg
import networkx as nx
from fastapi import APIRouter, Depends, HTTPException, Query

import edges as edges_mod
import graph_metrics
from config import settings
from deps import get_conn

router = APIRouter()

_DECAY = "EXP(-EXTRACT(EPOCH FROM (now() - created_at)) / $3)"


async def _circle_members(conn: asyncpg.Connection, person_id: str) -> set[str]:
    """Everyone in this person's circle, them included. Raises if the person
    has no circle: silently widening to the whole database would show them a
    map of strangers and call it their neighborhood."""
    row = await conn.fetchrow("SELECT circle_id FROM app_people WHERE id = $1", person_id)
    if row is None:
        raise HTTPException(404, "person not found")
    if row["circle_id"] is None:
        raise HTTPException(409, "person is not in a circle")
    members = await conn.fetch(
        "SELECT id FROM app_people WHERE circle_id = $1", row["circle_id"],
    )
    return {str(m["id"]) for m in members}


def _clusters(g: nx.Graph) -> dict[str, int]:
    if g.number_of_edges() == 0:
        return {n: i for i, n in enumerate(g.nodes)}
    from networkx.algorithms.community import greedy_modularity_communities
    communities = greedy_modularity_communities(g)
    cluster_of = {}
    for idx, community in enumerate(communities):
        for node in community:
            cluster_of[node] = idx
    return cluster_of


@router.get("/graph")
async def get_graph(
    since: Optional[datetime] = Query(default=None),
    person_id: Optional[str] = Query(
        default=None,
        description="Scope the map to this person's circle. Omitted, the whole database is returned.",
    ),
    conn: asyncpg.Connection = Depends(get_conn),
):
    scope = await _circle_members(conn, person_id) if person_id else None
    g = await graph_metrics.load_graph(conn, only=scope)
    cluster_of = _clusters(g)
    degree = dict(g.degree())

    if since is not None:
        edge_rows = await conn.fetch(
            "SELECT src_id, dst_id, kind, created_at FROM edges WHERE created_at > $1",
            since,
        )
        touched_ids = {str(r["src_id"]) for r in edge_rows} | {str(r["dst_id"]) for r in edge_rows}
    else:
        edge_rows = await conn.fetch("SELECT src_id, dst_id, kind, created_at FROM edges")
        touched_ids = set(g.nodes)

    if scope is not None:
        touched_ids &= scope
        edge_rows = [
            r for r in edge_rows
            if str(r["src_id"]) in scope and str(r["dst_id"]) in scope
        ]

    decayed = await edges_mod.all_edges_decayed(conn)
    strength_by_pair_kind = {
        (str(d["src_id"]), str(d["dst_id"]), d["kind"]): d["strength"] for d in decayed
    }

    people = await conn.fetch(
        "SELECT id, display_name FROM app_people WHERE id = ANY($1::uuid[])", list(touched_ids) or [None],
    ) if touched_ids else []
    name_of = {str(p["id"]): p["display_name"] for p in people}

    nodes = [
        {"id": pid, "name": name_of.get(pid, ""), "degree": degree.get(pid, 0), "cluster": cluster_of.get(pid, -1)}
        for pid in touched_ids
    ]
    # One row per (src, dst, kind), not per favor. `strength` is already the
    # decayed SUM over every favor between that pair, so emitting it beside
    # each underlying row invites a client to add them up and report a tie as
    # several times stronger than it is.
    out_edges = [
        {
            "src": src, "dst": dst, "kind": kind,
            "strength": strength_by_pair_kind.get((src, dst, kind), 0.0),
        }
        for src, dst, kind in dict.fromkeys(
            (str(r["src_id"]), str(r["dst_id"]), r["kind"]) for r in edge_rows
        )
    ]

    return {"nodes": nodes, "edges": out_edges}


@router.get("/graph/thread/{a_id}/{b_id}")
async def get_thread(a_id: str, b_id: str, conn: asyncpg.Connection = Depends(get_conn)):
    """Why these two are connected at all -- the pairwise view behind a node
    tap on the graph.

    Everything here is already-visible history (favors between the two, who
    they both know, claims they share). `give_balance` is deliberately not
    part of it: the ledger stays internal, see edges.py.
    """
    people = await conn.fetch(
        "SELECT id, display_name FROM app_people WHERE id = ANY($1::uuid[])", [a_id, b_id],
    )
    name_of = {str(p["id"]): p["display_name"] for p in people}
    if a_id not in name_of or b_id not in name_of:
        raise HTTPException(404, "person not found")

    # Directed, so the UI can say who did what for whom rather than "3 favors
    # happened" -- direction is the whole point of a reciprocity signal.
    favor_rows = await conn.fetch(
        "SELECT src_id, dst_id, created_at, "
        f"weight * {_DECAY} AS strength "
        "FROM edges WHERE kind = 'favor' "
        "AND ((src_id = $1 AND dst_id = $2) OR (src_id = $2 AND dst_id = $1)) "
        "ORDER BY created_at DESC",
        a_id, b_id, settings.EDGE_DECAY_SECONDS,
    )

    def _direction(rows, src):
        mine = [r for r in rows if str(r["src_id"]) == src]
        return {
            "count": len(mine),
            "strength": round(sum(float(r["strength"]) for r in mine), 4),
            "last_at": mine[0]["created_at"] if mine else None,
        }

    mutuals = await conn.fetch(
        """
        SELECT p.id, p.display_name FROM app_people p WHERE p.id IN (
          SELECT id FROM (
            SELECT dst_id AS id FROM edges WHERE src_id = $1
            UNION SELECT src_id AS id FROM edges WHERE dst_id = $1
          ) AS a
          INTERSECT
          SELECT id FROM (
            SELECT dst_id AS id FROM edges WHERE src_id = $2
            UNION SELECT src_id AS id FROM edges WHERE dst_id = $2
          ) AS b
        ) AND p.id NOT IN ($1, $2)
        """,
        a_id, b_id,
    )

    # Shared claims say why one of them is a good person to *send*, which is
    # the signal `_affinity` scores. Matched on canonical so "gluten free" and
    # "gluten-free" count as the same thing.
    shared = await conn.fetch(
        "SELECT DISTINCT ca.kind, ca.canonical, ca.raw_label "
        "FROM claims ca JOIN claims cb ON cb.canonical = ca.canonical "
        "WHERE ca.person_id = $1 AND cb.person_id = $2 "
        "AND ca.superseded_by IS NULL AND cb.superseded_by IS NULL "
        "AND ca.confidence >= $3 AND cb.confidence >= $3",
        a_id, b_id, settings.CONFIDENCE_FLOOR,
    )

    return {
        "a": {"id": a_id, "display_name": name_of[a_id]},
        "b": {"id": b_id, "display_name": name_of[b_id]},
        "favors": {
            "a_to_b": _direction(favor_rows, a_id),
            "b_to_a": _direction(favor_rows, b_id),
            "first_at": favor_rows[-1]["created_at"] if favor_rows else None,
        },
        "mutuals": [{"id": str(m["id"]), "display_name": m["display_name"]} for m in mutuals],
        "shared_claims": [
            {"kind": s["kind"], "canonical": s["canonical"], "raw_label": s["raw_label"]}
            for s in shared
        ],
    }
