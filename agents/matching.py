"""Who should help with this need -- the inverse of recommendations.py.

v2 deliberately reverses the old "no matchmaking" scope: this module ranks
*helpers for a need* (the old scorer ranked needs for a helper). The matcher
optimizes for ties worth forming, not fastest fulfilment: every match carries
a true, specific, human reason; the top three aim for three different kinds
of tie; the super-helper is quietly rested via an internal give_balance that
is never returned and never phrased.

Performance rule: exactly four SQL queries per ranking call (members, their
claims, decayed edges among them, claimed needs + open trips folded into one
statement). No per-pair queries -- the N+1 helpers in recommendations.py are
not used here.
"""

from __future__ import annotations

import difflib
import json
import re
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

import asyncpg
import networkx as nx

from config import settings

# ---------------------------------------------------------------------------
# Context
# ---------------------------------------------------------------------------


@dataclass
class Person:
    id: str
    display_name: str
    first_name: str
    floor: int | None
    unit: str | None
    availability: list[str]
    joined_days: float | None = None  # for "new to the building"


@dataclass
class CircleContext:
    asker_id: str
    people: dict[str, Person]
    claims: dict[str, list[dict]]        # person_id -> active claims >= floor
    G: "nx.Graph"                        # undirected; attrs: strength, favors_ab, favors_ba
    give_balance: dict[str, float]       # INTERNAL. Never returned, never phrased.
    busy: set[str]                       # claimed, unfulfilled need
    has_trip: set[str] = field(default_factory=set)  # open trip right now
    recent: list[str] = field(default_factory=list)  # favor one-liners, LLM context only


def _from_jsonb(value, default):
    if value is None:
        return default
    if isinstance(value, str):
        try:
            return json.loads(value)
        except ValueError:
            return default
    return value


def _int_or_none(value) -> int | None:
    try:
        return int(str(value))
    except (TypeError, ValueError):
        return None


async def load_circle(conn: asyncpg.Connection, person_id: str) -> CircleContext:
    # 1. Everyone in the asker's circle, asker included.
    members = await conn.fetch(
        "SELECT p2.id, p2.display_name, p2.address_unit, p2.address_floor, "
        "p2.availability, p2.joined_at "
        "FROM app_people p1 JOIN app_people p2 ON p2.circle_id = p1.circle_id "
        "WHERE p1.id = $1",
        person_id,
    )
    now = datetime.now(timezone.utc)
    people: dict[str, Person] = {}
    for m in members:
        joined = m["joined_at"]
        if joined is not None and joined.tzinfo is None:
            joined = joined.replace(tzinfo=timezone.utc)
        people[str(m["id"])] = Person(
            id=str(m["id"]),
            display_name=m["display_name"] or "",
            first_name=(m["display_name"] or "").split()[0] if m["display_name"] else "",
            floor=_int_or_none(m["address_floor"]),
            unit=m["address_unit"],
            availability=[str(a) for a in _from_jsonb(m["availability"], [])],
            joined_days=((now - joined).total_seconds() / 86400) if joined else None,
        )
    ids = list(people.keys())

    # 2. Their active claims, in one pass.
    claim_rows = await conn.fetch(
        "SELECT person_id, kind, canonical, raw_label, confidence FROM claims "
        "WHERE person_id = ANY($1::uuid[]) AND superseded_by IS NULL AND confidence >= $2",
        ids, settings.CONFIDENCE_FLOOR,
    )
    claims: dict[str, list[dict]] = {pid: [] for pid in ids}
    for r in claim_rows:
        claims[str(r["person_id"])].append(dict(r))

    # 3. Decayed edges among them, one pass, with per-direction favor strength.
    edge_rows = await conn.fetch(
        "SELECT src_id, dst_id, kind, "
        "SUM(weight * CASE WHEN kind IN ('favor','co_occurrence') "
        "    THEN EXP(-EXTRACT(EPOCH FROM (now() - created_at)) / $2) ELSE 1 END) AS strength "
        "FROM edges WHERE src_id = ANY($1::uuid[]) AND dst_id = ANY($1::uuid[]) "
        "GROUP BY src_id, dst_id, kind",
        ids, settings.EDGE_DECAY_SECONDS,
    )
    G = nx.Graph()
    G.add_nodes_from(ids)
    give_balance = {pid: 0.0 for pid in ids}
    for r in edge_rows:
        a, b = str(r["src_id"]), str(r["dst_id"])
        if a == b:
            continue
        s = float(r["strength"])
        if G.has_edge(a, b):
            G[a][b]["strength"] += s
        else:
            G.add_edge(a, b, strength=s, favors={})
        if r["kind"] == "favor":
            favors = G[a][b]["favors"]
            favors[(a, b)] = favors.get((a, b), 0.0) + s
            give_balance[a] = give_balance.get(a, 0.0) + s
            give_balance[b] = give_balance.get(b, 0.0) - s

    # 4. Who is mid-favor (excluded) and who has an open trip (errand signal).
    status_rows = await conn.fetch(
        "SELECT claimed_by AS pid, 'busy' AS tag FROM needs "
        "WHERE status = 'claimed' AND claimed_by = ANY($1::uuid[]) "
        "UNION ALL "
        "SELECT shopper_id, 'trip' FROM trips "
        "WHERE shopper_id = ANY($1::uuid[]) AND (status = 'shopping' OR "
        # Same bound as recommendations._upcoming_trip: an open trip that left
        # hours ago is an unclosed row, not someone "already heading out".
        "  (status = 'open' AND depart_at > now() - interval '2 hours'))",
        ids,
    )
    busy = {str(r["pid"]) for r in status_rows if r["tag"] == "busy" and r["pid"]}
    has_trip = {str(r["pid"]) for r in status_rows if r["tag"] == "trip" and r["pid"]}

    return CircleContext(
        asker_id=str(person_id), people=people, claims=claims, G=G,
        give_balance=give_balance, busy=busy, has_trip=has_trip,
    )


