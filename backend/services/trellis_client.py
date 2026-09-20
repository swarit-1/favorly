"""Client for the Trellis agent + graph service (see /agents and
"Agent & Graph Service Spec.md" §1: "the texting service receives an inbound
[signal] and POSTs it to /events. It does not interpret it... Everything that
looks like judgment happens [in Trellis]; everything that looks like plumbing
happens [here]").

Favorly's errand-coordination flow plays the same "plumbing" role the spec
assigns to the texting service: a trip handoff is a real-world favor, and a
parsed request is a message that might carry capability/need signal. Both are
forwarded here, fire-and-forget, so an outage in Trellis never breaks a trip.

Both services share one id space because both read the same identity:
`auth.users.id` == `users.id` == the `person_id` Trellis stores. There is no
registration step -- creating the user's auth account and `users` profile row
at signup is what makes them visible to Trellis, through its `app_people` view.
"""

import logging
import os

import httpx

logger = logging.getLogger("favorly.trellis_client")

TRELLIS_BASE_URL = os.getenv("TRELLIS_BASE_URL", "http://localhost:8010")
_TIMEOUT = httpx.Timeout(2.0)


async def _post(path: str, payload: dict) -> None:
    try:
        async with httpx.AsyncClient(base_url=TRELLIS_BASE_URL, timeout=_TIMEOUT) as client:
            resp = await client.post(path, json=payload)
            if resp.status_code >= 400:
                logger.warning("trellis %s returned %s: %s", path, resp.status_code, resp.text)
    except httpx.HTTPError as e:
        # Never let a Trellis outage break the errand-coordination flow.
        logger.warning("trellis %s call failed: %s", path, e)


async def log_favor(giver_id: str, receiver_id: str, description: str) -> None:
    """A trip handoff is a real-world favor -- the strongest edge signal Trellis has (§6)."""
    await _post("/favors", {
        "giver_id": str(giver_id), "receiver_id": str(receiver_id), "description": description,
    })


async def log_event(person_id: str, body: str, source_key: str | None = None) -> None:
    """Forward raw text so Trellis's extraction pipeline can mine capability/need
    signal from it -- never interpreted here (§1)."""
    payload = {"person_id": str(person_id), "kind": "message", "body": body}
    if source_key:
        payload["source_key"] = source_key
    await _post("/events", payload)
