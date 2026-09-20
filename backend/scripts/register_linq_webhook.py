"""One-shot: subscribe the Favorly backend to Linq inbound-message webhooks.

Usage:
    LINQ_API_KEY=... python scripts/register_linq_webhook.py https://<your-tunnel>.ngrok.app
"""

import os
import sys

import httpx

BASE_URL = os.getenv("LINQ_BASE_URL", "https://api.linqapp.com")


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: register_linq_webhook.py <public-base-url>")
    public_url = sys.argv[1].rstrip("/")

    resp = httpx.post(
        f"{BASE_URL}/api/partner/v3/webhook-subscriptions",
        headers={
            "Authorization": f"Bearer {os.environ['LINQ_API_KEY']}",
            "Content-Type": "application/json",
        },
        json={
            "target_url": f"{public_url}/webhooks/linq?version=2026-02-03",
            "subscribed_events": ["message.received"],
        },
        timeout=15,
    )
    print(resp.status_code, resp.text)


if __name__ == "__main__":
    main()
