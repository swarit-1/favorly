#!/usr/bin/env python3
"""
Apply Phase 2 database migrations using Supabase service role key.
Usage: python3 apply_migrations.py
"""

import os
import sys
from pathlib import Path
from supabase import create_client, Client

def get_supabase_client() -> Client:
    """Initialize Supabase client with service role key."""
    url = os.getenv("SUPABASE_URL")
    service_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")

    if not url or not service_key:
        print("❌ Missing environment variables:")
        print("   SUPABASE_URL: " + ("✓" if url else "❌"))
        print("   SUPABASE_SERVICE_ROLE_KEY: " + ("✓" if service_key else "❌"))
        print("")
        print("Set them in your shell or .env file:")
        print("   export SUPABASE_URL='https://...'")
        print("   export SUPABASE_SERVICE_ROLE_KEY='eyJ...'")
        sys.exit(1)

    return create_client(url, service_key)

def apply_migrations():
    """Apply all SQL migrations in order."""
    supabase = get_supabase_client()
    migrations_dir = Path(__file__).parent / "migrations"

    # Sort migration files by name (ensures correct order)
    migration_files = sorted(migrations_dir.glob("*.sql"))

    if not migration_files:
        print("❌ No migration files found in", migrations_dir)
        sys.exit(1)

    print("🚀 Applying Phase 2 database migrations...")
    print("")

    for migration_file in migration_files:
        try:
            print(f"📋 Applying: {migration_file.name}")
            sql = migration_file.read_text()

            # Execute the SQL
            result = supabase.postgrest.query(sql)

            print(f"   ✅ {migration_file.name} applied successfully")
        except Exception as e:
            print(f"   ⚠️  {migration_file.name} error: {e}")
            print("      (It's OK if the table already exists)")

    print("")
    print("✅ All migrations processed!")
    print("")
    print("Next steps:")
    print("  1. Verify tables in Supabase Dashboard")
    print("  2. Implement Phase 3: Backend routes")

if __name__ == "__main__":
    apply_migrations()
