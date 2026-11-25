# Handoff: Collage Studio — Folio dark theme

The light "Folio" redesign is already implemented. This package adds **only the dark theme**. Layout, components, copy, spacing, typography and motion are identical to light — **only colour tokens change**. Template artwork (the rendered slides) is content and does not change colour.

## About the design files
The `.dc.html` files are HTML design references, not production code. Open them in a browser (keep `support.js`, `Slide.dc.html`, `CarouselDoc.dc.html` alongside). Recreate in the existing Flutter codebase by swapping tokens.

## Tokens (light → dark)
| Token | Light | Dark | Notes |
|---|---|---|---|
| paper | `#F3EEE5` | `#171512` | Scaffold background |
| paperDeep | `#EAE3D7` | `#211E1A` | Sheets, selected rows, skeletons, empty slots |
| table | `#E4DCCF` | `#0D0C0B` | Editor canvas surround — darkest, so artwork pops |
| rule | `#CFC5B5` | `#36312B` | 1px dividers, inactive ticks, disabled fill |
| ruleStrong | `#A89D8D` | `#4C463F` | Page-edge slivers |
| stone | `#8A8073` | `#7D7468` | Disabled; text ≥24pt only |
| inkMuted | `#6F665C` | `#9E9487` | Small numerals |
| inkSoft | `#5E564C` | `#B4AA9C` | Secondary text |
| ink | `#1E1B17` | `#EEE7DB` | Primary text, primary buttons, selection rings |
| rouge | `#7B2D26` | `#D0756A` | Active-tab mark, Pro, destructive — lifted for contrast |
| onInk | `#F3EEE5` | `#171512` | Text on primary buttons (buttons invert: ivory fill, dark label) |
| disabledIcon | `#B5AB9C` | `#5C554C` | |
| scrim | `rgba(30,27,23,.42)` | `rgba(0,0,0,.62)` | Behind sheets |

Rules that still apply: ink = action, rouge = premium/active; no shadows; 0 radius; 1px rules.
Selection rings/handles on the canvas: ink ring (now ivory) with paper-filled handles (now dark).

## Implementation
- `theme_dark.dart` — `AppColorsDark` + `buildAppDarkTheme()` (derives from the existing `buildAppTheme()`).
- `MaterialApp(theme: buildAppTheme(), darkTheme: buildAppDarkTheme(), themeMode: ThemeMode.system)`.
- Any widget that hard-codes `AppColors.*` must read the active palette instead (e.g. `Theme.of(context).colorScheme`, or a ThemeExtension holding the Folio tokens) so it switches with the system.
- Status bar: light icons in dark (`SystemUiOverlayStyle.light`).
- Not compiled against the app yet — check before merging.

## Files
- `Redesign 2 Create Flow Dark.dc.html` — Discover, Preview, Editor (first open, rest, text, photo), Export, blank sheet.
- `Redesign 3 Library and Account Dark.dc.html` — Projects, empty/delete, Settings, Paywall, Pro preview, loading/offline, error, navigation.
- `Prototype Dark.dc.html` — clickable flow.
- `screenshots/` — 17 PNGs (2×): 2a–2i, 3a–3h, same ids as the light handoff.
