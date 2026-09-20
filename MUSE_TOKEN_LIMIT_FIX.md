# Muse API Token Limit Fix

**Date**: 2026-09-20  
**Issue**: Muse Vision API returning `finish_reason: "length"` (token limit exceeded)  
**Solution**: Increased max_tokens from 2048 to 4096 with environment variable override

---

## Problem

The Muse Spark API was hitting token limits during image analysis:

```
finish_reason: "length"
WARNING: Muse API returned empty content (finish_reason: length)
ERROR: Muse API returned no content (finish_reason: length) - may have hit token limit
```

This happened because:
1. Image analysis with detailed JSON responses requires more tokens
2. Multiple images in one request multiply token usage
3. Detailed pantry item descriptions use more tokens
4. Default was too low: `max_tokens=2048`

---

## Solution Implemented

### Changes Made

**File**: `backend/services/vision_service.py`

#### 1. VisionService (Muse API)
```python
# Before
self.model = os.getenv("MUSE_MODEL", "muse-spark-1.3")

# After
self.model = os.getenv("MUSE_MODEL", "muse-spark-1.3")
# Max tokens for vision responses (image analysis returns detailed JSON)
# Default 4096 for detailed responses. Configurable via MUSE_MAX_TOKENS env var
self.max_tokens = int(os.getenv("MUSE_MAX_TOKENS", "4096"))
```

#### 2. OpenAIVisionService (OpenAI fallback)
```python
# Before
self.model = "gpt-4-vision"

# After
self.model = "gpt-4-vision"
# Max tokens for vision responses
# Configurable via OPENAI_MAX_TOKENS env var, default 4096
self.max_tokens = int(os.getenv("OPENAI_MAX_TOKENS", "4096"))
```

#### 3. Updated all API calls to use configurable max_tokens
```python
# Before
"max_tokens": 2048,

# After (Muse)
"max_tokens": self.max_tokens,

# After (OpenAI)
max_tokens=self.max_tokens,
```

### Configuration

**File**: `backend/.env`

```bash
# Max tokens for Muse API responses (image analysis needs detailed JSON)
# Default: 4096. Increase if getting "finish_reason: length" errors
MUSE_MAX_TOKENS=4096

# Max tokens for OpenAI Vision API fallback
# Default: 4096
OPENAI_MAX_TOKENS=4096
```

---

## Token Limits by Use Case

### Recommended Settings

| Use Case | Max Tokens | Why |
|----------|-----------|-----|
| Pantry scan (1-2 images) | 4096 | Detailed item lists with descriptions |
| Receipt analysis | 4096 | Line-by-line items + amounts |
| Damage detection | 4096 | Multiple damage areas with descriptions |
| Shelf substitution | 4096 | Alternative products with explanations |

### If Still Hitting Limit

If you still see `finish_reason: "length"` errors, increase the values:

**Option 1: Environment Variable**
```bash
# In backend/.env
MUSE_MAX_TOKENS=8192
OPENAI_MAX_TOKENS=8192
```

**Option 2: For testing**
```bash
# In terminal before running backend
export MUSE_MAX_TOKENS=8192
export OPENAI_MAX_TOKENS=8192
uvicorn app:app --port 8000
```

### Maximum Recommended Values

- **Muse Spark**: Up to 16,384 tokens (model limit)
- **OpenAI GPT-4V**: Up to 4,096 tokens (model limit for vision)

However, higher values:
- Increase API costs
- Increase latency (slower responses)
- May hit rate limits if processing many images

---

## Testing the Fix

### 1. Verify Configuration is Loaded

```bash
# Check the health endpoint
curl http://localhost:8000/vision/health
curl http://localhost:8000/vision/config
```

Expected output:
```json
{
    "status": "ok",
    "vision_service": "real_with_fallback",
    "muse_api_key_configured": true,
    "muse_api_endpoint": "https://api.meta.ai/v1"
}
```

### 2. Test Pantry Scan

