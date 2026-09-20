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
from dataclasses import dataclass, field
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
    "trip": 0.20,          # you already have a trip that covers this
    "capability": 0.20,    # you have the thing or the skill the ask needs
    "reciprocity": 0.15,   # they've helped you before
    "forward": 0.10,       # you helped someone who is tied to them
    "mutual": 0.10,        # you share a connection
    "affinity": 0.10,      # you share the datapoints the ask depends on
    "fit": 0.10,           # your grocery claims complement their need
    "freshness": 0.05,     # tiebreaker only
}

FRESHNESS_HALFLIFE_HOURS = 48.0

# Signals that only mean something for a given kind of ask. A car, a store run
# and a shared diet are reasons to pick up groceries; none of them is a reason
# to hem trousers or walk the reservoir. Anything not listed applies everywhere.
_SIGNAL_CATEGORIES = {
    "fit": {"errand", "ride"},
    "affinity": {"errand"},
}

# An open trip whose departure is this far behind us is a row nobody closed,
# not a plan. Without the bound, yesterday's run is "you're going today" forever.
TRIP_STALE_AFTER = "2 hours"

# Filler stripped when quoting a need back in a reason sentence.
_ASK_FILLER = re.compile(
    r"^(hey |hi |so )?(could|can|would) (someone|anyone|somebody)( please)? |"
    r"^(any chance )?(someone|anyone|somebody) (could|can) |"
    r"^(i('m| am) )?(out of|running low on|low on) |"
    r"^(looking for|need|i need|i could use) (a |an |some )?|"
    r"^(please )?(grab|pick up|get) (me )?(a |an |some )?",
    re.IGNORECASE,
)


@dataclass
class FavorGraph:
    """The edge table, decayed and folded once per ranking call.

    `ties` is undirected and carries the summed, kind-weighted strength of
    everything between two people (favor 1.0 decaying, knows 0.6, same-floor
    neighbor 0.25) -- the number every graph signal below is scaled by.
    `favors` stays directed, because "they helped you" and "you helped them"
    are different facts and only one of them may be said.
    """

    ties: dict[str, dict[str, float]] = field(default_factory=dict)
    kinds: dict[str, dict[str, set]] = field(default_factory=dict)
    # (giver, receiver) -> (decayed strength, count)
    favors: dict[tuple[str, str], tuple[float, int]] = field(default_factory=dict)
    # (giver, receiver) -> title of the latest favor between them, when the
    # favor came through a need. Seeded history has no need behind it.
    favor_titles: dict[tuple[str, str], str] = field(default_factory=dict)
    names: dict[str, str] = field(default_factory=dict)

    def add(self, src: str, dst: str, kind: str, strength: float, count: int = 1) -> None:
        if src == dst:
            return
        for a, b in ((src, dst), (dst, src)):
            self.ties.setdefault(a, {})
            self.ties[a][b] = self.ties[a].get(b, 0.0) + strength
            self.kinds.setdefault(a, {}).setdefault(b, set()).add(kind)
        if kind == "favor":
            s, n = self.favors.get((src, dst), (0.0, 0))
            self.favors[(src, dst)] = (s + strength, n + count)

    def first_name(self, person_id: str) -> str:
        name = self.names.get(person_id) or ""
        return name.split()[0] if name else ""


async def load_favor_graph(conn: asyncpg.Connection, helper_id: str) -> FavorGraph:
    """Three queries however many needs are being ranked (this replaced a
    reciprocity query and a mutuals query per need)."""
    rows = await conn.fetch(
        "SELECT src_id, dst_id, kind, COUNT(*) AS n, "
        "SUM(weight * CASE WHEN kind IN ('favor','co_occurrence') "
        "    THEN EXP(-EXTRACT(EPOCH FROM (now() - created_at)) / $1) ELSE 1 END) AS strength "
        "FROM edges WHERE src_id <> dst_id "
        "GROUP BY src_id, dst_id, kind",
        settings.EDGE_DECAY_SECONDS,
    )
    g = FavorGraph()
    for r in rows:
        g.add(str(r["src_id"]), str(r["dst_id"]), r["kind"], float(r["strength"]), count=int(r["n"]))
    if g.ties:
        people = await conn.fetch(
            "SELECT id, display_name FROM app_people WHERE id = ANY($1::uuid[])",
            list(g.ties.keys()),
        )
        g.names = {str(p["id"]): p["display_name"] or "" for p in people}
    # What this helper actually did, for "who you helped to borrow a ladder".
    done = await conn.fetch(
        "SELECT DISTINCT ON (person_id) person_id, title FROM needs "
        "WHERE status = 'fulfilled' AND claimed_by = $1 AND title IS NOT NULL "
        "ORDER BY person_id, resolved_at DESC NULLS LAST",
        helper_id,
    )
    for r in done:
        g.favor_titles[(helper_id, str(r["person_id"]))] = r["title"]
    return g


