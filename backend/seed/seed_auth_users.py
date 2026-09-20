#!/usr/bin/env python3
"""Mint the demo cast as real Supabase Auth accounts with fake emails.

Identity order matters: `users.id` references `auth.users(id)`, so the auth
account is always created first and the profile row second.

Two jobs:

1. Any existing `users` row without an auth account gets one, with its **id
   pinned** to the id the row already has — so trips, ledger entries and the
   whole favor graph keep pointing at the same uuid.
2. Any name the agent service's seed data needs (agents/seed_data.py
   RESIDENTS) that has no profile at all gets a fresh auth account and a
   matching `users` row.

Idempotent — safe to re-run. Accounts it did not create are left alone unless
you pass --adopt, which resets their password to the dev one.

    python backend/seed/seed_auth_users.py
    python backend/seed/seed_auth_users.py --adopt
"""

import ast
import os
import re
import sys
from pathlib import Path

from dotenv import load_dotenv
from supabase import create_client, Client

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

load_dotenv()

EMAIL_DOMAIN = os.getenv("DEV_EMAIL_DOMAIN", "favorly.test")
DEV_PASSWORD = os.getenv("DEV_PASSWORD", "favorly-dev-2024")
REPO_ROOT = Path(__file__).resolve().parents[2]

# Named by the agent service's demo history but not in its RESIDENTS list.
EXTRA_CAST = ["Ana (Shopper)"]


def agent_residents() -> list[str]:
    """RESIDENTS from agents/seed_data.py — read, not duplicated, so the two
    seeders can't drift. Returns [] if the agent service isn't checked out."""
    path = REPO_ROOT / "agents" / "seed_data.py"
    if not path.exists():
        return []
    match = re.search(r"^RESIDENTS\s*=\s*(\[.*?\])", path.read_text(), re.S | re.M)
    return ast.literal_eval(match.group(1)) if match else []


def get_supabase_client() -> Client:
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        print("❌ SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")
        sys.exit(1)
    return create_client(url, key)


def slugify(name: str) -> str:
    """'Bob (Requester 1)' -> 'bob.requester.1'"""
    return re.sub(r"[^a-z0-9]+", ".", name.lower()).strip(".") or "person"


def dev_email(name: str, taken: set[str]) -> str:
    """A unique fake email for `name`. Duplicated names get -2, -3, ..."""
    base = slugify(name)
    candidate = f"{base}@{EMAIL_DOMAIN}"
    n = 2
    while candidate in taken:
        candidate = f"{base}-{n}@{EMAIL_DOMAIN}"
        n += 1
    taken.add(candidate)
    return candidate


def dev_circle_id(supabase: Client) -> str:
    """The circle new cast members join."""
    circles = supabase.table("circles").select("*").order("created_at").limit(1).execute()
    if circles.data:
        return circles.data[0]["id"]
    created = supabase.table("circles").insert({
        "name": "Maple St · Building B",
        "invite_code": "DEMO01",
    }).execute()
    return created.data[0]["id"]


def seed(adopt: bool = False):
    supabase = get_supabase_client()

    users = supabase.table("users").select("*").order("created_at").execute().data or []
    auth_users = supabase.auth.admin.list_users()
    auth_by_id = {str(u.id): u for u in auth_users}
    taken_emails = {u.email for u in auth_users if u.email}

    created, existing, skipped, minted = [], [], [], []

    # 1. Existing profiles that have no auth account — pin the id so nothing moves.
    for user in users:
        user_id, name = user["id"], user["name"]
        account = auth_by_id.get(user_id)

        if account is not None:
            metadata = account.user_metadata or {}
            if metadata.get("favorly_dev_seed"):
                existing.append((name, account.email, "already seeded"))
            elif adopt:
                supabase.auth.admin.update_user_by_id(user_id, {
                    "password": DEV_PASSWORD,
                    "user_metadata": {**metadata, "name": name, "favorly_dev_seed": True},
                })
                existing.append((name, account.email, "adopted — password reset"))
            else:
                supabase.auth.admin.update_user_by_id(user_id, {
                    "user_metadata": {**metadata, "name": name},
                })
                skipped.append((name, account.email, "pre-existing account — use --adopt"))
            continue

        email = dev_email(name, taken_emails)
        try:
            supabase.auth.admin.create_user({
                "id": user_id,
                "email": email,
                "password": DEV_PASSWORD,
                "email_confirm": True,
                "user_metadata": {"name": name, "favorly_dev_seed": True},
            })
            created.append((name, email, "created, id pinned"))
        except Exception as e:
            skipped.append((name, email, f"failed: {e}"))

    # 2. Cast the agent service needs but nobody has a profile for.
    have_names = {u["name"] for u in users}
    wanted = [n for n in agent_residents() + EXTRA_CAST if n not in have_names]
    if wanted:
        circle_id = dev_circle_id(supabase)
    for name in wanted:
        email = dev_email(name, taken_emails)
        try:
            # Auth first: users.id references auth.users(id).
            account = supabase.auth.admin.create_user({
                "email": email,
                "password": DEV_PASSWORD,
                "email_confirm": True,
                "user_metadata": {"name": name, "favorly_dev_seed": True},
            })
            supabase.table("users").insert({
                "id": str(account.user.id),
                "circle_id": circle_id,
                "name": name,
            }).execute()
            minted.append((name, email, "new account + profile"))
        except Exception as e:
            skipped.append((name, email, f"failed: {e}"))

    rows = created + minted + existing + skipped
    width = max([len(r[0]) for r in rows] + [4]) if rows else 4
    print(f"\n✅ {len(created)} account(s) for existing profiles (password: {DEV_PASSWORD})")
    for name, email, note in created:
        print(f"   {name:<{width}}  {email}  ({note})")
    if minted:
        print(f"\n🌱 {len(minted)} new cast member(s)")
        for name, email, note in minted:
            print(f"   {name:<{width}}  {email}  ({note})")
    if existing:
        print(f"\n♻️  {len(existing)} already had a dev account")
        for name, email, note in existing:
            print(f"   {name:<{width}}  {email}  ({note})")
    if skipped:
        print(f"\n⚠️  {len(skipped)} skipped")
        for name, detail, note in skipped:
            print(f"   {name:<{width}}  {detail}  ({note})")
    print()


if __name__ == "__main__":
    seed(adopt="--adopt" in sys.argv)
