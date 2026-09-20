"""Deterministic matching algorithms (SPEC_v0 §4) — no API key required."""

from .engine import (
    SECTION_KEYWORDS,
    assign_section,
    score_ask_for_trip,
    rank_trips_for_ask,
    recommend_asks_for_trip,
    MATCH_THRESHOLD,
)

__all__ = [
    "SECTION_KEYWORDS",
    "assign_section",
    "score_ask_for_trip",
    "rank_trips_for_ask",
    "recommend_asks_for_trip",
    "MATCH_THRESHOLD",
]
