# Handoff: Collage Studio — "Folio" redesign

## Overview
A visual + UX redesign of the existing Flutter app **Collage Studio** (repo `igorsoares0/collageapp`, internally named "Layer"). It replaces the dark "Darkroom" theme with a warm, editorial "printed magazine" identity and refines the main flow:

**Discover → Template Preview → (Paywall) → Editor → Export**, plus Projects, Settings and the blank-canvas sheet.

**No product capability changes.** Template JSON workflow, `TemplateStore`/API, the rendering engine (`template_canvas.dart` — `CanvasView`/`SlideView`), text & image slots, Pro gating (RevenueCat), auto-saved projects, PNG export via `share_plus` and gallery save via `gal` all stay exactly as they are. This is a re-skin + re-layout of the screens and widgets in `lib/src/screens/` and `lib/src/widgets/`, driven by a new `theme.dart`.

## About the Design Files
The files in this bundle are **design references created in HTML** — prototypes showing intended look and behavior, **not production code to copy**. The task is to **recreate these designs in the existing Flutter codebase**, using its established patterns (Material widgets themed via `ThemeData`, `google_fonts`, `material_symbols_icons`). Open the `.dc.html` files in a browser to view them.

## Fidelity
**High-fidelity.** Final colours, typography, spacing, layout and interactions. Recreate pixel-accurately. Photos are placeholders (Unsplash via picsum.photos) — in the app all artwork is the real template render.

---

## Design Tokens

### Colour (replace `AppColors` in `lib/src/theme.dart`)
| Token | Hex | Role |
|---|---|---|
| `paper` | `#F3EEE5` | Scaffold / app background (replaces `ink`) |
| `paperDeep` | `#EAE3D7` | Sheets, selected plan row, skeletons, empty slot fill |
| `table` | `#E4DCCF` | Editor canvas surround (the "table" the canvas sits on) |
| `rule` | `#CFC5B5` | Hairline dividers (1px), inactive ticks, disabled button fill |
| `ruleStrong` | `#A89D8D` | Page-edge slivers behind template covers |
| `stone` | `#8A8073` | Disabled; text only at ≥24pt (e.g. inactive category words) |
| `inkSoft` | `#5E564C` | Secondary text (6.1:1 on paper) |
| `inkMuted` | `#6F665C` | Small numerals / tertiary text |
| `ink` | `#1E1B17` | Primary text, primary buttons, selection rings, active ticks |
| `rouge` | `#7B2D26` | **Only**: active-tab mark, "Pro" marks, "Make it yours" eyebrow, destructive confirm button |
| `onInk` | `#F3EEE5` | Text/icons on ink |
| `disabledIcon` | `#B5AB9C` | Disabled icons (e.g. redo) |
| `scrim` | `rgba(30,27,23,.42)` | Behind bottom sheets |

