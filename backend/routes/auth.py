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
    print(f"🔑 URL: {url[:50]}...")
    print(f"🔑 KEY: {key[:20]}...")
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
    """Sign up a new user."""
    print(f"\n🚀 SIGNUP CALLED: {req.email} / {req.invite_code}")
    supabase = get_supabase_client()

    try:
        # Create auth user with email confirmation skipped
        try:
            auth_response = supabase.auth.sign_up({
                "email": req.email,
                "password": req.password,
                "options": {"skip_confirmation": True}
            })
        except Exception as auth_error:
            print(f"❌ Auth error: {auth_error}")
            raise HTTPException(status_code=400, detail=str(auth_error))

        if not auth_response.user:
            raise HTTPException(status_code=400, detail="Failed to create auth user")

        user_id = auth_response.user.id
        access_token = auth_response.session.access_token if auth_response.session else ""

        # Find circle by invite code
        print(f"🔍 Looking for circle with code: '{req.invite_code}'")
        circle_response = supabase.table("circles").select("*").eq("invite_code", req.invite_code).execute()
        print(f"📦 Full response: {circle_response}")
        print(f"📦 Data: {circle_response.data}")
        print(f"📦 Count: {circle_response.count}")
        if not circle_response.data:
            raise HTTPException(status_code=404, detail="Invalid invite code")

        circle_id = circle_response.data[0]["id"]

        # Create user in users table
        try:
            user_response = supabase.table("users").insert({
                "id": user_id,
                "circle_id": circle_id,
                "name": req.name,
            }).execute()
        except Exception as db_error:
            print(f"❌ Database error: {db_error}")
            raise HTTPException(status_code=500, detail=str(db_error))

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

        # Get user from users table
        user_response = supabase.table("users").select("*").eq("id", user_id).execute()
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
