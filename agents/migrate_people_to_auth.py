#!/usr/bin/env python3
"""One-shot migration: drop `people`, make Supabase Auth the identity source.

Before:  people (standalone table)  <-- events/claims/edges/needs/graph_metrics

After:   auth.users                 -- identity, the only place a person is born
           ^ FK
         public.users               -- profile: name, circle, venmo
           ^ FK
         events/claims/edges/needs/graph_metrics

`app_people` (a view over users JOIN auth.users) replaces `people` in queries,
exposing the same `id` / `display_name` columns plus `email` and `circle_id`.

Idempotent, safe to re-run. Runs in one transaction: it all lands or none of it.

    python agents/migrate_people_to_auth.py --dry-run
    python agents/migrate_people_to_auth.py
"""

import asyncio
import os
import sys

import asyncpg
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".env"))

# (table, column, nullable), every graph reference to a person.
GRAPH_REFS = [
    ("events", "person_id", False),
    ("claims", "person_id", False),
    ("edges", "src_id", False),
    ("edges", "dst_id", False),
    ("needs", "person_id", False),
    ("needs", "claimed_by", True),
    ("graph_metrics", "person_id", False),
]

APP_PEOPLE_VIEW = """
CREATE OR REPLACE VIEW app_people AS
SELECT u.id,
       u.name        AS display_name,
       a.email       AS email,
       u.circle_id   AS circle_id,
       u.venmo_handle,
       a.created_at  AS joined_at
FROM public.users u
JOIN auth.users a ON a.id = u.id;
"""


async def constraint_names(conn, table: str, column: str, ref_table: str) -> list[str]:
    """FK constraints on table.column pointing at ref_table."""
    rows = await conn.fetch(
        """
        SELECT con.conname
        FROM pg_constraint con
        JOIN pg_class child ON child.oid = con.conrelid
        JOIN pg_class parent ON parent.oid = con.confrelid
        JOIN pg_attribute att ON att.attrelid = child.oid AND att.attnum = ANY (con.conkey)
        WHERE con.contype = 'f'
          AND child.relname = $1
          AND att.attname = $2
          AND parent.relname = $3
        """,
        table, column, ref_table,
    )
    return [r["conname"] for r in rows]


async def preflight(conn) -> list[str]:
    """Everything that would make the migration fail, as a list of problems."""
    problems = []

    has_people = await conn.fetchval("SELECT to_regclass('public.people') IS NOT NULL")

    if has_people:
        orphans = await conn.fetch(
            "SELECT id, display_name FROM people p "
            "WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.id = p.id)"
        )
        for o in orphans:
            problems.append(
                f"people row '{o['display_name']}' ({o['id']}) has no users row, "
                "run backend/seed/seed_auth_users.py first"
            )

    unauthed = await conn.fetch(
        "SELECT id, name FROM users u "
        "WHERE NOT EXISTS (SELECT 1 FROM auth.users a WHERE a.id = u.id)"
    )
    for u in unauthed:
        problems.append(
            f"users row '{u['name']}' ({u['id']}) has no auth account, "
            "run backend/seed/seed_auth_users.py, or delete the row"
        )

    return problems


async def scrub_scratch_rows(conn, dry_run: bool) -> list[str]:
    """Delete users rows with no auth account that nothing references.

    These block the users.id -> auth.users(id) FK. Only rows with zero
    references anywhere are touched; anything else is left for preflight to
    report.
    """
    referencing = [
        ("trips", "shopper_id"), ("requests", "requester_id"),
        ("ledger_events", "user_id"), ("parses", "user_id"),
        ("settlements", "requester_id"), ("substitution_prompts", "requester_id"),
    ]
    has_people = await conn.fetchval("SELECT to_regclass('public.people') IS NOT NULL")
    if has_people:
        referencing += [("people", "id")]

    candidates = await conn.fetch(
        "SELECT id, name FROM users u "
        "WHERE NOT EXISTS (SELECT 1 FROM auth.users a WHERE a.id = u.id)"
    )

    removed = []
    for row in candidates:
        counts = {}
        for table, column in referencing:
            counts[f"{table}.{column}"] = await conn.fetchval(
                f"SELECT count(*) FROM {table} WHERE {column} = $1", row["id"]
            )
        if any(counts.values()):
            continue
        if not dry_run:
            await conn.execute("DELETE FROM users WHERE id = $1", row["id"])
        removed.append(f"{row['name']} ({row['id']})")
    return removed


async def migrate(dry_run: bool = False):
    url = os.getenv("DATABASE_URL")
    if not url:
        print("❌ DATABASE_URL must be set")
        sys.exit(1)

    conn = await asyncpg.connect(url)
    tr = conn.transaction()
    await tr.start()

    try:
        has_people = await conn.fetchval("SELECT to_regclass('public.people') IS NOT NULL")
        if not has_people:
            print("ℹ️  `people` is already gone, re-asserting the FKs and view.")

        removed = await scrub_scratch_rows(conn, dry_run=False)
        if removed:
            print(f"🗑️  Removed {len(removed)} unreferenced users row(s) with no auth account:")
            for r in removed:
                print(f"     {r}")

        problems = await preflight(conn)
        if problems:
            print("\n❌ Preflight failed, nothing was changed:\n")
            for p in problems:
                print(f"   • {p}")
            await tr.rollback()
            await conn.close()
            sys.exit(1)
        print("✅ Preflight clean")

        # 1. Identity: every profile must be a real auth account.
        if not await constraint_names(conn, "users", "id", "users"):
            await conn.execute(
                "ALTER TABLE users ADD CONSTRAINT users_id_auth_fkey "
                "FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE"
            )
            print("🔗 users.id -> auth.users(id)  (ON DELETE CASCADE)")
        else:
            print("🔗 users.id -> auth.users(id)  (already present)")

        # 2. Repoint every graph reference from people to users.
        for table, column, nullable in GRAPH_REFS:
            for name in await constraint_names(conn, table, column, "people"):
                await conn.execute(f"ALTER TABLE {table} DROP CONSTRAINT {name}")
            if await constraint_names(conn, table, column, "users"):
                print(f"   {table}.{column} -> users.id  (already present)")
                continue
            await conn.execute(
                f"ALTER TABLE {table} ADD CONSTRAINT {table}_{column}_users_fkey "
                f"FOREIGN KEY ({column}) REFERENCES users(id) ON DELETE CASCADE"
            )
            print(f"   {table}.{column} -> users.id")

        # 3. people is now unreferenced.
        if has_people:
            await conn.execute("DROP TABLE people")
            print("🗑️  Dropped table `people`")

        # 4. The view the agent service reads identity through.
        await conn.execute(APP_PEOPLE_VIEW)
        n = await conn.fetchval("SELECT count(*) FROM app_people")
        print(f"👁️  View `app_people` ready, {n} people")

        if dry_run:
            print("\n🔙 --dry-run: rolling back")
            await tr.rollback()
        else:
            await tr.commit()
            print("\n✅ Migration committed")
    except Exception:
        await tr.rollback()
        print("\n❌ Migration failed and was rolled back")
        raise
    finally:
        await conn.close()


if __name__ == "__main__":
    asyncio.run(migrate(dry_run="--dry-run" in sys.argv))
