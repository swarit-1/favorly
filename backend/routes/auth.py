"""Authentication routes."""

from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel, EmailStr
from uuid import UUID
import os
from supabase import create_client, Client

router = APIRouter(prefix="/auth", tags=["auth"])


def get_supabase_client() -> Client:
    """Get Supabase client."""
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")
    return create_client(url, key)


class SignupRequest(BaseModel):
    """Signup request."""
    name: str
    email: str
    password: str
    invite_code: str


class LoginRequest(BaseModel):
    """Login request."""
    email: str
    password: str


class AuthResponse(BaseModel):
    """Auth response."""
    user_id: UUID
    circle_id: UUID
    name: str
    access_token: str


@router.post("/signup", response_model=AuthResponse)
async def signup(req: SignupRequest):
    """Sign up a new user.

    Order matters: supabase-py swaps the client's PostgREST token to the new
    user's JWT after auth.sign_up(), so any table read on that client runs
    under RLS and silently returns nothing. The circle lookup happens BEFORE
    sign_up, and the users insert uses a fresh service-role client.
    """
    supabase = get_supabase_client()

    try:
        # 1. Validate the invite code first (service-role client, pre-sign_up)
        circle_response = supabase.table("circles").select("*").eq("invite_code", req.invite_code).execute()
        if not circle_response.data:
            raise HTTPException(status_code=404, detail="Invalid invite code")
        circle_id = circle_response.data[0]["id"]

        # 2. Create the auth user (mutates this client's session — see docstring)
        try:
            auth_response = supabase.auth.sign_up({
                "email": req.email,
                "password": req.password,
            })
        except Exception as auth_error:
            # Retried signups (e.g. after an earlier failed attempt created the
            # auth user but not the users row) fall through to plain login.
            if "already registered" in str(auth_error).lower():
                auth_response = supabase.auth.sign_in_with_password({
                    "email": req.email,
                    "password": req.password,
                })
            else:
                raise HTTPException(status_code=400, detail=str(auth_error))

        if not auth_response.user:
            raise HTTPException(status_code=400, detail="Failed to create auth user")

        user_id = auth_response.user.id
        access_token = auth_response.session.access_token if auth_response.session else ""

        # 3. Upsert the users row on a FRESH service-role client (the first
        # client now carries the end-user JWT and is RLS-restricted).
        db = get_supabase_client()
        user_response = db.table("users").upsert({
            "id": user_id,
            "circle_id": circle_id,
            "name": req.name,
        }).execute()
        if not user_response.data:
            raise HTTPException(status_code=500, detail="Failed to create user")

        return AuthResponse(
            user_id=user_id,
            circle_id=circle_id,
            name=req.name,
            access_token=access_token,
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/login", response_model=AuthResponse)
async def login(req: LoginRequest):
    """Log in a user."""
    supabase = get_supabase_client()

    try:
        # Sign in
        auth_response = supabase.auth.sign_in_with_password({
            "email": req.email,
            "password": req.password,
        })
        if not auth_response.user or not auth_response.session:
            raise HTTPException(status_code=401, detail="Invalid credentials")

        user_id = auth_response.user.id
        access_token = auth_response.session.access_token

        # Get user from users table — fresh service-role client; sign_in
        # swapped `supabase`'s PostgREST token to the end-user JWT (RLS).
        db = get_supabase_client()
        user_response = db.table("users").select("*").eq("id", user_id).execute()
        if not user_response.data:
            raise HTTPException(status_code=404, detail="User not found")

        user_data = user_response.data[0]

        return AuthResponse(
            user_id=user_id,
            circle_id=user_data["circle_id"],
            name=user_data["name"],
            access_token=access_token,
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


# ============================================================================
# DEV BYPASS — log in as any seeded Supabase Auth user by name or email.
# Real Supabase Auth accounts with fake @favorly.test emails, seeded by
# backend/seed/seed_auth_users.py with their ids pinned to the ids the test
# data already uses. So this issues a genuine JWT — the only thing it skips is
# you having to know the password.
#
# Only mounted when ENVIRONMENT=development. Delete this block (plus
# dev_login_screen.dart) once real auth is wired up.
# ============================================================================

DEV_PASSWORD = os.getenv("DEV_PASSWORD", "favorly-dev-2024")


def _require_dev():
    """404 unless we're running in development."""
    if os.getenv("ENVIRONMENT") != "development":
        raise HTTPException(status_code=404, detail="Not found")


class DevLoginRequest(BaseModel):
    """Dev login: a name or an email, no password."""
    name: str


class DevUser(BaseModel):
    """Someone you can dev-log-in as."""
    id: UUID
    name: str
    email: str
    circle_id: UUID | None = None
    seeded: bool


def _dev_roster(supabase: Client) -> list[DevUser]:
    """Every auth account that also has a `users` row, newest circle info attached."""
    rows = supabase.table("users").select("id, name, circle_id").execute().data or []
    by_id = {r["id"]: r for r in rows}

    roster = []
    for auth_user in supabase.auth.admin.list_users():
        row = by_id.get(str(auth_user.id))
        if row is None or not auth_user.email:
            continue
        metadata = auth_user.user_metadata or {}
        roster.append(DevUser(
            id=auth_user.id,
            name=metadata.get("name") or row["name"],
            email=auth_user.email,
            circle_id=row["circle_id"],
            seeded=bool(metadata.get("favorly_dev_seed")),
        ))
    roster.sort(key=lambda u: (not u.seeded, u.name))
    return roster


@router.get("/dev/users", response_model=list[DevUser])
async def dev_list_users():
    """Everyone you can dev-log-in as. `seeded` false means we don't know the password."""
    _require_dev()
    try:
        return _dev_roster(get_supabase_client())
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/dev/login", response_model=AuthResponse)
async def dev_login(req: DevLoginRequest):
    """Log in as whoever matches `name` — an email, an exact name, else a substring.

    Signs in for real against Supabase Auth with the shared dev password, so the
    token you get back is a genuine JWT.
    """
    _require_dev()
    supabase = get_supabase_client()
    wanted = req.name.strip().lower()
    if not wanted:
        raise HTTPException(status_code=400, detail="name is required")

    try:
        roster = _dev_roster(supabase)

        match = next((u for u in roster if u.email.lower() == wanted), None)
        if match is None:
            match = next((u for u in roster if u.name.lower() == wanted), None)
        if match is None:
            match = next((u for u in roster if wanted in u.name.lower()), None)
        if match is None:
            raise HTTPException(
                status_code=404,
                detail=f"No dev user matching '{req.name}'. GET /auth/dev/users to see the roster.",
            )
        if not match.seeded:
            raise HTTPException(
                status_code=409,
                detail=(
                    f"'{match.name}' ({match.email}) is a real account, not a seeded one — "
                    "its password is unknown. Run: python backend/seed/seed_auth_users.py --adopt"
                ),
            )
        if match.circle_id is None:
            raise HTTPException(status_code=409, detail=f"'{match.name}' has no circle")

        session = supabase.auth.sign_in_with_password({
            "email": match.email,
            "password": DEV_PASSWORD,
        })
        if not session.session:
            raise HTTPException(status_code=401, detail="Dev password rejected — re-run the seed script")

        return AuthResponse(
            user_id=match.id,
            circle_id=match.circle_id,
            name=match.name,
            access_token=session.session.access_token,
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
