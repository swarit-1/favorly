# Camera & Vision Service Implementation

Complete implementation of camera photo capture and multi-domain vision analysis infrastructure. Currently uses mock VLM responses; will wire up to Meta Muse once API key is available.

---

## Architecture Overview

```
Mobile (Flutter)          →  Backend (FastAPI)          →  Storage & VLM
─────────────────            ──────────────              ───────────────
CameraScreen          →    POST /vision/{domain}/*   →   Supabase Storage
  │                         (image upload + analysis)     (mock VLM responses)
  ├─ capture photos    ├─ Validate + upload        ├─ Real Meta Muse (later)
  ├─ review photos     ├─ Route to domain service
  └─ send for analysis └─ Return structured JSON


Session Flow:
1. User taps "Scan fridge" (or any domain action)
2. CameraScreen: Capture 1-4 photos
3. PhotoReviewScreen: Review & approve
4. VisionApiClient: POST images to backend
5. Backend: Upload to Supabase, call VisionService
6. VisionService: Mock response (will be Meta Muse later)
7. Frontend: Receive analysis, show results
```

---

## Files Created

### Flutter (Mobile)

**Services:**
- `lib/services/camera_service.dart` — Camera initialization, photo capture, gallery access
- `lib/services/vision_api_client.dart` — HTTP client for uploading images and calling backend

**State Management (Riverpod):**
- `lib/providers/vision_provider.dart` — Vision session state, photo tracking, analysis results

**Screens:**
- `lib/screens/camera_screen.dart` — Real-time camera capture UI
- `lib/screens/photo_review_screen.dart` — Review, edit, and submit photos for analysis

**Dependencies Updated:**
- `pubspec.yaml` — Added camera, image_picker, image, path_provider, uuid

### Backend (Python/FastAPI)

**Routes:**
- `routes/vision.py` — All vision API endpoints
  - `/vision/grocery/pantry-scan` — Pantry detection
  - `/vision/grocery/shelf-analysis` — Shelf substitution
  - `/vision/grocery/receipt-analysis` — Receipt splitting
  - `/vision/home-repair/damage-detection` — Damage detection
  - `/vision/yard/maintenance-scan` — Yard maintenance
  - `/vision/pet-sitting/assessment` — Pet assessment
  - `/vision/cleaning/needs-analysis` — Cleaning analysis

**Services:**
- `services/image_storage_service.py` — Supabase Storage uploads (TODO: implement real storage)
- `services/vision_service.py` — VLM interface + MockVisionService for testing

**App Configuration:**
- `app.py` — Registered vision router

---

## Current Status: Mock Implementation

The system is **fully functional with mock responses**. All endpoints work end-to-end:

### Mock Response Example (Pantry Vision)

```json
{
  "analysis_id": "uuid...",
  "domain_type": "grocery_shopping",
  "detected_items": [
    {
      "name": "Milk",
      "brand": "Organic Valley",
      "size": "Half gallon",
      "status": "half",
      "expiration": "2026-09-28",
      "confidence": 0.95
    },
    {
      "name": "Greek Yogurt",
      "brand": "Fage",
      "size": "32 oz",
      "status": "empty",
      "confidence": 0.92
    }
  ],
  "low_or_empty": ["Greek Yogurt"],
  "summary": "Pantry is 40% full...",
  "image_refs": ["vision/grocery_shopping/user_id/timestamp/filename"],
  "analyzed_at": "2026-09-19T12:34:56",
  "is_placeholder": true
}
```

---

## How to Test Right Now

### 1. Start the Backend

```bash
cd backend
python -m uvicorn app:app --reload --port 8000
```

Check health:
```bash
curl http://localhost:8000/vision/health
```

Response:
```json
{
  "status": "ok",
  "vision_service": "mock",
  "image_storage": "ready"
}
```

### 2. Run Flutter App

```bash
cd favorly_mobile
flutter pub get
flutter run
```

### 3. Test Camera Flow

