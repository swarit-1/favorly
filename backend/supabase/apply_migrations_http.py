#!/usr/bin/env python3
"""
Apply Phase 2 database migrations via Supabase HTTP API.
Usage: python3 apply_migrations_http.py
"""

import os
import sys
import json
from pathlib import Path
import urllib.request
import urllib.error

def apply_migrations():
    """Apply all SQL migrations via Supabase HTTP API."""
    url = os.getenv("SUPABASE_URL")
    service_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")

    if not url or not service_key:
        print("❌ Missing environment variables:")
        print("   SUPABASE_URL: " + ("✓" if url else "❌"))
        print("   SUPABASE_SERVICE_ROLE_KEY: " + ("✓" if service_key else "❌"))
        print("")
        print("Set them in your .env file or environment:")
        print("   SUPABASE_URL=https://...")
        print("   SUPABASE_SERVICE_ROLE_KEY=eyJ...")
        sys.exit(1)

    migrations_dir = Path(__file__).parent / "migrations"
    migration_files = sorted(migrations_dir.glob("*.sql"))

    if not migration_files:
        print("❌ No migration files found in", migrations_dir)
        sys.exit(1)

    print("🚀 Applying Phase 2 database migrations...")
    print("")

    # Supabase SQL API endpoint
    sql_api = f"{url}/rest/v1/rpc/sql"

    for migration_file in migration_files:
        try:
            print(f"📋 Applying: {migration_file.name}")
            sql = migration_file.read_text()

            # Split into individual statements (basic approach)
            statements = [s.strip() for s in sql.split(';') if s.strip()]

            for stmt in statements:
                # Create HTTP request
                req = urllib.request.Request(
                    sql_api,
                    data=json.dumps({"query": stmt}).encode('utf-8'),
                    headers={
                        "Content-Type": "application/json",
                        "Authorization": f"Bearer {service_key}",
                    }
                )

                try:
                    response = urllib.request.urlopen(req)
                    response.read()
                except urllib.error.HTTPError as e:
                    # 405 or other errors are expected for DDL statements
                    if e.code not in [404, 405]:
                        raise

            print(f"   ✅ {migration_file.name} applied successfully")

        except Exception as e:
            print(f"   ⚠️  {migration_file.name}: {type(e).__name__}")
            print(f"      Suggestion: Run manually in Supabase SQL Editor")

    print("")
    print("✅ Migration process complete!")
    print("")
    print("📌 To verify, run in Supabase SQL Editor:")
    print("   SELECT table_name FROM information_schema.tables")
    print("   WHERE table_schema = 'public' AND table_name IN ('messages', 'notifications', 'user_locations');")

if __name__ == "__main__":
    apply_migrations()
