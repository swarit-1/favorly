#!/usr/bin/env python3
"""Seed demo circle and users into MongoDB."""

import asyncio
import json
import os
from pathlib import Path
from motor.motor_asyncio import AsyncClient

async def seed_demo():
    """Load and insert demo data into MongoDB."""

    # Load demo data
    demo_file = Path(__file__).parent / "demo_circle.json"
    with open(demo_file) as f:
        demo_data = json.load(f)

    # Get MongoDB connection
    mongo_uri = os.getenv("MONGODB_URI")
    if not mongo_uri:
        print("❌ MONGODB_URI not set")
        return

    db_name = os.getenv("MONGODB_DB_NAME", "favorly_demo")
    client = AsyncClient(mongo_uri)
    db = client[db_name]

    try:
        # Insert circle
        circle = demo_data["circle"]
        result = await db.circles.update_one(
            {"id": circle["id"]},
            {"$set": circle},
            upsert=True,
        )
        print(f"✓ Circle: {result.matched_count} matched, {result.upserted_id or 'updated'}")

        # Insert users
        for user in demo_data["users"]:
            result = await db.users.update_one(
                {"id": user["id"]},
                {"$set": user},
                upsert=True,
            )
            print(f"✓ User: {user['name']}")

        # Insert prior trips (for ledger seeding)
        for trip in demo_data.get("prior_trips", []):
            result = await db.trips.update_one(
                {"id": trip["id"]},
                {"$set": trip},
                upsert=True,
            )
            print(f"✓ Trip: {trip['store']}")

        print("\n✅ Demo data seeded successfully!")

        # Show summary
        circle_count = await db.circles.count_documents({})
        user_count = await db.users.count_documents({})
        trip_count = await db.trips.count_documents({})
        print(f"\nSummary:")
        print(f"  Circles: {circle_count}")
        print(f"  Users: {user_count}")
        print(f"  Trips: {trip_count}")

    except Exception as e:
        print(f"❌ Error: {e}")
    finally:
        client.close()


if __name__ == "__main__":
    from dotenv import load_dotenv
    load_dotenv()
    asyncio.run(seed_demo())
