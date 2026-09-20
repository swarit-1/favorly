"""Favorly Route (Visa stretch S2): shortest walk through the store for the
shopper's merged list, plus at most three explained, consent-first suggestions.

A store is laid out for the store. Your route is laid out for you.

The planner core is pure functions over plain dicts so it is fully testable
offline. Only the FastAPI handler at the bottom touches Supabase.
"""

import json
import re
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/route", tags=["route"])

LAYOUT_PATH = Path(__file__).resolve().parent.parent / "seed" / "store_layouts" / "generic_grocery.json"

DEFAULT_ITEM_PRICE = 5.00  # estimate when an item has no max_price
DEFAULT_CAP = 40.00        # TripCaps.max_dollars_per_person default
MAX_SUGGESTIONS = 3

# Free-text neighbor needs ("can someone grab milk") mapped to a groceryish
# item + section. Longest keyword wins. Needs that do not match are skipped.
NEED_KEYWORDS: List[Tuple[str, str]] = [
    ("paper towels", "household"),
    ("toilet paper", "household"),
    ("ice cream", "frozen"),
    ("orange juice", "beverages"),
    ("milk", "dairy"),
    ("eggs", "dairy"),
    ("egg", "dairy"),
    ("cheese", "dairy"),
    ("yogurt", "dairy"),
    ("butter", "dairy"),
    ("bread", "bakery"),
    ("bagels", "bakery"),
    ("bananas", "produce"),
    ("apples", "produce"),
    ("avocado", "produce"),
    ("lettuce", "produce"),
    ("tomatoes", "produce"),
    ("onions", "produce"),
    ("chicken", "meat"),
    ("beef", "meat"),
    ("bacon", "meat"),
    ("coffee", "beverages"),
    ("soda", "beverages"),
    ("water", "beverages"),
    ("cereal", "pantry"),
    ("pasta", "pantry"),
    ("rice", "pantry"),
    ("flour", "pantry"),
    ("sugar", "pantry"),
    ("olive oil", "pantry"),
    ("detergent", "household"),
    ("dish soap", "household"),
    ("toothpaste", "personal_care"),
    ("shampoo", "personal_care"),
    ("soap", "personal_care"),
]

# Fallback section guess for pantry-scan / history item names.
ITEM_SECTION_GUESS: Dict[str, str] = {kw: sec for kw, sec in NEED_KEYWORDS}


# ============================================================================
# Pure planner core (no I/O, plain dicts)
# ============================================================================

def load_layout(path: Optional[Path] = None) -> dict:
    """Load a store layout file into {width_m, height_m, nodes:{key:{x,y}}}."""
    with open(path or LAYOUT_PATH) as f:
        raw = json.load(f)
    return {
        "width_m": raw["width_m"],
        "height_m": raw["height_m"],
        "nodes": {k: {"x": float(v["x"]), "y": float(v["y"])} for k, v in raw["nodes"].items()},
    }


def manhattan(a: dict, b: dict) -> float:
    return abs(a["x"] - b["x"]) + abs(a["y"] - b["y"])


def path_length(points: List[dict]) -> float:
    return sum(manhattan(points[i], points[i + 1]) for i in range(len(points) - 1))


def held_karp(points: List[dict]) -> Tuple[List[int], float]:
    """Exact shortest path visiting every point, start fixed at points[0]
    (entrance) and end fixed at points[-1] (checkout). Manhattan metric.
    Returns (visit order as indices, total distance). Fine for <= 12 nodes.
    """
    n = len(points)
    if n <= 2:
        order = list(range(n))
        return order, path_length([points[i] for i in order])
    mids = list(range(1, n - 1))
    m = len(mids)
    d = [[manhattan(points[i], points[j]) for j in range(n)] for i in range(n)]

    # dp[(mask, j)] = (cost of reaching mids[j] having visited mask, parent j)
    dp: Dict[Tuple[int, int], Tuple[float, Optional[int]]] = {}
    for ji in range(m):
        dp[(1 << ji, ji)] = (d[0][mids[ji]], None)
    for mask in range(1, 1 << m):
        for ji in range(m):
            if not mask & (1 << ji) or (mask, ji) not in dp:
                continue
            cost, _ = dp[(mask, ji)]
            for ki in range(m):
                if mask & (1 << ki):
                    continue
                nm = mask | (1 << ki)
                nc = cost + d[mids[ji]][mids[ki]]
                if (nm, ki) not in dp or nc < dp[(nm, ki)][0]:
                    dp[(nm, ki)] = (nc, ji)

    full = (1 << m) - 1
    best_total, best_ji = None, None
    for ji in range(m):
        cost, _ = dp[(full, ji)]
        total = cost + d[mids[ji]][n - 1]
        if best_total is None or total < best_total:
            best_total, best_ji = total, ji

    order_mids: List[int] = []
    mask, ji = full, best_ji
    while ji is not None:
        order_mids.append(ji)
        _, parent = dp[(mask, ji)]
        mask ^= 1 << ji
        ji = parent
    order_mids.reverse()
    return [0] + [mids[i] for i in order_mids] + [n - 1], best_total


