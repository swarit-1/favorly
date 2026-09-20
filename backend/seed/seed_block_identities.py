#!/usr/bin/env python3
"""Mint or adopt the v2 block cast (16 people) as Supabase identities.

cast.py is the single source of truth for who exists. The shared database
predates this cast, so rows are ADOPTED by exact name where they already
exist (keeping their ids, so favor history survives); only missing people get
new auth accounts, with cast ids pinned. Old resident "Maya Chen" is renamed
"Nora Chen" (two Mayas make "you both know Maya" ambiguous).

Idempotent. Never deletes. Demo circle only.

    python backend/seed/seed_block_identities.py
"""

import os
import sys

from dotenv import load_dotenv

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from cast import BLOCK_CHARACTERS, DEMO_CIRCLE, DemoCharacter  # noqa: E402

load_dotenv()

DEV_PASSWORD = os.getenv("DEV_PASSWORD", "favorly-dev-2024")
DEMO_ASKER_NAME = os.getenv("DEMO_ASKER_NAME", "Swarit Srivastava")


def get_supabase_client():
    from supabase import create_client

    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        print("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")
        sys.exit(1)
    return create_client(url, key)


def _asker_character() -> DemoCharacter:
    slug = DEMO_ASKER_NAME.lower().replace(" ", ".")
    from cast import make_stable_uuid

    return DemoCharacter(
        id=str(make_stable_uuid(DEMO_ASKER_NAME.lower().replace(" ", "-"))),
        name=DEMO_ASKER_NAME,
        email=f"{slug}@favorly.test",
        role="both",
        venmo_handle=DEMO_ASKER_NAME.lower().replace(" ", "-"),
        availability=["Sat", "Sun"],
        address_unit="3C",
        address_floor="3",
    )


def seed():
    sb = get_supabase_client()

    # 0. The circle itself.
    existing_circle = sb.table("circles").select("id").eq("id", DEMO_CIRCLE.id).execute().data
    if not existing_circle:
        sb.table("circles").insert({
            "id": DEMO_CIRCLE.id, "name": DEMO_CIRCLE.name,
            "invite_code": DEMO_CIRCLE.invite_code,
        }).execute()
        print(f"created circle {DEMO_CIRCLE.name} ({DEMO_CIRCLE.invite_code})")

    users = sb.table("users").select("id, name").execute().data or []
    by_name = {}
    for u in users:
        by_name.setdefault(u["name"], u["id"])

    # 1. Rename the old resident: Maya Chen -> Nora Chen.
    if "Nora Chen" not in by_name and "Maya Chen" in by_name:
        sb.table("users").update({"name": "Nora Chen"}).eq("id", by_name["Maya Chen"]).execute()
        by_name["Nora Chen"] = by_name.pop("Maya Chen")
        print("renamed Maya Chen -> Nora Chen")

    auth_users = sb.auth.admin.list_users()
    auth_by_email = {u.email: str(u.id) for u in auth_users if u.email}

    cast = list(BLOCK_CHARACTERS) + [_asker_character()]
    for char in cast:
        profile = {
            "circle_id": DEMO_CIRCLE.id,
            "name": char.name,
            "venmo_handle": char.venmo_handle,
            "address_unit": char.address_unit,
            "address_floor": char.address_floor,
            "availability": char.availability,
        }
        if char.name in by_name:
            # Adopt: keep the id (and its favor history), refresh the profile.
            sb.table("users").update(profile).eq("id", by_name[char.name]).execute()
            print(f"adopted  {char.name} ({by_name[char.name]})")
            continue

        # Auth account first (users.id references auth.users.id).
        user_id = auth_by_email.get(char.email)
        if user_id is None:
            try:
                created = sb.auth.admin.create_user({
                    "id": char.id,
                    "email": char.email,
                    "password": DEV_PASSWORD,
                    "email_confirm": True,
                    "user_metadata": {"name": char.name, "favorly_dev_seed": True},
                })
                user_id = str(created.user.id)
            except Exception as e:
                print(f"skipped  {char.name}: auth create failed: {e}")
                continue
        sb.table("users").upsert({"id": user_id, **profile}).execute()
        print(f"created  {char.name} ({user_id})")

    print("\nblock cast ready.")


if __name__ == "__main__":
    seed()
