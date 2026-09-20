"""Write path: one event in, zero or more grocery-relevant claims out."""

import asyncpg

from config import settings
from db import vector_literal
from embeddings import embed, cosine
import canonicalization
import llm

# Absolute noise floor applied at write time -- distinct from the 0.6
# profile-display floor, which is enforced at query time so that a single
# low-confidence observation still sits in the graph for debugging.
EXTRACTION_MIN_CONFIDENCE = 0.3

VALID_CLAIM_KINDS = (
    "dietary", "mobility", "budget", "preference",
    # v2: matching signal for any-favor ranking
    "has_item", "skill", "interest", "availability",
)


async def process_event(conn: asyncpg.Connection, event_id: str, person_id: str, body: str) -> list[str]:
    raw_claims = llm.extract_claims(body)
    written_ids = []

    for rc in raw_claims:
        confidence = float(rc.get("confidence", 0))
        if confidence < EXTRACTION_MIN_CONFIDENCE:
            continue

        evidence = (rc.get("evidence") or "").strip()

        # The core hallucination guard: the quoted evidence must be a literal
        # substring of the input, or the claim is discarded outright.
        #
        # We locate the span ourselves rather than trusting the model's
        # character offsets -- LLMs reliably quote but unreliably count, so a
        # correct quote routinely comes back with wrong indices. Verifying the
        # quote is the guarantee that matters; the offsets are just bookkeeping.
        if not evidence:
            continue
        start = body.find(evidence)
        if start == -1:
            lowered = body.lower().find(evidence.lower())
            if lowered == -1:
                continue  # not actually in the message -- invented
            start = lowered
        end = start + len(evidence)

        label = rc.get("label", "").strip()
        kind = rc.get("kind", "").strip()
        if not label or kind not in VALID_CLAIM_KINDS:
            continue

        canonical = await canonicalization.resolve_canonical(conn, label)
        raw_embedding = embed(label)

        claim_id = await _corroborate_and_write(
            conn, person_id, kind, canonical, label, confidence,
            raw_embedding, event_id, start, end,
        )
        written_ids.append(claim_id)

    return written_ids


async def _corroborate_and_write(
    conn: asyncpg.Connection, person_id: str, kind: str, canonical: str,
    raw_label: str, confidence: float, embedding: list[float],
    event_id: str, span_start: int, span_end: int,
) -> str:
    """§4 corroboration rule: same-kind claims above 0.85 cosine are treated as
    the same claim (observations++, confidence via noisy-OR) rather than a new row.
    """
    existing = await conn.fetch(
        "SELECT id, confidence, embedding, observations FROM claims "
        "WHERE person_id = $1 AND kind = $2 AND superseded_by IS NULL",
        person_id, kind,
    )

    best_id, best_sim, best_conf, best_obs = None, -1.0, None, None
    for row in existing:
        existing_vec = _parse_vector(row["embedding"])
        sim = cosine(embedding, existing_vec)
        if sim > best_sim:
            best_sim, best_id, best_conf, best_obs = sim, row["id"], row["confidence"], row["observations"]

    if best_sim > settings.CORROBORATION_SIM_THRESHOLD:
        new_conf = 1 - (1 - best_conf) * (1 - confidence)  # noisy-OR
        await conn.execute(
            "UPDATE claims SET confidence = $1, observations = observations + 1 WHERE id = $2",
            new_conf, best_id,
        )
        return str(best_id)

    row = await conn.fetchrow(
        "INSERT INTO claims (person_id, kind, canonical, raw_label, confidence, embedding, "
        "event_id, span_start, span_end, observations) "
        "VALUES ($1, $2, $3, $4, $5, $6::vector, $7, $8, $9, 1) RETURNING id",
        person_id, kind, canonical, raw_label, confidence,
        vector_literal(embedding), event_id, span_start, span_end,
    )
    return str(row["id"])


def _parse_vector(value) -> list[float]:
    if isinstance(value, str):
        return [float(x) for x in value.strip("[]").split(",")]
    return list(value)
