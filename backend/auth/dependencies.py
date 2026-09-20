"""FastAPI dependencies for authentication."""

import os
from uuid import UUID
from fastapi import Header, HTTPException, status
from supabase import create_client, Client


def get_supabase_client() -> Client:
    """Get or create Supabase client."""
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        raise HTTPException(status_code=500, detail="Supabase not configured")
    return create_client(url, key)


async def get_current_user_id(authorization: str = Header(...)) -> UUID:
    """
    Extract and verify user ID from Authorization header.

    Supports two formats:
    - Bearer <jwt> -- verify with Supabase (production)
    - User-<uuid> -- accept in development mode only

    Returns the verified user UUID.
    """
    environment = os.getenv("ENVIRONMENT", "development")

    # Development bypass: User-<uuid> header
    if authorization.startswith("User-"):
        if environment != "development":
            raise HTTPException(
                status_code=403,
                detail="Dev bypass disabled in production",
            )
        try:
            user_id_str = authorization.replace("User-", "")
            return UUID(user_id_str)
        except ValueError:
            raise HTTPException(
                status_code=400,
                detail="Invalid user ID format",
            )

    # Production: Bearer <jwt>
    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=401,
            detail="Missing or invalid authorization header",
        )

    token = authorization.replace("Bearer ", "").strip()
    if not token:
        raise HTTPException(
            status_code=401,
            detail="Empty bearer token",
        )

    try:
        supabase = get_supabase_client()
        user = supabase.auth.get_user(token)

        if not user or not user.user:
            raise HTTPException(
                status_code=401,
                detail="Invalid or expired token",
            )

        user_id = user.user.id
        try:
            return UUID(user_id)
        except ValueError:
            raise HTTPException(
                status_code=500,
                detail="Invalid user ID format from Supabase",
            )
    except Exception as e:
        # Log the error but don't expose details to client
        if isinstance(e, HTTPException):
            raise
        raise HTTPException(
            status_code=401,
            detail="Token verification failed",
        )
