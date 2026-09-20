# Favorly mobile

Flutter client for Favorly: one neighbor's trip carries the whole building.
One codebase runs on iOS, Android, and the web.

## Run it

```sh
flutter pub get
flutter run -d <device>        # iPhone simulator, Android emulator, or chrome
flutter build web              # static site in build/web
```

The app runs fully offline against seeded demo data (`lib/state/demo_store.dart`).
Every mutation in that store is annotated with the backend route it maps to,
so wiring `backend/app.py` is a one-for-one swap.

### One-device demo

Open the **You** tab and switch neighbors under **Demo** to see the same trip
from the shopper's side (Ana) or a requester's side (Chloe). The shopper's
"waiting for an answer" screen also has a labeled **Demo · Answer as Chloe**
shortcut so the substitution beat works on a single phone.

Demo invite code: `MAPLE7` (used by the join screen after **Leave circle**).

## Design

- Tokens live in `lib/theme/tokens.dart`: Meta's public palette (cobalt
  `#0064E0`, ink `#1C2B33`, soft surface `#F1F4F7`), one accent, contrast
  figures in the comments.
- Type is Figtree (bundled, OFL), the closest open face to Meta's Optimistic.
  Caveat renders the handwritten list in the demo camera preview.
- Screens use the widgets in `lib/widgets/`: `FavorlyPage` (scrolling body +
  sticky bottom actions that rise above the keyboard), `Panel`/`PanelRow`,
  `FButton` (pill), `TripHero` (the one saturated surface), `Viewfinder` and
  friends for camera stand-ins.
- Camera, microphone, and realtime are stand-ins: swap `Viewfinder`'s child for
  a live preview, `VoiceCaptureSheet` for a recorder, and `DemoStore` for the
  API + Supabase realtime.

## Tests

```sh
flutter test                                                # widget tests
flutter test --run-skipped -t golden --update-goldens       # regenerate screenshots
```

`test/screens_golden_test.dart` walks the whole demo loop on an iPhone-sized
surface with the real fonts and writes one PNG per screen to `test/goldens/`.
It is skipped by default (see `dart_test.yaml`) because rendering differs
slightly across platforms.

## iOS builds from an iCloud folder

If this checkout lives under `~/Documents` with iCloud Drive syncing, the iOS
build fails with `resource fork, Finder information, or similar detritus not
allowed` while codesigning `Flutter.framework`. macOS tags synced files with
extended attributes as they are written. Either move the checkout outside the
synced folder or build a copy:

```sh
rsync -a --exclude build --exclude .dart_tool --exclude .git . /tmp/favorly_mobile/
cd /tmp/favorly_mobile && flutter build ios --simulator --debug
```

Plugins resolve through Swift Package Manager
(`flutter config --enable-swift-package-manager`), so CocoaPods is optional.
