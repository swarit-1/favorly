"""Shared Supabase client."""

import os
from supabase import create_client, Client


def get_supabase_client() -> Client:
    """Get Supabase client with credentials from environment."""
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")
    return create_client(url, key)
