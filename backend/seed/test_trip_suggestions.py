#!/usr/bin/env python3
"""Create test data for trip suggestions feature.

Scenario:
- Ana creates a Trader Joe's trip with requests from Ben & Chloe
- Ben creates a Trader Joe's trip (should see Ana & Chloe's requests)
- Chloe creates a CVS trip (should see Ana & Ben's requests)
"""

import os
import sys
from datetime import datetime, timedelta
from dotenv import load_dotenv
from supabase import create_client, Client
from uuid import uuid4

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


def create_test_trips():
    """Create trips from different shoppers with cross-requests."""
    print("🌱 Creating trip suggestion test data...\n")

    try:
        # ====================================================================
        # ANA'S TRADER JOE'S TRIP (baseline)
        # ====================================================================
        depart_time = datetime.now() + timedelta(hours=1)
        ana_trip = supabase.table("trips").insert({
            "shopper_id": str(ANA.id),
            "circle_id": str(DEMO_CIRCLE.id),
            "store": "Trader Joe's",
            "depart_at": depart_time.isoformat(),
            "caps": {
                "max_requesters": 6,
                "max_dollars_per_person": 40.00,
                "max_items_per_person": 8,
            },
            "status": TripStatus.OPEN.value,
        }).execute()
        ana_trip_id = ana_trip.data[0]["id"]
        print(f"✅ Ana's Trader Joe's trip: {ana_trip_id}")

        # Ben requests on Ana's trip
        ben_req = supabase.table("requests").insert({
            "trip_id": ana_trip_id,
            "requester_id": str(BEN.id),
            "status": RequestStatus.PENDING.value,
        }).execute()
        for item in [
            ("Oat Milk", "dairy", 3.99),
            ("Bananas", "produce", 1.99),
        ]:
            supabase.table("items").insert({
                "request_id": ben_req.data[0]["id"],
                "trip_id": ana_trip_id,
                "name": item[0],
                "qty": 1,
                "max_price": item[2],
                "section": item[1],
                "status": ItemStatus.PENDING.value,
            }).execute()
        print(f"   - Ben's request on Ana's trip")

        # Chloe requests on Ana's trip
        chloe_req = supabase.table("requests").insert({
            "trip_id": ana_trip_id,
            "requester_id": str(CHLOE.id),
            "status": RequestStatus.PENDING.value,
        }).execute()
        for item in [
            ("Dark Chocolate", "pantry", 3.99),
            ("Organic Spinach", "produce", 3.99),
        ]:
            supabase.table("items").insert({
                "request_id": chloe_req.data[0]["id"],
                "trip_id": ana_trip_id,
                "name": item[0],
                "qty": 1,
                "max_price": item[2],
                "section": item[1],
                "status": ItemStatus.PENDING.value,
            }).execute()
        print(f"   - Chloe's request on Ana's trip")

        # ====================================================================
        # BEN'S TRADER JOE'S TRIP (will show Ana & Chloe's requests)
        # ====================================================================
        depart_time_ben = datetime.now() + timedelta(hours=2)
        ben_trip = supabase.table("trips").insert({
            "shopper_id": str(BEN.id),
            "circle_id": str(DEMO_CIRCLE.id),
            "store": "Trader Joe's",
            "depart_at": depart_time_ben.isoformat(),
            "caps": {
                "max_requesters": 6,
                "max_dollars_per_person": 40.00,
                "max_items_per_person": 8,
            },
            "status": TripStatus.OPEN.value,
        }).execute()
        ben_trip_id = ben_trip.data[0]["id"]
        print(f"\n✅ Ben's Trader Joe's trip: {ben_trip_id}")
        print(f"   → Should show Ana & Chloe's requests from Ana's trip")

        # Ana requests on Ben's trip
        ana_req = supabase.table("requests").insert({
            "trip_id": ben_trip_id,
            "requester_id": str(ANA.id),
            "status": RequestStatus.PENDING.value,
        }).execute()
        for item in [
            ("Greek Yogurt", "dairy", 5.99),
            ("Almond Butter", "pantry", 8.99),
        ]:
            supabase.table("items").insert({
                "request_id": ana_req.data[0]["id"],
                "trip_id": ben_trip_id,
                "name": item[0],
                "qty": 1,
                "max_price": item[2],
                "section": item[1],
                "status": ItemStatus.PENDING.value,
            }).execute()
        print(f"   - Ana's request on Ben's trip")

        # ====================================================================
        # CHLOE'S CVS TRIP (will show Ana & Ben's requests)
        # ====================================================================
        depart_time_chloe = datetime.now() + timedelta(hours=3)
        chloe_trip = supabase.table("trips").insert({
            "shopper_id": str(CHLOE.id),
            "circle_id": str(DEMO_CIRCLE.id),
            "store": "CVS",
            "depart_at": depart_time_chloe.isoformat(),
            "caps": {
                "max_requesters": 6,
                "max_dollars_per_person": 30.00,
                "max_items_per_person": 6,
            },
            "status": TripStatus.OPEN.value,
        }).execute()
        chloe_trip_id = chloe_trip.data[0]["id"]
        print(f"\n✅ Chloe's CVS trip: {chloe_trip_id}")

        # Maya requests on Chloe's trip
        maya_req = supabase.table("requests").insert({
            "trip_id": chloe_trip_id,
            "requester_id": str(MAYA.id),
            "status": RequestStatus.PENDING.value,
        }).execute()
        for item in [
            ("Aspirin", "household", 4.99),
            ("Face Mask", "household", 2.99),
        ]:
            supabase.table("items").insert({
                "request_id": maya_req.data[0]["id"],
                "trip_id": chloe_trip_id,
                "name": item[0],
                "qty": 1,
                "max_price": item[2],
                "section": item[1],
                "status": ItemStatus.PENDING.value,
            }).execute()
        print(f"   - Maya's request on Chloe's trip")

        print("\n✅ Test data created!")
        print(f"\n🧪 Test suggestions endpoint:")
        print(f"   - Ben's trip ID: {ben_trip_id}")
        print(f"     Expected: Ana & Chloe's requests from Ana's Trader Joe's trip")
        print(f"   - Chloe's trip ID: {chloe_trip_id}")
        print(f"     Expected: Maya's requests from Chloe's CVS trip")

    except Exception as e:
        print(f"❌ Error: {e}")
        raise


if __name__ == "__main__":
    create_test_trips()
