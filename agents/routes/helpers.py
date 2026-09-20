"""v2 endpoints: who should help, invites, conversation state, graph stats.

The graph finds, the model phrases, a validator checks, templates back it all
up -- same discipline as recommendations.py, pointed the other way (helpers
for a need). Scores exist internally and are never rendered into copy.
"""

import json
import time
from datetime import datetime, timezone

import asyncpg
import networkx as nx
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel

import llm
import matching
import sse
from deps import get_conn
from recommendations import strip_dashes, validate_reason

router = APIRouter()


class InviteIn(BaseModel):
    helper_id: str


class RespondIn(BaseModel):
    accept: bool


def _from_jsonb(value, default):
    if value is None:
        return default
    if isinstance(value, str):
        try:
            return json.loads(value)
        except ValueError:
            return default
    return value


async def _get_need(conn: asyncpg.Connection, need_id: str):
    need = await conn.fetchrow("SELECT * FROM needs WHERE id = $1", need_id)
    if not need:
        raise HTTPException(404, "need not found")
    return need


# ---------------------------------------------------------------------------
# Ranking
# ---------------------------------------------------------------------------

# P5: last good helpers response per need text, served only when ranking
# raises or times out. (need_text_key -> (expires_at, response))
_stale_cache: dict[str, tuple[float, dict]] = {}
_STALE_TTL = 600.0


def _helper_match(c: dict, rank: int, reason: str, spark: str | None,
                  ctx: matching.CircleContext, asker_first: str) -> dict:
    person: matching.Person = c["person"]
    path = []
    if c["path_ids"]:
        for i, pid in enumerate(c["path_ids"]):
            p = ctx.people.get(pid)
            name = "You" if pid == ctx.asker_id else (p.first_name if p else "")
            path.append({"id": pid, "name": name})
    return {
        "person": {
            "id": person.id, "display_name": person.display_name,
            "first_name": person.first_name,
        },
        "rank": rank,
        "tie": c["tie"],
        "tie_label": strip_dashes(c["tie_label"]),
        "hops": c["hops"],
        "path": path,
        "headline": strip_dashes(c["headline"] or ""),
        "where": c["where"],
        "reason": strip_dashes(reason),
        "spark": strip_dashes(spark) if spark else None,
        "signals": c["signals"],
        "why": {
            "weights": matching.WEIGHTS,
            "matched_claims": [c["headline"]] if c["headline"] else [],
            "mutual_names": c["mutual_names"],
            "shared": c["shared"],
            "favors_they_did_for_you": c["favors_they_did_for_you"],
            "favors_you_did_for_them": c["favors_you_did_for_them"],
            "graph_reason": strip_dashes(matching.template_reason(c)),
        },
        "invite_status": None,
    }


