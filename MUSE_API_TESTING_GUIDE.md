# Meta Muse API Testing Guide

## Quick Start Testing

### 1. Check Service Status
```bash
curl http://localhost:8000/vision/health | python3 -m json.tool
```

Expected output:
```json
{
    "status": "ok",
    "vision_service": "real_with_fallback",
    "image_storage": "ready",
    "muse_api_key_configured": true,
    "muse_api_endpoint": "https://graph.meta.com/v19.0"
}
```

### 2. Check Configuration
```bash
curl http://localhost:8000/vision/config | python3 -m json.tool
```

Expected output:
```json
{
    "vision_service_type": "FallbackVisionService",
    "muse_api_key_set": true,
    "muse_api_endpoint": "https://graph.meta.com/v19.0",
    "fallback_enabled": true,
    "real_service_available": false
}
```

## Test Endpoints

### Test Pantry Scan
```bash
# Create a test image
python3 << 'EOF'
import base64
jpeg_base64 = "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAv/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8VAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCwAA8A/9k="
with open('/tmp/test_image.jpg', 'wb') as f:
    f.write(base64.b64decode(jpeg_base64))
print("✅ Test image created")
EOF

# Test the endpoint
curl -s -X POST http://localhost:8000/vision/grocery/pantry-scan \
  -F "files=@/tmp/test_image.jpg" | python3 -m json.tool
```

### Test Shelf Analysis
```bash
curl -s -X POST http://localhost:8000/vision/grocery/shelf-analysis \
  -F "file=@/tmp/test_image.jpg" \
  -F "original_item=Greek Yogurt" \
  -F "user_preferences={\"brand_pref\": \"organic\"}" | python3 -m json.tool
```

### Test Receipt Analysis
```bash
curl -s -X POST http://localhost:8000/vision/grocery/receipt-analysis \
  -F "file=@/tmp/test_image.jpg" \
  -F "trip_id=trip_12345" \
  -F "merged_list=[{\"name\": \"Milk\", \"requester\": \"Bob\"}]" | python3 -m json.tool
```

### Test Other Domains
```bash
# Damage detection
curl -s -X POST http://localhost:8000/vision/home-repair/damage-detection \
  -F "files=@/tmp/test_image.jpg" | python3 -m json.tool

# Yard maintenance
curl -s -X POST http://localhost:8000/vision/yard/maintenance-scan \
  -F "files=@/tmp/test_image.jpg" | python3 -m json.tool

# Pet assessment
curl -s -X POST http://localhost:8000/vision/pet-sitting/assessment \
  -F "files=@/tmp/test_image.jpg" \
  -F "pet_info={\"type\": \"dog\", \"breed\": \"labrador\"}" | python3 -m json.tool

# Cleaning analysis
curl -s -X POST http://localhost:8000/vision/cleaning/needs-analysis \
  -F "files=@/tmp/test_image.jpg" | python3 -m json.tool
```

## Response Format

All vision endpoints return a consistent format:

```json
{
    "analysis_id": "uuid-string",
    "domain_type": "grocery_shopping|home_repair|yard_work|pet_sitting|cleaning",
    "detected_items": [...],
    "summary": "Brief summary of findings",
    "image_refs": ["path/to/image.jpg"],
    "analyzed_at": "2026-09-20T08:38:37.713066",
    "is_placeholder": true|false
}
```

**Note**: `is_placeholder: true` means the system used mock data (either because the real API failed or wasn't available).

## Testing the Real Muse API

When the actual Muse API endpoint is verified and accessible:

1. **Verify the API endpoint**:
   ```bash
   # Check your Meta Muse API documentation for the correct endpoint
   export MUSE_API_BASE_URL="https://your-actual-muse-endpoint/v1"
   ```

2. **Restart the backend**:
   ```bash
   pkill -f "uvicorn app:app"
   python3 -m uvicorn app:app --port 8000
   ```

3. **Check health endpoint**:
   ```bash
   curl http://localhost:8000/vision/health
   ```
   Should show `"vision_service": "real_with_fallback"` and eventually `"real_service_available": true` if connection succeeds.

4. **Monitor logs for API calls**:
   ```bash
   # Watch for "📡 Calling Meta Muse API" messages
   tail -f /tmp/uvicorn.log | grep -E "Muse|API|response"
   ```

## Debugging

### Check Current Configuration
```bash
curl http://localhost:8000/vision/config
```

### View Backend Logs
```bash
# If running in background
tail -50 /tmp/uvicorn.log

# If running in foreground
# Press Ctrl+C to stop viewing, logs appear in console
```

### Test Specific API Endpoint
```bash
python3 << 'EOF'
import httpx
import asyncio
import json

async def test_muse():
    async with httpx.AsyncClient() as client:
        url = "https://graph.meta.com/v19.0/me/messages"
        headers = {
            "Authorization": "Bearer your_api_key",
            "Content-Type": "application/json",
        }
        
        try:
            response = await client.post(url, json={}, headers=headers, timeout=10)
            print(f"Status: {response.status_code}")
            print(f"Response: {response.text}")
        except Exception as e:
            print(f"Error: {e}")

asyncio.run(test_muse())
EOF
```

## Understanding Fallback Behavior

### When Fallback Activates
- Muse API endpoint is unreachable (DNS/network error)
- API returns 4xx or 5xx error
- API request times out
- API key is invalid or expired
- Unexpected response format

### How to Know if Fallback is Active
1. Check `is_placeholder: true` in response
2. Check health endpoint: `"vision_service": "fallback_to_mock"`
3. Check logs for error messages before fallback

### Fallback Provides
- Realistic mock data for testing
- Same response format as real API
- Consistent behavior across calls
- System continues to work without real API

## Performance Testing

### Response Time
```bash
# Measure response time with timing breakdown
curl -w "@/tmp/curl_format.txt" -s http://localhost:8000/vision/health
```

Create `/tmp/curl_format.txt`:
```
    time_namelookup:  %{time_namelookup}s\n
       time_connect:  %{time_connect}s\n
    time_appconnect:  %{time_appconnect}s\n
   time_pretransfer:  %{time_pretransfer}s\n
       time_redirect:  %{time_redirect}s\n
  time_starttransfer:  %{time_starttransfer}s\n
                     ----------\n
          time_total:  %{time_total}s\n
```

### Load Testing with Multiple Requests
```bash
#!/bin/bash
for i in {1..10}; do
    curl -s -X POST http://localhost:8000/vision/grocery/pantry-scan \
      -F "files=@/tmp/test_image.jpg" > /dev/null &
done
wait
echo "✅ 10 concurrent requests completed"
```

## Next Steps

1. **Verify Real Muse API Endpoint**
   - Confirm correct endpoint URL with Meta
   - Test connection with manual curl request
   - Update `MUSE_API_BASE_URL` if different

2. **Validate API Response Format**
   - Test real API responses
   - Adjust response parsing if needed
   - Update prompts if necessary

3. **Performance Optimization**
   - Monitor response times
   - Implement caching if needed
   - Optimize image preprocessing

4. **Production Readiness**
   - Test with production credentials
   - Configure rate limiting
   - Set up monitoring and alerting
