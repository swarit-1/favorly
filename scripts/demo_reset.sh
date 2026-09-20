#!/usr/bin/env bash
# One button before going on stage. Reseeds the block scenario, clears the
# backend agent's in-memory state, and warms both services (Trellis on Vercel
# cold-starts slowly -- ping three times; ping again 60s before going on).
set -uo pipefail

BACKEND_URL="${BACKEND_URL:-http://localhost:8000}"
TRELLIS_URL="${TRELLIS_URL:-http://localhost:8010}"

echo "== reseeding block scenario on Trellis ($TRELLIS_URL)"
curl -s -m 120 -X POST "$TRELLIS_URL/admin/demo/reset" -H 'Content-Type: application/json' || {
  echo "!! demo reset failed"; exit 1; }
echo

echo "== clearing backend agent in-memory state"
curl -s -m 10 -X POST "$BACKEND_URL/webhooks/linq/reset" || echo "!! backend reset route unreachable"
echo

echo "== warmup pings (3x each)"
for i in 1 2 3; do
  printf "  trellis /health:  "; curl -s -m 20 "$TRELLIS_URL/health"; echo
  printf "  backend /health:  "; curl -s -m 20 "$BACKEND_URL/health"; echo
done

echo "== ready. Ping /health once more 60s before going on."