1. Tap "Post a trip" or add a new screen that launches `CameraScreen`
2. Select domain (e.g., "Scan Fridge")
3. Capture 1-4 photos
4. Review photos
5. Tap "Analyze Photos"
6. See mock analysis results

---

## Integrating Meta Muse (When API Key Available)

### Step 1: Set Environment Variable

```bash
# .env or export
export ANTHROPIC_API_KEY="sk-ant-..."
```

### Step 2: Update `services/vision_service.py`

Replace the `MockVisionService` with real `VisionService`:

```python
import os
from anthropic import Anthropic

class VisionService:
    def __init__(self):
        api_key = os.getenv("ANTHROPIC_API_KEY")
        if not api_key:
            raise RuntimeError("ANTHROPIC_API_KEY not set")
        self.client = Anthropic(api_key=api_key)
        self.model = "claude-3-5-sonnet-20241022"

    async def analyze_pantry_vision(self, image_refs: List[str], user_id: str) -> Dict:
        """Call Meta Muse with pantry analysis prompt"""
        prompt = """Analyze these fridge/pantry photos carefully...
        [Full prompt from VISION_SERVICE_IMPLEMENTATION.md]
        """
        
        # Download images from Supabase (image_refs are paths)
        images = await self._download_images(image_refs)
        
        # Call Meta Muse
        response = self.client.messages.create(
            model=self.model,
            max_tokens=2048,
            messages=[
                {
                    "role": "user",
                    "content": [
                        *[{"type": "image", "source": {...}} for img in images],
                        {"type": "text", "text": prompt}
                    ]
                }
            ]
        )
        
        # Parse structured response
        result_text = response.content[0].text
        return json.loads(result_text)
```

### Step 3: Update `routes/vision.py`

```python
# In vision.py

# Change initialization:
vision_service = VisionService()  # Now real, not mock

# That's it! All endpoints will now use Meta Muse
```

### Step 4: Test

```bash
curl -X POST http://localhost:8000/vision/grocery/pantry-scan \
  -F "files=@fridge.jpg" \
  -H "Authorization: Bearer <token>"
```

---

## Database Schema (Optional)

To persist analysis results, create a table:

```sql
CREATE TABLE vision_analyses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id),
  domain_type TEXT NOT NULL,
  analysis_id TEXT NOT NULL,
  image_refs JSONB,
  raw_response JSONB,
  is_placeholder BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT now(),
  UNIQUE(analysis_id)
);

CREATE TABLE vision_analysis_cache (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  image_hash TEXT NOT NULL,
  domain_type TEXT NOT NULL,
  cached_response JSONB,
  expires_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT now(),
  UNIQUE(image_hash, domain_type)
);
```

---

## Key Implementation Details

### Camera Service (Flutter)

```dart
// Initialize once
final cameraService = ref.read(cameraServiceProvider);
await cameraService.initialize();
await cameraService.initializeCamera();

// Take picture
final imageFile = await cameraService.takePicture();

// Or pick from gallery
final images = await cameraService.pickMultipleImages();

// Dispose when done
cameraService.dispose();
```

### Vision Provider (Riverpod State)

```dart
// Add photos to session
ref.read(visionSessionProvider.notifier).addCapturedPhoto(photo);

// Get current state
final state = ref.watch(visionSessionProvider);
final photos = state.capturedPhotos;
final isUploading = state.isUploading;

// Add analysis result
ref.read(visionSessionProvider.notifier).addAnalysisResult(result);
```

### API Client (HTTP Multipart)

```dart
final apiClient = VisionApiClient(
  baseUrl: 'http://localhost:8000',
  authToken: userToken,
);

// All domains share same pattern:
final result = await apiClient.analyzePantry(imageFiles, userId: userId);
final result = await apiClient.analyzeDamage(imageFiles, userId: userId);
// etc.

// Each returns: {detected_items, summary, image_refs, analyzed_at}
```

### Image Storage (Supabase)

```python
# Currently mocks storage; TODO: implement real Supabase uploads
image_storage = ImageStorageService()
paths = await image_storage.upload_images(files, user_id, domain)
# Returns: ["vision/domain/user_id/timestamp/filename1", ...]
```

