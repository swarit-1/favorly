#!/usr/bin/env python3
"""Seed demo data into Supabase."""

import os
import sys
from uuid import uuid4
from datetime import datetime, timedelta
from dotenv import load_dotenv
from supabase import create_client, Client

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from shared.contracts.models import (
    TripStatus,
    RequestStatus,
    ItemStatus,
    StoreSection,
)

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")

if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
    print("❌ SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")
    exit(1)

supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)


def seed_demo():
    """Seed demo circle with users and a trip."""
    print("🌱 Seeding demo data...")

    try:
        # Create circle
        circle_id = str(uuid4())
        circle_response = supabase.table("circles").insert({
            "id": circle_id,
            "name": "Maple St · Building B",
            "invite_code": "DEMO01",
        }).execute()
        print(f"✅ Created circle: {circle_response.data[0]['name']}")

        # Create demo users
        users = []
        user_names = ["Ana (Shopper)", "Bob (Requester 1)", "Charlie (Requester 2)"]
        for i, name in enumerate(user_names):
            user_id = str(uuid4())
            user_response = supabase.table("users").insert({
                "id": user_id,
                "circle_id": circle_id,
                "name": name,
                "venmo_handle": f"@{name.split()[0].lower()}",
            }).execute()
            users.append(user_response.data[0])
            print(f"✅ Created user: {name}")

        shopper_id = users[0]["id"]
        requester1_id = users[1]["id"]
        requester2_id = users[2]["id"]

        # Create a trip
        depart_time = datetime.now() + timedelta(hours=2)
        trip_response = supabase.table("trips").insert({
            "shopper_id": shopper_id,
            "circle_id": circle_id,
            "store": "Trader Joe's",
            "depart_at": depart_time.isoformat(),
            "caps": {
                "max_requesters": 6,
                "max_dollars_per_person": 40.00,
                "max_items_per_person": 8,
            },
            "status": TripStatus.OPEN.value,
        }).execute()
        trip_id = trip_response.data[0]["id"]
        print(f"✅ Created trip: {trip_response.data[0]['store']}")

        # Create requests with items for requester 1
        items_1 = [
            {"name": "Organic Bananas", "qty": 2, "max_price": 3.99, "section": StoreSection.PRODUCE.value},
            {"name": "Greek Yogurt", "qty": 1, "max_price": 6.99, "section": StoreSection.DAIRY.value},
            {"name": "Whole Wheat Bread", "qty": 1, "max_price": 4.49, "section": StoreSection.BAKERY.value},
        ]

        request1_response = supabase.table("requests").insert({
            "trip_id": trip_id,
            "requester_id": requester1_id,
            "status": RequestStatus.PENDING.value,
        }).execute()
        request1_id = request1_response.data[0]["id"]

        for item in items_1:
            supabase.table("items").insert({
                "request_id": request1_id,
                "trip_id": trip_id,
                "name": item["name"],
                "qty": item["qty"],
                "max_price": item["max_price"],
                "section": item["section"],
                "status": ItemStatus.PENDING.value,
            }).execute()

        print(f"✅ Created request 1 with {len(items_1)} items")

        # Create requests with items for requester 2
        items_2 = [
            {"name": "Almond Butter", "qty": 1, "max_price": 8.99, "section": StoreSection.PANTRY.value},
            {"name": "Dark Chocolate", "qty": 2, "max_price": 2.99, "section": StoreSection.PANTRY.value},
            {"name": "Frozen Berries", "qty": 1, "max_price": 4.99, "section": StoreSection.FROZEN.value},
        ]

        request2_response = supabase.table("requests").insert({
            "trip_id": trip_id,
            "requester_id": requester2_id,
            "status": RequestStatus.PENDING.value,
        }).execute()
        request2_id = request2_response.data[0]["id"]

        for item in items_2:
            supabase.table("items").insert({
                "request_id": request2_id,
                "trip_id": trip_id,
                "name": item["name"],
                "qty": item["qty"],
                "max_price": item["max_price"],
                "section": item["section"],
                "status": ItemStatus.PENDING.value,
            }).execute()

        print(f"✅ Created request 2 with {len(items_2)} items")

        print("\n✅ Demo data seeded successfully!")
        print(f"\n📝 Demo Credentials:")
        print(f"Circle Invite Code: DEMO01")
        print(f"\nUsers:")
        for user in users:
            print(f"  - {user['name']}")

    except Exception as e:
        print(f"❌ Error seeding data: {e}")
        raise


if __name__ == "__main__":
    seed_demo()