def sections_in_written_order(items: List[dict]) -> List[str]:
    """Distinct sections in the order the items were written (first mention)."""
    seen: List[str] = []
    for it in items:
        sec = it.get("section") or "other"
        if sec not in seen:
            seen.append(sec)
    return seen


def group_by_section(items: List[dict]) -> Dict[str, List[dict]]:
    grouped: Dict[str, List[dict]] = {}
    for it in items:
        grouped.setdefault(it.get("section") or "other", []).append(it)
    return grouped


def baseline_distance(items: List[dict], layout: dict) -> float:
    """The same sections walked in the order they were written down."""
    nodes = layout["nodes"]
    secs = [s for s in sections_in_written_order(items) if s in nodes]
    points = [nodes["entrance"]] + [nodes[s] for s in secs] + [nodes["checkout"]]
    return path_length(points)


def plan_route(items: List[dict], layout: dict) -> Tuple[List[dict], List[dict], float]:
    """Optimal stop order for the given items.

    Returns (stops, path_points, distance_m). Stops carry order, section, x, y
    and their items. Empty list still yields a valid entrance-to-checkout walk.
    """
    nodes = layout["nodes"]
    grouped = group_by_section(items)
    secs = [s for s in grouped if s in nodes]
    points = [nodes["entrance"]] + [nodes[s] for s in secs] + [nodes["checkout"]]
    keys = ["entrance"] + secs + ["checkout"]
    order, dist = held_karp(points)

    stops: List[dict] = []
    path: List[dict] = []
    stop_no = 0
    for idx in order:
        key = keys[idx]
        pt = points[idx]
        path.append({"x": pt["x"], "y": pt["y"]})
        if key in ("entrance", "checkout"):
            continue
        stop_no += 1
        stops.append({
            "order": stop_no,
            "section": key,
            "x": pt["x"],
            "y": pt["y"],
            "items": [
                {
                    "name": it["name"],
                    "qty": it.get("qty", 1),
                    "requester_first": it.get("requester_first") or "",
                }
                for it in grouped[key]
            ],
        })
    return stops, path, dist


def insertion_delta(path: List[dict], point: dict) -> float:
    """Extra Manhattan metres to detour through point on the given path."""
    if len(path) < 2:
        return manhattan(path[0], point) * 2 if path else 0.0
    return min(
        manhattan(a, point) + manhattan(point, b) - manhattan(a, b)
        for a, b in zip(path, path[1:])
    )


def _slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def _fmt_m(metres: float) -> str:
    return str(int(round(metres)))


def _title(section: str) -> str:
    return section.replace("_", " ").capitalize()


def extract_need_item(body: str) -> Optional[Tuple[str, str]]:
    """Map a free-text need to (item name, section), or None if not groceryish."""
    low = body.lower()
    for kw, sec in NEED_KEYWORDS:
        if kw in low:
            return kw, sec
    return None


def guess_section(name: str) -> str:
    low = name.lower()
    for kw, sec in ITEM_SECTION_GUESS.items():
        if kw in low:
            return sec
    return "other"


