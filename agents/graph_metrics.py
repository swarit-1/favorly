"""Topology as a pure function of the event log. Load the whole favor graph
into networkx, compute structural metrics for visualization, cache briefly,
discard. `give_balance` (reciprocity) is the one internal-only signal here.
"""

import time

import networkx as nx
import asyncpg

from config import settings
import edges as edges_mod

_last_computed_at: float = 0.0


async def load_graph(conn: asyncpg.Connection) -> nx.Graph:
    people_rows = await conn.fetch("SELECT id FROM people")
    edge_rows = await conn.fetch("SELECT DISTINCT src_id, dst_id FROM edges WHERE src_id <> dst_id")

    g = nx.Graph()
    g.add_nodes_from(str(r["id"]) for r in people_rows)
    g.add_edges_from((str(r["src_id"]), str(r["dst_id"])) for r in edge_rows)
    return g


async def recompute_all(conn: asyncpg.Connection) -> nx.Graph:
    global _last_computed_at
    g = await load_graph(conn)

    if g.number_of_nodes() >= 2:
        betweenness = nx.betweenness_centrality(g)
    else:
        betweenness = {n: 0.0 for n in g.nodes}
    clustering = nx.clustering(g)
    degree = dict(g.degree())

    for person_id in g.nodes:
        gb = await edges_mod.give_balance(conn, person_id)
        await conn.execute(
            "INSERT INTO graph_metrics (person_id, degree, betweenness, clustering, give_balance, computed_at) "
            "VALUES ($1, $2, $3, $4, $5, now()) "
            "ON CONFLICT (person_id) DO UPDATE SET degree=$2, betweenness=$3, clustering=$4, "
            "give_balance=$5, computed_at=now()",
            person_id, degree.get(person_id, 0), betweenness.get(person_id, 0.0),
            clustering.get(person_id, 0.0), gb,
        )
    _last_computed_at = time.time()
    return g


async def ensure_fresh(conn: asyncpg.Connection) -> nx.Graph:
    """Recompute only if the cache is older than METRICS_CACHE_SECONDS."""
    if time.time() - _last_computed_at > settings.METRICS_CACHE_SECONDS:
        return await recompute_all(conn)
    return await load_graph(conn)
