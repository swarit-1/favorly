"""Phone-to-person identity bridge.

An SMS sender is only useful to the graph if their phone resolves to a real
Supabase identity (auth account + `users` row) -- that id is the `person_id`
Trellis stores. Resolution order:

1. In-memory cache (AgentStore.profiles).
2. `users.phone` lookup (migration 005_users_phone.sql adds the column).
3. LINQ_USER_PHONES env ("+16175550101=Swarit Srivastava,..."): resolve by
   exact `users.name` inside the demo circle, then write the phone onto the
   row so step 2 hits next time.
4. Unknown phone: auto-provision -- Supabase Auth user first, then the
   `users` row with the same id, demo circle from seed/cast.py, name
   "Neighbor 1234". A judge can text cold and still get ranked matches.
5. No Supabase env (tests): random in-memory UUID, exactly the old behaviour.

Every Supabase step is best-effort: any failure falls through to the
in-memory profile so a reply is always sent.
"""

from __future__ import annotations

import os
import re
from uuid import UUID, uuid4

from shared.contracts.models import User

from .store import AgentStore, Profile


def _phone_env_map() -> dict[str, str]:
    """'+15551234567=Alice Smith,+1555...=Bob' -> {'+1555...': 'Alice Smith'}"""
    mapping: dict[str, str] = {}
    for pair in os.getenv("LINQ_USER_PHONES", "").split(","):
        if "=" in pair:
            phone, name = pair.split("=", 1)
            mapping[phone.strip()] = name.strip()
    return mapping


def _demo_circle_id() -> str:
    from seed.cast import DEMO_CIRCLE

    return DEMO_CIRCLE.id


def _profile_from_row(row: dict, phone: str) -> Profile:
    user = User(
        id=UUID(str(row["id"])),
        circle_id=UUID(str(row["circle_id"])) if row.get("circle_id") else UUID(_demo_circle_id()),
        name=row.get("name") or f"Neighbor {phone[-4:]}",
        venmo_handle=row.get("venmo_handle"),
    )
    return Profile(user=user, phone=phone)


def _supabase():
    """Service-role client, or None when env is absent (tests, offline dev)."""
    if not (os.getenv("SUPABASE_URL") and os.getenv("SUPABASE_SERVICE_ROLE_KEY")):
        return None
    try:
        from db.client import get_supabase_client

        return get_supabase_client()
    except Exception as e:
        print(f"[identity] supabase client unavailable: {e}", flush=True)
        return None


def _lookup_by_phone(sb, phone: str) -> dict | None:
    try:
        rows = sb.table("users").select("*").eq("phone", phone).limit(1).execute().data
        return rows[0] if rows else None
    except Exception as e:
        print(f"[identity] phone lookup failed: {e}", flush=True)
        return None


def _resolve_env_name(sb, phone: str) -> dict | None:
    """LINQ_USER_PHONES name -> users row inside the demo circle; writes the
    phone onto the row so the plain phone lookup hits next time."""
    name = _phone_env_map().get(phone)
    if not name:
        return None
    try:
        rows = (
            sb.table("users").select("*")
            .eq("name", name).eq("circle_id", _demo_circle_id())
            .limit(1).execute().data
        )
        if not rows:
            return None
        row = rows[0]
        try:
            sb.table("users").update({"phone": phone}).eq("id", row["id"]).execute()
        except Exception as e:
            print(f"[identity] phone write-back failed: {e}", flush=True)
        row["phone"] = phone
        return row
    except Exception as e:
        print(f"[identity] env-name lookup failed: {e}", flush=True)
        return None


def _provision(sb, phone: str) -> dict | None:
    """Auth account first (users.id references auth.users.id -- same ordering
    as backend/seed/seed_auth_users.py), then the profile row."""
    digits = re.sub(r"\D", "", phone)
    email = f"p{digits}@favorly.test"
    password = os.getenv("DEV_PASSWORD", "favorly-dev-2024")
    name = f"Neighbor {digits[-4:] or '0000'}"
    try:
        created = sb.auth.admin.create_user({
            "email": email,
            "password": password,
            "email_confirm": True,
            "user_metadata": {"name": name, "favorly_sms_provisioned": True},
        })
        user_id = str(created.user.id)
    except Exception as e:
        # Retried provision: the auth account may already exist from an
        # earlier partial attempt. Try to find it by email.
        try:
            existing = sb.auth.admin.list_users()
            match = next((u for u in existing if u.email == email), None)
            if match is None:
                print(f"[identity] auth provision failed: {e}", flush=True)
                return None
            user_id = str(match.id)
        except Exception as e2:
            print(f"[identity] auth provision failed: {e}; lookup failed: {e2}", flush=True)
            return None
    try:
        rows = sb.table("users").upsert({
            "id": user_id,
            "circle_id": _demo_circle_id(),
            "name": name,
            "phone": phone,
        }).execute().data
        return rows[0] if rows else None
    except Exception as e:
        print(f"[identity] users row provision failed: {e}", flush=True)
        return None


def resolve(store: AgentStore, phone: str) -> Profile:
    """The bridge. Always returns a Profile; only the id's provenance varies."""
    if phone in store.profiles:
        return store.profiles[phone]

    sb = _supabase()
    if sb is not None:
        row = _lookup_by_phone(sb, phone) or _resolve_env_name(sb, phone) or _provision(sb, phone)
        if row is not None:
            profile = _profile_from_row(row, phone)
            store.profiles[phone] = profile
            return profile

    # No Supabase env, or every remote step failed: old in-memory behaviour.
    user = User(id=uuid4(), circle_id=store.circle.id, name=f"Neighbor {phone[-4:]}")
    profile = Profile(user=user, phone=phone)
    store.profiles[phone] = profile
    return profile
