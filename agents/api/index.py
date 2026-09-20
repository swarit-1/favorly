"""Vercel entrypoint for the Trellis agent + graph service.

The service's modules import each other as top-level names (`import db`,
`import extraction`), which works locally because uvicorn runs from inside
this directory. Put it on sys.path so the same imports resolve here.

Deployed as its own Vercel project (root directory: agents/) because a Vercel
project serves one app, and the errand API is already the other one.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import app  # noqa: E402

__all__ = ["app"]