def build_suggestions(
    items: List[dict],
    extra_items: List[dict],
    path: List[dict],
    layout: dict,
    neighbor_needs: Optional[List[dict]] = None,
    pantry_low: Optional[List[dict]] = None,
    forgotten: Optional[List[dict]] = None,
) -> List[dict]:
    """At most MAX_SUGGESTIONS suggestions, each with a visible reason and a
    computed added_distance_m. Priority: neighbor, then future_you, then
    forgotten. Never suggests anything already on the list.

    neighbor_needs: [{name, section, requester_first}]
    pantry_low:     [{name, section?, scanned_day?}]
    forgotten:      [{name, section, qty?}]
    """
    nodes = layout["nodes"]
    have = {it["name"].strip().lower() for it in items}
    have |= {it["name"].strip().lower() for it in extra_items}
    route_sections = {
        it.get("section") or "other"
        for it in list(items) + list(extra_items)
        if (it.get("section") or "other") in nodes
    }

    out: List[dict] = []
    seen_names = set()

    def add(kind: str, name: str, qty: int, section: str, title: str, reason: str,
            added: float, requester_first: Optional[str] = None):
        if len(out) >= MAX_SUGGESTIONS:
            return
        key = name.strip().lower()
        if key in have or key in seen_names:
            return
        seen_names.add(key)
        sug = {
            "id": f"sug-{kind}-{_slug(name)}",
            "kind": kind,
            "title": title,
            "reason": reason,
            "item": {"name": name, "qty": qty, "section": section},
            "added_distance_m": round(added, 1),
        }
        if requester_first:
            sug["requester_first"] = requester_first
        out.append(sug)

    for need in neighbor_needs or []:
        sec = need["section"]
        if sec not in route_sections:
            continue  # only detours that cost nothing: the aisle is already on the walk
        first = need.get("requester_first") or "A neighbor"
        add(
            "neighbor", need["name"], need.get("qty", 1), sec,
            f"{need['name'].capitalize()} for {first}",
            f"{first} needs {need['name']}. {_title(sec)} is already on your route. Adds 0 m.",
            0.0, requester_first=first,
        )

    for low in pantry_low or []:
        sec = low.get("section") or guess_section(low["name"])
        if sec not in nodes:
            continue
        added = 0.0 if sec in route_sections else insertion_delta(path, nodes[sec])
        day = low.get("scanned_day")
        when = f" on {day}" if day else ""
        add(
            "future_you", low["name"], low.get("qty", 1), sec,
            f"{low['name'].capitalize()} for future you",
            f"Your pantry scan{when} showed {low['name']} running low. Adds {_fmt_m(added)} m.",
            added,
        )

    for old in forgotten or []:
        sec = old["section"]
        if sec not in route_sections:
            continue  # only if its section is already on the path
        add(
            "forgotten", old["name"], old.get("qty", 1), sec,
            f"{old['name'].capitalize()}, usually on your list",
            f"{old['name'].capitalize()} was on your last list but not this one. "
            f"{_title(sec)} is already on your route. Adds 0 m.",
            0.0,
        )

    return out


def build_caps(items: List[dict], extra_items: List[dict], cap: float) -> List[dict]:
    """Per-requester running totals against the trip cap. Items without a
    max_price count as a DEFAULT_ITEM_PRICE estimate."""
    totals: Dict[str, float] = {}
    names: Dict[str, str] = {}
    for it in list(items) + list(extra_items):
        rid = it.get("requester_id")
        if not rid:
            continue
        rid = str(rid)
        price = it.get("max_price")
        totals[rid] = totals.get(rid, 0.0) + (float(price) if price is not None else DEFAULT_ITEM_PRICE)
        if it.get("requester_first"):
            names[rid] = it["requester_first"]
    return [
        {
            "requester_first": names.get(rid, ""),
            "requester_id": rid,
            "cap": round(cap, 2),
            "running_total": round(total, 2),
            "over": total > cap,
        }
        for rid, total in totals.items()
    ]


def build_plan(
    trip_id: str,
    store: str,
    items: List[dict],
    extra_items: List[dict],
    layout: dict,
    cap: float = DEFAULT_CAP,
    neighbor_needs: Optional[List[dict]] = None,
    pantry_low: Optional[List[dict]] = None,
    forgotten: Optional[List[dict]] = None,
) -> dict:
    """Assemble the full frozen response shape from plain dicts."""
    all_items = list(items) + list(extra_items)
    stops, path, dist = plan_route(all_items, layout)
    baseline = baseline_distance(all_items, layout)
    suggestions = build_suggestions(
        items, extra_items, path, layout,
        neighbor_needs=neighbor_needs, pantry_low=pantry_low, forgotten=forgotten,
    )
    return {
        "trip_id": trip_id,
        "store": store,
        "layout": {
            "width_m": layout["width_m"],
            "height_m": layout["height_m"],
            "nodes": [
                {"key": k, "x": v["x"], "y": v["y"]}
                for k, v in layout["nodes"].items()
            ],
        },
        "stops": stops,
        "path": path,
        "distance_m": round(dist, 1),
        "baseline_distance_m": round(baseline, 1),
        "suggestions": suggestions,
        "caps": build_caps(items, extra_items, cap),
    }


# ============================================================================
# FastAPI handler (the only part that touches the DB)
# ============================================================================

class ExtraItem(BaseModel):
    name: str
    qty: int = 1
    section: str = "other"
    requester_id: Optional[str] = None


class RoutePlanRequest(BaseModel):
    trip_id: str
    extra_items: List[ExtraItem] = Field(default_factory=list)


def _first_name(full: str) -> str:
    return (full or "").split()[0] if (full or "").strip() else ""


