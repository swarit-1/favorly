#!/usr/bin/env python3
"""Clean up items with invalid StoreSection values."""

import os
from dotenv import load_dotenv
from supabase import create_client

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")

if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
    print("❌ Missing SUPABASE credentials")
    exit(1)

supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

# Get all items with invalid sections (e.g., 'snacks')
print("🔍 Checking for items with invalid sections...")

# Fetch all items
items = supabase.table("items").select("id, name, section, request_id, trip_id").execute()

invalid_sections = ["snacks"]
items_to_delete = []

for item in items.data or []:
    if item["section"] in invalid_sections:
        items_to_delete.append(item)
        print(f"  Found invalid: {item['name']} (section: {item['section']}) - id: {item['id']}")

if items_to_delete:
    print(f"\n🗑️  Deleting {len(items_to_delete)} items with invalid sections...")
    for item in items_to_delete:
        supabase.table("items").delete().eq("id", item["id"]).execute()
        print(f"  ✅ Deleted {item['name']}")
    print(f"\n✅ Cleaned up {len(items_to_delete)} invalid items")
else:
    print("✅ No invalid sections found")
