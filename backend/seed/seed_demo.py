#!/usr/bin/env python3
"""Seed the demo circle + users into Postgres/Supabase, and register each user
in the Trellis agent + graph service with the SAME id -- so favors logged from
this backend (see services/trellis_client.py) resolve there with no mapping.
"""

import asyncio
import json
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

import asyncpg
from dotenv import load_dotenv


def _dt(iso: str) -> datetime:
    """asyncpg needs real (naive) datetime objects for this project's
    `timestamp without time zone` columns -- unlike the Supabase REST client
    (PostgREST), it won't coerce an ISO string, and it rejects a tz-aware
    datetime against a tz-naive column."""
    return datetime.fromisoformat(iso.replace("Z", "+00:00")).replace(tzinfo=None)

load_dotenv()

import db
from services import trellis_client


async def seed_demo():
    demo_file = Path(__file__).parent / "demo_circle.json"
    demo_data = json.loads(demo_file.read_text())

    pool = await db.init_pool()
    if pool is None:
        print("DATABASE_URL not set")
        return

    async with pool.acquire() as conn:
        circle = demo_data["circle"]
        await conn.execute(
            "INSERT INTO circles (id, name, invite_code, created_at) VALUES ($1, $2, $3, $4) "
            "ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name",
            circle["id"], circle["name"], circle["invite_code"], _dt(circle["created_at"]),
        )
        print(f"circle: {circle['name']}")

        for user in demo_data["users"]:
            await conn.execute(
                "INSERT INTO users (id, circle_id, name, venmo_handle, created_at) "
                "VALUES ($1, $2, $3, $4, $5) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name",
                user["id"], user["circle_id"], user["name"], user.get("venmo_handle"), _dt(user["created_at"]),
            )
            await trellis_client.register_person(user["id"], user["name"])
            print(f"user: {user['name']} (registered in Trellis with the same id)")

        for trip in demo_data.get("prior_trips", []):
            caps = trip.get("caps", {})
            await conn.execute(
                "INSERT INTO trips (id, shopper_id, circle_id, store, depart_at, caps, status, created_at) "
                "VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7, $8) ON CONFLICT (id) DO NOTHING",
                trip["id"], trip["shopper_id"], trip["circle_id"], trip["store"],
                _dt(trip["depart_at"]), json.dumps(caps), trip["status"], _dt(trip["created_at"]),
            )
            print(f"prior trip: {trip['store']}")

    print("\nDemo data seeded.")
    await db.close_pool()


if __name__ == "__main__":
    asyncio.run(seed_demo())