async def _rank_and_phrase(conn, need, limit: int) -> dict:
    asker_id = str(need["person_id"])
    ctx = await matching.load_circle(conn, asker_id)
    asker = ctx.people.get(asker_id)
    asker_first = asker.first_name if asker else "You"

    need_dict = {
        "category": need["category"] or "errand",
        "requires": _from_jsonb(need["requires"], []),
        "when_text": need["when_text"],
        "title": need["title"],
    }
    top = matching.rank_helpers(ctx, need_dict, limit=limit)
    if not top:
        return {"need_id": str(need["id"]), "decided_by": "graph", "helpers": []}

    # Deterministic facts per candidate; the model may only phrase these.
    facts_by_id = {c["person_id"]: matching.candidate_facts(ctx, c, asker_first) for c in top}
    sparks_by_id = {c["person_id"]: matching.spark_for(c["shared"]) for c in top}

    decided_by = "graph"
    phrased_by_id: dict[str, dict] = {}
    context = {
        "ask": {
            "title": need["title"], "category": need_dict["category"],
            "when": need["when_text"], "text": need["body"],
        },
        "asker": {"first_name": asker_first},
        "recent": ctx.recent,
        "candidates": [
            {
                "person_id": c["person_id"],
                "first_name": c["person"].first_name,
                "where": c["where"],
                "tie": c["tie_label"],
                "facts": facts_by_id[c["person_id"]],
                "shared": c["shared"],
            }
            for c in top
        ],
    }
    phrased = llm.phrase_helpers(context)
    if phrased:
        for item in phrased:
            pid = str(item.get("person_id", ""))
            if pid not in facts_by_id:
                continue  # model invented a person -- drop it
            reason = str(item.get("reason", "")).strip()
            spark = item.get("spark")
            spark = str(spark).strip() if spark else None
            allowed = " ".join(
                facts_by_id[pid]
                + [asker_first, need["title"] or "", need["body"] or ""]
                + [c["person"].display_name for c in top]
                + [s for s in ([spark] if spark else [])]
                + [" ".join(next(c["shared"] for c in top if c["person_id"] == pid))]
            )
            if reason and len(reason.split()) <= 34 and validate_reason(reason, allowed):
                phrased_by_id[pid] = {"reason": reason, "spark": spark}
        if phrased_by_id:
            decided_by = "model"
            # The model may reorder: apply its order first, keep the rest.
            order = [str(i.get("person_id", "")) for i in phrased if str(i.get("person_id", "")) in phrased_by_id]
            top.sort(key=lambda c: order.index(c["person_id"]) if c["person_id"] in order else 99)

    helpers = []
    for i, c in enumerate(top[:limit], start=1):
        pid = c["person_id"]
        ph = phrased_by_id.get(pid)
        reason = ph["reason"] if ph else matching.template_reason(c)
        spark = (ph.get("spark") if ph else None) or sparks_by_id.get(pid)
        helpers.append(_helper_match(c, i, reason, spark, ctx, asker_first))

    return {"need_id": str(need["id"]), "decided_by": decided_by, "helpers": helpers}


@router.get("/needs/{need_id}/helpers")
async def get_helpers(
    need_id: str,
    limit: int = Query(default=3, ge=1, le=5),
    conn: asyncpg.Connection = Depends(get_conn),
):
    """Rank people for a need. Side effect: stores the ordered shortlist."""
    need = await _get_need(conn, need_id)
    cache_key = f"{need['person_id']}:{(need['body'] or '').strip().lower()}"

    try:
        result = await _rank_and_phrase(conn, need, limit)
    except Exception as e:
        stale = _stale_cache.get(cache_key)
        if stale and stale[0] > time.monotonic():
            print(f"[helpers] ranking failed ({e}); serving stale cache", flush=True)
            stale_result = dict(stale[1])
            stale_result["need_id"] = str(need["id"])
            return stale_result
        raise

    shortlist = [
        {
            "rank": h["rank"],
            "person_id": h["person"]["id"],
            "first_name": h["person"]["first_name"],
            "tie": h["tie"],
            "tie_label": h["tie_label"],
            "mutual": (h["why"]["mutual_names"][0].split()[0] if h["why"]["mutual_names"] else None),
            "headline": h["headline"],
            "where": h["where"],
            "reason": h["reason"],
            "spark": h["spark"],
        }
        for h in result["helpers"]
    ]
    await conn.execute(
        "UPDATE needs SET shortlist = $1 WHERE id = $2", json.dumps(shortlist), need_id,
    )
    _stale_cache[cache_key] = (time.monotonic() + _STALE_TTL, result)
    return result


# ---------------------------------------------------------------------------
# Invites
# ---------------------------------------------------------------------------


@router.post("/needs/{need_id}/invite")
async def invite_helper(need_id: str, payload: InviteIn, conn: asyncpg.Connection = Depends(get_conn)):
    need = await _get_need(conn, need_id)
    if need["status"] != "open":
        raise HTTPException(409, f"need is {need['status']}, expected open")
    if str(need["person_id"]) == payload.helper_id:
        raise HTTPException(422, "you can't invite yourself")
    helper = await conn.fetchrow("SELECT id FROM app_people WHERE id = $1", payload.helper_id)
    if not helper:
        raise HTTPException(404, "helper not found")

    entry = next(
        (s for s in _from_jsonb(need["shortlist"], []) if s.get("person_id") == payload.helper_id),
        {},
    )
    await conn.execute(
        "INSERT INTO need_invites (need_id, helper_id, rank, reason, spark) "
        "VALUES ($1, $2, $3, $4, $5) "
        "ON CONFLICT (need_id, helper_id) DO NOTHING",
        need_id, payload.helper_id, entry.get("rank"), entry.get("reason"), entry.get("spark"),
    )
    await sse.publish("invite_sent", {"need_id": need_id, "helper_id": payload.helper_id})
    return {"status": "pending"}


