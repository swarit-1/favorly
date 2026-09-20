# Vision Opt-Out Model — Testing Guide

## Overview
This guide verifies that the vision opt-out model implementation is working correctly. The opt-out model means:
- **ALL detected items** are automatically shown in the review list
- Users can **toggle items OFF** before attaching them
- **No items** are added if nothing was detected

## Implementation Changes

### 1. Backend (`backend/routes/vision.py`)
- ✅ Removed `should_restock` filter from `_add_items_to_trip()`
- ✅ Now adds **ALL** detected items with valid non-empty names
- ✅ Log message changed from "No items marked for restocking" → "No items detected to add"

### 2. Frontend — Add List Screen (`favorly_mobile/lib/screens/add_list_screen.dart`)
- ✅ `_continue()` now reads `visionSessionProvider.lastAnalysis` for photo mode
- ✅ New `_parsedDetectedItems()` method extracts detected items from vision result
- ✅ Correctly handles null analysis, empty arrays, and invalid item data

### 3. Frontend — Review List Screen (`favorly_mobile/lib/screens/review_list_screen.dart`)
- ✅ `_DraftRow` now has `onRemove` callback for quick opt-out
- ✅ Replaced chevron icon with visible × remove button
- ✅ Users can remove items without opening the edit sheet

## Test Plan

### Environment Setup

```bash
# Terminal 1: Start backend (already running on :8000)
cd backend && uvicorn app:app --reload --port 8000

# Terminal 2: Start mobile app
cd favorly_mobile && flutter run

# Or with specific device:
flutter run -d <device-id>
```

### Test Cases

#### Test 1: Happy Path — All Items Detected and Displayed

**Steps:**
1. Open the app and navigate to a trip
2. Tap "Add your list"
3. Switch to "Photo" tab
4. Tap "Take a photo" to open camera
5. Take/confirm a photo (anything will work with mock vision service)
6. After analysis completes, you should see "Use this photo" button
7. Tap "Use this photo"

**Expected Result:**
- ✅ ReviewListScreen shows **3 detected items**:
  - "Milk"
  - "Greek Yogurt"
  - "Bread"
- ✅ Each item shows with quantity, optional price, and × remove button
- ✅ All items are visible (not in edit sheet)

**What's happening:**
```
PhotoReviewScreen (analysis completes)
  ↓
VisionApiClient returns mock data
  ↓
visionSessionProvider.addAnalysisResult()
  ↓
AddListScreen._continue() reads lastAnalysis
  ↓
_parsedDetectedItems() extracts detected_items from result['detected_items']
  ↓
ReviewListScreen displays all 3 items
```

---

#### Test 2: Opt-Out — Remove Unwanted Items

**Prerequisite:** Complete Test 1 and be at ReviewListScreen

**Steps:**
1. On ReviewListScreen, look at the item rows
2. Tap × button (far right) on "Greek Yogurt" row
3. Verify the row disappears immediately
4. Tap × button on "Bread" row
5. Only "Milk" should remain
6. Tap "Attach 1 item" button

**Expected Result:**
- ✅ × button removes items from the list immediately (no confirmation)
- ✅ Item count updates in button label ("Attach 2 items" → "Attach 1 item")
- ✅ Proceeding with attachment only includes remaining items

**What's happening:**
```
User taps × button
  ↓
_DraftRow.onRemove callback fires
  ↓
setState(() => _items.removeAt(i))
  ↓
List rebuilds with item removed
  ↓
Button label updates: "Attach N items"
```

---

#### Test 3: Edit — Modify Item Details (Not Just Remove)

**Prerequisite:** Complete Test 1 and be at ReviewListScreen

**Steps:**
1. On ReviewListScreen, tap on "Greek Yogurt" item (not the × button, but the item row)
2. ItemEditSheet should open
3. Edit the name to "Fage Greek Yogurt"
4. Add a note: "32oz container"
5. Set max price to "6.99"
6. Tap "Save"
7. Verify the item is updated in the list with the new details