# ---------------------------------------------------------------------------
# Signals. Each returns (value 0..1, evidence). Pure, unit-testable.
# ---------------------------------------------------------------------------

WEIGHTS = {
    "capability": 0.30, "tie": 0.20, "similarity": 0.15, "reciprocity": 0.10,
    "nearness": 0.10, "availability": 0.10, "balance": 0.05,
}

_SYNONYM_GROUPS = [
    {"ladder", "step ladder"},
    {"drill", "tools", "toolbox", "tool kit"},
    {"car", "truck", "suv"},
    {"handy", "carpentry", "diy", "handy with tools"},
    {"audio setup", "speakers", "sound system", "audio engineering"},
]


def _norm(tag: str) -> str:
    t = re.sub(r"[^a-z0-9 ]", " ", (tag or "").lower()).strip()
    t = " ".join(w[:-1] if w.endswith("s") and len(w) > 3 else w for w in t.split())
    return t


def _synonymous(a: str, b: str) -> bool:
    for group in _SYNONYM_GROUPS:
        hits_a = any(g in a or a in g for g in group)
        hits_b = any(g in b or b in g for g in group)
        if hits_a and hits_b:
            return True
    return False


def _tag_matches(required: str, label: str) -> float:
    """1.0 direct, 0.7 synonym, 0 otherwise."""
    req, lab = _norm(required), _norm(label)
    if not req or not lab:
        return 0.0
    req_tokens, lab_tokens = set(req.split()), set(lab.split())
    if req_tokens <= lab_tokens or lab_tokens <= req_tokens:
        return 1.0
    if difflib.SequenceMatcher(None, req, lab).ratio() >= 0.85:
        return 1.0
    if _synonymous(req, lab):
        return 0.7
    if not settings.MOCK_LLM:
        try:  # embedding cosine >= 0.80 counts as a synonym-level match
            from embeddings import cosine, embed
            if cosine(embed(req), embed(lab)) >= 0.80:
                return 0.7
        except Exception:
            pass
    return 0.0


def _headline_for(claim: dict) -> str:
    label = (claim.get("raw_label") or claim.get("canonical") or "").strip()
    if claim.get("kind") == "has_item":
        return f"Has a {label}"
    if claim.get("kind") == "skill":
        if label.startswith(("handy", "good with")):
            return label[0].upper() + label[1:]
        return f"Can help with {label}"
    if claim.get("kind") == "interest":
        return f"Also into {label}"
    return label.capitalize() if label else ""


