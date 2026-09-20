"""Which open needs should *you* help with, and why.

Two stages, deliberately split:

1. **The graph retrieves and scores.** SQL finds open needs; arithmetic scores
   each on trip/reciprocity/mutual/fit/freshness. Bounded -- the model never
   scans raw history, it sees a fixed-size context however big the graph gets.
2. **The model decides.** It gets that context and chooses which favors are
   actually worth surfacing, in what order, and how to frame each one. It can
   reorder and drop; it cannot invent, because every need_id it returns is
   checked against the candidates it was given, and every name/number in its
   text is checked against the facts.

If the model is unavailable (no key, API error, failed validation) the
deterministic ranking is returned instead, in the identical response shape --
so the frontend contract never changes.
"""

import math
import re
from datetime import datetime, timezone

import asyncpg

import llm
from config import settings

# What a recommendation is scored on. `trip` leads because it's the premise of
# the product: the cheapest favor to do is one on a trip you're already making.
# A real prior favor outweighs a structural coincidence -- being mutuals is a
# nudge, owing someone is not. Freshness is a tiebreaker and never produces a
# reason of its own ("posted recently" is not a reason to help anyone).
WEIGHTS = {
    "trip": 0.30,          # you already have a trip that covers this
    "reciprocity": 0.25,   # they've helped you before
    "mutual": 0.15,        # you share a connection
    "fit": 0.15,           # your grocery claims complement their need
    "affinity": 0.10,      # you share the datapoints the ask depends on
    "freshness": 0.05,     # tiebreaker only
}

FRESHNESS_HALFLIFE_HOURS = 48.0

# Filler stripped when quoting a need back in a reason sentence.
_ASK_FILLER = re.compile(
    r"^(hey |hi |so )?(could|can|would) (someone|anyone|somebody)( please)? |"
    r"^(any chance )?(someone|anyone|somebody) (could|can) |"
    r"^(i('m| am) )?(out of|running low on|low on) |"
    r"^(looking for|need|i need|i could use) (a |an |some )?|"
    r"^(please )?(grab|pick up|get) (me )?(a |an |some )?",
    re.IGNORECASE,
)


async def _reciprocity(conn: asyncpg.Connection, helper_id: str, needer_id: str) -> tuple[float, int]:
    """Decayed weight of favors the needer has done *for the helper*. This is
    the "they helped you, want to return it" signal."""
    row = await conn.fetchrow(
        "SELECT COALESCE(SUM(weight * EXP(-EXTRACT(EPOCH FROM (now() - created_at)) / $3)), 0) AS s, "
        "       COUNT(*) AS n "
        "FROM edges WHERE src_id = $1 AND dst_id = $2 AND kind = 'favor'",
        needer_id, helper_id, settings.EDGE_DECAY_SECONDS,
    )
    return min(float(row["s"]), 1.0), int(row["n"])