def _reciprocity(g: FavorGraph, helper_id: str, needer_id: str) -> tuple[float, int]:
    """Decayed weight of favors the needer has done *for the helper*. This is
    the "they helped you, want to return it" signal."""
    strength, count = g.favors.get((needer_id, helper_id), (0.0, 0))
    return min(strength, 1.0), count


def _mutuals(g: FavorGraph, helper_id: str, needer_id: str) -> list[tuple[str, float]]:
    """(person_id, strength) for everyone tied to both of you, strongest first.

    Strength is the weaker leg of the two-hop path, the same bottleneck rule
    matching.tie_signal uses. Someone you have both traded favors with is a
    real connection; someone who merely shares a floor with each of you is a
    quarter of one. Counting heads, as this used to, scored them the same."""
    mine, theirs = g.ties.get(helper_id, {}), g.ties.get(needer_id, {})
    shared = [
        (pid, min(mine[pid], theirs[pid]))
        for pid in mine.keys() & theirs.keys()
        if pid not in (helper_id, needer_id)
    ]
    return sorted(shared, key=lambda m: (-m[1], g.names.get(m[0], "")))


_FORWARD_RELATION = (
    # Strongest kind of tie between the person you helped and the asker wins.
    ("knows", "knows {needer}"),
    ("favor", "has traded favors with {needer}"),
    ("co_occurrence", "runs into {needer} a lot"),
    ("neighbor", "lives on {needer}'s floor"),
)


def _forward(g: FavorGraph, helper_id: str, needer_id: str) -> tuple[float, str | None, str | None]:
    """Pay it forward: you helped Y, and Y is tied to the person asking.

    Returns (value, via_id, reason). The value is the weaker of "how much you
    did for Y" and "how close Y is to them", so a fresh favor for the asker's
    good friend outranks an old one for someone who shares their hallway. This
    is the path that closes a triangle: a favor for Y's friend turns a two-hop
    tie into a direct one."""
    best: tuple[float, str] | None = None
    for (giver, receiver), (given, _) in g.favors.items():
        if giver != helper_id or receiver == needer_id:
            continue
        tie = g.ties.get(receiver, {}).get(needer_id, 0.0)
        if tie <= 0:
            continue
        value = min(min(given, 1.0), min(tie, 1.0))
        if best is None or value > best[0]:
            best = (value, receiver)
    if best is None:
        return 0.0, None, None

    value, via = best
    via_name, needer_name = g.first_name(via), g.first_name(needer_id)
    if not via_name or not needer_name:
        return value, via, None
    kinds = g.kinds.get(via, {}).get(needer_id, set())
    relation = next((text for kind, text in _FORWARD_RELATION if kind in kinds), None)
    if relation is None:
        return value, via, None
    # Titles are imperative by contract ("Borrow a ladder"), so they read
    # cleanly after "helped to". The rule parser's catch-all keeps the asker's
    # own words ("Help me untangle my bike chain"), which do not: skip those.
    title = (g.favor_titles.get((helper_id, via)) or "").strip().rstrip(".")
    if title and not _FIRST_PERSON.search(title):
        did = f"you helped to {title[0].lower()}{title[1:]}"
    else:
        did = "you recently helped out"
    return value, via, f"{via_name}, who {did}, {relation.format(needer=needer_name)}"


_FIRST_PERSON = re.compile(r"\b(i|me|my|mine|we|us|our)\b", re.IGNORECASE)