@router.post("/needs/{need_id}/invites/{helper_id}/respond")
async def respond_invite(
    need_id: str, helper_id: str, payload: RespondIn,
    conn: asyncpg.Connection = Depends(get_conn),
):
    need = await _get_need(conn, need_id)
    inv = await conn.fetchrow(
        "SELECT * FROM need_invites WHERE need_id = $1 AND helper_id = $2", need_id, helper_id,
    )
    if not inv:
        raise HTTPException(404, "invite not found")
    if inv["status"] not in ("pending",):
        raise HTTPException(409, f"invite is already {inv['status']}")

    if payload.accept:
        if need["status"] != "open":
            raise HTTPException(409, f"need is already {need['status']}")
        await conn.execute(
            "UPDATE needs SET status = 'claimed', claimed_by = $1 WHERE id = $2",
            helper_id, need_id,
        )
        await conn.execute(
            "UPDATE need_invites SET status = 'accepted', responded_at = now() "
            "WHERE need_id = $1 AND helper_id = $2",
            need_id, helper_id,
        )
        await conn.execute(
            "UPDATE need_invites SET status = 'expired', responded_at = now() "
            "WHERE need_id = $1 AND status = 'pending'",
            need_id,
        )
        await sse.publish("need_claimed", {"need_id": need_id, "claimed_by": helper_id})
        return {"status": "accepted"}

    await conn.execute(
        "UPDATE need_invites SET status = 'declined', responded_at = now() "
        "WHERE need_id = $1 AND helper_id = $2",
        need_id, helper_id,
    )
    await sse.publish("invite_declined", {"need_id": need_id, "helper_id": helper_id})

    # Next shortlist entry not yet invited, as a HelperMatch-shaped stub.
    invited = {
        str(r["helper_id"]) for r in await conn.fetch(
            "SELECT helper_id FROM need_invites WHERE need_id = $1", need_id,
        )
    }
    nxt = next(
        (s for s in _from_jsonb(need["shortlist"], []) if s.get("person_id") not in invited),
        None,
    )
    next_match = None
    if nxt:
        next_match = {
            "person": {"id": nxt.get("person_id"), "first_name": nxt.get("first_name"),
                       "display_name": nxt.get("first_name")},
            "rank": nxt.get("rank"),
            "tie": nxt.get("tie"),
            "tie_label": nxt.get("tie_label"),
            "headline": nxt.get("headline"),
            "where": nxt.get("where"),
            "reason": nxt.get("reason"),
            "spark": nxt.get("spark"),
            "invite_status": None,
        }
    return {"status": "declined", "next": next_match}


@router.post("/needs/{need_id}/broadcast")
async def broadcast_need(need_id: str, conn: asyncpg.Connection = Depends(get_conn)):
    """Clears the shortlist; the need stays open to the whole feed."""
    need = await _get_need(conn, need_id)
    if need["status"] != "open":
        raise HTTPException(409, f"need is {need['status']}, expected open")
    await conn.execute("UPDATE needs SET shortlist = '[]' WHERE id = $1", need_id)
    await sse.publish("need_broadcast", {"need_id": need_id})
    return {"status": "open", "broadcast": True}


@router.post("/needs/{need_id}/cancel")
async def cancel_need(need_id: str, conn: asyncpg.Connection = Depends(get_conn)):
    need = await _get_need(conn, need_id)
    if need["status"] in ("fulfilled", "cancelled"):
        raise HTTPException(409, f"need is already {need['status']}")
    await conn.execute(
        "UPDATE needs SET status = 'cancelled', resolved_at = now() WHERE id = $1", need_id,
    )
    await conn.execute(
        "UPDATE need_invites SET status = 'expired', responded_at = now() "
        "WHERE need_id = $1 AND status = 'pending'",
        need_id,
    )
    await sse.publish("need_cancelled", {"need_id": need_id})
    return {"status": "cancelled"}