**Expected Result:**
- ✅ Tapping the row (not ×) opens the edit sheet
- ✅ Changes are saved and reflected in the list
- ✅ Edit and remove are two separate workflows

**What's happening:**
```
User taps item row
  ↓
_DraftRow.onTap callback fires
  ↓
_ReviewListScreenState._edit(i) opens ItemEditSheet
  ↓
User modifies and saves
  ↓
setState() updates _items[index] with new ItemDraft
```

---

#### Test 4: Text/Voice Input Still Works

**Prerequisite:** Be at AddListScreen

**Steps:**
1. Switch to "Type" tab
2. Enter: "milk\noat milk\nbread"
3. Tap "Review list"

**Expected Result:**
- ✅ ReviewListScreen shows 3 items (all parsed from text)
- ✅ Same × remove button workflow works
- ✅ Text mode is unaffected by vision changes

**What's happening:**
```
AddListScreen._continue() with photo mode? NO → use text mode
  ↓
ref.read(storeProvider).drafts(IntakeSource.text, text: _text.text)
  ↓
DemoStore parses text into ItemDraft[]
  ↓
ReviewListScreen displays all items from text
```

---

#### Test 5: No Items Detected (Edge Case)

**Steps:**
1. (Optional) Temporarily mock an empty detected_items array in backend
2. Or wait for a scenario where vision returns empty
3. Navigate to AddListScreen → Photo tab → capture photo
4. If no items detected, you should see a message

**Expected Result:**
- ✅ If `detected_items: []`, ReviewListScreen shows:
  - "Check your list" title
  - "We couldn't find any items. Add them below." message
  - User can manually add items with + button
- ✅ "Attach list" button is disabled (no items to attach)

**What's happening:**
```
Backend detects 0 items
  ↓
VisionAnalysisResult has detected_items: []
  ↓
_parsedDetectedItems([]) returns []
  ↓
ReviewListScreen.drafts = [] (empty)
  ↓
"Attach" button disabled (canAttach checks _items.isNotEmpty)
```

---

#### Test 6: Flagged Items (Uncertain Confidence)

**Prerequisite:** Complete Test 1, be at ReviewListScreen

**Steps:**
1. Look at items in the list
2. Check if any are highlighted with attention color
3. If flagged, you should see:
   - Amber/attention background color
   - ⚠️ icon with "Check this" message
   - "Looks right" button to confirm

**Expected Result:**
- ✅ Flagged items have visible visual distinction
- ✅ "Looks right" button marks item as confirmed
- ✅ Can still use × to remove flagged items
- ✅ Cannot attach until all flagged items are confirmed or removed

**What's happening:**
```
Backend might mark items with needsConfirmation: true
  ↓
_DraftRow checks draft.needsConfirmation
  ↓
If true, shows attention color and confirms button
  ↓
User taps "Looks right" → _confirm(i) → draft.needsConfirmation = false
```

---

#### Test 7: Capacity Caps

**Prerequisite:** Complete Test 1

**Steps:**
1. On ReviewListScreen, note the trip's caps (e.g., "Up to 5 items, $50 total")
2. Try to add more items manually (+ button) to exceed caps
3. Verify notice appears: "Over [Shopper]'s cap of..."
4. Verify "Attach" button becomes disabled

**Expected Result:**
- ✅ Notice appears when exceeding item or dollar caps
- ✅ "Attach" button is disabled (cannot proceed)
- ✅ Removing items until within caps re-enables attach

**What's happening:**
```
canAttach = !_reading && _items.isNotEmpty && flagged == 0 && !overItems && !overDollars
  ↓
If overItems || overDollars, Notice widget shown
  ↓
Button disabled if !canAttach
```

---

## Data Flow Diagram