async def _upcoming_trip(conn: asyncpg.Connection, helper_id: str) -> dict | None:
    """The helper's next open grocery trip, from the errand-coordination
    backend's `trips` table (same database -- see backend/schema.sql).
    Returns None when that table isn't present, so this service still runs
    standalone against its own Postgres."""
    try:
        row = await conn.fetchrow(
            "SELECT id, store, depart_at FROM trips "
            "WHERE shopper_id = $1 AND (status = 'shopping' OR "
            f"  (status = 'open' AND depart_at > now() - interval '{TRIP_STALE_AFTER}')) "
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
        return 1.0, f"you're going to {store} {when}, the store they asked for"
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
    """Similar-datapoint signal, the competence version of homophily. A
    gluten-free helper shopping a gluten-free ask buys the right bread on the
    first try; same for keto, vegan, budget shoppers. Complements _fit (which
    is about who *can* help): affinity is about who helps *well*. Mobility is
    deliberately excluded: two carless people matching helps no one."""
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
    ask = _ask_sentence(first_name, detail)

    # Ordered by how actionable each signal is, strongest first.
    fragments = []
    if detail.get("invite_reason"):
        fragments.append(detail["invite_reason"].rstrip("."))
    if detail["trip_reason"]:
        fragments.append(detail["trip_reason"])
    if detail.get("capability_reason"):
        fragments.append(detail["capability_reason"])
    if parts["reciprocity"] > 0:
        n = detail["favor_count"]
        fragments.append(
            f"{first_name} helped you out {n} time{'s' if n != 1 else ''} recently"
        )
    if detail.get("forward_reason"):
        fragments.append(detail["forward_reason"])
    # The person a forward path runs through is a mutual by definition. Saying
    # "you helped Nora, who knows Priya, and you both know Nora" is one fact twice.
    mutual_names = [n for n in detail["mutual_names"] if n != detail.get("forward_via_name")]
    if parts["mutual"] > 0 and mutual_names:
        fragments.append(f"you both know {', '.join(mutual_names[:2])}")
    if detail["fit_reason"]:
        fragments.append(detail["fit_reason"])
    if detail.get("affinity_reason"):
        fragments.append(detail["affinity_reason"])

    if not fragments:
        # No connection to draw on -- say the honest thing, and still lead with
        # the ask rather than restating metadata.
        return f"{ask} No one's offered yet."

    lead = fragments[0][0].upper() + fragments[0][1:]
    # The forward fragment already carries two commas; chaining a second
    # fragment onto it reads as a list of three unrelated things.
    if len(fragments) > 1 and fragments[0] != detail.get("forward_reason"):
        lead += f", and {fragments[1]}"
    return f"{lead}. {ask}"


def _ask_sentence(first_name: str, detail: dict) -> str:
    """"Grace needs milk and eggs." is right for an errand and wrong for
    everything else ("Priya needs anyone up for the reservoir loop"). Any
    other favor quotes its title, in the invite copy's own words."""
    title = (detail.get("title") or "").strip().rstrip(".")
    if detail.get("category", "errand") == "errand" or not title:
        return f"{first_name} needs {detail['ask']}."
    return f"{first_name} is hoping for a hand: {title[0].lower()}{title[1:]}."


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
        if not is_proper:
            continue
        # "Swarit's" is one token here, and the facts only ever say "Swarit".
        # Checking it whole rejected every possessive of a neighbor's name --
        # which is the title the prompt asks for ("Untangle Swarit's bike
        # chain") -- and dropped the recommendation with it. The whole token is
        # still tried first so a name that owns its apostrophe ("Joe's") passes.
        lowered = token.lower()
        forms = {lowered, lowered.removesuffix("'s"), lowered.strip("'")}
        if not any(f and (f in allowed or f in _REASON_STOPWORDS) for f in forms):
            return False
    return True


async def recommend_for(conn: asyncpg.Connection, helper_id: str, limit: int = 10) -> list[dict]:
    """Rank open needs posted by other people for this helper."""
    needs = await conn.fetch(
        "SELECT n.id, n.person_id, n.body, n.created_at, p.display_name, "
        "n.category, n.title, n.when_text, n.requires, "
        "i.status AS invite_status "
        "FROM needs n JOIN app_people p ON p.id = n.person_id "
        "LEFT JOIN need_invites i ON i.need_id = n.id AND i.helper_id = $1 "
        "WHERE n.status = 'open' AND n.person_id <> $1 "
        "ORDER BY n.created_at DESC LIMIT 200",
        helper_id,
    )
    if not needs:
        return []

    helper_claims = await _claims(conn, helper_id)
    trip = await _upcoming_trip(conn, helper_id)
    graph = await load_favor_graph(conn, helper_id)
    out = []

    for need in needs:
        needer_id = str(need["person_id"])
        category = need["category"] or "errand"

        trip_score, trip_reason = _trip_signal(trip, need["body"])
        # An open grocery run says nothing about a bookshelf carry or a walk:
        # keep the trip signal only for errands, or when the ask names the store.
        if category != "errand" and trip_score < 1.0:
            trip_score, trip_reason = 0.0, None
        reciprocity, favor_count = _reciprocity(graph, helper_id, needer_id)
        mutuals = _mutuals(graph, helper_id, needer_id)
        mutual_names = [graph.names[pid] for pid, _ in mutuals if graph.names.get(pid)]
        mutual = min(sum(strength for _, strength in mutuals), 1.0)
        forward, forward_via, forward_reason = _forward(graph, helper_id, needer_id)
        needer_claims = await _claims(conn, needer_id)
        fit, fit_reason = _fit(helper_claims, needer_claims)
        affinity, affinity_reason = _affinity(helper_claims, needer_claims, need["body"])
        # Same rule as the trip gate, for the other two grocery-era signals.
        if category not in _SIGNAL_CATEGORIES["fit"]:
            fit, fit_reason = 0.0, None
        if category not in _SIGNAL_CATEGORIES["affinity"]:
            affinity, affinity_reason = 0.0, None
        freshness, age_hours = _freshness(need["created_at"])

        # v2: do I have the thing or the skill this ask depends on?
        import matching as matching_mod
        requires = [
            r for r in (matching_mod._from_jsonb(need["requires"], []) or []) if r
        ]
        cap, cap_headline = matching_mod.capability(
            category, requires, helper_claims,
        )
        cap_reason = None
        if cap > 0 and requires:
            cap_reason = f"you have what they need: {requires[0]}"

        parts = {
            "trip": trip_score,
            "capability": cap,
            "reciprocity": reciprocity,
            "forward": forward,
            "mutual": mutual,
            "fit": fit,
            "affinity": affinity,
            "freshness": freshness,
        }
        score = sum(WEIGHTS[k] * v for k, v in parts.items())
        detail = {
            "favor_count": favor_count,
            "mutual_names": mutual_names,
            "forward_reason": forward_reason,
            "forward_via_name": graph.names.get(forward_via) if forward_via else None,
            "fit_reason": fit_reason,
            "affinity_reason": affinity_reason,
            "trip_reason": trip_reason,
            "capability_reason": cap_reason,
            "ask": _summarize_ask(need["body"]),
            "title": need["title"],
            "category": category,
            "age": _describe_age(age_hours),
        }
        if need["invite_status"] == "pending":
            detail["invite_reason"] = f"{need['display_name'].split()[0]} asked for you"

        out.append({
            "need_id": str(need["id"]),
            "body": need["body"],
            "needer_name": need["display_name"],
            "needer_id": needer_id,
            "ask": detail["ask"],
            "posted": detail["age"],
            "category": need["category"] or "errand",
            "title": need["title"],
            "when_text": need["when_text"],
            "invited": need["invite_status"] == "pending",
            "score": round(score, 4),
            "signals": {k: round(v, 4) for k, v in parts.items()},
            "detail": detail,
            "template_reason": _build_reason(need["display_name"], parts, detail),
        })

    # A pending invite means the asker picked this helper by name: it adds a
    # flat bonus and always sorts first.
    for c in out:
        if c["invited"]:
            c["score"] = round(c["score"] + 0.5, 4)
    out.sort(key=lambda r: (not r["invited"], -r["score"]))
    return out[:limit]


def _reciprocity_fact(needer_name: str, favor_count: int) -> str | None:
    """Stated in the direction it actually happened. Phrased as something they
    did for you, never as something you owe -- the ledger stays out of the copy."""
    if not favor_count:
        return None
    first = needer_name.split()[0]
    times = "once" if favor_count == 1 else f"{favor_count} times"
    return f"{first} helped you out {times} recently"


def _true_facts(c: dict) -> list[str]:
    """Everything the model may say about one candidate, already written in
    second person and already directional, so it can lift a fact almost
    verbatim instead of paraphrasing (and inverting) it.

    This is every signal that fired, not a subset. It used to omit capability
    and affinity, so the model was shown a nonzero capability score with
    nothing to say about it and wrote "No mutual connections noted." for a
    helper whose actual reason was that they own the drill."""
    detail = c["detail"]
    first = c["needer_name"].split()[0]
    # The forward path's middle person is already named in that fact.
    mutuals = [n.split()[0] for n in detail["mutual_names"] if n != detail.get("forward_via_name")]
    facts = [
        detail.get("invite_reason"),
        detail["trip_reason"],
        detail.get("capability_reason"),
        _reciprocity_fact(c["needer_name"], detail["favor_count"]),
        detail.get("forward_reason"),
        f"you and {first} both know {', '.join(mutuals)}" if mutuals else None,
        detail["fit_reason"],
        detail.get("affinity_reason"),
    ]
    return [f for f in facts if f]


# The app's copy has no dashes in it. The prompt says so, but a model that
# slips one in shouldn't put it on someone's home screen, so it is stripped on
# the way out rather than trusted on the way in.
_DASHES = {"\u2014": ", ", "\u2013": ", ", "\u2012": ", "}


def strip_dashes(text: str) -> str:
    for dash, replacement in _DASHES.items():
        text = text.replace(f" {dash} ", replacement).replace(dash, replacement)
    return " ".join(text.split()).replace(" ,", ",")


def _why(c: dict) -> dict:
    """The structured version of the reason: the same facts `_build_reason`
    turns into a sentence, kept separate so a client can draw them instead of
    parsing prose. Every field is derived, never model-written -- the model
    only ever phrases `reason`, and this is what it was phrasing from.

    `weights` rides along so the client can show a signal's contribution
    (weight x value) without hardcoding a copy of WEIGHTS that silently drifts
    when the scoring is retuned."""
    detail = c["detail"]
    return {
        "weights": WEIGHTS,
        "mutual_names": detail["mutual_names"],
        "favor_count": detail["favor_count"],
        "trip_reason": detail["trip_reason"],
        "fit_reason": detail["fit_reason"],
        "affinity_reason": detail["affinity_reason"],
        "capability_reason": detail.get("capability_reason"),
        "forward_reason": detail.get("forward_reason"),
        "forward_via": detail.get("forward_via_name"),
        # The template sentence the graph alone would have produced. When the
        # model wrote `reason`, this is what it replaced -- worth showing side
        # by side in a "how this was decided" view.
        "graph_reason": c["template_reason"],
    }


def _as_suggestion(c: dict, *, title: str, action: str, reason: str, effort: str) -> dict:
    title, action, reason = (strip_dashes(t) for t in (title, action, reason))
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
        "why": _why(c),
        "posted": c["posted"],
        "category": c.get("category", "errand"),
        "when_text": c.get("when_text"),
        "invited": c.get("invited", False),
    }