# ---------------------------------------------------------------------------
# Conversation state: everything a stateless client needs to interpret
# "2", "yes", "done". Derived from the database, never process memory.
# ---------------------------------------------------------------------------


def _person_out(row) -> dict:
    name = row["display_name"] or ""
    floor = None
    try:
        floor = int(str(row["address_floor"]))
    except (TypeError, ValueError):
        pass
    return {
        "id": str(row["id"]), "display_name": name,
        "first_name": name.split()[0] if name else "",
        "floor": floor, "unit": row["address_unit"],
    }


@router.get("/people/{person_id}/state")
async def get_state(person_id: str, conn: asyncpg.Connection = Depends(get_conn)):
    person = await conn.fetchrow(
        "SELECT id, display_name, address_unit, address_floor FROM app_people WHERE id = $1",
        person_id,
    )
    if not person:
        raise HTTPException(404, "person not found")

    # Most recent open ask I posted, with shortlist + invite statuses.
    open_ask = None
    ask_row = await conn.fetchrow(
        "SELECT * FROM needs WHERE person_id = $1 AND status = 'open' "
        "ORDER BY created_at DESC LIMIT 1",
        person_id,
    )
    if ask_row:
        inv_rows = await conn.fetch(
            "SELECT helper_id, status FROM need_invites WHERE need_id = $1", ask_row["id"],
        )
        status_by_helper = {str(r["helper_id"]): r["status"] for r in inv_rows}
        shortlist = [
            {
                "rank": s.get("rank"),
                "person_id": s.get("person_id"),
                "first_name": s.get("first_name"),
                "invite_status": status_by_helper.get(s.get("person_id")),
            }
            for s in _from_jsonb(ask_row["shortlist"], [])
        ]
        open_ask = {
            "need_id": str(ask_row["id"]),
            "title": ask_row["title"],
            "category": ask_row["category"] or "errand",
            "shortlist": shortlist,
        }

    # Most recent pending invite addressed to me, on a still-open need.
    pending_invite = None
    inv = await conn.fetchrow(
        "SELECT i.need_id, i.created_at, n.title, n.category, n.when_text, n.person_id AS asker_id, "
        "n.shortlist "
        "FROM need_invites i JOIN needs n ON n.id = i.need_id "
        "WHERE i.helper_id = $1 AND i.status = 'pending' AND n.status = 'open' "
        "ORDER BY i.created_at DESC LIMIT 1",
        person_id,
    )
    if inv:
        asker = await conn.fetchrow(
            "SELECT id, display_name, address_unit, address_floor FROM app_people WHERE id = $1",
            str(inv["asker_id"]),
        )
        entry = next(
            (s for s in _from_jsonb(inv["shortlist"], []) if s.get("person_id") == person_id),
            {},
        )
        asker_out = _person_out(asker) if asker else {}
        pending_invite = {
            "need_id": str(inv["need_id"]),
            "title": inv["title"],
            "category": inv["category"] or "errand",
            "when_text": inv["when_text"],
            "asker": {
                "id": asker_out.get("id"), "first_name": asker_out.get("first_name"),
                "floor": asker_out.get("floor"),
            },
            "mutual_first_name": entry.get("mutual"),
        }

    # Most recent claimed need I'm part of, either side.
    active_favor = None
    active = await conn.fetchrow(
        "SELECT * FROM needs WHERE status = 'claimed' AND (person_id = $1 OR claimed_by = $1) "
        "ORDER BY created_at DESC LIMIT 1",
        person_id,
    )
    if active:
        role = "helper" if str(active["claimed_by"]) == person_id else "asker"
        other_id = str(active["person_id"]) if role == "helper" else str(active["claimed_by"])
        other = await conn.fetchrow(
            "SELECT id, display_name, address_unit, address_floor FROM app_people WHERE id = $1",
            other_id,
        )
        spark_row = await conn.fetchrow(
            "SELECT spark FROM need_invites WHERE need_id = $1 AND status = 'accepted' LIMIT 1",
            active["id"],
        )
        other_out = _person_out(other) if other else {}
        active_favor = {
            "need_id": str(active["id"]),
            "title": active["title"],
            "role": role,
            "other": {
                "id": other_out.get("id"), "first_name": other_out.get("first_name"),
                "unit": other_out.get("unit"),
            },
            "spark": spark_row["spark"] if spark_row else None,
        }

    return {
        "person": _person_out(person),
        "open_ask": open_ask,
        "pending_invite": pending_invite,
        "active_favor": active_favor,
    }


