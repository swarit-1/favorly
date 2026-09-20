"""Vercel entrypoint.

Vercel's Python runtime imports this file and serves the ASGI app it exports.
`app.py` imports `routes` and `shared` as top-level packages, so the backend
directory has to be on sys.path — locally that happens because uvicorn is run
from inside it; here we do it explicitly.

Note: Vercel does not run ASGI lifespan events, so the startup Supabase check
in app.py is skipped. /health performs the same check per request.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import app  # noqa: E402

__all__ = ["app"]
