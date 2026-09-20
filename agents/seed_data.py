"""Seed data for the grocery-favor graph. Seed events, not claims -- the real
extraction pipeline builds the graph, so every reset exercises the actual
system and every claim traces back to a message, not a typed-in table row.

Eight residents with grocery-relevant signal (dietary/mobility/budget/
preference) and a skewed favor history (Sam gives, rarely receives) to
demonstrate reciprocity tracking. No intro/matchmaking narrative -- this
service only tracks favors and grocery-relevant facts, it doesn't propose
that anyone meet anyone.
"""

from datetime import datetime, timedelta, timezone

import asyncpg

import edges as edges_mod
import extraction
import canonicalization

RESIDENTS = [
    "Maya Chen", "Sam Okonkwo", "Priya Raman", "Dev Patel",
    "Elena Vasquez", "Marcus Hill", "Grace Adebayo", "Jordan Reyes",
]

# (body, days_ago). Kept oblique on purpose -- a message that states the fact
# outright proves nothing about the extractor.
SEED_MESSAGES: dict[str, list[tuple[str, float]]] = {
    "Maya Chen": [
        ("trying to eat vegetarian more this year, any easy recipes?", 4),
    ],
    "Sam Okonkwo": [
        ("happy to grab anything while I am at the store, just text me", 8),
        ("I have a car so grocery runs are easy for me, no big deal", 6),
    ],
    "Priya Raman": [
        ("any tips for gluten free bread that doesn't taste like cardboard", 5),
    ],
    "Dev Patel": [
        ("kind of tight on budget this month, trying to stick to a list", 6),
    ],
    "Elena Vasquez": [
        ("always shop at trader joe's for produce, everything else feels wrong", 5),
    ],
    "Marcus Hill": [
        ("my partner has a peanut allergy so I read every label now", 5),
    ],
    "Grace Adebayo": [
        ("I don't have a car anymore so grocery runs are trickier these days", 3),
    ],
    "Jordan Reyes": [
        ("just moved to the building, still figuring out where to shop", 1),
    ],
}

# (giver, receiver, days_ago). Skewed so Sam gives and rarely receives.
SEED_FAVOR_EDGES = [
    ("Sam Okonkwo", "Maya Chen", 9), ("Sam Okonkwo", "Dev Patel", 7),
    ("Sam Okonkwo", "Priya Raman", 5), ("Sam Okonkwo", "Grace Adebayo", 3),
    ("Maya Chen", "Priya Raman", 8), ("Elena Vasquez", "Marcus Hill", 6),
    ("Marcus Hill", "Grace Adebayo", 4), ("Elena Vasquez", "Jordan Reyes", 2),
]

# (person, need body, hours_ago). Open needs for the recommendation feed.
SEED_NEEDS = [
    ("Grace Adebayo", "could someone grab milk and eggs for me this week? can't get to the store", 5),
    ("Priya Raman", "need gluten free bread if anyone is heading to trader joe's", 20),
    ("Dev Patel", "running low on rice and beans, anyone going somewhere cheap?", 30),
    ("Jordan Reyes", "out of coffee and don't know the area yet, any chance someone can grab some?", 2),
]

# Graph tables only. Identities are Supabase Auth accounts + `users` profile
# rows and are never truncated by a seed -- mint them with
# backend/seed/seed_auth_users.py.
_SEED_TABLES = ("needs", "edges", "claims", "events")


# ---------------------------------------------------------------------------
# Additive demo history: builds a dense favor web on top of whoever already
# exists, WITHOUT truncating. Use this against a shared/live database where
# real people (and another team's rows) must survive -- unlike seed(), which
# wipes first.
# ---------------------------------------------------------------------------

# Neighbours added if missing, each with a message that real extraction turns
# into a grocery-relevant claim.
DEMO_NEIGHBORS = [
    ("Maya Chen", "going vegetarian this year so I skip the meat aisle entirely"),
    ("Sam Okonkwo", "I have a car and I'm at the store constantly, happy to grab things"),
    ("Priya Raman", "I'm gluten free so I have to read every label"),
    ("Elena Vasquez", "I always shop at Trader Joe's, everything else feels wrong"),
    ("Grace Adebayo", "I don't have a car and I can't carry heavy bags anymore"),
    ("Dev Patel", "money is tight this month so I'm sticking to a strict list"),
]

# (giver, receiver, days_ago). Shaped so several people have real reciprocity
# and the graph has genuine mutual connections rather than a star.
DEMO_FAVORS = [
    ("Sam Okonkwo", "Ana (Shopper)", 4),
    ("Maya Chen", "Ana (Shopper)", 11),
    ("Sam Okonkwo", "Grace Adebayo", 6),
    ("Sam Okonkwo", "Dev Patel", 9),
    ("Maya Chen", "Priya Raman", 7),
    ("Ana (Shopper)", "Elena Vasquez", 13),
    ("Elena Vasquez", "Maya Chen", 8),
    ("Priya Raman", "Grace Adebayo", 5),
    ("Dev Patel", "Elena Vasquez", 10),
]

# (person, need body, hours_ago)
DEMO_NEEDS = [
    ("Grace Adebayo", "could someone grab milk, eggs and bread for me this week?", 4),
    ("Priya Raman", "need gluten free pasta if anyone is heading to the store", 9),
    ("Dev Patel", "running low on rice and lentils, nothing fancy needed", 22),
    ("Maya Chen", "out of olive oil and coffee, can anyone help?", 31),
    ("Elena Vasquez", "need a big bag of onions if someone has room in the car", 14),
]


class MissingIdentities(RuntimeError):
    """Seed data names someone with no Supabase Auth account + `users` row."""

    def __init__(self, names: list[str]):
        self.names = names
        super().__init__(
            "No auth account for: " + ", ".join(names) + ". "
            "Run `python backend/seed/seed_auth_users.py` to mint them, then retry."
        )