def _load_trip_data(trip_id: str) -> Tuple[dict, List[dict], Dict[str, str]]:
    """Trip row, its accepted request items as planner dicts, and a
    requester_id -> first name map."""
    from db.client import get_supabase_client

    supabase = get_supabase_client()
    trip_resp = supabase.table("trips").select("*").eq("id", trip_id).execute()
    if not trip_resp.data:
        raise HTTPException(status_code=404, detail="Trip not found")
    trip = trip_resp.data[0]

    reqs = supabase.table("requests").select("*").eq("trip_id", trip_id).eq("status", "accepted").execute()
    items: List[dict] = []
    firsts: Dict[str, str] = {}
    for req in reqs.data:
        rid = str(req["requester_id"])
        if rid not in firsts:
            user = supabase.table("users").select("name").eq("id", rid).execute()
            firsts[rid] = _first_name(user.data[0]["name"]) if user.data else ""
        rows = supabase.table("items").select("*").eq("request_id", req["id"]).execute()
        for row in rows.data:
            items.append({
                "name": row["name"],
                "qty": row.get("qty", 1),
                "section": row.get("section") or "other",
                "max_price": row.get("max_price"),
                "requester_id": rid,
                "requester_first": firsts[rid],
            })
    return trip, items, firsts


def _load_neighbor_needs(shopper_id: str) -> List[dict]:
    """Open needs posted by someone other than the shopper, mapped to items.
    Degrades silently to [] when the table or client is unavailable."""
    try:
        from db.client import get_supabase_client

        supabase = get_supabase_client()
        resp = supabase.table("needs").select("*").eq("status", "open").neq("person_id", shopper_id).limit(20).execute()
        out = []
        for row in resp.data or []:
            hit = extract_need_item(row.get("body") or "")
            if not hit:
                continue
            first = ""
            try:
                user = supabase.table("users").select("name").eq("id", row["person_id"]).execute()
                if user.data:
                    first = _first_name(user.data[0]["name"])
            except Exception:
                pass
            out.append({"name": hit[0], "section": hit[1], "requester_first": first})
        return out
    except Exception:
        return []


def _load_pantry_low(shopper_id: str) -> List[dict]:
    """Latest pantry scan's low_or_empty items. Silently [] if none/unavailable."""
    try:
        from db.client import get_supabase_client

        supabase = get_supabase_client()
        resp = (
            supabase.table("pantry_scans").select("low_or_empty, created_at")
            .eq("user_id", shopper_id).order("created_at", desc=True).limit(1).execute()
        )
        if not resp.data:
            return []
        scan = resp.data[0]
        day = None
        try:
            from shared.timestamps import parse_timestamp
            day = parse_timestamp(scan["created_at"]).strftime("%A")
        except Exception:
            pass
        return [{"name": n, "scanned_day": day} for n in (scan.get("low_or_empty") or [])]
    except Exception:
        return []


def _load_forgotten(shopper_id: str, trip_id: str) -> List[dict]:
    """Items from the shopper's previous trips. Silently [] without history."""
    try:
        from db.client import get_supabase_client

        supabase = get_supabase_client()
        trips = (
            supabase.table("trips").select("id")
            .eq("shopper_id", shopper_id).neq("id", trip_id)
            .order("created_at", desc=True).limit(3).execute()
        )
        out = []
        for t in trips.data or []:
            reqs = supabase.table("requests").select("id").eq("trip_id", t["id"]).execute()
            for req in reqs.data or []:
                rows = supabase.table("items").select("name, section").eq("request_id", req["id"]).execute()
                for row in rows.data or []:
                    out.append({"name": row["name"], "section": row.get("section") or "other"})
        return out
    except Exception:
        return []


@router.post("/plan")
async def plan_route_endpoint(body: RoutePlanRequest):
    """Plan the shortest walk for a trip's merged list plus accepted extras.

    Stateless: accepting a suggestion means re-posting with it in extra_items.
    """
    trip, items, firsts = _load_trip_data(body.trip_id)
    shopper_id = str(trip.get("shopper_id") or "")

    caps_data = trip.get("caps") or {}
    if isinstance(caps_data, str):
        try:
            caps_data = json.loads(caps_data)
        except Exception:
            caps_data = {}
    cap = float(caps_data.get("max_dollars_per_person", DEFAULT_CAP))

    extra_items = []
    for ex in body.extra_items:
        rid = str(ex.requester_id) if ex.requester_id else None
        extra_items.append({
            "name": ex.name,
            "qty": ex.qty,
            "section": ex.section,
            "requester_id": rid,
            "requester_first": firsts.get(rid, "") if rid else "",
            "max_price": None,
        })

    layout = load_layout()
    return build_plan(
        trip_id=body.trip_id,
        store=trip.get("store") or "the store",
        items=items,
        extra_items=extra_items,
        layout=layout,
        cap=cap,
        neighbor_needs=_load_neighbor_needs(shopper_id),
        pantry_low=_load_pantry_low(shopper_id),
        forgotten=_load_forgotten(shopper_id, body.trip_id),
    )
