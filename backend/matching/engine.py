"""Matching engine — SPEC_v0 §4.1 section assignment plus favor-ask ↔ trip scoring.

All functions are pure and deterministic so they can be tested without any
network or API key. rapidfuzz's token_set_ratio is the only dependency.
"""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Iterable, Optional

from rapidfuzz.fuzz import token_set_ratio

from shared.contracts.models import StoreSection, Trip, TripStatus

# ---------------------------------------------------------------------------
# §4.1 — Section assignment: keyword table + token_set_ratio ≥ 80 else OTHER
# ---------------------------------------------------------------------------

SECTION_KEYWORDS: dict[StoreSection, list[str]] = {
    StoreSection.PRODUCE: [
        "banana", "apple", "orange", "lemon", "lime", "avocado", "tomato",
        "onion", "garlic", "potato", "carrot", "celery", "lettuce", "spinach",
        "kale", "broccoli", "cucumber", "pepper", "mushroom", "berries",
        "strawberry", "blueberry", "grape", "mango", "cilantro", "basil",
        "ginger", "salad greens", "scallion",
    ],
    StoreSection.DAIRY: [
        "milk", "oat milk", "almond milk", "soy milk", "cheese", "cheddar",
        "mozzarella", "parmesan", "yogurt", "greek yogurt", "butter", "eggs",
        "cream", "half and half", "sour cream", "cream cheese", "cottage cheese",
    ],
    StoreSection.MEAT: [
        "chicken", "chicken breast", "beef", "ground beef", "steak", "pork",
        "bacon", "sausage", "turkey", "ham", "salmon", "shrimp", "fish",
        "tofu", "deli meat", "hot dogs",
    ],
    StoreSection.BAKERY: [
        "bread", "sourdough", "bagel", "baguette", "tortilla", "croissant",
        "muffin", "bun", "rolls", "pita", "cake", "cookies",
    ],
    StoreSection.FROZEN: [
        "ice cream", "frozen pizza", "frozen berries", "frozen vegetables",
        "frozen peas", "popsicle", "frozen dumplings", "frozen waffles",
    ],
    StoreSection.PANTRY: [
        "rice", "pasta", "spaghetti", "cereal", "oats", "oatmeal", "flour",
        "sugar", "salt", "olive oil", "vegetable oil", "vinegar", "peanut butter",
        "jam", "honey", "beans", "canned beans", "chickpeas", "lentils",
        "canned tomatoes", "soup", "broth", "ramen", "granola", "chips",
        "crackers", "salsa", "soy sauce", "hot sauce", "ketchup", "mustard",
        "mayo", "spices", "protein bars", "nuts", "almonds", "trail mix",
        "chocolate", "candy",
    ],
    StoreSection.BEVERAGES: [
        "water", "sparkling water", "seltzer", "soda", "coke", "juice",
        "orange juice", "coffee", "coffee beans", "tea", "kombucha",
        "energy drink", "gatorade", "beer", "wine",
    ],
    StoreSection.HOUSEHOLD: [
        "paper towels", "toilet paper", "dish soap", "laundry detergent",
        "sponges", "trash bags", "aluminum foil", "plastic wrap", "ziploc",
        "batteries", "light bulb", "cleaner", "bleach", "wipes", "napkins",
        "air freshener",
    ],
    StoreSection.PERSONAL_CARE: [
        "toothpaste", "toothbrush", "shampoo", "conditioner", "soap",
        "body wash", "deodorant", "razor", "lotion", "sunscreen", "tylenol",
        "advil", "ibuprofen", "band aid", "vitamins", "medicine", "tampons",
        "pads", "floss", "chapstick", "contact solution",
    ],
}

SECTION_MATCH_CUTOFF = 80  # spec §4.1


def _normalize(name: str) -> str:
    """Lowercase, drop digits, naive-singularize tokens ('2 ripe bananas' → 'ripe banana')."""
    tokens = []
    for tok in name.lower().split():
        if tok.isdigit():
            continue
        if len(tok) > 3 and tok.endswith("s") and not tok.endswith("ss"):
            tok = tok[:-1]
        tokens.append(tok)
    return " ".join(tokens)