async def _mutuals(conn: asyncpg.Connection, helper_id: str, needer_id: str) -> list[str]:
    """Names of people both of you have exchanged favors with."""
    rows = await conn.fetch(
        """
        SELECT p.display_name FROM people p WHERE p.id IN (
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
        helper_id, needer_id,
    )
    return [r["display_name"] for r in rows]


async def _upcoming_trip(conn: asyncpg.Connection, helper_id: str) -> dict | None:
    """The helper's next open grocery trip, from the errand-coordination
    backend's `trips` table (same database -- see backend/schema.sql).
    Returns None when that table isn't present, so this service still runs
    standalone against its own Postgres."""
    try:
        row = await conn.fetchrow(
            "SELECT id, store, depart_at FROM trips "
            "WHERE shopper_id = $1 AND status IN ('open', 'shopping') "
            "ORDER BY depart_at ASC LIMIT 1",
            helper_id,
        )
    except asyncpg.exceptions.UndefinedTableError:
        return None
    if not row:
        return None
    return {"id": str(row["id"]), "store": row["store"], "depart_at": row["depart_at"]}


def _trip_signal(trip: dict | None, need_body: str) -> tuple[float, str | None]:
    """Strongest when the need names the store you're already going to."""
    if not trip:
        return 0.0, None
    when = _describe_when(trip["depart_at"])
    store = trip["store"]
    if store and store.lower() in need_body.lower():
        return 1.0, f"you're going to {store} {when} — the store they asked for"
    return 0.7, f"you're already going to {store} {when}"


def _describe_when(depart_at: datetime) -> str:
    if depart_at.tzinfo is None:
        depart_at = depart_at.replace(tzinfo=timezone.utc)
    delta_h = (depart_at - datetime.now(timezone.utc)).total_seconds() / 3600
    if delta_h < 0:
        return "today"
    if delta_h < 24:
        hour = depart_at.hour % 12 or 12
        return f"at {hour}:{depart_at.minute:02d}{'am' if depart_at.hour < 12 else 'pm'}"
    if delta_h < 48:
        return "tomorrow"
    return f"in {int(delta_h / 24)} days"


def _summarize_ask(body: str) -> str:
    """Short version of the need for use inside a reason sentence. Presentation
    only -- the full body is always returned alongside it."""
    ask = body.split("?")[0].split(".")[0].split(",")[0].strip()
    # Each alternative is ^-anchored, so one sub() pass only strips the
    # outermost prefix ("could someone grab X" -> "grab X"). Repeat to peel.
    for _ in range(3):
        stripped = _ASK_FILLER.sub("", ask).strip()
        if stripped == ask:
            break
        ask = stripped
    words = ask.split()
    if len(words) > 8:
        ask = " ".join(words[:8]) + "…"
    return ask or body[:40]


async def _claims(conn: asyncpg.Connection, person_id: str) -> list[dict]:
    rows = await conn.fetch(
        "SELECT kind, canonical, raw_label FROM claims "
        "WHERE person_id = $1 AND superseded_by IS NULL AND confidence >= $2",
        person_id, settings.CONFIDENCE_FLOOR,
    )
    return [dict(r) for r in rows]


_NEGATION = re.compile(r"\b(no|not|don'?t|doesn'?t|can'?t|without|lost|lack)\b", re.IGNORECASE)
_CAR = re.compile(r"\b(cars?|vehicle|driv\w*)\b", re.IGNORECASE)
_NO_TRANSPORT = re.compile(r"\b(carry|carrying|bags?|store|transport|bus|walk\w*)\b", re.IGNORECASE)


def _mobility(claims: list[dict]) -> tuple[bool, bool]:
    """(has_transport, lacks_transport) from a person's mobility claims.

    Matched on label text rather than an exact canonical string: real
    extraction produces "car access", "has a car", "no car anymore" and
    canonicalization won't always land them on one label, so exact matching
    silently drops the signal.
    """
    has = lacks = False
    for c in claims:
        if c.get("kind") != "mobility":
            continue
        text = f"{c.get('canonical', '')} {c.get('raw_label', '')}".lower()
        negated = bool(_NEGATION.search(text))
        # Word-boundary, not substring: "carrying" contains "car", and reading
        # "needs help carrying bags" as car ownership tells someone who just
        # said they have no car that they have one.
        if _CAR.search(text):
            lacks = lacks or negated
            has = has or not negated
        elif _NO_TRANSPORT.search(text):
            lacks = True  # "can't get to the store", "trouble carrying bags"
    return has, lacks


def _fit(helper_claims: list[dict], needer_claims: list[dict]) -> tuple[float, str | None]:
    """Grocery-scoped complementarity. Mobility is the signal that actually
    decides who can help whom -- dietary/budget/preference describe what to
    buy, not who should go."""
    helper_has, _ = _mobility(helper_claims)
    _, needer_lacks = _mobility(needer_claims)

    if helper_has and needer_lacks:
        return 1.0, "you have a car and they don't"
    if helper_has:
        return 0.4, "you have a car"
    return 0.0, None


_AFFINITY_KINDS = {"dietary", "preference", "budget"}


def _claim_label(c: dict) -> str:
    return (c.get("canonical") or c.get("raw_label") or "").strip().lower()


def _affinity(helper_claims: list[dict], needer_claims: list[dict], need_body: str) -> tuple[float, str | None]:
    """Similar-datapoint signal — the competence version of homophily. A
    gluten-free helper shopping a gluten-free ask buys the right bread on the
    first try; same for keto, vegan, budget shoppers. Complements _fit (which
    is about who *can* help): affinity is about who helps *well*. Mobility is
    deliberately excluded — two carless people matching helps no one."""
    helper = {_claim_label(c) for c in helper_claims if c.get("kind") in _AFFINITY_KINDS}
    needer = {_claim_label(c) for c in needer_claims if c.get("kind") in _AFFINITY_KINDS}
    helper.discard(""); needer.discard("")
    shared = helper & needer
    if shared:
        label = sorted(shared, key=len, reverse=True)[0]
        return (1.0 if len(shared) > 1 else 0.7), f"you both mentioned {label}"
    body = need_body.lower()
    known = sorted((l for l in helper if len(l) > 3 and l in body), key=len, reverse=True)
    if known:
        return 0.5, f"you know your way around {known[0]}"
    return 0.0, None


def _freshness(created_at: datetime) -> tuple[float, float]:
    hours = (datetime.now(timezone.utc) - created_at).total_seconds() / 3600
    return math.exp(-max(hours, 0) / FRESHNESS_HALFLIFE_HOURS), hours


def _describe_age(hours: float) -> str:
    if hours < 1:
        return "just now"
    if hours < 24:
        return f"{int(hours)}h ago"
    return f"{int(hours / 24)}d ago"


def _build_reason(needer_name: str, parts: dict, detail: dict) -> str:
    """Assembled only from signals that fired -- never generated, so it can't
    assert anything the graph doesn't hold. Always names the actual ask: the
    point is "why you, for this", not "here is a thing that exists"."""
    first_name = needer_name.split()[0]
    ask = detail["ask"]

    # Ordered by how actionable each signal is, strongest first.
    fragments = []
    if detail["trip_reason"]:
        fragments.append(detail["trip_reason"])
    if parts["reciprocity"] > 0:
        n = detail["favor_count"]
        fragments.append(
            f"{first_name} picked up groceries for you {n} time{'s' if n != 1 else ''} recently"
        )
    if parts["mutual"] > 0:
        fragments.append(f"you both know {', '.join(detail['mutual_names'][:2])}")
    if detail["fit_reason"]:
        fragments.append(detail["fit_reason"])
    if detail.get("affinity_reason"):
        fragments.append(detail["affinity_reason"])

    if not fragments:
        # No connection to draw on -- say the honest thing, and still lead with
        # the ask rather than restating metadata.
        return f"{first_name} needs {ask}. No one's offered yet."

    lead = fragments[0][0].upper() + fragments[0][1:]
    if len(fragments) > 1:
        lead += f", and {fragments[1]}"
    return f"{lead} — {first_name} needs {ask}."


_REASON_STOPWORDS = {
    "you", "your", "they", "them", "their", "and", "the", "a", "an", "is", "are",
    "was", "were", "to", "for", "of", "at", "on", "in", "it", "no", "not", "yet",
    "needs", "need", "already", "going", "picked", "up", "groceries", "recently",
    "both", "know", "mentioned", "having", "car", "one", "offered", "store",
    "asked", "time", "times", "since", "help", "helped", "grab", "get", "some",
    "today", "tomorrow", "days", "anyone", "someone", "still", "while", "there",
    "who", "this", "that", "with", "has", "have", "had", "been", "will", "can",
    "could", "would", "just", "now", "out", "run", "low", "week", "run's",
}


def validate_reason(text: str, allowed_text: str) -> bool:
    """Reject phrasing that introduces a proper noun or number the facts don't
    contain. Cheap, but it catches the failure that matters: a plausible,
    checkable, wrong detail about a neighbor."""
    allowed = allowed_text.lower()
    for match in re.finditer(r"[A-Za-z']+|\d+", text):
        token = match.group()
        if token.isdigit():
            if token not in allowed:
                return False
            continue
        prefix = text[: match.start()].rstrip()
        at_sentence_start = prefix == "" or prefix[-1] in ".!?—-"
        is_proper = token[0].isupper() and not at_sentence_start
        if is_proper and token.lower() not in allowed and token.lower() not in _REASON_STOPWORDS:
            return False
    return True


async def recommend_for(conn: asyncpg.Connection, helper_id: str, limit: int = 10) -> list[dict]:
    """Rank open needs posted by other people for this helper."""
    needs = await conn.fetch(
        "SELECT n.id, n.person_id, n.body, n.created_at, p.display_name "
        "FROM needs n JOIN people p ON p.id = n.person_id "
        "WHERE n.status = 'open' AND n.person_id <> $1 "
        "ORDER BY n.created_at DESC LIMIT 200",
        helper_id,
    )
    if not needs:
        return []

    helper_claims = await _claims(conn, helper_id)
    trip = await _upcoming_trip(conn, helper_id)
    out = []

    for need in needs:
        needer_id = str(need["person_id"])

        trip_score, trip_reason = _trip_signal(trip, need["body"])
        reciprocity, favor_count = await _reciprocity(conn, helper_id, needer_id)
        mutual_names = await _mutuals(conn, helper_id, needer_id)
        mutual = min(len(mutual_names) / 2.0, 1.0)
        needer_claims = await _claims(conn, needer_id)
        fit, fit_reason = _fit(helper_claims, needer_claims)
        affinity, affinity_reason = _affinity(helper_claims, needer_claims, need["body"])
        freshness, age_hours = _freshness(need["created_at"])

        parts = {
            "trip": trip_score,
            "reciprocity": reciprocity,
            "mutual": mutual,
            "fit": fit,
            "affinity": affinity,
            "freshness": freshness,
        }
        score = sum(WEIGHTS[k] * v for k, v in parts.items())
        detail = {
            "favor_count": favor_count,
            "mutual_names": mutual_names,
            "fit_reason": fit_reason,
            "affinity_reason": affinity_reason,
            "trip_reason": trip_reason,
            "ask": _summarize_ask(need["body"]),
            "age": _describe_age(age_hours),
        }

        out.append({
            "need_id": str(need["id"]),
            "body": need["body"],
            "needer_name": need["display_name"],
            "needer_id": needer_id,
            "ask": detail["ask"],
            "posted": detail["age"],
            "score": round(score, 4),
            "signals": {k: round(v, 4) for k, v in parts.items()},
            "detail": detail,
            "template_reason": _build_reason(need["display_name"], parts, detail),
        })

    out.sort(key=lambda r: r["score"], reverse=True)
    return out[:limit]


def _reciprocity_fact(needer_name: str, favor_count: int) -> str | None:
    """Stated in the direction it actually happened. Phrased as something they
    did for you, never as something you owe -- the ledger stays out of the copy."""
    if not favor_count:
        return None
    first = needer_name.split()[0]
    times = "once" if favor_count == 1 else f"{favor_count} times"
    return f"{first} picked up groceries for you {times} recently"


def _as_suggestion(c: dict, *, title: str, action: str, reason: str, effort: str) -> dict:
    return {
        "need_id": c["need_id"],
        "title": title,
        "action": action,
        "requested_by": {"id": c["needer_id"], "display_name": c["needer_name"]},
        "original_request": c["body"],
        "reason": reason,
        "effort": effort,
        "score": c["score"],
        "signals": c["signals"],
        "posted": c["posted"],
    }


def _fallback_suggestions(candidates: list[dict]) -> list[dict]:
    """Deterministic version, in the same shape the model would return."""
    out = []
    for c in candidates:
        first = c["needer_name"].split()[0]
        out.append(_as_suggestion(
            c,
            title=f"Grab {c['ask']} for {first}"[:60],
            action=(
                # Not .capitalize() -- that lowercases the rest, mangling
                # proper nouns like "Trader Joe's".
                c["detail"]["trip_reason"][0].upper() + c["detail"]["trip_reason"][1:]
                if c["detail"]["trip_reason"]
                else f"Pick up {c['ask']} for {first}"
            ),
            reason=c["template_reason"],
            effort="low" if c["signals"]["trip"] > 0 else "medium",
        ))
    return out


async def suggest_favors(conn: asyncpg.Connection, helper_id: str, limit: int = 10) -> dict:
    """Graph retrieves and scores; the model decides. Returns the structured
    payload the frontend renders."""
    candidates = await recommend_for(conn, helper_id, limit)
    if not candidates:
        return {"person_id": helper_id, "decided_by": "graph", "favors": []}

    by_id = {c["need_id"]: c for c in candidates}
    helper = await conn.fetchrow("SELECT display_name FROM people WHERE id = $1", helper_id)
    helper_claims = await _claims(conn, helper_id)
    trip = await _upcoming_trip(conn, helper_id)

    context = {
        "helper": {
            "display_name": helper["display_name"] if helper else "",
            "about": [c["raw_label"] for c in helper_claims],
            "upcoming_trip": (
                {"store": trip["store"], "when": _describe_when(trip["depart_at"])}
                if trip else None
            ),
        },
        # Facts are handed over pre-phrased and directional. A bare
        # `favor_count: 2` invites the model to invert who helped whom -- and
        # "you helped them" when they helped you is exactly the plausible,
        # checkable, wrong detail that destroys trust in a reason.
        "candidates": [
            {
                "need_id": c["need_id"],
                "request": c["body"],
                "asked_for": c["ask"],
                "neighbor": c["needer_name"],
                "posted": c["posted"],
                "signals": c["signals"],
                # Already written in second person, addressed to the helper, so
                # the model can lift them almost verbatim instead of
                # paraphrasing (and inverting) them.
                "true_facts": [
                    f
                    for f in [
                        _reciprocity_fact(c["needer_name"], c["detail"]["favor_count"]),
                        (
                            f"you and {c['needer_name'].split()[0]} both know "
                            + ", ".join(n.split()[0] for n in c["detail"]["mutual_names"])
                            if c["detail"]["mutual_names"]
                            else None
                        ),
                        c["detail"]["trip_reason"],
                        c["detail"]["fit_reason"],
                    ]
                    if f
                ],
            }
            for c in candidates
        ],
    }

    decided = llm.decide_favors(context)
    if not decided:
        return {"person_id": helper_id, "decided_by": "graph",
                "favors": _fallback_suggestions(candidates)}

    favors = []
    for item in decided:
        c = by_id.get(str(item.get("need_id", "")))
        if c is None:
            continue  # model referenced a need it wasn't given -- drop it

        title = str(item.get("title", "")).strip()
        action = str(item.get("action", "")).strip()
        reason = str(item.get("reason", "")).strip()
        if not (title and action and reason):
            continue

        # Every name/number in the model's text must trace back to the facts.
        allowed = " ".join([
            c["needer_name"], c["body"], c["ask"], c["template_reason"],
            " ".join(c["detail"]["mutual_names"]), c["detail"]["trip_reason"] or "",
            helper["display_name"] if helper else "",
        ])
        if not all(validate_reason(t, allowed) for t in (title, action, reason)):
            continue

        effort = item.get("effort")
        favors.append(_as_suggestion(
            c, title=title, action=action, reason=reason,
            effort=effort if effort in ("low", "medium", "high") else "medium",
        ))

    if not favors:  # model dropped or failed everything -- don't return nothing
        return {"person_id": helper_id, "decided_by": "graph",
                "favors": _fallback_suggestions(candidates)}

    return {"person_id": helper_id, "decided_by": "model", "favors": favors}
