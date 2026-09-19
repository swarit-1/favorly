# Lane B — AI / Vision

Owner: _TBD_ · Depends on: A (contracts, H2) · Blocks: D (needs cached fixtures for every demo beat)
Models this lane must emit: [`docs/SPEC_v0.md`](../SPEC_v0.md) §3.3. Fallback chain: §5.6.

## Mission
Three perception calls that always return valid contract JSON in <12s, behind one interface, with a
provider chain that never lets the demo block on an API. Perception only — matching lives in Lane A.

## In scope
- `ai/vision_service.py` — `VisionService` Protocol:
  ```python
  class VisionService(Protocol):
      async def parse_list(self, source: ParseSource, *, text: str | None = None, image: bytes | None = None) -> ParsedList: ...
      async def identify_shelf_candidates(self, item: Item, image: bytes) -> ShelfCandidates: ...
      async def split_receipt(self, image: bytes) -> ReceiptSplit: ...
  ```
- Adapters: `MuseSparkVision` (Meta Model API via `openai.AsyncOpenAI(base_url=META_BASE_URL)`), `OpenAIVision` (`gpt-4o`, `response_format=json_schema` from `Model.model_json_schema()`), `MockVision` (returns `ai/fixtures/`), `CachedVision` (hash-keyed fixture store, SPEC §5.6).
- `FallbackVision(primary, secondary, cache)` — timeout 12s each, 1 repair retry on `pydantic.ValidationError`, records `{provider, latency_ms, raw_text}` on every call.
- `ai/speech.py` — `transcribe(audio: bytes) -> str` via Whisper `whisper-1`; Deepgram fallback.
- `ai/prompts/` — one file per surface, versioned (`parse_list_v1.md`…). Prompts include the JSON schema and the rules in SPEC §5.1/§5.3.
- `ai/image.py` — normalize: EXIF rotate, downscale longest side to 1600px, JPEG q85, strip metadata.
- `ai/fixtures/` — for each staged demo image from Lane D: `{sha256}.json` cached output + a human-readable copy (`parsed_list_handwritten_demo.json`, `shelf_demo.json`, `receipt_demo.json`).
- `ai/eval/` — tiny harness: run each surface over `eval/inputs/*` and report schema-valid rate, latency p50/p95, and (for receipts) whether totals reconcile.

## Out of scope
Section assignment, receipt→item matching, settlement math, substitution re-ranking (all Lane A). Any UI. Any persistence beyond the fixture cache.

## Prompting rules (all surfaces)
- Temperature 0. System prompt = role + schema + "Return only JSON matching the schema."
- **Never invent.** Uncertain → `confidence < 0.7` and `needs_confirmation=true` (lists) or omit (shelf/receipt).
- Receipt: instruct the model to copy `description` verbatim, compute nothing — `subtotal`, `tax`, `total` must be read from the receipt. Our validator reconciles; on failure the repair prompt says which sum is off by how much.
- Shelf: pass `item.name`, `item.note`, `item.max_price`; ask for ≤4 candidates visible on the shelf, price only if legible, `reason` ≤120 chars.
- Voice "Post Trip" (PRD §8 beat 1): transcript → `parse_trip(text) -> TripDraft{store, depart_at, confidence}` using the same text path (pending PM decision SPEC §7.4).

## Provider config
```
VISION_PROVIDER=muse|openai|mock        # primary
VISION_FALLBACK=openai|mock             # secondary
META_BASE_URL, META_API_KEY, OPENAI_API_KEY, DEEPGRAM_API_KEY
VISION_CACHE_DIR=ai/fixtures
```

## Milestones
- **H0–2:** Confirm at the Meta booth: Muse Spark endpoint, model name, whether `response_format=json_schema` is honored, rate limits, image input format (SPEC §7.1). `MockVision` returns hand-written fixtures so A and C are unblocked.
- **H2–8:** `OpenAIVision` for all three surfaces working on Lane D's staged images; `FallbackVision` + `CachedVision`; Whisper transcription.
- **H8–14:** `MuseSparkVision` as primary; prompt iteration until eval harness shows 100% schema-valid on demo inputs and receipt reconciliation passes; latency p95 <12s.
- **H14–18:** Shelf prompt tuning with the pre-staged shelf photo (must return the intended substitute in top-3 with the right price).
- **H18–22:** Record cached fixtures for **every** demo image (list photo, shelf, receipt, handoff) and for the voice transcript. Deliver `ai/fixtures/MANIFEST.md` (image → fixture → expected UI outcome) to Lane D.

## Acceptance
- `uv run pytest ai/` green: adapters mocked, fallback chain order verified, cache hit on second call, `image.normalize` idempotent.
- `uv run python -m ai.eval` on demo inputs: schema-valid 100%, receipt reconciles, p95 latency <12s (real providers; run once with `VISION_PROVIDER=muse` and once with `openai`).
- Pulling the network cable (`VISION_PROVIDER=mock`) still completes every demo beat with the cached fixtures.

## Risks
- Muse Spark image input or JSON mode differs from OpenAI → adapter absorbs it; contract does not change.
- Handwriting parse quality → Lane D stages a legible list; `needs_confirmation` flow covers the rest.