def assign_section(item_name: str) -> StoreSection:
    """Best-scoring section by max token_set_ratio over its keywords; ≥80 or OTHER."""
    name = _normalize(item_name)
    best_section, best_score = StoreSection.OTHER, 0.0
    for section, keywords in SECTION_KEYWORDS.items():
        score = max(token_set_ratio(name, _normalize(kw)) for kw in keywords)
        if score > best_score:
            best_section, best_score = section, score
    return best_section if best_score >= SECTION_MATCH_CUTOFF else StoreSection.OTHER


# ---------------------------------------------------------------------------
# Favor-ask ↔ trip scoring (agent recommendations)
#
# score = 0.5*coverage + 0.3*time_fit + 0.2*capacity
#   coverage  — fraction of the ask's items the trip's store plausibly carries
#   time_fit  — trips departing soon (but not already gone) score higher
#   capacity  — room left under the trip's max_requesters cap
# ---------------------------------------------------------------------------

MATCH_THRESHOLD = 0.45

# Which sections a store plausibly carries, keyed by keywords in the store name.
# Default (no keyword hit) = full-service grocery: everything.
_STORE_PROFILES: list[tuple[list[str], set[StoreSection]]] = [
    (
        ["cvs", "walgreens", "pharmacy", "rite aid"],
        {
            StoreSection.PERSONAL_CARE, StoreSection.HOUSEHOLD,
            StoreSection.BEVERAGES, StoreSection.PANTRY, StoreSection.OTHER,
        },
    ),
    (
        ["home depot", "hardware", "lowes", "ace"],
        {StoreSection.HOUSEHOLD, StoreSection.OTHER},
    ),
    (
        ["liquor", "wine", "beer"],
        {StoreSection.BEVERAGES, StoreSection.OTHER},
    ),
]

_ALL_SECTIONS = set(StoreSection)


def _store_sections(store: str) -> set[StoreSection]:
    lowered = store.lower()
    for keywords, sections in _STORE_PROFILES:
        if any(kw in lowered for kw in keywords):
            return sections
    return _ALL_SECTIONS


def _coverage(sections: Iterable[StoreSection], store: str) -> float:
    carried = _store_sections(store)
    sections = list(sections)
    if not sections:
        return 0.0
    hits = sum(1 for s in sections if s in carried or s is StoreSection.OTHER)
    return hits / len(sections)


def _time_fit(depart_at: datetime, now: datetime) -> float:
    """1.0 right up to departure, decaying the further out the trip is."""
    delta = depart_at - now
    if delta < timedelta(minutes=-15):
        return 0.0  # already left
    hours_out = max(delta.total_seconds(), 0) / 3600
    return max(0.0, 1.0 - hours_out / 12)  # linear decay over 12h


def _capacity(trip: Trip, current_requesters: int) -> float:
    cap = trip.caps.max_requesters
    return max(0.0, (cap - current_requesters) / cap)


def score_ask_for_trip(
    item_sections: Iterable[StoreSection],
    trip: Trip,
    current_requesters: int,
    now: Optional[datetime] = None,
) -> float:
    """Score how well a favor ask (its items' sections) fits an open trip."""
    if trip.status is not TripStatus.OPEN:
        return 0.0
    now = now or datetime.utcnow()
    return round(
        0.5 * _coverage(item_sections, trip.store)
        + 0.3 * _time_fit(trip.depart_at, now)
        + 0.2 * _capacity(trip, current_requesters),
        4,
    )


def rank_trips_for_ask(
    item_sections: list[StoreSection],
    trips: list[tuple[Trip, int]],  # (trip, current_requester_count)
    now: Optional[datetime] = None,
) -> list[tuple[Trip, float]]:
    """Open trips ranked best-first for a favor ask. Filters below MATCH_THRESHOLD."""
    scored = [
        (trip, score_ask_for_trip(item_sections, trip, n, now)) for trip, n in trips
    ]
    return sorted(
        [(t, s) for t, s in scored if s >= MATCH_THRESHOLD],
        key=lambda pair: pair[1],
        reverse=True,
    )


def recommend_asks_for_trip(
    asks: list[tuple[str, list[StoreSection]]],  # (ask_id, item sections)
    trip: Trip,
    current_requesters: int,
    now: Optional[datetime] = None,
) -> list[tuple[str, float]]:
    """Pending favor asks ranked best-first for a shopper's open trip."""
    scored = [
        (ask_id, score_ask_for_trip(sections, trip, current_requesters, now))
        for ask_id, sections in asks
    ]
    return sorted(
        [(a, s) for a, s in scored if s >= MATCH_THRESHOLD],
        key=lambda pair: pair[1],
        reverse=True,
    )
