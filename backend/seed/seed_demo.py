#!/usr/bin/env python3
"""Seed demo data into Supabase using canonical cast."""

import os
import sys
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
from cast import (
    DEMO_CIRCLE,
    ALL_CHARACTERS,
    REALISTIC_ITEMS,
    ANA,
    BEN,
    CHLOE,
    MAYA,
)

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")

if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
    print("❌ SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")
    exit(1)

supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)


def seed_demo():
    """Seed demo circle with users and multiple trips in different states."""
    print("🌱 Seeding demo data from canonical cast...")

    try:
        # Create circle (using stable UUID from cast)
        circle_response = supabase.table("circles").insert({
            "id": DEMO_CIRCLE.id,
            "name": DEMO_CIRCLE.name,
            "invite_code": DEMO_CIRCLE.invite_code,
        }).execute()
        print(f"✅ Created circle: {circle_response.data[0]['name']}")
        print(f"   Invite code: {DEMO_CIRCLE.invite_code}")

        # Create demo users (using stable UUIDs from cast)
        users_created = []
        for char in ALL_CHARACTERS:
            user_response = supabase.table("users").insert({
                "id": char.id,
                "circle_id": DEMO_CIRCLE.id,
                "name": char.name,
                "venmo_handle": char.venmo_handle,
            }).execute()
            users_created.append(user_response.data[0])
            print(f"✅ Created user: {char.name}")

        # Get user IDs
        ana_id = ANA.id
        ben_id = BEN.id
        chloe_id = CHLOE.id
        maya_id = MAYA.id

        # ====================================================================
        # TRIP 1: OPEN (waiting for requests)
        # ====================================================================
        depart_time_1 = datetime.now() + timedelta(hours=2)
        trip1_response = supabase.table("trips").insert({
            "shopper_id": ana_id,
            "circle_id": DEMO_CIRCLE.id,
            "store": "Trader Joe's",
            "depart_at": depart_time_1.isoformat(),
            "caps": {
                "max_requesters": 6,
                "max_dollars_per_person": 40.00,
                "max_items_per_person": 8,
            },
            "status": TripStatus.OPEN.value,
        }).execute()
        trip1_id = trip1_response.data[0]["id"]
        print(f"\n✅ Created OPEN trip: {trip1_response.data[0]['store']}")

        # Ben's request for trip 1
        ben_items = [
            {"name": "Oat Milk", "qty": 1, "max_price": 3.99},
            {"name": "Bananas", "qty": 2, "max_price": 1.98},
            {"name": "Greek Yogurt", "qty": 2, "max_price": 5.98},
        ]
        request1_response = supabase.table("requests").insert({
            "trip_id": trip1_id,
            "requester_id": ben_id,
            "status": RequestStatus.PENDING.value,
        }).execute()
        request1_id = request1_response.data[0]["id"]

        for item in ben_items:
            section = "dairy" if "Milk" in item["name"] or "Yogurt" in item["name"] else "produce"
            supabase.table("items").insert({
                "request_id": request1_id,
                "trip_id": trip1_id,
                "name": item["name"],
                "qty": item["qty"],
                "max_price": item["max_price"],
                "section": section,
                "status": ItemStatus.PENDING.value,
            }).execute()
        print(f"   - Ben's request (3 items, ${sum(i['max_price'] for i in ben_items):.2f})")

        # Chloe's request for trip 1
        chloe_items = [
            {"name": "Dark Chocolate Almonds", "qty": 1, "max_price": 3.99},
            {"name": "Organic Spinach", "qty": 1, "max_price": 3.99},
            {"name": "Salmon Fillet", "qty": 1, "max_price": 9.99},
        ]
        request2_response = supabase.table("requests").insert({
            "trip_id": trip1_id,
            "requester_id": chloe_id,
            "status": RequestStatus.PENDING.value,
        }).execute()
        request2_id = request2_response.data[0]["id"]

        for item in chloe_items:
            if "Spinach" in item["name"]:
                section = "produce"
            elif "Salmon" in item["name"]:
                section = "frozen"
            else:
                section = "snacks"
            supabase.table("items").insert({
                "request_id": request2_id,
                "trip_id": trip1_id,
                "name": item["name"],
                "qty": item["qty"],
                "max_price": item["max_price"],
                "section": section,
                "status": ItemStatus.PENDING.value,
            }).execute()
        print(f"   - Chloe's request (3 items, ${sum(i['max_price'] for i in chloe_items):.2f})")

        # ====================================================================
        # TRIP 2: SHOPPING (shopper is out)
        # ====================================================================
        depart_time_2 = datetime.now() - timedelta(minutes=30)
        trip2_response = supabase.table("trips").insert({
            "shopper_id": ana_id,
            "circle_id": DEMO_CIRCLE.id,
            "store": "Costco",
            "depart_at": depart_time_2.isoformat(),
            "caps": {
                "max_requesters": 6,
                "max_dollars_per_person": 50.00,
                "max_items_per_person": 10,
            },
            "status": TripStatus.SHOPPING.value,
        }).execute()
        trip2_id = trip2_response.data[0]["id"]
        print(f"\n✅ Created SHOPPING trip: {trip2_response.data[0]['store']}")

        # Maya's request for trip 2 (ACCEPTED)
        maya_items = [
            {"name": "Organic Coffee", "qty": 1, "max_price": 12.99},
            {"name": "Frozen Berries", "qty": 2, "max_price": 9.98},
            {"name": "Peanut Butter", "qty": 1, "max_price": 3.99},
        ]
        request3_response = supabase.table("requests").insert({
            "trip_id": trip2_id,
            "requester_id": maya_id,
            "status": RequestStatus.ACCEPTED.value,
        }).execute()
        request3_id = request3_response.data[0]["id"]

        for item in maya_items:
            if "Coffee" in item["name"]:
                section = "beverages"
            elif "Berries" in item["name"]:
                section = "frozen"
            else:
                section = "pantry"
            supabase.table("items").insert({
                "request_id": request3_id,
                "trip_id": trip2_id,
                "name": item["name"],
                "qty": item["qty"],
                "max_price": item["max_price"],
                "section": section,
                "status": ItemStatus.PURCHASED.value,
            }).execute()
        print(f"   - Maya's request (3 items, ACCEPTED and purchased, ${sum(i['max_price'] for i in maya_items):.2f})")

        # ====================================================================
        # TRIP 3: DONE (completed trip)
        # ====================================================================
        depart_time_3 = datetime.now() - timedelta(hours=2)
        trip3_response = supabase.table("trips").insert({
            "shopper_id": ana_id,
            "circle_id": DEMO_CIRCLE.id,
            "store": "Whole Foods",
            "depart_at": depart_time_3.isoformat(),
            "caps": {
                "max_requesters": 4,
                "max_dollars_per_person": 35.00,
                "max_items_per_person": 6,
            },
            "status": TripStatus.DONE.value,
        }).execute()
        trip3_id = trip3_response.data[0]["id"]
        print(f"\n✅ Created DONE trip: {trip3_response.data[0]['store']}")

        # Ben's completed request for trip 3
        ben_trip3_items = [
            {"name": "Almond Flour", "qty": 1, "max_price": 5.99},
            {"name": "Organic Eggs", "qty": 1, "max_price": 3.99},
        ]
        request4_response = supabase.table("requests").insert({
            "trip_id": trip3_id,
            "requester_id": ben_id,
            "status": RequestStatus.COMPLETED.value,
        }).execute()
        request4_id = request4_response.data[0]["id"]

        for item in ben_trip3_items:
            if "Eggs" in item["name"]:
                section = "dairy"
            else:
                section = "pantry"
            supabase.table("items").insert({
                "request_id": request4_id,
                "trip_id": trip3_id,
                "name": item["name"],
                "qty": item["qty"],
                "max_price": item["max_price"],
                "section": section,
                "status": ItemStatus.DELIVERED.value,
            }).execute()
        print(f"   - Ben's request (2 items, COMPLETED, ${sum(i['max_price'] for i in ben_trip3_items):.2f})")

        print("\n✅ Demo data seeded successfully!")
        print(f"\n📝 Demo Credentials:")
        print(f"  Circle: {DEMO_CIRCLE.name}")
        print(f"  Invite Code: {DEMO_CIRCLE.invite_code}")
        print(f"\n👥 Users:")
        for char in ALL_CHARACTERS:
            print(f"  - {char.name} ({char.role}) · email: {char.email}")

    except Exception as e:
        print(f"❌ Error seeding data: {e}")
        raise


if __name__ == "__main__":
    seed_demo()
