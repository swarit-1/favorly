"""LLM calls, scoped to grocery-relevant extraction. All structured output.
Every function has a MOCK_LLM=1 fixture path (rule-based, deterministic,
offline) so the pipeline is fully testable without an API key.

Real calls use an OpenAI-compatible chat completions endpoint with
response_format={"type": "json_object"}.
"""

import json
import re

from config import settings

_client = None


def _get_client():
    global _client
    if _client is None:
        from openai import OpenAI
        _client = OpenAI(api_key=settings.LLM_API_KEY, base_url=settings.LLM_BASE_URL)
    return _client


def _chat_json(system: str, user: str) -> dict:
    client = _get_client()
    resp = client.chat.completions.create(
        model=settings.LLM_MODEL,
        messages=[{"role": "system", "content": system}, {"role": "user", "content": user}],
        response_format={"type": "json_object"},
        temperature=0.3,
    )
    return json.loads(resp.choices[0].message.content)


# ============================================================================
# Extraction: grocery-relevant claims only (dietary / mobility / budget /
# preference) -- no capability/need/affinity mining, no matchmaking signal.
# ============================================================================

EXTRACTION_SYSTEM_PROMPT = """You extract grocery-relevant facts from one
message in a neighborhood grocery-run app. Only extract facts that matter for
grocery trips: dietary restrictions or preferences, mobility (car access,
ability to carry bags, need for a ride), budget constraints, or store/brand
preferences. Rules that matter more than the rest:
1. Every claim must quote a literal, verbatim substring of the input as
   `evidence`, with its exact character span. Not a paraphrase.
2. Return an empty array freely -- most messages contain nothing relevant.
   Do not invent a claim rather than returning nothing.
3. Confidence is about the inference, not the writing.
4. Nothing outside dietary/mobility/budget/preference -- no general
   capabilities, hobbies, or life-stage facts unrelated to grocery shopping.
Return JSON: {"claims": [{"kind": "dietary|mobility|budget|preference",
"label": str, "confidence": float, "evidence": str, "span": [start, end]}]}"""

# Compact rule table used by the mock extractor. Scoped to grocery-relevant
# signal only -- exists so the pipeline (span verification, canonicalization,
# corroboration) is exercisable end to end with zero network calls.
_MOCK_RULES = [
    (r"vegetarian|vegan\b", "dietary", "vegetarian", 0.75),
    (r"gluten[- ]free|celiac", "dietary", "gluten free", 0.75),
    (r"lactose[- ]intoler|dairy[- ]free", "dietary", "dairy free", 0.75),
    (r"allergic to \w+|nut allergy|peanut allergy", "dietary", "food allergy", 0.7),
    (r"kosher|halal", "dietary", "dietary observance", 0.7),
    (r"don't have a car|no car|not driving|can't drive", "mobility", "no car access", 0.7),
    (r"\bi have a (car|truck|suv)\b|happy to drive|can drive", "mobility", "has car access", 0.7),
    (r"can't carry|trouble carrying|heavy bags are hard", "mobility", "needs help carrying bags", 0.65),
    (r"tight (on cash|budget)|on a budget|watching my spending", "budget", "budget conscious", 0.6),
    (r"always shop at (trader joe'?s|whole foods|costco|aldi)", "preference", "store preference", 0.6),
    (r"only buy organic|prefer organic", "preference", "prefers organic", 0.6),
    (r"brand loyal|always get the same brand", "preference", "brand preference", 0.55),
]


def _extract_claims_mock(body: str) -> list[dict]:
    claims = []
    seen_labels = set()
    for pattern, kind, label, confidence in _MOCK_RULES:
        m = re.search(pattern, body, re.IGNORECASE)
        if not m:
            continue
        if label in seen_labels:
            continue
        seen_labels.add(label)
        start, end = m.span()
        claims.append({
            "kind": kind,
            "label": label,
            "confidence": confidence,
            "evidence": body[start:end],  # literal substring, by construction
            "span": [start, end],
        })
        if len(claims) >= 5:
            break
    return claims


