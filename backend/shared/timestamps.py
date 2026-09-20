"""Parsing Postgres timestamps on Python 3.10.

Postgres trims trailing zeros off fractional seconds, so Supabase hands back
strings like '2026-09-20T03:25:05.41256' (5 digits). Python 3.10's
`datetime.fromisoformat` only accepts exactly 3 or 6 fractional digits and
raises on everything else — which means roughly one row in ten blows up a
whole endpoint. Python 3.11+ is tolerant; until the runtime moves, parse
through here.
"""

import re
from datetime import datetime

_FRACTION = re.compile(r"(\.\d+)")


def parse_timestamp(value: str | datetime) -> datetime:
    """`datetime.fromisoformat`, but tolerant of any number of fractional digits."""
    if isinstance(value, datetime):
        return value

    def pad(match: re.Match) -> str:
        digits = match.group(1)[1:][:6]
        return "." + digits.ljust(6, "0")

    return datetime.fromisoformat(_FRACTION.sub(pad, value, count=1))