def capability(
    category: str, requires: list[str], helper_claims: list[dict], *,
    helper_floor: int | None = None, asker_floor: int | None = None,
    has_open_trip: bool = False, asker_claims: list[dict] | None = None,
) -> tuple[float, str | None]:
    """Match need.requires against the helper's has_item + skill claims."""
    cap_claims = [c for c in helper_claims if c.get("kind") in ("has_item", "skill", "mobility")]
    interests = [c for c in helper_claims if c.get("kind") == "interest"]

    best_val, best_claim = 0.0, None
    if requires:
        per_tag: list[float] = []
        for req in requires:
            tag_best, tag_claim = 0.0, None
            for c in cap_claims:
                for label in (c.get("canonical"), c.get("raw_label")):
                    v = _tag_matches(req, label or "")
                    if v > tag_best:
                        tag_best, tag_claim = v, c
            # company activities live in interest claims
            if category == "company" and tag_best == 0.0:
                for c in interests:
                    for label in (c.get("canonical"), c.get("raw_label")):
                        v = _tag_matches(req, label or "")
                        if v > tag_best:
                            tag_best, tag_claim = v, c
            per_tag.append(tag_best)
            if tag_best > best_val:
                best_val, best_claim = tag_best, tag_claim
        matched = min(per_tag) if per_tag else 0.0
        if matched > 0:
            return matched, _headline_for(best_claim) if best_claim else None

    # Category fallbacks when requires is empty or nothing matched.
    if category == "company":
        shared = _shared_interests(asker_claims or [], helper_claims)
        if shared:
            return 0.5, f"Also into {sorted(shared)[0]}"
        return 0.0, None
    if category == "hands":
        for c in cap_claims:
            label = f"{c.get('canonical', '')} {c.get('raw_label', '')}".lower()
            if "handy" in label or "moving" in label or "carpent" in label or "strong" in label:
                return 0.6, _headline_for(c)
        return 0.3, None
    if category in ("ride", "errand"):
        for c in cap_claims:
            label = f"{c.get('canonical', '')} {c.get('raw_label', '')}".lower()
            if ("car" in label.split() or "has car" in label or "truck" in label) and "no car" not in label:
                return 1.0, "Has a car"
        if has_open_trip:
            return 1.0, "Already heading out on a run"
        return 0.0, None
    if category == "care":
        if helper_floor is not None and helper_floor == asker_floor:
            return 0.6, "Lives on your floor"
        return 0.3, None
    return 0.0, None


def _shared_interests(a_claims: list[dict], b_claims: list[dict]) -> set[str]:
    def labels(cs):
        return {
            (c.get("canonical") or c.get("raw_label") or "").strip().lower()
            for c in cs if c.get("kind") == "interest"
        } - {""}
    return labels(a_claims) & labels(b_claims)


def tie_signal(
    G: "nx.Graph", asker_id: str, helper_id: str, people: dict[str, Person],
) -> tuple[float, str, str, int | None, list[str]]:
    """(value, tie_class, tie_label, hops, path_ids). Hop-minimal path,
    tie-broken by best bottleneck strength."""
    try:
        paths = list(nx.all_shortest_paths(G, asker_id, helper_id))
    except (nx.NetworkXNoPath, nx.NodeNotFound):
        paths = []

    if not paths:
        person = people.get(helper_id)
        if person and person.joined_days is not None and person.joined_days < 30:
            return 0.15, "new", "New to the building", None, []
        return 0.15, "new", "New to you", None, []

    def bottleneck(path):
        return min(G[a][b].get("strength", 0.0) for a, b in zip(path, path[1:]))

    best = max(paths, key=bottleneck)
    hops = len(best) - 1
    if hops == 1:
        return 1.0, "close", "You know each other", 1, best
    if hops == 2:
        mutual = people.get(best[1])
        name = mutual.first_name if mutual else "a neighbor"
        return 0.85, "friend_of_friend", f"Friend of {name}", 2, best
    if hops == 3:
        return 0.55, "extended", "New to you", 3, best
    return 0.30, "extended", "New to you", hops, best


_SIMILARITY_KINDS = {"interest", "preference", "dietary", "availability"}


def similarity(a_claims: list[dict], b_claims: list[dict]) -> tuple[float, list[str]]:
    def labels(cs):
        return {
            (c.get("canonical") or c.get("raw_label") or "").strip().lower()
            for c in cs if c.get("kind") in _SIMILARITY_KINDS
        } - {""}
    shared = sorted(labels(a_claims) & labels(b_claims))
    if len(shared) >= 2:
        return 1.0, shared
    if len(shared) == 1:
        return 0.5, shared
    return 0.0, []


def reciprocity(G: "nx.Graph", asker_id: str, helper_id: str) -> tuple[float, tuple[int, int]]:
    """Decayed favors either direction, capped at 1. Evidence keeps direction:
    (they_helped_you, you_helped_them) as rough counts."""
    if not G.has_edge(asker_id, helper_id):
        return 0.0, (0, 0)
    favors = G[asker_id][helper_id].get("favors", {})
    they = favors.get((helper_id, asker_id), 0.0)
    you = favors.get((asker_id, helper_id), 0.0)
    return min(they + you, 1.0), (round(they + 0.25), round(you + 0.25))


