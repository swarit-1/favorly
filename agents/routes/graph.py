"""GET /graph -- the favor-network visualization endpoint. `since` lets the
frontend animate deltas instead of redrawing."""

from datetime import datetime
from typing import Optional

import asyncpg
import networkx as nx
from fastapi import APIRouter, Depends, Query

import edges as edges_mod
import graph_metrics
from deps import get_conn

router = APIRouter()


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
async def get_graph(since: Optional[datetime] = Query(default=None), conn: asyncpg.Connection = Depends(get_conn)):
    g = await graph_metrics.load_graph(conn)
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
    out_edges = [
        {
            "src": str(r["src_id"]), "dst": str(r["dst_id"]), "kind": r["kind"],
            "strength": strength_by_pair_kind.get((str(r["src_id"]), str(r["dst_id"]), r["kind"]), 0.0),
        }
        for r in edge_rows
    ]

    return {"nodes": nodes, "edges": out_edges}