def extract_claims(body: str) -> list[dict]:
    """One event body in, zero or more raw claim dicts out."""
    if settings.MOCK_LLM:
        return _extract_claims_mock(body)
    try:
        result = _chat_json(EXTRACTION_SYSTEM_PROMPT, body)
        return result.get("claims", [])
    except Exception:
        return []


# ============================================================================
# Canonicalization adjudication (middle similarity band only)
# ============================================================================

DECIDE_SYSTEM_PROMPT = """You decide which favors a neighbor should do in a
neighborhood grocery app.

You are given a `helper` (the person you're advising) and a list of
`candidates` -- open requests from neighbors, each already scored by the
graph. The graph did the retrieval; you make the judgment call about which
are actually worth doing, in what order, and how to frame each one.

The signals attached to each candidate mean:
- trip: the helper already has a grocery trip planned that covers this. This
  is the strongest practical reason -- the errand is nearly free to them.
- reciprocity: that neighbor has done favors FOR THE HELPER recently. Never
  state this the other way round -- the helper has not helped them. Each
  candidate's `true_facts` spells out the direction; copy it faithfully.
- mutual: they share connections in the neighborhood.
- fit: the helper's situation complements the need (e.g. has a car, neighbor
  doesn't).
- freshness: how recently it was posted.

Rules:
- You may reorder, and you may DROP a candidate that isn't worth surfacing.
  You may NOT invent a candidate: every need_id you return must appear in the
  input.
- Each candidate's `true_facts` is the authoritative list of what is true,
  already written in second person. Lift them almost verbatim -- do not
  restate one backwards, embellish it, or add facts of your own. No invented
  names, stores, numbers, times, or details. If you aren't given a store name,
  don't name one.
- Write to the helper as "you". Never say "the helper", and never echo the
  field names or formatting of this input.
- `title`: under 6 words, imperative, names the item and the neighbor's first
  name, e.g. "Grab oat milk for Bob".
- `action`: one short line describing what they'd actually do.
- `reason`: one sentence, under 25 words, saying why this person specifically.
  Never imply debt or obligation -- no "you owe them" or "pay it back".
- Be concrete, not vague. Use the specifics you were given: name the mutual
  connection ("you both know Maya") rather than saying "mutual friends"; name
  the store; say what they actually asked for. A specific reason is the whole
  point -- a generic one is worse than none.
- `effort`: "low" if it's on a trip they're already making, otherwise judge it.
- Return them best-first.

Return JSON: {"favors": [{"need_id": str, "title": str, "action": str,
"reason": str, "effort": "low"|"medium"|"high"}]}"""


def decide_favors(context: dict) -> list[dict] | None:
    """Let the model choose and frame the favors, using the graph's context.

    Returns None when unavailable (MOCK_LLM, no key, API error, malformed
    output) so the caller falls back to the deterministic graph ranking.
    """
    if settings.MOCK_LLM or not settings.LLM_API_KEY:
        return None
    try:
        result = _chat_json(DECIDE_SYSTEM_PROMPT, json.dumps(context, default=str))
        favors = result.get("favors")
        return favors if isinstance(favors, list) else None
    except Exception:
        return None


def adjudicate_canonical(raw_label: str, candidates: list[tuple[str, float]]) -> str:
    """candidates: top-3 (canonical_label, similarity). Returns a canonical label --
    either one of the candidates, or a decision that this is genuinely new (in which
    case the caller mints raw_label as the new canonical).
    """
    if not candidates:
        return raw_label
    if settings.MOCK_LLM:
        # Heuristic stand-in: snap to the closest candidate since we don't have a
        # real judgment call offline.
        return candidates[0][0]
    try:
        system = (
            "Decide whether a new label refers to the same underlying concept as one "
            "of the candidate canonical labels, or is genuinely distinct. "
            'Return JSON: {"canonical": str} -- either an exact candidate label, or the '
            "raw label itself if none fit."
        )
        user = json.dumps({"raw_label": raw_label, "candidates": [c for c, _ in candidates]})
        result = _chat_json(system, user)
        return result.get("canonical", raw_label)
    except Exception:
        return candidates[0][0]