async def _resolve_identities(conn: asyncpg.Connection, names: list[str]) -> dict[str, str]:
    """Map display_name -> id using the `app_people` view.

    This service can no longer create a person: identity is an auth account
    plus a `users` profile row, both minted at signup (or by the auth seeder).
    """
    rows = await conn.fetch(
        "SELECT id, display_name FROM app_people WHERE display_name = ANY($1::text[])",
        names,
    )
    found = {r["display_name"]: str(r["id"]) for r in rows}
    missing = [n for n in names if n not in found]
    if missing:
        raise MissingIdentities(missing)
    return found


async def build_demo_history(conn: asyncpg.Connection) -> dict:
    """Additive. Safe to re-run; safe against a shared database."""
    now = datetime.now(timezone.utc)
    await canonicalization.seed_vocabulary(conn)

    # Every name this function touches, not just the neighbours: the favor and
    # need tables reference people (e.g. "Ana (Shopper)") who aren't in DEMO_NEIGHBORS.
    referenced = (
        [n for n, _ in DEMO_NEIGHBORS]
        + [g for g, _, _ in DEMO_FAVORS] + [r for _, r, _ in DEMO_FAVORS]
        + [n for n, _, _ in DEMO_NEEDS]
    )
    ids = await _resolve_identities(conn, sorted(set(referenced)))

    claims_made = 0
    for name, message in DEMO_NEIGHBORS:
        row = await conn.fetchrow(
            "INSERT INTO events (person_id, kind, body) VALUES ($1, 'message', $2) RETURNING id",
            ids[name], message,
        )
        claims_made += len(await extraction.process_event(conn, str(row["id"]), ids[name], message))

    favors = 0
    for giver, receiver, days_ago in DEMO_FAVORS:
        if giver not in ids or receiver not in ids:
            continue
        created_at = now - timedelta(days=days_ago)
        row = await conn.fetchrow(
            "INSERT INTO events (person_id, kind, body, occurred_at) "
            "VALUES ($1, 'favor_logged', $2, $3) RETURNING id",
            ids[giver], f"helped {receiver} with groceries", created_at,
        )
        await edges_mod.write_edge(
            conn, ids[giver], ids[receiver], "favor",
            event_id=str(row["id"]), created_at=created_at)
        favors += 1

    needs_made = 0
    for name, body, hours_ago in DEMO_NEEDS:
        if name not in ids:
            continue
        created_at = now - timedelta(hours=hours_ago)
        row = await conn.fetchrow(
            "INSERT INTO events (person_id, kind, body, occurred_at) "
            "VALUES ($1, 'message', $2, $3) RETURNING id",
            ids[name], body, created_at,
        )
        await extraction.process_event(conn, str(row["id"]), ids[name], body)
        await conn.execute(
            "INSERT INTO needs (person_id, body, event_id, created_at) VALUES ($1,$2,$3,$4)",
            ids[name], body, str(row["id"]), created_at,
        )
        needs_made += 1

    return {
        "people_resolved": len(ids), "claims_extracted": claims_made,
        "favors_written": favors, "needs_posted": needs_made,
        "people": ids,
    }


async def reset(conn: asyncpg.Connection):
    async with conn.transaction():
        for table in _SEED_TABLES:
            await conn.execute(f"TRUNCATE TABLE {table} CASCADE")


async def seed(conn: asyncpg.Connection, scenario: str = "warm") -> dict:
    await reset(conn)
    await canonicalization.seed_vocabulary(conn)

    # Residents are real auth accounts, not rows this service invents.
    person_ids = await _resolve_identities(conn, RESIDENTS)

    if scenario == "cold":
        return {"scenario": "cold", "person_ids": person_ids}

    now = datetime.now(timezone.utc)

    for name, messages in SEED_MESSAGES.items():
        pid = person_ids[name]
        for body, days_ago in messages:
            occurred_at = now - timedelta(days=days_ago)
            event_row = await conn.fetchrow(
                "INSERT INTO events (person_id, kind, body, occurred_at) "
                "VALUES ($1, 'message', $2, $3) RETURNING id",
                pid, body, occurred_at,
            )
            # Run extraction synchronously during seeding so /admin/seed returns
            # a fully-populated, deterministic graph (replay the log, get the
            # same graph every time).
            await extraction.process_event(conn, str(event_row["id"]), pid, body)

    for giver, receiver, days_ago in SEED_FAVOR_EDGES:
        g_id, r_id = person_ids[giver], person_ids[receiver]
        created_at = now - timedelta(days=days_ago)
        event_row = await conn.fetchrow(
            "INSERT INTO events (person_id, kind, body, occurred_at) "
            "VALUES ($1, 'favor_logged', $2, $3) RETURNING id",
            g_id, f"helped {receiver} with groceries", created_at,
        )
        await edges_mod.write_edge(conn, g_id, r_id, "favor", event_id=str(event_row["id"]), created_at=created_at)

    for name, body, hours_ago in SEED_NEEDS:
        pid = person_ids[name]
        created_at = now - timedelta(hours=hours_ago)
        event_row = await conn.fetchrow(
            "INSERT INTO events (person_id, kind, body, occurred_at) "
            "VALUES ($1, 'message', $2, $3) RETURNING id",
            pid, body, created_at,
        )
        await extraction.process_event(conn, str(event_row["id"]), pid, body)
        await conn.execute(
            "INSERT INTO needs (person_id, body, event_id, created_at) VALUES ($1, $2, $3, $4)",
            pid, body, str(event_row["id"]), created_at,
        )

    return {"scenario": "warm", "person_ids": person_ids}
