"""WebSocket connection manager for realtime updates via MongoDB change streams."""

import asyncio
import json
from typing import Set
from fastapi import WebSocket
from motor.motor_asyncio import AsyncCollection
from bson import json_util


class ConnectionManager:
    """Manages WebSocket connections and broadcasts."""

    def __init__(self):
        self.active_connections: dict[str, Set[WebSocket]] = {}
        self.change_stream_tasks: dict[str, asyncio.Task] = {}

    async def connect(self, websocket: WebSocket, trip_id: str):
        """Accept and register a WebSocket connection."""
        await websocket.accept()
        if trip_id not in self.active_connections:
            self.active_connections[trip_id] = set()
        self.active_connections[trip_id].add(websocket)
        print(f"✓ Client connected to trip {trip_id} ({len(self.active_connections[trip_id])} total)")

    def disconnect(self, websocket: WebSocket, trip_id: str):
        """Unregister a WebSocket connection."""
        if trip_id in self.active_connections:
            self.active_connections[trip_id].discard(websocket)
            if not self.active_connections[trip_id]:
                del self.active_connections[trip_id]
                # Stop change stream listener if no more connections
                if trip_id in self.change_stream_tasks:
                    self.change_stream_tasks[trip_id].cancel()
                    del self.change_stream_tasks[trip_id]
            print(f"✓ Client disconnected from trip {trip_id}")

    async def broadcast(self, trip_id: str, message: dict):
        """Broadcast a message to all clients connected to a trip."""
        if trip_id not in self.active_connections:
            return

        disconnected = set()
        for websocket in self.active_connections[trip_id]:
            try:
                await websocket.send_json(message)
            except Exception as e:
                print(f"✗ Error broadcasting to client: {e}")
                disconnected.add(websocket)

        # Clean up disconnected clients
        for websocket in disconnected:
            self.disconnect(websocket, trip_id)

    async def listen_to_collection(
        self,
        collection: AsyncCollection,
        trip_id: str,
        collection_name: str,
        filter_field: str = "trip_id",
    ):
        """
        Listen to MongoDB change stream for a specific trip and broadcast updates.

        Args:
            collection: MongoDB collection to watch
            trip_id: Trip ID to filter by
            collection_name: Name of collection (for message type)
            filter_field: Field to filter by trip_id (default: "trip_id")
        """
        from uuid import UUID

        try:
            pipeline = [
                {
                    "$match": {
                        "fullDocument": {
                            filter_field: str(trip_id)  # trip_id as string in DB
                        }
                    }
                }
            ]

            async with collection.watch(pipeline) as stream:
                async for change in stream:
                    if trip_id not in self.active_connections:
                        break  # No more listeners

                    # Format message for clients
                    message = {
                        "type": f"{collection_name}_updated",
                        "data": json.loads(json_util.dumps(change)),
                    }

                    await self.broadcast(trip_id, message)

        except asyncio.CancelledError:
            print(f"✓ Change stream listener stopped for {collection_name}:{trip_id}")
        except Exception as e:
            print(f"✗ Error in change stream: {e}")


# Global connection manager
manager = ConnectionManager()