```bash
# Create a test image
python3 << 'EOF'
import base64
# Minimal valid JPEG
jpeg_base64 = "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAv/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8VAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCwAA8A/9k="
with open('/tmp/test.jpg', 'wb') as f:
    f.write(base64.b64decode(jpeg_base64))
print("✅ Test image created")
EOF

# Test pantry scan endpoint
curl -s -X POST http://localhost:8000/vision/grocery/pantry-scan \
  -F "files=@/tmp/test.jpg" | python3 -m json.tool
```

Expected behavior:
- No `finish_reason: "length"` errors
- Response completes successfully
- Falls back gracefully if Muse fails

### 3. Check Logs

```bash
# Watch for max_tokens being used
tail -f /tmp/uvicorn.log | grep -E "Max tokens|finish_reason"
```

---

## How Token Limits Work

### Muse Spark API

The response uses **OpenAI-compatible format** (streaming-style):

```json
{
  "choices": [{
    "finish_reason": "stop" | "length" | "error",
    "message": {"content": "...detailed JSON response..."}
  }]
}
```

- `finish_reason: "stop"` = Complete response ✅
- `finish_reason: "length"` = Hit token limit, response truncated ❌
- `finish_reason: "error"` = API error ❌

### Cost Impact

From Meta's pricing (approximate):
- **Muse Spark 1.3**: Input tokens cheaper than output
- Higher `max_tokens` = potentially higher cost
- Actual cost depends on:
  - Image count (preprocessing tokens)
  - Actual output used (not reserved)
  - Prompt length

**Recommendation**: Use 4096 as baseline. Only increase if needed.

---

## Environment Setup Reference

### Complete backend/.env with token limits

```bash
# Supabase
SUPABASE_URL=https://lkvtmyvqytvsmfbauepa.supabase.co
SUPABASE_KEY=sb_publishable_...
SUPABASE_SERVICE_ROLE_KEY=sb_secret_...

# Vision APIs
MUSE_API_KEY=LLM_...
MUSE_API_BASE_URL=https://api.meta.ai/v1
MUSE_MODEL=muse-spark-1.3
MUSE_MAX_TOKENS=4096          # ← Token limit for Muse

OPENAI_API_KEY=sk-...
OPENAI_MAX_TOKENS=4096        # ← Token limit for OpenAI fallback

# Image storage
AWS_S3_BUCKET=favorly-images
AWS_REGION=us-east-1

# Server
ENVIRONMENT=development
PORT=8000
```

---

## Monitoring & Debugging

### Enable Debug Logging

In `backend/app.py` or your logging config:

```python
import logging
logging.getLogger("backend.services.vision_service").setLevel(logging.DEBUG)
```

This will show:
- Token counts in request
- Response lengths
- `finish_reason` values
- Provider fallback decisions

### Common Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| `finish_reason: "length"` | Response truncated | Increase MUSE_MAX_TOKENS |
| Empty response | API failure | Check MUSE_API_KEY, endpoint URL |
| 404 "model not found" | OpenAI key issues | Check OPENAI_API_KEY, quota |
| Slow responses | High token limits | Reduce max_tokens, optimize prompt |

---

## Verification Checklist

- [x] `MUSE_MAX_TOKENS` environment variable added to backend/.env
- [x] `OPENAI_MAX_TOKENS` environment variable added to backend/.env
- [x] VisionService uses `self.max_tokens` from env (default 4096)
- [x] OpenAIVisionService uses `self.max_tokens` from env (default 4096)
- [x] All API calls use `self.max_tokens` instead of hardcoded 2048
- [x] Print statements show actual max_tokens being used
- [x] No `finish_reason: "length"` errors on pantry scans
- [x] Fallback chain works: Muse → OpenAI → Mock

---

## Summary

**Before**: Fixed max_tokens of 2048 → hits limit on detailed image analysis  
**After**: Configurable max_tokens with 4096 default → handles detailed responses

The fix is **backwards compatible** and environment-driven. No code changes needed for the default case; just restart the backend.

```bash
# Restart backend with new env vars
pkill -f "uvicorn app:app"
cd backend && .venv/bin/uvicorn app:app --port 8000
```

---

**Generated**: 2026-09-20  
**For**: HackMIT 2026 - Favorly v2 Demo  
**Issue**: Muse Vision API token limit errors  
**Status**: ✅ RESOLVED
