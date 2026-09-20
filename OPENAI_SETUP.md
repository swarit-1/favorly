# OpenAI Vision API Setup Guide

## Overview

We've switched from Meta Muse to OpenAI's Vision API for grocery image analysis. This includes:
- Pantry scanning (detect products, quantities, expiration dates)
- Shelf substitution analysis (find alternatives for out-of-stock items)
- Receipt analysis (split costs among requesters)

## Security Reminder

⚠️ **NEVER share your API key in chat, email, or commit it to git.**

If you accidentally expose an API key:
1. Revoke it immediately in your OpenAI account
2. Generate a new one
3. Update your `.env` file locally

## Setup Steps

### 1. Get Your OpenAI API Key

1. Go to https://platform.openai.com/account/api-keys
2. Click "Create new secret key"
3. Copy the key (you can only see it once)
4. Store it securely

### 2. Create `.env` File (Local Only)

Create `/Users/joshuawu/favorly/backend/.env`:

```bash
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your_key_here
OPENAI_API_KEY=sk-proj-YOUR_KEY_HERE
ENVIRONMENT=development
PORT=8000
ANTHROPIC_API_KEY=sk-ant-...
```

**IMPORTANT:** Never commit this file. It's already in `.gitignore`.

### 3. Install Dependencies

```bash
cd /Users/joshuawu/favorly/backend
pip install -r requirements.txt
```

Or with uv:
```bash
uv pip install -r requirements.txt
```

### 4. Start the Backend

```bash
cd /Users/joshuawu/favorly/backend
python -m uvicorn app:app --reload --port 8000
```

Or with uv:
```bash
uv run uvicorn app:app --reload --port 8000
```

## Testing the Integration

### Test Pantry Scan

```bash
curl -X POST "http://localhost:8000/vision/grocery/pantry-scan" \
  -F "files=@/path/to/fridge/photo.jpg"
```

Expected response:
```json
{
  "analysis_id": "uuid",
  "domain_type": "grocery_shopping",
  "detected_items": [
    {
      "name": "Milk",
      "brand": "Organic Valley",
      "size": "Half gallon",
      "status": "half",
      "expiration": "2026-09-28",
      "confidence": 0.95
    }
  ],
  "summary": "About 40% full, mostly fresh...",
  "image_refs": [...],
  "analyzed_at": "2026-09-20T...",
  "is_placeholder": false
}
```

### Test Shelf Analysis

```bash
curl -X POST "http://localhost:8000/vision/grocery/shelf-analysis" \
  -F "file=@/path/to/shelf/photo.jpg" \
  -F "original_item=Greek Yogurt" \
  -F "user_preferences={\"type\": \"greek\", \"max_price\": 8}"
```

## API Endpoints

### Grocery-Focused (Real OpenAI)

- `POST /vision/grocery/pantry-scan` - Detect pantry items
- `POST /vision/grocery/shelf-analysis` - Find substitutions
- `POST /vision/grocery/receipt-analysis` - Split receipt costs

### Other Domains (Mock Data)

Until implemented, these return mock data:
- `POST /vision/home-repair/damage-detection`
- `POST /vision/yard/maintenance-scan`
- `POST /vision/pet-sitting/assessment`
- `POST /vision/cleaning/needs-analysis`

## Debugging

### Check Vision Service Status

```bash
curl http://localhost:8000/vision/health
```

Response:
```json
{
  "status": "ok",
  "vision_service": "real",  // or "mock"
  "image_storage": "ready"
}
```

### Enable Debug Logging

Set environment variable:
```bash
export LOG_LEVEL=DEBUG
python -m uvicorn app:app --reload
```

### Common Issues

**"OPENAI_API_KEY not set"**
- Check that `.env` file exists in `/Users/joshuawu/favorly/backend/`
- Verify the key is valid and not expired

**"Invalid image format"**
- Ensure JPG, PNG, GIF, or WebP format
- Images are automatically converted to base64

**"Response not valid JSON"**
- The API response might include markdown formatting
- The service automatically extracts JSON from responses

## Cost Estimation

OpenAI Vision API pricing (as of 2026-09):
- `gpt-4-turbo`: $0.01 per 1K input tokens, $0.03 per 1K output tokens
- Typical pantry scan: ~500-800 tokens (~$0.01)
- Typical shelf analysis: ~400-600 tokens (~$0.01)
- Typical receipt: ~800-1200 tokens (~$0.02)

**Note:** Images are expensive. A single image is ~170 tokens.

## Optimization Tips

1. **Compress images** before sending (max 1024x1024 maintains quality)
2. **Batch requests** when analyzing multiple items
3. **Cache results** for identical images
4. **Use detail: "low"** for quick scans, "high" for detailed analysis

## Next Steps

- [ ] Implement home repair/damage detection
- [ ] Implement yard maintenance analysis
- [ ] Add image caching layer
- [ ] Add token usage metrics/monitoring
- [ ] Implement fallback to Claude for high-detail analysis

## Questions?

Refer to OpenAI docs: https://platform.openai.com/docs/guides/vision