```
📱 Camera App
   └─> PhotoReviewScreen
        └─> analyzePantry()
            └─> Vision API / Backend
                 └─> MockVisionService.analyze_pantry_vision()
                     └─> {
                           "detected_items": [
                             {"name": "Milk", ...},
                             {"name": "Greek Yogurt", ...},
                             {"name": "Bread", ...}
                           ]
                         }
                 └─> Backend._add_items_to_trip()
                     └─> Adds ALL items to Supabase
                         (no should_restock filter)

   ↓ User taps "Use this photo"

AddListScreen
   └─> _continue()
       └─> if photo mode:
           └─> ref.read(visionSessionProvider).lastAnalysis
               └─> _parsedDetectedItems(analysis)
                   └─> Extracts analysis.result['detected_items']
                       └─> [ItemDraft(name: "Milk"), ...]

   ↓

ReviewListScreen
   ├─> Shows all detected items
   ├─> Each item has:
   │   ├─> Name, quantity, price inputs
   │   ├─> "Looks right" button (if flagged)
   │   └─> × remove button (opt-out)
   │
   ├─> User can:
   │   ├─> Tap row to edit details
   │   ├─> Tap × to remove item (opt-out)
   │   └─> Tap "Looks right" to confirm flagged items
   │
   └─> Tap "Attach N items" → store.attachRequest()
       └─> Only includes items that weren't removed
```

---

## Verification Checklist

- [ ] All 3 detected items appear in ReviewListScreen (not in edit sheet)
- [ ] × button is visible and clickable on each item
- [ ] × button removes items immediately (no confirmation dialog)
- [ ] Item count updates in "Attach N items" button
- [ ] Tapping item row (not ×) opens edit sheet
- [ ] Edit and remove are separate workflows
- [ ] Text/voice modes still work normally
- [ ] Empty detection handled gracefully
- [ ] Flagged items show visual distinction
- [ ] Capacity caps enforced correctly
- [ ] "Attach" button disabled until requirements met
- [ ] Attached items appear in trip detail screen

---

## Troubleshooting

### Items not appearing in review screen
- [ ] Check `visionSessionProvider.lastAnalysis` is set (backend returns analysis)
- [ ] Verify `analysis.result['detected_items']` is non-null (check backend response)
- [ ] Confirm `_parsedDetectedItems()` isn't filtering out items (check name field)

### × button not removing items
- [ ] Verify `_DraftRow` has `onRemove` parameter (check constructor)
- [ ] Verify call site passes `onRemove: () => setState(() => _items.removeAt(i))`
- [ ] Check that `CupertinoButton` has correct `onPressed` callback

### Items appearing from old code
- [ ] Verify `AddListScreen._continue()` uses `_parsedDetectedItems()` for photo mode
- [ ] Verify NOT calling `store.drafts(IntakeSource.photo)` (old hardcoded demo)

### Backend not adding items to database
- [ ] Verify `_add_items_to_trip()` removed `should_restock` filter
- [ ] Check items have valid non-empty `name` field
- [ ] Verify Supabase connection is working (`/health` endpoint)

---

## Success Criteria

✅ **Implementation is complete when:**
1. All detected items display in ReviewListScreen (not in edit sheet)
2. Users can opt-out of unwanted items with × button
3. Edit and remove workflows are separate and both work
4. Complete flow: Camera → Analysis → Review → Attach works end-to-end
5. All edge cases handled (empty, null, invalid data)
6. Text/voice modes unaffected

---

## Next Steps After Testing

1. **QA Sign-off:** Verify all test cases pass
2. **Performance Testing:** Check with larger photo sets (4+ photos)
3. **User Testing:** Observe user interactions with opt-out UI
4. **Dogfooding:** Use in real shopping trip scenarios
5. **Backend Optimization:** If needed, optimize pantry scan storage/retrieval

---

**Last Updated:** 2026-09-20  
**Implementation Status:** ✅ Complete, ready for testing
