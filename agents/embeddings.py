"""Embedding client. Caches by text hash (§12 rate-limit mitigation: canonical
labels get embedded once, ever). MOCK_LLM=1 uses a deterministic pseudo-embedding
so canonicalization/corroboration logic is fully exercisable with no network call.
"""

import hashlib
import math
from functools import lru_cache

from config import settings

_client = None


def _get_client():
    global _client
    if _client is None:
        from openai import OpenAI
        _client = OpenAI(api_key=settings.EMBEDDING_API_KEY, base_url=settings.EMBEDDING_BASE_URL)
    return _client


def _mock_embedding(text: str) -> list[float]:
    """Deterministic, hash-seeded pseudo-embedding. Not semantically meaningful,
    but stable across calls so identical/near-identical text hashes similarly,
    which is enough to exercise corroboration (exact repeats) end to end offline.
    """
    dim = settings.EMBEDDING_DIM
    seed = int(hashlib.sha256(text.strip().lower().encode()).hexdigest(), 16)
    vec = []
    x = seed
    for i in range(dim):
        x = (x * 6364136223846793005 + 1442695040888963407) % (2 ** 64)
        vec.append((x / 2 ** 64) * 2 - 1)
    norm = math.sqrt(sum(v * v for v in vec)) or 1.0
    return [v / norm for v in vec]


@lru_cache(maxsize=4096)
def _cached_embed(text: str) -> tuple:
    if settings.MOCK_LLM:
        return tuple(_mock_embedding(text))
    client = _get_client()
    resp = client.embeddings.create(model=settings.EMBEDDING_MODEL, input=text)
    return tuple(resp.data[0].embedding)


def embed(text: str) -> list[float]:
    return list(_cached_embed(text))


def cosine(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a)) or 1.0
    nb = math.sqrt(sum(y * y for y in b)) or 1.0
    return dot / (na * nb)
