# Favorly style guide

Scope: the Flutter app in `favorly_mobile/`. The code is the source of truth
(`lib/theme/tokens.dart`, `lib/theme/theme.dart`, `lib/widgets/`); this file
explains the rules behind it so new screens look like the existing ones.

## Principles

1. **One trip, one card.** The blue `TripHero` is the only saturated surface in
   the app. Everything else is white canvas, hairline panels, and ink text.
2. **One accent.** Meta cobalt marks actions, selection, and progress. It is
   never decoration. If two blue things sit next to each other, one is wrong.
3. **Show exceptions, not admin.** Flag the uncertain row, collapse what is
   already right, and let people confirm with one tap.
4. **AI proposes, people approve.** Nothing a model produced becomes canonical
   without a visible edit or confirm step. Labels say what happens, not what
   the system does.
5. **Thumb first.** The primary action lives in the sticky bottom bar. Targets
   are 44 pt or larger. Important controls sit mid-screen or lower.

## Color

Tokens are in `FColors`. Ratios are WCAG contrast against the surface named.

| Token | Hex | Use | Contrast |
| --- | --- | --- | --- |
| `canvas` | `#FFFFFF` | Page and panel background | |
| `surface` | `#F1F4F7` | Inputs, secondary buttons, chips, leading icons | |
| `surfacePressed` | `#E3E8ED` | Pressed state of `surface` | |
| `hairline` | `#DEE3E9` | Panel borders, dividers, top rule of bars | |
| `ink` | `#1C2B33` | Titles, body, values | 13.9:1 on canvas |
| `inkSecondary` | `#465A69` | Subtitles, helper text | 7.2:1 on canvas |
| `inkTertiary` | `#5A6B7A` | Captions, chevrons, "no cap" | 5.5:1 on canvas |
| `inkDisabled` | `#A5AFB8` | Disabled labels only | |
| `blue` | `#0064E0` | Primary buttons, links, active tab, progress, selection ring | 5.4:1 on canvas; white on it 5.4:1 |
| `bluePressed` | `#0457CB` | Pressed primary, hero gradient start | |
| `blueBright` | `#0082FB` | Hero gradient end only, never under text | |
| `blueTint` | `#E8F1FE` | Selected rows, info notices | blue on it 4.8:1 |
| `success` | `#1B7434` | Got it, paid, delivered | 5.8:1 on canvas |
| `attention` | `#9A5B00` | Check this, needs review, countdown under 30 s | 5.4:1 on canvas, 4.9:1 on tint |
| `critical` | `#E41E3F` | Remove, leave, errors | 4.6:1 on canvas |
| `plum` | `#6B4A99` | Fourth avatar tint only | 6.9:1 on canvas |

Rules:

- Each signal color has a `Tint` partner (`successTint`, `attentionTint`,
  `criticalTint`, `blueTint`). Tint is the background, the base color is the
  icon, and the text stays `ink` unless it is a short caption.
- Color never carries meaning alone. Every notice, pill, and check mark pairs
  its color with an icon or a word.
- Avatars use four muted tints (blue, green, amber, plum). They are content,
  not UI, and the only place more than one hue appears.
- No pure black, no gradients outside the hero, no shadows on cards. Depth
  comes from hairlines and spacing.

## Type

Family: Figtree, bundled (`assets/fonts/`). It is the closest open face to
Meta's Optimistic. `Caveat` is used only inside the demo camera preview.
Styles are in `FType`.

| Style | Size / line | Weight | Use |
| --- | --- | --- | --- |
| `display` | 34 / 40 | 800 | One number per screen, e.g. the amount owed |
| `title` | 28 / 34 | 700 | Page title, greeting |
| `heading` | 22 / 28 | 700 | Sheet titles, empty-state titles, hero store name (26) |
| `subheading` | 17 / 22 | 600 | Section headers, top bar title |
| `body` | 17 / 24 | 400 | Paragraphs, page subtitles |
| `bodyStrong` | 17 / 24 | 600 | Row titles, item names |
| `bodySmall` | 15 / 20 | 400 | Row subtitles, helper text |
| `bodySmallStrong` | 15 / 20 | 600 | Notice text, small buttons, chips |
| `caption` | 13 / 18 | 500 | Footnotes, timeline, "carried" |
| `captionStrong` | 13 / 18 | 600 | Pills, tab labels, tags |
| `eyebrow` | 12 / 16 | 700, +0.6 tracking, uppercase | Store sections, hero status |
| `money`, `moneySmall` | 17 / 24, 15 / 20 | 600, tabular figures | Every dollar amount |

Rules:

- Body never drops below 15 pt; captions never below 13. Nothing lighter than
  400.
- Money always uses `money` or `moneySmall` so columns align. Whole dollars
  render as `$40`, cents as `$4.29` (`moneyShort` vs `money` in `util/format.dart`).
- Sentence case everywhere: titles, buttons, labels. Uppercase is reserved for
  `eyebrow`.
- Titles get negative tracking (already in the tokens). Do not add tracking
  elsewhere.

## Spacing and shape

- 4 pt grid. Page gutter 20. Panel padding 16 horizontal, 12 vertical. Section
  header top 28, bottom 10. Gap between stacked buttons 8.
- Radii: pill (buttons, chips, pills, progress), 24 (hero, viewfinder, empty
  state), 18 (panels, candidate cards), 12 (inputs, notices), 8 (quantity tags).
- Row minimum height 56; dense rows 44.
- Panels have a 1 px `hairline` border and inset dividers. No card inside a
  card. Group with `Panel`, separate with space.

## Components

Use these before writing new widgets.