@router.get("/people/{person_id}/asks")
async def get_asks(person_id: str, conn: asyncpg.Connection = Depends(get_conn)):
    """Open + claimed needs I posted, plus fulfilled in the last 10 minutes."""
    person = await conn.fetchrow("SELECT id FROM app_people WHERE id = $1", person_id)
    if not person:
        raise HTTPException(404, "person not found")
    rows = await conn.fetch(
        "SELECT n.*, p.display_name AS helper_name FROM needs n "
        "LEFT JOIN app_people p ON p.id = n.claimed_by "
        "WHERE n.person_id = $1 AND (n.status IN ('open','claimed') "
        "  OR (n.status = 'fulfilled' AND n.resolved_at > now() - interval '10 minutes')) "
        "ORDER BY n.created_at DESC",
        person_id,
    )
    asks = []
    for r in rows:
        inv_rows = await conn.fetch(
            "SELECT i.helper_id, i.status, i.rank, p.display_name "
            "FROM need_invites i JOIN app_people p ON p.id = i.helper_id "
            "WHERE i.need_id = $1 ORDER BY i.rank NULLS LAST",
            r["id"],
        )
        helper_name = r["helper_name"] or ""
        asks.append({
            "need_id": str(r["id"]),
            "title": r["title"],
            "body": r["body"],
            "category": r["category"] or "errand",
            "status": r["status"],
            "when_text": r["when_text"],
            "created_at": r["created_at"],
            "helpers": [
                {
                    "person_id": str(i["helper_id"]),
                    "first_name": (i["display_name"] or "").split()[0],
                    "rank": i["rank"],
                    "invite_status": i["status"],
                }
                for i in inv_rows
            ],
            "accepted_helper": (
                {"person_id": str(r["claimed_by"]), "first_name": helper_name.split()[0] if helper_name else ""}
                if r["claimed_by"] else None
            ),
        })
    return {"asks": asks}


# ---------------------------------------------------------------------------
# Graph stats
# ---------------------------------------------------------------------------


@router.get("/graph/stats")
async def graph_stats(person_id: str = Query(...), conn: asyncpg.Connection = Depends(get_conn)):
    row = await conn.fetchrow("SELECT circle_id FROM app_people WHERE id = $1", person_id)
    if not row:
        raise HTTPException(404, "person not found")
    members = await conn.fetch(
        "SELECT id FROM app_people WHERE circle_id = $1", row["circle_id"],
    )
    ids = {str(m["id"]) for m in members}
    edge_rows = await conn.fetch(
        "SELECT DISTINCT src_id, dst_id FROM edges WHERE src_id <> dst_id",
    )
    g = nx.Graph()
    g.add_nodes_from(ids)
    g.add_edges_from(
        (str(r["src_id"]), str(r["dst_id"]))
        for r in edge_rows
        if str(r["src_id"]) in ids and str(r["dst_id"]) in ids
    )
    if g.number_of_nodes() > 1 and g.number_of_edges() > 0:
        biggest = max(nx.connected_components(g), key=len)
        sub = g.subgraph(biggest)
        avg_sep = nx.average_shortest_path_length(sub) if sub.number_of_nodes() > 1 else 0.0
    else:
        avg_sep = 0.0
    triangles = sum(nx.triangles(g).values()) // 3
    return {
        "people": g.number_of_nodes(),
        "ties": g.number_of_edges(),
        "avg_separation": round(avg_sep, 2),
        "triangles": triangles,
    }