def nearness(asker_floor: int | None, helper_floor: int | None) -> tuple[float, str]:
    """Never a unit number before acceptance."""
    if asker_floor is None or helper_floor is None:
        return 0.3, "in the building"
    delta = helper_floor - asker_floor
    if delta == 0:
        return 1.0, "same floor"
    direction = "up" if delta > 0 else "down"
    n = abs(delta)
    if n == 1:
        return 0.8, f"1 floor {direction}"
    if n <= 3:
        return 0.6, f"{n} floors {direction}"
    return 0.4, f"{n} floors {direction}"


_DAY_TOKENS = {
    "monday": "mon", "tuesday": "tue", "wednesday": "wed", "thursday": "thu",
    "friday": "fri", "saturday": "sat", "sunday": "sun",
}


def _target_days(when_text: str | None, now: datetime) -> set[str]:
    if not when_text:
        return set()
    lowered = when_text.lower()
    days: set[str] = set()
    for full, short in _DAY_TOKENS.items():
        if full[:5] in lowered or re.search(rf"\b{short}\b", lowered):
            days.add(short)
    if "today" in lowered or "tonight" in lowered or lowered.startswith(("at ", "around ")):
        days.add(now.strftime("%a").lower()[:3])
    if "tomorrow" in lowered:
        days.add((now + timedelta(days=1)).strftime("%a").lower()[:3])
    if "weekend" in lowered:
        days |= {"sat", "sun"}
    return days


def availability_signal(
    person_availability: list[str], helper_claims: list[dict],
    when_text: str | None, now: datetime,
) -> float:
    """users.availability + availability claims vs when_text + today.
    Match 1.0, unknown 0.5, conflict 0.2."""
    _days = {"mon", "tue", "wed", "thu", "fri", "sat", "sun"}
    tokens = {a.strip().lower()[:3] for a in person_availability if a} & _days
    full = {a.strip().lower() for a in person_availability if a}
    claim_text = " ".join(
        (c.get("canonical") or c.get("raw_label") or "").lower()
        for c in helper_claims if c.get("kind") == "availability"
    )
    if "every day" in full or "everyday" in full or "works from home" in claim_text:
        return 1.0
    targets = _target_days(when_text, now)
    if not targets:
        return 0.5 if (tokens or claim_text) else 0.5
    if "mon to fri" in full or "weekday" in full:
        tokens |= {"mon", "tue", "wed", "thu", "fri"}
    if "free weekends" in claim_text or "weekend" in claim_text:
        tokens |= {"sat", "sun"}
    if "free afternoons" in claim_text or "evenings" in full or "afternoon" in claim_text:
        # time-of-day availability says nothing about the day: treat as open
        if not tokens:
            return 1.0
    if not tokens:
        return 0.5
    return 1.0 if targets & tokens else 0.2


def balance_factor(gb: float, circle_median: float) -> float:
    """Internal. 1.0 normally, 0.4 when far above the circle median. No
    evidence. Never in copy, context, or the API."""
    return 0.4 if gb >= circle_median + 1.5 else 1.0


# ---------------------------------------------------------------------------
# Ranking
# ---------------------------------------------------------------------------