Role rule (keeps the current build's principle): **ink = action, rouge = premium/active**. They never swap. Gold (`#E9C46A`) is retired.

Template content colours (`kColorChoices` in `text_style_bar.dart`) are **content, not chrome** — keep as is.

### Typography
Fonts via `google_fonts`:
- **Newsreader** (serif; opsz 6..72; 400/500; italic) — display, titles, numerals. Replaces Bricolage Grotesque.
- **Instrument Sans** (400/500/600) — all UI (already used).

| Style | Font | Size / line-height | Weight | Tracking | Use |
|---|---|---|---|---|---|
| display | Newsreader | 44 / 0.98 | 400 | −0.025em | Discover headline |
| displayIt | Newsreader Italic | same | 400 | | Second half of headlines ("*worth keeping.*") |
| headlineL | Newsreader | 46 / 0.95 | 400 | −0.025em | Screen titles (Projects, Settings) |
| headline | Newsreader | 40–42 / 0.95–0.98 | 400 | −0.02em | Preview title, Export headline, Paywall |
| title | Newsreader | 22–30 / 1.0–1.1 | 400 | −0.015em | Featured name, sheet titles |
| caption title | Newsreader | 18 / 1.1 | 400 | 0 | Template names under tiles |
| numeral | Newsreader Italic | 12–40 | 400 | −0.02em | Slide counters ("01/05"), collection numbers |
| wordmark | Newsreader 26, "Studio" italic | | 400 | −0.02em | Masthead "Collage *Studio*" |
| category | Newsreader | 24 | 400 | 0 | Category index words |
| body | Instrument Sans | 15 / 22 | 400 | 0 | Paragraphs |
| bodyS | Instrument Sans | 13–13.5 / 1.5 | 400 | 0 | Secondary paragraphs (inkSoft) |
| label | Instrument Sans | 13–15 | 500 | 0 | Buttons, rows |
| caption | Instrument Sans | 11.5–12 | 400 | 0 | Meta under tiles ("4:5 · 5 slides") |
| eyebrow | Instrument Sans | 11.5 (11 small) | 600 | +0.16em, UPPERCASE | Section labels, headers |
| navLabel | Instrument Sans | 11 | 600 | +0.04em | Bottom bar |

Minimum text size anywhere in chrome: **11px**.

### Spacing, grid, shape
- Base 4: `4, 8, 12, 16, 20, 24, 32, 48, 64`.
- **Screen margin 20.** Content grid: 6 columns, 10 gutter on 390pt width. Rows alternate splits (4+2, 3+3 staggered, full-bleed, 2+4).
- Captions sit 8–12 below images, anchored by a 1px ink rule on top.
- **Corner radius: 0 everywhere** (buttons, sheets, images, fields). Only the device itself is rounded.
- **No shadows / elevation.** Separation is tone (paper → paperDeep → table) and 1px rules.
- **Page edges** (signature): behind a multi-slide template cover, two offset 1px-outlined slivers, 4px and 8px up-right. Flutter: two `Container`s in a `Stack`, offset (4,−4) and (8,−8), `paper` fill + 1px `ruleStrong` border, beneath the cover. One sliver for ≤3 slides, two for more; none for single-panel.
- Min touch target **44×44**.

### Icons
Keep `material_symbols_icons`, **Outlined, weight 200** (300 when active/on ink), never filled, usually paired with a label. Mapping:
`arrow_back, undo, redo, settings, add, title (Text), imagesmode (Photo), grid_view (Layout), interests (Assets), format_paint (Colour/Background), layers, photo_library, ios_share, download, check, close, north_east (external link), history (restore), auto_stories (Discover tab), photo_library (Projects tab), format_align_left/center/right`.

---

## Components

**Primary button** — full-width, height 54 (52 in dense contexts), `ink` fill, `onInk` text, label left (15/500) + icon right (20, wght 300), padding 0 20. No radius. Pressed: 92% opacity. Disabled: `rule` fill, `inkSoft` text.
**Secondary button** — same metrics, 1px `ink` border, transparent.
**Compact primary** ("Export" in editor bar) — height 38, padding 0 16, 13/500.
**Text link** — 13–14/500, underline 1px, offset 5.
**Bottom nav** — height 64 + safe area, top 1px `rule`, `paper` bg. Grid `1fr 72 1fr`. Item: icon 24 over label 11/600 (+0.04em), gap 4. Active: ink icon+label, plus an 18×2 `rouge` bar 9px above the icon (at the bar's top edge). Inactive: `inkSoft`. Centre create: 52×44 ink square, `add` 24 wght 250. Items: Discover (`auto_stories`) · + · Projects (`photo_library`). Same destinations as `_HomeBottomBar` today.
**Top bar (push screens)** — height 48–52: back icon (24, padding 10) left, centred eyebrow (e.g. "PHOTOGRAPHY — N° 01"), empty 44 right.
**Category index** — horizontal row of Newsreader 24 words with superscript count (Instrument Sans 11). Active: ink + 1px ink underline (padding-bottom 10), count in rouge. Inactive: `stone`. Sticky under the headline; bordered top 1px ink, bottom 1px rule.
**Template folio (tile)** — cover = slide 1 at the template's **own aspect** (keep `aspectRatioOf`), page edges behind, caption below: top rule 1px ink, eyebrow row (category left, rouge "Pro" right if premium), Newsreader 18 name, caption meta "4:5 · 5 slides".
- **Large tiles (≥4 of 6 columns) and the featured strip are horizontally pageable** (PageView, snap per slide) with **ticks** below: 14×1 `rule` each, active 14×3 `ink`, gap 4. Narrow tiles (≤3 columns) are static and open on tap.
**Slide ticks (preview)** — 18 wide, gap 6, same on/off as above.
**Slide strip (editor)** — the whole document rendered continuous at 44×55 per slide (no gaps between slides), active slide outlined 1px ink (offset 3), Newsreader-italic numerals 12 below ("01"…), then a dashed 44×55 "+ SLIDE" (existing Panel action). Tap = focus slide; long-press = existing slide actions (move left/right, delete).
**Editor toolbar** — 6 equal columns: Text, Photo, Layout, Assets, Colour, Layers (icon 24 wght 200 + 11/500 label). Maps 1:1 to `EditorToolbar` callbacks (Panel moved into the strip's "+ Slide").
**Context bar header** — eyebrow "TEXT · TITLE" / "PHOTO · SLOT 2" left; right: "Duplicate", "Delete" (13/500 inkSoft), "Done" (13/500 ink, underlined). 10 bottom padding + 1px rule.
**Text bar** — align segmented (3 icons in a 1px ink box, selected = ink fill/onInk icon), Bold = 40×40 1px-ink square with Newsreader "B" (selected = ink fill), size slider = 1px ink track with 2×17 ink thumb between small/large "A", font specimens (62 wide: "Aa" 24 in that face + 11px name; selected = 2px ink underline; premium fonts show rouge "Pro"), colour chips 28×28 square (selected = 1px ink outline, offset 2).
**Photo bar** — current photo thumb 64×80 + secondary button "Replace photo" (`photo_library`) + hint "Drag to move · pinch to resize · twist to rotate".
**Selection ring** — 1px ink (or paper on dark photos) rectangle + four 7–8px square handles (paper fill, 1px ink border). No glow, no rounded handles.
**Bottom sheet** — `paper` (or `paperDeep` for confirm sheets), 1px ink top rule, no radius, no drag handle, padding 22 20 34. Title Newsreader 24–28 left, "CLOSE" eyebrow right. Scrim `rgba(30,27,23,.42)`.
**Message (snackbar)** — flat ink strip, margin 12 sides, sits above the nav, padding 14 16, text 13 onInk, "OK" eyebrow in `rule`. Reuse existing copy (`purchaseOutcomeMessage` etc.).
**Skeleton** — `paperDeep` blocks in the final ragged silhouette (as `_SkeletonGrid` does), breathing paperDeep↔table at 900ms; static under reduced motion.
**Progress** — 1px `rule` track, 3px ink fill.

---

## Screens

### Discover (replaces `GalleryScreen` templates tab) — board 2a, Prototype step 01
Scroll column, 20 margins:
1. Masthead row: wordmark "Collage *Studio*" (26) left; `settings` icon (24, wght 200) right → `SettingsScreen`. 1px ink rule below (10 top margin).
2. Headline "Make something *worth keeping.*" (display 44), 26–30 top. Shown in full on first launch only; later launches can collapse it.
3. Category index (sticky), 24 top. "All" + categories from the index (same logic as today's `_FilterChip` set, sorted). Counts = templates per category.
4. Featured: eyebrow "N° 01 — <CATEGORY>" + rouge "PRO" if premium; horizontally pageable strip of that template's slides at 248×310 (4:5) flush, ticks below, name (Newsreader 30) + "Lifestyle / 4:5 · 6 slides". Featured = first template in index order (no new API).
5. Collection in alternating rhythm (see grid rules), each a template folio. Order = index order filtered by category.
6. End note "That's the collection." (Newsreader italic 22) + "Pull down to check for new templates." (keeps `RefreshIndicator`).
Offline (`IndexResult.fromCache`): one rouge eyebrow line under the masthead "☁ OFFLINE — SAVED COPIES" (`cloud_off`). Error: "The collection *is out of reach.*" + body "Couldn't load templates. Check your connection and try again — your projects are still here." + secondary "Try again" + link "Open Projects".

### Template Preview (`TemplatePreviewScreen`) — 2b, step 02
Top bar with eyebrow "<CATEGORY> — N° nn". Title Newsreader 40 two lines (second italic) left; right caption "Portrait 4:5 · 5 slides" + **"Needs 3 photos"** (ink, 500) — count of image slots from the template JSON. Canvas: continuous document, slides **flush** (as today's `_controllerFor`), slide width = screen − 2×20 − peek (≈272 at 390), next slide peeks on the right; PageView snaps per slide. Below: numeral "01/05" (Newsreader italic 34 / 18) + ticks. Bottom: primary "Use this template →"; premium + not Pro → "Unlock with *Pro* →" → Paywall (gate stays on the button, as today). Hero tag `template-<id>` from the Discover cover is kept.

### Editor — first open (new empty state of `TemplateScreen`) — 2i, step 03
Top bar: back · title (Newsreader 16) over eyebrow "0 OF 3 PHOTOS" · undo/redo (disabled) · compact "Export" (disabled). Canvas on `table` showing placeholders: each image slot = `paperDeep` (or `#6F665C` when white text sits over it) with an inset dashed 1px border, a 1px square with the fill-order number (Newsreader italic) and eyebrow "PHOTO n". Template text stays rendered. Bottom panel (1px ink top rule): rouge eyebrow "MAKE IT YOURS", "Start with *your photos.*" (Newsreader 30), body "Pick 3 from your library — they fill the numbered frames in order. You can swap or move any of them after.", primary "Add 3 photos" (`photo_library`) → existing photos-first multi-pick that fills slots in order, link "Skip — edit text first". After photos are placed (or skip) the panel animates out and the standard editor (below) appears.

### Editor — at rest — 2c, step 04
Top bar subtitle "SLIDE 02 OF 05 · SAVED". Canvas = existing continuous `CanvasView` on `table`, cut guides as 1px dashed `inkSoft` lines (existing `showCutGuides`). InteractiveViewer behaviour unchanged. Hint chip "PINCH TO STEP BACK" bottom-left (optional). Below: slide strip, then toolbar. Elements may cross cuts (e.g. a title spanning slides 1–2) — existing behaviour.

### Editor — text selected — 2d
Strip + toolbar cross-fade to the Text bar (existing 200ms `AnimatedSwitcher`, fade + 6% rise). Same controls as `TextStyleBar`; premium fonts still route to Paywall on pick.

### Editor — photo selected — 2e
Photo bar (see Components). Sticker/grid/background bars: same shell, same visual language.

### Export (new full-screen route replacing the inline export spinner) — 2f/2g, step 05
Developing: eyebrow "EXPORT" + "1080 × 1350 · PNG"; headline "Developing *your carousel.*"; row of slide frames (paperDeep) — each fades in 0→40%→100% as its PNG renders; line "Slide 03 of 05" + "Rendering at full size"; progress bar; footnote "Keep the app open — this takes a few seconds."
Ready: close icon; "Five slides, *ready.*" (number spelled from slide count); horizontally scrollable slide row (184×230); "Swipe to check each slide"; primary **Share** (`ios_share` → existing `share_plus` export); secondary **Save to Photos** (`download` → existing `gal` save) which turns to "Saved to Photos ✓" for 1.2s; footnote "Your project is saved — find it again in Projects." Permission denied → message "Allow gallery access to save your collage." Errors reuse existing copy.

### Blank canvas sheet (`_createFromScratch`) — 2h
Sheet "A blank *canvas*" + "Choose a format. You can add slides once you're in." Three formats drawn at true proportion (Story 72×128, Portrait 96×120, Square 100×100; 1px ink border; unselected fill paperDeep, selected transparent + outer 1px outline offset 4) with captions "Story / 9:16 · 1080×1920" etc. Primary "Start with <Format> →".

### Projects (`ProjectsList`) — 3a/3b, step 06
Title "Projects" (46) + count numeral (italic 30, stone). Eyebrow row "MOST RECENT FIRST" / "SAVES ITSELF". Latest project: full continuous document strip (176×220 per slide, pageable) + name (Newsreader 24) + "Edited 2 hours ago · 5 slides" (from `updatedAt`) + `more_horiz` → Open / Delete. Older projects: catalogue rows — italic index numeral, mini continuous strip (60×75 per slide), name + date · count. Delete confirm = paperDeep sheet: "Delete project?" / existing copy / Cancel (secondary) + Delete (rouge fill). Empty: dashed frames, "Nothing here *yet.*", "Edit a template or start from a blank canvas — it saves itself, page by page.", link "Browse templates".

### Settings (`SettingsScreen`) — 3c
Title "Settings" (46). Sections as eyebrow + 1px ink rule, rows as 16px-padded lines with 1px rule: MEMBERSHIP (Pro cover thumb + "Collage Studio *Pro*" + "Unlock every premium template." + link "See plans"; "Restore purchases" `history`); when Pro: "Pro · Active — all templates unlocked" + "Manage subscription ↗" when `managementUrl` arrives. LEGAL (Privacy Policy ↗, Terms of Service ↗). ABOUT (Version 1.0.0). Colophon footer.

### Paywall (`PaywallScreen`) — 3d
Sharp spread of 3 premium covers from `catalog` (replaces blurred mosaic), close icon. Rouge eyebrow "COLLAGE STUDIO PRO", "The whole *collection.*" (40). Benefits = today's three lines, numbered 01–03 with rules. Plans: rows (13 14 padding) with square radio (14px, 1px border; selected = 8px ink square, row fill paperDeep, 1px ink border; unselected 1px rule border); title 15/500 + price 12.5 inkSoft; annual savings as rouge Newsreader italic "Save 50%" (computed as today). Primary "Continue →", link "Restore purchases", "Auto-renews. Cancel anytime." Busy/plans-unavailable states as today.

---

## Interactions & Motion
| Moment | Behaviour | Timing |
|---|---|---|
| Tap folio | Image dims 6%, caption rule draws L→R, then push Preview | 160ms |
| Into Preview | Hero cover → hero slide; page edges unfold into neighbours; title rises 8px | 320ms easeOut |
| Page slides | Snap per slide; numeral + ticks update | 250ms easeOutCubic |
| Into Editor | Canvas holds; paper → table; strip/tools slide up | 240ms |
| Select / Done | Bar cross-fade + 6% rise (existing switcher) | 200ms |
| Photos placed | Panel slides down, strip + toolbar rise | 280ms |
| Export develops | Each slide fades in as rendered; light haptic at end | per slide |
| Unlock Pro | Every rouge "Pro" fades out in place; no reflow | 200ms |
| Sheets | Slide up, scrim fades | 340ms cubic(.2,.7,.2,1) |
Reduced motion (`MediaQuery.disableAnimationsOf`): all become instant, as today.
Gesture rule: only large tiles/featured page horizontally on Discover; small tiles tap only.

## State Management
No new backend state. UI-only additions:
- Discover: selected category (exists), per-tile page index (ValueNotifier per tile, as `_CardCarousel` does), headline-collapsed flag (persist after first launch, e.g. `shared_preferences` if available — or skip).
- Preview: page index (exists).
- Editor: `hasPlacedPhoto` / first-open panel visibility (derive from `SlotContent` having no images); export disabled while no image placed.
- Export route: progress (slides rendered / total), saved flag.
- Image-slot count for "Needs N photos": count image slots (ImageLayer + grid cells) in the template document.

## Assets
- Fonts: Newsreader, Instrument Sans (Google Fonts via `google_fonts`).
- Icons: Material Symbols Outlined (existing package), weight 200/300.
- Photos in the mocks: placeholders from picsum.photos/Unsplash — not shipped; the app renders real templates.

## Files (in this folder)
- `Redesign 1 Direction and System.dc.html` — rationale, tokens, components.
- `Redesign 2 Create Flow.dc.html` — Discover, Preview, Editor states (2i first open, 2c rest, 2d text, 2e photo), Export, blank sheet.
- `Redesign 3 Library and Account.dc.html` — Projects, empty/delete, Settings, Paywall, Pro preview, loading/offline, error, navigation & motion table.
- `Prototype.dc.html` — clickable main flow.
- `Current UI.dc.html` — the current build, for comparison.
- `Slide.dc.html`, `CarouselDoc.dc.html` — sample template artwork used by the boards (content, not UI).
- `theme_folio.dart` — drop-in starting point for `lib/src/theme.dart`.

Open any `.dc.html` directly in a browser (needs `support.js` alongside, included).

### Screenshots (`screenshots/`, 2× PNG, each with its design notes)
- `1a-direction.png`, `1b-foundations.png`, `1c-components.png` — system
- `2a-discover.png` (full scroll) · `2b-preview.png` · `2i-editor-first-open.png` · `2c-editor-rest.png` · `2d-editor-text.png` · `2e-editor-photo.png` · `2f-export-developing.png` · `2g-export-ready.png` · `2h-blank-canvas-sheet.png`
- `3a-projects.png` · `3b-projects-empty-delete.png` · `3c-settings.png` · `3d-paywall.png` · `3e-preview-pro.png` · `3f-loading-offline.png` · `3g-error-message.png` · `3h-navigation-motion.png`