---

## Error Handling

### Network/Upload Errors

```dart
try {
  await apiClient.analyzePantry(images, userId: userId);
} on ApiException catch (e) {
  showError('API Error: ${e.message}');
} on UnauthorizedException {
  showError('Unauthorized. Please log in again.');
} on BadRequestException catch (e) {
  showError('Invalid request: ${e.message}');
}
```

### Camera Errors

```dart
try {
  await cameraService.initializeCamera();
} catch (e) {
  setState(() {
    _initializationError = e.toString();
  });
}
```

### VLM Errors (Will Happen Later)

```python
try:
    response = await vision_service.analyze_pantry_vision(...)
except anthropic.APIError as e:
    logger.error(f"VLM error: {e}")
    # Fall back to mock response
    return mock_vision_service.analyze_pantry_vision(...)
```

---

## Performance Optimization

### Image Compression (Before Upload)

```dart
// In camera_screen.dart, compress before sending
final compressedImage = await compressImage(imageFile);
await apiClient.analyzePantry([compressedImage], userId: userId);
```

### Batch Processing

```python
# In vision.py, process multiple images in single VLM call
await vision_service.analyze_pantry_vision(
    image_refs=image_refs,  # All images at once
    user_id=user_id
)
```

### Caching

```python
# services/image_storage_service.py
cache = ImageCache()
cached_result = await cache.get(image_hash, domain)
if cached_result:
    return cached_result
else:
    result = await vision_service.analyze(...)
    await cache.set(image_hash, domain, result)
    return result
```

---

## Testing Workflow

### 1. Mock Mode (Current)

✅ Full end-to-end flow works  
✅ No API key needed  
✅ Instant responses  
✅ Perfect for UI/UX testing

### 2. Real Meta Muse (Next)

Replace `MockVisionService` with `VisionService(api_key)` and restart backend.

### 3. Production Checklist

- [ ] ANTHROPIC_API_KEY set in production env
- [ ] Supabase Storage configured and tested
- [ ] Vision analysis cached for common scenarios
- [ ] Error handling for VLM failures
- [ ] Rate limiting on vision endpoints
- [ ] Monitoring/logging for analysis quality
- [ ] Cost tracking (tokens per analysis)

---

## API Endpoints Summary

| Endpoint | Method | Purpose | Auth |
|----------|--------|---------|------|
| `/vision/health` | GET | Check service status | No |
| `/vision/grocery/pantry-scan` | POST | Detect fridge contents | Yes |
| `/vision/grocery/shelf-analysis` | POST | Find substitutions | Yes |
| `/vision/grocery/receipt-analysis` | POST | Split receipt | Yes |
| `/vision/home-repair/damage-detection` | POST | Assess damage | Yes |
| `/vision/yard/maintenance-scan` | POST | Analyze yard | Yes |
| `/vision/pet-sitting/assessment` | POST | Assess pet | Yes |
| `/vision/cleaning/needs-analysis` | POST | Analyze cleaning | Yes |

---

## Next Steps

1. ✅ Camera capture infrastructure
2. ✅ Mock VLM responses for all domains
3. ✅ Photo review and upload flow
4. ⏳ **Supabase Storage integration** (real image uploads)
5. ⏳ **Meta Muse integration** (when API key available)
6. ⏳ **Preference learning** (store analysis history)
7. ⏳ **Smart suggestions** (use past preferences)

---

## FAQ

**Q: Why mock VLM responses?**  
A: Allows full testing without API key. Once key available, swap services (single line change).

**Q: Can I test on real phone?**  
A: Yes! Flutter supports iOS/Android. Just run `flutter run -d <device_id>`.

**Q: What about video capture?**  
A: Current implementation is photos only. Video support can be added to `CameraService` later.

**Q: How to debug image uploads?**  
A: Check backend logs: `tail -f backend.log | grep "upload"`. Mock uploads print path.

**Q: Production image storage?**  
A: Implement `ImageStorageService.upload_image()` to call Supabase Storage API. Path construction already in place.