def _fallback_suggestions(candidates: list[dict]) -> list[dict]:
    """Deterministic version, in the same shape the model would return."""
    out = []
    for c in candidates:
        first = c["needer_name"].split()[0]
        out.append(_as_suggestion(
            c,
            title=(c["title"] or f"Grab {c['ask']} for {first}")[:60],
            action=_fallback_action(c, first),
            reason=c["template_reason"],
            effort="low" if c["signals"]["trip"] > 0 else "medium",
        ))
    return out


def _fallback_action(c: dict, first: str) -> str:
    trip_reason = c["detail"]["trip_reason"]
    if trip_reason:
        # Not .capitalize() -- that lowercases the rest, mangling proper nouns
        # like "Trader Joe's".
        return trip_reason[0].upper() + trip_reason[1:]
    title = (c.get("title") or "").strip().rstrip(".")
    category = c.get("category", "errand")
    # "Pick up" is an errand verb. It used to be the only one, which produced
    # "Pick up anyone up for the reservoir loop for Priya".
    if category == "errand" or not title:
        return f"Pick up {c['ask']} for {first}"
    if _FIRST_PERSON.search(title):
        return f"Give {first} a hand"
    if category == "company":
        return f"{title} with {first}"
    return f"{title} for {first}"


async def suggest_favors(conn: asyncpg.Connection, helper_id: str, limit: int = 10) -> dict:
    """Graph retrieves and scores; the model decides. Returns the structured
    payload the frontend renders."""
    candidates = await recommend_for(conn, helper_id, limit)
    if not candidates:
        return {"person_id": helper_id, "decided_by": "graph", "favors": []}

    by_id = {c["need_id"]: c for c in candidates}
    helper = await conn.fetchrow("SELECT display_name FROM app_people WHERE id = $1", helper_id)
    helper_claims = await _claims(conn, helper_id)
    facts_by_id = {c["need_id"]: _true_facts(c) for c in candidates}

    context = {
        # No `upcoming_trip` here. The helper's store run used to ride along at
        # the top of every request, so the model cited it for walks, bookshelves
        # and hemming alike -- it was the one specific, nameable fact in view.
        # A trip now reaches the model only as a `true_fact` on a candidate it
        # is actually a reason for (see the category gate in recommend_for).
        "helper": {
            "display_name": helper["display_name"] if helper else "",
            "about": [c["raw_label"] for c in helper_claims],
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
                "category": c.get("category", "errand"),
                "title": c.get("title"),
                "when": c.get("when_text"),
                # Only what fired. A row of zeros is a list of things to not
                # mention, and naming them is how they get mentioned.
                "signals": {k: v for k, v in c["signals"].items() if v > 0},
                "true_facts": facts_by_id[c["need_id"]],
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
        # The facts themselves are included: the template sentence only ever
        # uses the top two, so a name from the third was being rejected.
        allowed = " ".join([
            c["needer_name"], c["body"], c["ask"], c["template_reason"],
            c["title"] or "", " ".join(facts_by_id[c["need_id"]]),
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
