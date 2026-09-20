#!/usr/bin/env python3
"""Mint the canonical demo cast as real Supabase Auth accounts with fake emails.

Identity order matters: `users.id` references `auth.users(id)`, so the auth
account is always created first and the profile row second.

Uses the canonical cast from cast.py as the single source of truth for demo
characters and their emails.

Idempotent — safe to re-run. Accounts it did not create are left alone unless
you pass --adopt, which resets their password to the dev one.

    python backend/seed/seed_auth_users.py
    python backend/seed/seed_auth_users.py --adopt
"""

import os
import re
import sys
from pathlib import Path

from dotenv import load_dotenv
from supabase import create_client, Client

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from cast import ALL_CHARACTERS, DEMO_CIRCLE

load_dotenv()

EMAIL_DOMAIN = os.getenv("DEV_EMAIL_DOMAIN", "favorly.test")
DEV_PASSWORD = os.getenv("DEV_PASSWORD", "favorly-dev-2024")


def get_supabase_client() -> Client:
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        print("❌ SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")
        sys.exit(1)
    return create_client(url, key)


def seed(adopt: bool = False):
    """Seed auth accounts for all canonical cast members."""
    supabase = get_supabase_client()

    users = supabase.table("users").select("*").order("created_at").execute().data or []
    auth_users = supabase.auth.admin.list_users()
    auth_by_id = {str(u.id): u for u in auth_users}
    taken_emails = {u.email for u in auth_users if u.email}

    created, existing, skipped = [], [], []

    # Process all canonical cast members
    for char in ALL_CHARACTERS:
        user_id = char.id
        account = auth_by_id.get(user_id)

        if account is not None:
            # Auth account already exists
            metadata = account.user_metadata or {}
            if metadata.get("favorly_dev_seed"):
                existing.append((char.name, account.email, "already seeded"))
            elif adopt:
                supabase.auth.admin.update_user_by_id(user_id, {
                    "password": DEV_PASSWORD,
                    "user_metadata": {**metadata, "name": char.name, "favorly_dev_seed": True},
                })
                existing.append((char.name, account.email, "adopted — password reset"))
            else:
                supabase.auth.admin.update_user_by_id(user_id, {
                    "user_metadata": {**metadata, "name": char.name},
                })
                skipped.append((char.name, account.email, "pre-existing account — use --adopt"))
            continue

        # Create new auth account with canonical email from cast
        email = char.email
        if email in taken_emails:
            skipped.append((char.name, email, "email already taken"))
            continue

        try:
            supabase.auth.admin.create_user({
                "id": user_id,
                "email": email,
                "password": DEV_PASSWORD,
                "email_confirm": True,
                "user_metadata": {"name": char.name, "favorly_dev_seed": True},
            })
            created.append((char.name, email, "created, id pinned"))
            taken_emails.add(email)
        except Exception as e:
            skipped.append((char.name, email, f"failed: {e}"))

    # Print results
    rows = created + existing + skipped
    width = max([len(r[0]) for r in rows] + [4]) if rows else 4

    if created:
        print(f"\n✅ {len(created)} account(s) created (password: {DEV_PASSWORD})")
        for name, email, note in created:
            print(f"   {name:<{width}}  {email}  ({note})")

    if existing:
        print(f"\n♻️  {len(existing)} already had a dev account")
        for name, email, note in existing:
            print(f"   {name:<{width}}  {email}  ({note})")

    if skipped:
        print(f"\n⚠️  {len(skipped)} skipped")
        for name, detail, note in skipped:
            print(f"   {name:<{width}}  {detail}  ({note})")

    if created or existing:
        print(f"\n📝 Demo Circle: {DEMO_CIRCLE.name} (invite: {DEMO_CIRCLE.invite_code})")

    print()


if __name__ == "__main__":
    seed(adopt="--adopt" in sys.argv)