def rank_helpers(ctx: CircleContext, need: dict, now: datetime | None = None, limit: int = 3) -> list[dict]:
    """Score every eligible circle member for this need. Returns candidate
    dicts in contract shape (reason = deterministic template; phrasing is the
    route's job). give_balance never leaves this function."""
    now = now or datetime.now(timezone.utc)
    asker = ctx.people.get(ctx.asker_id)
    asker_claims = ctx.claims.get(ctx.asker_id, [])
    category = need.get("category") or "errand"
    requires = [r for r in (need.get("requires") or []) if r]
    when_text = need.get("when_text")

    balances = sorted(ctx.give_balance.values()) or [0.0]
    median = balances[len(balances) // 2]

    candidates = []
    for pid, person in ctx.people.items():
        if pid == ctx.asker_id or pid in ctx.busy:
            continue
        helper_claims = ctx.claims.get(pid, [])

        cap, headline = capability(
            category, requires, helper_claims,
            helper_floor=person.floor, asker_floor=asker.floor if asker else None,
            has_open_trip=pid in ctx.has_trip, asker_claims=asker_claims,
        )
        if category == "borrow" and cap <= 0:
            continue  # hard filter: you cannot lend what you do not have

        tie_val, tie_class, tie_label, hops, path_ids = tie_signal(ctx.G, ctx.asker_id, pid, ctx.people)
        sim_val, shared = similarity(asker_claims, helper_claims)
        rec_val, (they_n, you_n) = reciprocity(ctx.G, ctx.asker_id, pid)
        near_val, where = nearness(asker.floor if asker else None, person.floor)
        avail_val = availability_signal(person.availability, helper_claims, when_text, now)
        bal_val = balance_factor(ctx.give_balance.get(pid, 0.0), median)

        signals = {
            "capability": round(cap, 3), "tie": round(tie_val, 3),
            "similarity": round(sim_val, 3), "reciprocity": round(rec_val, 3),
            "nearness": round(near_val, 3), "availability": round(avail_val, 3),
            "balance": round(bal_val, 3),
        }
        score = sum(WEIGHTS[k] * v for k, v in signals.items())

        mutual_names = []
        if hops == 2 and len(path_ids) == 3:
            mid = ctx.people.get(path_ids[1])
            if mid:
                mutual_names.append(mid.display_name)

        candidates.append({
            "person": person,
            "person_id": pid,
            "score": score,
            "signals": signals,
            "tie": tie_class,
            "tie_label": tie_label,
            "hops": hops,
            "path_ids": path_ids,
            "headline": headline,
            "where": where,
            "shared": shared,
            "mutual_names": mutual_names,
            "favors_they_did_for_you": they_n,
            "favors_you_did_for_them": you_n,
        })

    candidates.sort(key=lambda c: c["score"], reverse=True)
    top = candidates[:limit]

    # Diversity rule: three of the same tie class is a worse story than two
    # plus a different face, when the swap costs little.
    if len(top) == limit and limit >= 3:
        classes = {c["tie"] for c in top}
        if len(classes) == 1:
            threshold = 0.8 * top[-1]["score"]
            alt = next(
                (c for c in candidates[limit:] if c["tie"] not in classes and c["score"] >= threshold),
                None,
            )
            if alt is not None:
                top[-1] = alt
    return top


# ---------------------------------------------------------------------------
# Facts and phrasing (graph finds, model phrases, validator checks)
# ---------------------------------------------------------------------------

_SPARK_PHRASES = {
    "formula 1": "follow Formula 1",
    "chess": "play chess",
    "climbing": "climb",
    "running": "run",
    "walking": "like an evening walk",
    "gardening": "garden",
    "dog owner": "have dogs",
    "yoga": "do yoga",
    "baking": "bake",
    "works from home": "work from home",
    "vegetarian": "eat vegetarian",
    "gluten free": "keep it gluten free",
}


def spark_for(shared: list[str]) -> str | None:
    if not shared:
        return None
    label = shared[0]
    phrase = _SPARK_PHRASES.get(label)
    if phrase:
        return f"You both {phrase}."
    return f"You both mentioned {label}."


def candidate_facts(ctx: CircleContext, c: dict, asker_first: str) -> list[str]:
    """True, deterministic, second-person facts the model may phrase from."""
    person: Person = c["person"]
    facts: list[str] = []
    if c["headline"]:
        facts.append(f"{c['headline']}.")
    facts.append(f"{person.first_name} is {c['where']} from you.")
    if c["tie"] == "close":
        facts.append(f"You and {person.first_name} know each other.")
    elif c["tie"] == "friend_of_friend" and c["mutual_names"]:
        facts.append(f"You both know {c['mutual_names'][0].split()[0]}.")
    elif c["tie"] == "new":
        if person.joined_days is not None and person.joined_days < 30:
            facts.append(f"{person.first_name} is new to the building.")
            facts.append(f"This would be {person.first_name}'s first favor here.")
        else:
            facts.append(f"You two have not crossed paths yet.")
    if c["favors_they_did_for_you"] > 0:
        facts.append(f"{person.first_name} helped you out recently.")
    if person.availability:
        facts.append(f"Usually free: {', '.join(person.availability[:3])}.")
    if not ctx.G.degree(ctx.asker_id):
        facts.append("This would be your first favor in the building.")
    return facts


def template_reason(c: dict) -> str:
    """Headline + strongest human fact. The fallback when the model is off or
    fails validation."""
    person: Person = c["person"]
    bits = []
    if c["headline"]:
        bits.append(c["headline"])
    if c["tie"] == "close":
        bits.append("you know each other")
    elif c["tie"] == "friend_of_friend" and c["mutual_names"]:
        bits.append(f"you both know {c['mutual_names'][0].split()[0]}")
    elif c["favors_they_did_for_you"] > 0:
        bits.append(f"{person.first_name} helped you out recently")
    elif c["tie"] == "new" and person.joined_days is not None and person.joined_days < 30:
        bits.append(f"this would be {person.first_name}'s first favor here")
    else:
        bits.append(f"{person.first_name} is {c['where']}")
    lead = bits[0][0].upper() + bits[0][1:] if bits[0] else ""
    if len(bits) > 1:
        return f"{lead}, and {bits[1]}."
    return f"{lead}."
