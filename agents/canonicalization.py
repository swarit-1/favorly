"""Entity resolution: embed-and-snap against a growing canonical vocabulary,
scoped to grocery-relevant concepts (dietary, mobility, budget, preference).
"""

import re
from typing import Optional

import asyncpg

from config import settings
from embeddings import embed, cosine
import llm

# Seed vocabulary: grocery-relevant concepts only.
SEED_LABELS = [
    "vegetarian", "vegan", "gluten free", "dairy free", "food allergy",
    "dietary observance", "no car access", "has car access",
    "needs help carrying bags", "budget conscious", "store preference",
    "prefers organic", "brand preference",
]

# In-process cache: canonical -> embedding. Populated at startup, appended to
# whenever mint_new() creates a genuinely new concept.
_vocab_cache: dict[str, list[float]] = {}


def normalize_new_label(raw_label: str) -> str:
    """Turn a raw label into a canonical-looking slug."""
    slug = re.sub(r"[^a-z0-9]+", " ", raw_label.lower()).strip()
    return slug


async def seed_vocabulary(conn: asyncpg.Connection):
    rows = await conn.fetch("SELECT canonical, embedding FROM canonical_labels")
    for row in rows:
        _vocab_cache[row["canonical"]] = _parse_vector(row["embedding"])

    for label in SEED_LABELS:
        if label in _vocab_cache:
            continue
        vec = embed(label)
        await _persist_canonical(conn, label, vec)


def _parse_vector(value) -> list[float]:
    if isinstance(value, str):
        return [float(x) for x in value.strip("[]").split(",")]
    return list(value)


async def _persist_canonical(conn: asyncpg.Connection, canonical: str, vec: list[float]):
    from db import vector_literal
    await conn.execute(
        "INSERT INTO canonical_labels (canonical, embedding) VALUES ($1, $2::vector) "
        "ON CONFLICT (canonical) DO NOTHING",
        canonical, vector_literal(vec),
    )
    _vocab_cache[canonical] = vec


def nearest_canonical(raw_embedding: list[float]) -> Optional[tuple[str, float]]:
    """Best match against the in-memory vocabulary. None if vocabulary is empty."""
    best = None
    best_sim = -1.0
    for canonical, vec in _vocab_cache.items():
        sim = cosine(raw_embedding, vec)
        if sim > best_sim:
            best_sim = sim
            best = canonical
    if best is None:
        return None
    return best, best_sim


def top_candidates(raw_embedding: list[float], n: int = 3) -> list[tuple[str, float]]:
    scored = [(c, cosine(raw_embedding, v)) for c, v in _vocab_cache.items()]
    scored.sort(key=lambda x: x[1], reverse=True)
    return scored[:n]


async def _ensure_vocab_loaded(conn: asyncpg.Connection):
    """Lazily populate the in-process cache. Without this, any caller that runs
    extraction without going through app startup (a script, a worker in a fresh
    process) sees an empty vocabulary, snaps to nothing, and mints a duplicate
    concept for every label -- which is how you end up with 'car access' and
    'has car access' as separate canonicals that never match each other."""
    if not _vocab_cache:
        await seed_vocabulary(conn)


async def resolve_canonical(conn: asyncpg.Connection, raw_label: str) -> str:
    """The embed-and-snap decision."""
    await _ensure_vocab_loaded(conn)
    raw_vec = embed(raw_label)
    nearest = nearest_canonical(raw_vec)

    if nearest is None:
        canonical = normalize_new_label(raw_label)
        await _persist_canonical(conn, canonical, raw_vec)
        return canonical

    canonical, sim = nearest
    if sim > settings.CANON_SNAP_THRESHOLD:
        return canonical
    if sim > settings.CANON_ADJUDICATE_THRESHOLD:
        candidates = top_candidates(raw_vec, 3)
        decided = llm.adjudicate_canonical(raw_label, candidates)
        if decided not in _vocab_cache:
            # Model decided this is genuinely new, or returned the raw label verbatim.
            decided = normalize_new_label(decided)
            await _persist_canonical(conn, decided, raw_vec)
        return decided

    new_canonical = normalize_new_label(raw_label)
    await _persist_canonical(conn, new_canonical, raw_vec)
    return new_canonical