| Need | Widget | Notes |
| --- | --- | --- |
| Primary action | `FButton` (`primary`) | 52 pt pill, full width, one per screen, in the bottom bar |
| Secondary action | `FButton` (`secondary`) | Surface pill, stacked under the primary |
| Low-emphasis action | `FButton` (`tertiary`) | Blue text pill, e.g. Skip this item |
| Action on the hero | `FButton` (`onAccent`) | White pill, blue text |
| Destructive | `FButton` (`destructive`) | Red text, always paired with a confirm sheet |
| Inline text action | `FTextButton` | Edit, Copy, Looks right |
| Icon-only control | `FIconButton` | 44 pt target, `label` is required |
| Grouped rows | `Panel` + `PanelRow` | Leading icon or avatar, title, subtitle, value or trailing, chevron only when tappable |
| Section label | `SectionHeader` | Optional trailing text action |
| Store section | `Eyebrow` | Uppercase, no icon |
| Status strip | `Notice` | Kinds: info, success, attention, critical, neutral |
| Small status | `StatusPill` | Got it, Swapped, Skipped, Paid, Done |
| Nothing here yet | `EmptyState` | Icon, title, one sentence, optional action |
| Progress | `ProgressBar` | 6 pt, blue on surface, animated |
| A person | `Avatar`, `MemberChip` | Initials on a tint; chips show first names |
| Quick picks | `SelectChip` | Blue ring when selected |
| Number entry | `QtyStepper` | Minus, value, plus; each button has a 48 pt target |
| Camera | `Viewfinder` | Corner brackets, hint pill, `status` for the reading state |
| Timer | `CountdownRing` | Blue, turns amber under 30 s |
| Screen shell | `FavorlyPage`, `FTopBar`, `PageTitle`, `BottomActions` | See anatomy below |
| Short task | `showFavorlySheet` + `SheetBody` + `SheetTitle` | Drag handle, rises above the keyboard |

Icons: Cupertino only, outlined by default, filled for the selected tab and
for status marks. Sizes 16 (inline), 18 (chevron), 20 (buttons, notices),
22 (top bar), 24 (tabs).

## Screen anatomy

```
┌──────────────────────────────┐
│ ‹  Title                  ⋯  │  FTopBar, 52 pt, only on pushed screens
│                              │
│ Page title                   │  PageTitle: title 28 + subtitle 17 secondary
│ One-sentence subtitle.       │
│                              │
│ [ content: hero, notices,    │  ListView, gutter 20
│   panels, sections ]         │
│                              │
├──────────────────────────────┤  hairline
│ [      Primary action      ] │  BottomActions: primary, then secondary
│ [      Secondary action    ] │  rises above keyboard and home indicator
└──────────────────────────────┘
```

- Root tabs (Trips, Circle, You) have no top bar; the greeting or the circle
  name is the title.
- Pushed screens always have a back chevron. Sheets are dismissible unless the
  task is destructive.
- The bottom bar holds at most two buttons plus one caption. If a screen needs
  more, the screen is doing too much.

## Copy

- Say what happens: "Attach 5 items", "Mark delivered", "Pay $7.02 with Venmo".
  Never "Submit", "OK", "Continue".
- The verb survives the flow: "Post trip" leads to "Trip posted".
- Uncertainty is a specific instruction, not a score: "Check this · Read “2”,
  but it could be a 4". No percentages, no "AI" or "model" in the interface.
- Errors say what went wrong and what to do: "That code doesn’t match a
  circle. Ask a neighbor for theirs." No "Oops", no exclamation marks.
- Neighbors, trips, lists, favors. Not users, orders, carts, tasks, or points.
- Money is external and said plainly: "Favorly never touches your money."

## Motion

- Durations: 140 ms (press), 260 ms (state), 420 ms (progress). One curve,
  `easeOutCubic`. Cupertino page transitions on every platform.
- Buttons scale to 0.97 on press. Nothing else moves on tap.
- One orchestrated moment per flow: the check mark on "Your list is with Ana",
  the sheet sliding up with a substitution prompt. Everything else is static.
- Repeating animations (listening bars, skeleton shimmer) stop when reduced
  motion is on; check `MediaQuery.disableAnimationsOf`.

## Accessibility floor

- 44 pt targets, 48 for steppers. Text scales with the system setting; use
  `minHeight`, never fixed heights, on anything with text.
- Every icon-only control has a label. Selectable cards declare `selected`
  and `inMutuallyExclusiveGroup`. Check controls declare `checked`.
- Contrast: 4.5:1 for text under 18 pt, 3:1 for larger or bold text. The token
  table above is the reference; do not introduce a color without a ratio.
- Keyboard focus shows a 2 px ring on the web build (built into `FButton`).

## Do not

- Add a second accent, a gradient, a drop shadow, a purple, or a neon.
- Use Material ripples, Material icons, Roboto, Inter, or a serif.
- Put a card inside a card, or a full-width button on a wide layout outside
  the phone-width frame.
- Show a toast over the primary button. Toasts belong above the bottom bar,
  which `FavorlyPage` already guarantees.
- Name people "John Doe" or use round demo numbers. Seed data uses real-looking
  names and messy amounts.
- Write "Elevate", "Seamless", "Effortless", or "Smart".

## Adding a screen

1. Start from `FavorlyPage` with `FTopBar` and `PageTitle`.
2. Build content from `Panel`, `Notice`, `EmptyState`, and the hero if the
   screen is about a trip.
3. Put the one primary action in `bottom`. Add at most one secondary.
4. Read state from `storeProvider`; write through a `DemoStore` method
   annotated with the backend route it replaces.
5. Add the screen to `test/screens_golden_test.dart` and regenerate:
   `flutter test --run-skipped -t golden --update-goldens`.
6. Check the golden at phone width for wrapping, then run `flutter analyze`.
