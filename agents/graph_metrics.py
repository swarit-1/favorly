"""Loads the favor graph into networkx for the /graph visualization endpoint.

Previously this also computed betweenness/clustering and cached them in a
`graph_metrics` table. Nothing ever read them back -- they were left over from
the intro-routing scorer, which is gone -- so the table and the per-recompute
centrality passes were removed rather than left as a cost with no consumer.
"""

import networkx as nx
import asyncpg


async def load_graph(conn: asyncpg.Connection, only: set[str] | None = None) -> nx.Graph:
    """The whole favor graph, or just the slice spanned by `only`.

    Scoping matters for degree and clustering, not just for what gets drawn:
    a graph built from everyone and then filtered down reports degrees that
    count neighbors the caller can't see, and puts people in communities
    computed against strangers.
    """
    people_rows = await conn.fetch("SELECT id FROM app_people")
    edge_rows = await conn.fetch("SELECT DISTINCT src_id, dst_id FROM edges WHERE src_id <> dst_id")

    g = nx.Graph()
    g.add_nodes_from(
        str(r["id"]) for r in people_rows if only is None or str(r["id"]) in only
    )
    g.add_edges_from(
        (str(r["src_id"]), str(r["dst_id"]))
        for r in edge_rows
        if only is None or (str(r["src_id"]) in only and str(r["dst_id"]) in only)
    )
    return g
