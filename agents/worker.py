"""Async extraction worker. The POST to /events returns as soon as the row is
written; extraction happens here, off the request path.
"""

import asyncio
import logging

import db
import extraction
import sse
from config import settings

logger = logging.getLogger("trellis.worker")

extraction_queue: asyncio.Queue = asyncio.Queue()

_tasks: list[asyncio.Task] = []


async def enqueue_event(event_id: str, person_id: str, body: str):
    """Hand extraction to the background worker, or just do it.

    Serverless has no background: the invocation freezes the moment the
    response is sent, so a queued item would sit there until the instance is
    recycled and the claim would never be written. Inline costs the caller an
    LLM round-trip; silently losing the extraction costs the graph.
    """
    if settings.SERVERLESS or not _tasks:
        await _extract_now(event_id, person_id, body)
        return
    await extraction_queue.put((event_id, person_id, body))


async def _extract_now(event_id: str, person_id: str, body: str):
    try:
        async with db.pool().acquire() as conn:
            claim_ids = await extraction.process_event(conn, event_id, person_id, body)
        await sse.publish("extraction_complete", {
            "event_id": event_id, "person_id": person_id, "claim_count": len(claim_ids),
        })
        if claim_ids:
            await sse.publish("claim_extracted", {
                "event_id": event_id, "person_id": person_id, "claim_ids": claim_ids,
            })
    except Exception:
        logger.exception("inline extraction failed for event %s", event_id)


async def _extraction_worker():
    while True:
        event_id, person_id, body = await extraction_queue.get()
        try:
            async with db.pool().acquire() as conn:
                claim_ids = await extraction.process_event(conn, event_id, person_id, body)
            # Visible no-ops beat silence: always emit a count, even zero.
            await sse.publish("extraction_complete", {
                "event_id": event_id, "person_id": person_id, "claim_count": len(claim_ids),
            })
            if claim_ids:
                await sse.publish("claim_extracted", {
                    "event_id": event_id, "person_id": person_id, "claim_ids": claim_ids,
                })
        except Exception:
            logger.exception("extraction failed for event %s", event_id)
        finally:
            extraction_queue.task_done()


def start_workers():
    _tasks.append(asyncio.create_task(_extraction_worker()))


def stop_workers():
    for t in _tasks:
        t.cancel()
    _tasks.clear()
