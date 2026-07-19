import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
// `show`: a bare import would clash with the app's own model `Layer`.
import 'package:flutter/rendering.dart'
    show
        BoxHitTestResult,
        PaintingContext,
        RenderBox,
        RenderObjectWithChildMixin,
        RenderProxyBox;
import 'package:google_fonts/google_fonts.dart';

import '../model/asset_record.dart';
import '../model/slot_content.dart';
import '../model/template.dart';
import 'frame_assets.dart';

/// Resolves a template fontFamily name into a TextStyle. The default uses
/// GoogleFonts (runtime download, spec §20); tests inject a plain resolver
/// because google_fonts fails asynchronously without network/assets.
typedef FontResolver = TextStyle Function(String family, TextStyle base);

/// Resolved-style cache. GoogleFonts.getFont is NOT cheap per call (variant
/// map construction + a loadFontIfNecessary future every time), and the
/// canvas + style bar call it on every rebuild — which during a drag means
/// every frame. Keyed by (family, base) since the base style carries the
/// per-layer size/weight/color.
final Map<(String, TextStyle), TextStyle> _resolvedFontCache = {};

TextStyle googleFontsResolver(String family, TextStyle base) {
  // A styling spree can grow the key space; reset rather than grow forever.
  if (_resolvedFontCache.length > 512) _resolvedFontCache.clear();
  return _resolvedFontCache.putIfAbsent((family, base), () {
    try {
      return GoogleFonts.getFont(family, textStyle: base);
    } catch (_) {
      return base;
    }
  });
}

/// RENDERING CONTRACT (must match the editor's Konva renderer):
/// - Coordinates are in template space (canvas is 1080 wide); this widget
///   scales the whole canvas via FittedBox, never individual values.
/// - x/y are the layer's top-left corner BEFORE rotation.
/// - rotation is in degrees, clockwise, around the top-left corner
///   (Konva rotates around the node origin, NOT the center).
/// - layers[0] is the bottom of the stack.
/// - Text has fixed width and automatic height.
/// User scale adjustments are clamped so a slot can't vanish or swallow
/// the canvas — shared by the pinch gesture and the corner-handle resize.
const double _kMinSlotScale = 0.3;
const double _kMaxSlotScale = 4.0;

/// Hittable margin the selection chrome floats around the element (pre-scale
/// template px, divided by the slot scale to stay visually constant) so the
/// corner handles — which sit on the element corners and spill outward — are
/// fully touchable. `_slot` shifts the element back by the same amount so it
/// doesn't move on selection. Must exceed _kResizeReach AND the floating
/// handles' far edge (_kRotateHandleDrop/_kDeleteHandleRise + glyph radius 30)
/// so those buttons stay fully inside the touchable chrome box.
const double kChromePad = 100.0;

/// Radius of the rotate/delete buttons' touch zones (pre-scale template px /
/// scale). Kept tighter than the resize zones: these buttons float OUTSIDE
/// the element, so a bigger radius would steal taps meant for the canvas or
/// neighboring elements.
const double _kCornerReach = 72.0;

/// Base radius of the corner/edge RESIZE touch zones — more generous than the
/// glyph buttons because a missed grab silently degrades into an element
/// move. Capped per element by [_resizeReach].
const double _kResizeReach = 96.0;

/// The effective resize-zone radius for an element: [_kResizeReach], but
/// never more than 45% of the shorter side — so the four corner and four
/// edge zones can never swallow the interior, and dragging the middle of a
/// small element still MOVES it.
double _resizeReach(Size size, double scale) {
  final pad = kChromePad / scale;
  final w = size.width - 2 * pad;
  final h = size.height - 2 * pad;
  return math.min(_kResizeReach / scale, 0.45 * math.min(w, h));
}

/// How far below the element's bottom edge the rotation handle floats (pre-
/// scale template px / scale). Far enough that the glyph clears the bottom
/// edge pill (half-thickness 17 + gap), yet kept under [kChromePad] so the
/// handle stays inside the chrome's hit region that _SlotGestures covers.
const double _kRotateHandleDrop = 68.0;

/// How far above the element's top edge the delete handle floats (pre-scale
/// template px / scale) — the rotation handle's mirror on the opposite edge,
/// under the same [kChromePad] constraint.
const double _kDeleteHandleRise = 68.0;

/// True when [local] is within reach of one of the element's four corners —
/// the resize zones. [size] is the PADDED chrome box; corners are axis-aligned
/// because both callers sit inside the rotation transforms, so [local] arrives
/// already un-rotated. Shared by _SlotGestures (which zone a touch starts in)
/// and _RingHitRegion (which touches the overlay claims at all).
bool _nearCornerZone(Offset local, Size size, double scale) {
  final pad = kChromePad / scale;
  final reach = _resizeReach(size, scale);
  final w = size.width - 2 * pad;
  final h = size.height - 2 * pad;
  final corners = [
    Offset(pad, pad),
    Offset(pad + w, pad),
    Offset(pad, pad + h),
    Offset(pad + w, pad + h),
  ];
  return corners.any((c) => (local - c).distanceSquared <= reach * reach);
}

/// Distance² from [local] to the rotation handle's center, which floats
/// below the element's bottom-center (axis-aligned, as with [_nearCornerZone]).
/// Exposed separately from the zone check so the bottom edge pill — whose
/// touch zone overlaps the handle's — can arbitrate by nearest center.
double _rotateHandleDistSq(Offset local, Size size, double scale) {
  final pad = kChromePad / scale;
  final w = size.width - 2 * pad;
  final h = size.height - 2 * pad;
  final handle = Offset(pad + w / 2, pad + h + _kRotateHandleDrop / scale);
  return (local - handle).distanceSquared;
}

/// True when [local] is within reach of the rotation handle.
bool _nearRotateZone(Offset local, Size size, double scale) {
  final reach = _kCornerReach / scale;
  return _rotateHandleDistSq(local, size, scale) <= reach * reach;
}

/// Distance² from [local] to the delete handle's center, which floats above
/// the element's top-center — the top edge pill arbitrates against it the
/// same way the bottom one does against the rotation handle.
double _deleteHandleDistSq(Offset local, Size size, double scale) {
  final pad = kChromePad / scale;
  final w = size.width - 2 * pad;
  final handle = Offset(pad + w / 2, pad - _kDeleteHandleRise / scale);
  return (local - handle).distanceSquared;
}

/// True when [local] is within reach of the delete handle.
bool _nearDeleteZone(Offset local, Size size, double scale) {
  final reach = _kCornerReach / scale;
  return _deleteHandleDistSq(local, size, scale) <= reach * reach;
}

/// Which edge pill a one-finger drag started on — the Canva-style single-axis
/// resize handles at the middle of each side. Values name the DRAGGED edge;
/// the opposite edge stays fixed while stretching.
enum SlotEdge { top, right, bottom, left }

/// Edge pill dimensions (pre-scale template px / scale): a capsule lying along
/// its edge — wide on top/bottom, tall on left/right.
const double _kEdgePillLength = 112.0;
const double _kEdgePillThickness = 34.0;

/// Whether a side is long enough to host its edge pill without colliding with
/// the corner dots: pill 112 + corner dot 60 is the collision-free minimum
/// (172), plus 12 of breathing room per side, all /scale. Shared by the
/// chrome (draw) and the hit zone (grab), so a visible pill is always
/// grabbable and an absent one never steals the touch.
bool _edgePillsFit(double sideLen, double scale) => sideLen >= 196.0 / scale;

/// The nearest edge-pill zone within reach of [local], with its center
/// distance² (for arbitration against the rotate/delete handles, whose zones
/// overlap the bottom/top pills) — or null. Same contract as
/// [_nearCornerZone]: [size] is the padded chrome box and [local] arrives
/// axis-aligned. [vertical] false suppresses the top/bottom pills (text:
/// height is automatic, only the wrap width stretches).
(SlotEdge, double)? _nearEdgeZone(
  Offset local,
  Size size,
  double scale, {
  bool vertical = true,
}) {
  final pad = kChromePad / scale;
  final reach = _resizeReach(size, scale);
  final half = _kEdgePillLength / 2 / scale;
  final w = size.width - 2 * pad;
  final h = size.height - 2 * pad;
  final horizontalPills = vertical && _edgePillsFit(w, scale);
  final verticalPills = _edgePillsFit(h, scale);
  // The zone is a CAPSULE around the pill, not a circle around its center:
  // distance to the pill's segment, so a grab near either tip still counts.
  // [horizontal] is the pill's long axis, along its edge.
  final mids = <(SlotEdge, Offset, bool, bool)>[
    (SlotEdge.top, Offset(pad + w / 2, pad), true, horizontalPills),
    (SlotEdge.bottom, Offset(pad + w / 2, pad + h), true, horizontalPills),
    (SlotEdge.left, Offset(pad, pad + h / 2), false, verticalPills),
    (SlotEdge.right, Offset(pad + w, pad + h / 2), false, verticalPills),
  ];
  (SlotEdge, double)? best;
  for (final (edge, mid, horizontal, exists) in mids) {
    if (!exists) continue;
    final along = horizontal ? local.dx - mid.dx : local.dy - mid.dy;
    final across = horizontal ? local.dy - mid.dy : local.dx - mid.dx;
    final overshoot = math.max(0.0, along.abs() - half);
    final d2 = overshoot * overshoot + across * across;
    if (d2 <= reach * reach && (best == null || d2 < best.$2)) {
      best = (edge, d2);
    }
  }
  return best;
}

/// Renders ONE panel (a carousel slide) in template space. The screen lays
/// out several of these side by side; tests and single-panel templates use the
/// [TemplateCanvas] convenience wrapper below.
class PanelCanvas extends StatelessWidget {
  final Panel panel;
  final double canvasWidth;
  final double canvasHeight;
  final SlotContent content;
  final FontResolver fontResolver;

  /// When set, slot layers (image and text) become tappable (FittedBox/
  /// Transform map the hit test back to template space) and empty image
  /// placeholders show a photo icon. The screen decides what a tap means
  /// (select, open the picker, …).
  final void Function(String slotId)? onSlotTap;

  /// Tap on the canvas outside any slot (background, shapes, stickers) —
  /// used by the screen to clear the selection.
  final VoidCallback? onCanvasTap;

  /// Slot currently selected by the user: rendered with a border and corner
  /// resize handles (the chrome lives inside the slot's transform chain, so
  /// it follows rotation and scale).
  final String? selectedSlotId;

  /// Text slot being edited inline: its Text swaps for an autofocused
  /// TextField with the same style, and the slot's move/pinch gestures are
  /// suspended so the field owns cursor/selection gestures.
  final String? editingSlotId;

  /// Streams every keystroke of the inline editor; store it in
  /// SlotContent.texts.
  final void Function(String slotId, String value)? onTextChanged;

  /// Attached to the inline editor of the [editingSlotId] text slot so the
  /// screen can measure its on-screen rect and lift the canvas above the
  /// keyboard. Only the panel holding that slot uses it.
  final GlobalKey? editingFieldKey;

  /// When set, slot layers (image/text — the user's content) become
  /// draggable. [delta] arrives in template space: gesture events are
  /// transformed into the listener's local coordinates, so the FittedBox
  /// scale is already accounted for. Accumulate it into
  /// SlotContent.offsets. Shape/sticker layers are template design and
  /// stay fixed.
  final void Function(String slotId, Offset delta)? onSlotDrag;

  /// When set, slot layers can be pinch-resized. [scale] is the new
  /// absolute scale for the slot (the canvas combines the gesture ratio
  /// with the scale the slot had when the gesture started); store it in
  /// SlotContent.scales.
  final void Function(String slotId, double scale)? onSlotScale;

  /// When set, slot layers can be rotated by dragging the rotation handle
  /// below the element. [degrees] is the new absolute USER rotation for the
  /// slot (added on top of any template rotation); store it in
  /// SlotContent.rotations.
  final void Function(String slotId, double degrees)? onSlotRotate;

  /// When set, dragging an edge pill stretches the slot along ONE axis.
  /// [factor] is the new absolute stretch for that axis (store it in
  /// SlotContent.stretchX/stretchY per [edge]); [offsetDelta] is the position
  /// compensation (template space) that keeps the OPPOSITE edge fixed — add
  /// it to the slot's offset in the same edit.
  final void Function(
    String slotId,
    SlotEdge edge,
    double factor,
    Offset offsetDelta,
  )?
  onSlotEdgeResize;

  /// Tap on an image slot's photo icon — the ONLY way to open the gallery, so
  /// tapping the element itself just selects it (for move/resize). Empty slots
  /// show the icon inline; a filled, selected slot shows a "replace" overlay.
  final void Function(String slotId)? onPickImage;

  /// Tap on the selected element's delete handle (the ✕ above it). Reports the
  /// same id the move/resize gestures use — the slot id, or the LAYER id for
  /// stickers and grids. The screen decides what deleting means.
  final void Function(String slotId)? onSlotDelete;

  /// Remote asset catalog (frames/stickers). A slot's frameAssetId resolves
  /// against this plus the bundled seeds; empty = seeds only. Preview usages
  /// also merge in the photo assets embedded in the template's response.
  final List<AssetRecord> assetCatalog;

  /// When true, empty image slots and grid cells show the designer's sample
  /// photo (imageAssetId, resolved against [assetCatalog]) instead of the
  /// placeholder. The PREVIEW opts in — the editor never does, so the user
  /// starts from placeholders and exports only their own photos.
  final bool showTemplatePhotos;

  /// A finished grid-divider drag reports the grid layer's id, whether the
  /// COLUMN tracks changed (else rows), and the new full fraction list. Store
  /// it as a SlotContent grid override. Fired ONCE per drag, on release — the
  /// in-flight drag repaints the grid locally, so per-frame content updates
  /// (and the whole-screen rebuilds they cause) never happen. Wired only when
  /// a grid cell is selected.
  final void Function(String gridId, bool columns, List<double> fractions)?
  onGridFractions;

  /// Screen-space selection overlay wiring. When set and a slot is selected,
  /// the canvas suppresses its in-canvas chrome VISUALS and instead mounts a
  /// [CompositedTransformTarget] on the selected element's padded chrome box,
  /// so a [CanvasSelectionOverlay] stacked over the canvas area can float the
  /// chrome and its ring/handle gestures ABOVE the canvas — unclipped by the
  /// canvas bounds. (Hit tests gate on every ancestor's size, so handles that
  /// spill past the canvas edge can never be touched from inside it; the
  /// follower is the framework's sanctioned escape hatch.) Null keeps the
  /// legacy all-in-canvas chrome (tests, bare usages).
  final LayerLink? selectionLink;

  /// Reports the selected element's padded chrome-box size in leader-local
  /// units, post-layout and only when it changes — the overlay needs it to
  /// size the follower, and text slots size to their content so it can't be
  /// derived from the layer alone.
  final ValueChanged<Size>? onSelectionSize;

  /// Key for the export RepaintBoundary. It sits INSIDE the FittedBox, on the
  /// template-unit canvas box, so [capturePng] always captures exactly
  /// canvasWidth×canvasHeight — a boundary OUTSIDE the FittedBox captures the
  /// letterbox bands whenever the panel's on-screen box doesn't match the
  /// canvas aspect, silently shrinking the artwork inside the exported PNG.
  final GlobalKey? exportKey;

  /// Alignment guide lines to draw over this panel, in template units — the
  /// screen computes them while an element is being dragged (see snap.dart).
  /// They paint INSIDE the FittedBox (same coordinates as the layers) but
  /// OUTSIDE the export boundary, so they can never leak into the PNG.
  final List<double> guideXs;
  final List<double> guideYs;

  /// Neighbouring panels, for the carousel bleed: panels are contiguous in
  /// the design (the on-screen gap is cosmetic), so whatever a neighbour's
  /// layer spills past the shared edge continues here, offset by exactly one
  /// canvas width. Ghosts are inert (IgnorePointer), clipped to the canvas,
  /// and render INSIDE the export boundary so the exported slide carries the
  /// bleed. Both neighbour bleeds paint UNDER this panel's own layers: they're
  /// cosmetic echoes for swipe continuity, so a local element the user adds
  /// here (text, sticker…) always sits above an image that spills in from an
  /// adjacent panel — it's still reorderable against the panel's real layers.
  final Panel? panelBefore;
  final Panel? panelAfter;

  const PanelCanvas({
    super.key,
    required this.panel,
    required this.canvasWidth,
    required this.canvasHeight,
    this.content = const SlotContent(),
    this.fontResolver = googleFontsResolver,
    this.onSlotTap,
    this.onCanvasTap,
    this.selectedSlotId,
    this.editingSlotId,
    this.onTextChanged,
    this.onSlotDrag,
    this.onSlotScale,
    this.onSlotRotate,
    this.onSlotEdgeResize,
    this.onPickImage,
    this.onSlotDelete,
    this.editingFieldKey,
    this.assetCatalog = const [],
    this.showTemplatePhotos = false,
    this.onGridFractions,
    this.selectionLink,
    this.onSelectionSize,
    this.exportKey,
    this.guideXs = const [],
    this.guideYs = const [],
    this.panelBefore,
    this.panelAfter,
  });

  /// Stack order and visibility honour the user's per-layer overrides
  /// (SlotContent), falling back to the template's own order/hidden flags.
  List<Layer> _visibleLayers(Panel p) {
    final byId = {for (final l in p.layers) l.id: l};
    final orderedIds = content.orderedLayerIds(p.id, [
      for (final l in p.layers) l.id,
    ]);
    return [
      for (final id in orderedIds)
        if (byId[id] case final layer?)
          if (!content.layerHidden(layer.id, layer.hidden)) layer,
    ];
  }

  /// A neighbour's layers painted as this panel's carousel bleed: shifted by
  /// one canvas width, inert, and clipped to the canvas box. Rendered with no
  /// callbacks and no selection, so no chrome ever repeats here — editing
  /// happens on the owner panel.
  Widget _bleed(Panel neighbour, double dx) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ClipRect(
          child: Transform.translate(
            offset: Offset(dx, 0),
            child: Stack(
              // The neighbour's layers overflow the shifted box by design;
              // the ClipRect above is the only clip that should apply.
              clipBehavior: Clip.none,
              children: [
                for (final layer in _visibleLayers(neighbour))
                  _LayerWidget(
                    layer: layer,
                    content: content,
                    fontResolver: fontResolver,
                    assetCatalog: assetCatalog,
                    showTemplatePhotos: showTemplatePhotos,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleLayers = _visibleLayers(panel);
    return FittedBox(
      child: SizedBox(
        width: canvasWidth,
        height: canvasHeight,
        child: Stack(
          children: [
            // The export boundary lives in template units (inside the
            // FittedBox) — see [exportKey]. Always present so each panel is
            // also a repaint island regardless of export wiring.
            RepaintBoundary(
              key: exportKey,
              child: SizedBox(
                width: canvasWidth,
                height: canvasHeight,
                // The deselect detector wraps the whole canvas: slot detectors
                // are deeper and win the gesture arena, so this only fires for
                // taps on the background and shapes. (A detector on the white
                // backdrop wouldn't work — any full-bleed shape layer above it
                // swallows the hit test.)
                child: GestureDetector(
                  onTap: onCanvasTap,
                  child: Stack(
                    children: [
                      // Panel background: the user's per-panel override if
                      // set, else the panel's own backgroundColor.
                      Positioned.fill(
                        child: ColoredBox(
                          key: const ValueKey('canvas-background'),
                          color:
                              content.backgroundFor(panel.id) ??
                              panel.backgroundColor,
                        ),
                      ),
                      // Both bleeds sit UNDER this panel's own layers (see
                      // panelBefore/panelAfter): a local element always wins
                      // over an image spilling in from an adjacent panel.
                      if (panelBefore case final p?) _bleed(p, -canvasWidth),
                      if (panelAfter case final p?) _bleed(p, canvasWidth),
                      for (final layer in visibleLayers)
                        _LayerWidget(
                          layer: layer,
                          content: content,
                          fontResolver: fontResolver,
                          onSlotTap: onSlotTap,
                          onSlotDrag: onSlotDrag,
                          onSlotScale: onSlotScale,
                          onSlotRotate: onSlotRotate,
                          onSlotEdgeResize: onSlotEdgeResize,
                          onPickImage: onPickImage,
                          onSlotDelete: onSlotDelete,
                          onTextChanged: onTextChanged,
                          assetCatalog: assetCatalog,
                          showTemplatePhotos: showTemplatePhotos,
                          selectedSlotId: selectedSlotId,
                          onGridFractions: onGridFractions,
                          selectionLink: selectionLink,
                          onSelectionSize: onSelectionSize,
                          selected:
                              layer is ImageLayer &&
                                  layer.slotId == selectedSlotId ||
                              layer is TextLayer &&
                                  layer.slotId == selectedSlotId ||
                              layer is StickerLayer &&
                                  layer.id == selectedSlotId,
                          editing:
                              layer is TextLayer &&
                              layer.slotId == editingSlotId,
                          fieldKey:
                              layer is TextLayer &&
                                  layer.slotId == editingSlotId
                              ? editingFieldKey
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // Alignment guides float above the artwork but outside the export
            // boundary — visible while dragging, never in the PNG.
            if (guideXs.isNotEmpty || guideYs.isNotEmpty)
              Positioned.fill(
                key: const ValueKey('alignment-guides'),
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _GuidePainter(guideXs: guideXs, guideYs: guideYs),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Draws the alignment guide lines edge to edge in template units. The stroke
/// is set in template px, so on screen it scales with the canvas like every
/// other element — thin at fit-to-screen, never fat when zoomed in.
class _GuidePainter extends CustomPainter {
  final List<double> guideXs;
  final List<double> guideYs;

  const _GuidePainter({required this.guideXs, required this.guideYs});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      // Light blue, NOT the paper-white accent: guides must stay visible
      // over white panel backgrounds. (Literal, not a token: rendering code
      // stays free of UI-theme imports.)
      ..color = const Color(0xFF5AA2FF)
      ..strokeWidth = 3;
    for (final x in guideXs) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (final y in guideYs) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GuidePainter oldDelegate) =>
      !identical(oldDelegate.guideXs, guideXs) ||
      !identical(oldDelegate.guideYs, guideYs);
}

/// Convenience wrapper that renders a template's FIRST panel — used by tests
/// and any single-panel context. Multi-panel screens use [PanelCanvas] per
/// panel directly.
/// v4 continuous-canvas renderer (Modelo B). See docs/model-b-migration.md.
///
/// STATUS: read-only, and nothing mounts it yet. Gestures, selection chrome and
/// inline editing stay on [PanelCanvas] until the editor itself moves to the
/// continuous model — this widget exists to prove the render and to drive the
/// thumbnail and the sliced export.
///
/// The whole document is painted ONCE, [Document.contentWidth] wide. There is
/// no bleed here and there never will be: a layer whose x crosses a cut line
/// simply spans it, because every layer already lives in one coordinate space.
/// Killing [PanelCanvas._bleed] is the entire point of the migration.
class CanvasView extends StatelessWidget {
  final Document document;
  final SlotContent content;
  final FontResolver fontResolver;

  /// See [PanelCanvas.assetCatalog].
  final List<AssetRecord> assetCatalog;

  /// See [PanelCanvas.showTemplatePhotos].
  final bool showTemplatePhotos;

  /// Dashed lines on the interior cut lines, so the designer sees where each
  /// slide ends. Editor-only: drawn OUTSIDE the export boundary, so a guide can
  /// never reach the exported PNG.
  final bool showCutGuides;

  /// Export boundary, in template units and inside the FittedBox — same
  /// contract as [PanelCanvas.exportKey]. The sliced export crops slide rects
  /// out of this one raster.
  final GlobalKey? exportKey;

  const CanvasView({
    super.key,
    required this.document,
    required this.content,
    required this.fontResolver,
    this.assetCatalog = const [],
    this.showTemplatePhotos = false,
    this.showCutGuides = false,
    this.exportKey,
  });

  /// In the continuous model the list order IS the stack order, so there is no
  /// per-panel reorder override to apply — only the hidden filter survives.
  List<Layer> get _visibleLayers => [
    for (final layer in document.layers)
      if (!content.layerHidden(layer.id, layer.hidden)) layer,
  ];

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      child: SizedBox(
        width: document.contentWidth,
        height: document.slideHeight,
        child: Stack(
          children: [
            RepaintBoundary(
              key: exportKey,
              child: SizedBox(
                width: document.contentWidth,
                height: document.slideHeight,
                child: Stack(
                  // Layers may extend past the document box by design; nothing
                  // here should clip them but the export crop.
                  clipBehavior: Clip.none,
                  children: [
                    // Backgrounds are the one naturally per-slide datum, so
                    // they are painted per slide rect rather than as one fill.
                    for (var i = 0; i < document.slideCount; i++)
                      Positioned.fromRect(
                        rect: document.slideRect(i),
                        child: ColoredBox(
                          key: ValueKey('slide-background-$i'),
                          color: document.backgroundFor(i),
                        ),
                      ),
                    for (final layer in _visibleLayers)
                      _LayerWidget(
                        layer: layer,
                        content: content,
                        fontResolver: fontResolver,
                        assetCatalog: assetCatalog,
                        showTemplatePhotos: showTemplatePhotos,
                      ),
                  ],
                ),
              ),
            ),
            if (showCutGuides && document.slideCount > 1)
              Positioned.fill(
                key: const ValueKey('cut-guides'),
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _CutGuidePainter(
                      xs: [
                        for (var i = 1; i < document.slideCount; i++)
                          document.slideRect(i).left,
                      ],
                      gutter: document.gutter,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Dashed verticals on the slide cut lines, in template units so the dash
/// scales with the canvas like everything else.
class _CutGuidePainter extends CustomPainter {
  final List<double> xs;
  final double gutter;

  const _CutGuidePainter({required this.xs, required this.gutter});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x66000000)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const dash = 24.0;
    const gap = 16.0;
    for (final x in xs) {
      // With a gutter the cut is a band, so mark the slide's edge — the start
      // of the next slide minus the gutter reads as where the previous ended.
      for (final lineX in {x, x - gutter}) {
        for (var y = 0.0; y < size.height; y += dash + gap) {
          canvas.drawLine(
            Offset(lineX, y),
            Offset(lineX, math.min(y + dash, size.height)),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_CutGuidePainter old) =>
      !identical(old.xs, xs) || old.gutter != gutter;
}

class TemplateCanvas extends StatelessWidget {
  final Template template;
  final SlotContent content;
  final FontResolver fontResolver;
  final void Function(String slotId)? onSlotTap;
  final VoidCallback? onCanvasTap;
  final String? selectedSlotId;
  final String? editingSlotId;
  final void Function(String slotId, String value)? onTextChanged;
  final void Function(String slotId, Offset delta)? onSlotDrag;
  final void Function(String slotId, double scale)? onSlotScale;
  final void Function(String slotId, double degrees)? onSlotRotate;
  final void Function(
    String slotId,
    SlotEdge edge,
    double factor,
    Offset offsetDelta,
  )?
  onSlotEdgeResize;
  final void Function(String slotId)? onSlotDelete;
  final List<AssetRecord> assetCatalog;

  /// See [PanelCanvas.exportKey].
  final GlobalKey? exportKey;

  const TemplateCanvas({
    super.key,
    required this.template,
    this.content = const SlotContent(),
    this.fontResolver = googleFontsResolver,
    this.onSlotTap,
    this.onCanvasTap,
    this.selectedSlotId,
    this.editingSlotId,
    this.onTextChanged,
    this.onSlotDrag,
    this.onSlotScale,
    this.onSlotRotate,
    this.onSlotEdgeResize,
    this.onSlotDelete,
    this.assetCatalog = const [],
    this.exportKey,
  });

  @override
  Widget build(BuildContext context) {
    return PanelCanvas(
      panel: template.panels.first,
      // Carousel bleed from the second panel, matching the web thumbnail.
      panelAfter: template.panels.length > 1 ? template.panels[1] : null,
      canvasWidth: template.canvasWidth,
      canvasHeight: template.canvasHeight,
      content: content,
      fontResolver: fontResolver,
      onSlotTap: onSlotTap,
      onCanvasTap: onCanvasTap,
      selectedSlotId: selectedSlotId,
      editingSlotId: editingSlotId,
      onTextChanged: onTextChanged,
      onSlotDrag: onSlotDrag,
      onSlotScale: onSlotScale,
      onSlotRotate: onSlotRotate,
      onSlotEdgeResize: onSlotEdgeResize,
      onSlotDelete: onSlotDelete,
      assetCatalog: assetCatalog,
      exportKey: exportKey,
    );
  }
}

class _LayerWidget extends StatelessWidget {
  final Layer layer;
  final SlotContent content;
  final FontResolver fontResolver;
  final void Function(String slotId)? onSlotTap;
  final void Function(String slotId, Offset delta)? onSlotDrag;
  final void Function(String slotId, double scale)? onSlotScale;
  final void Function(String slotId, double degrees)? onSlotRotate;
  final void Function(
    String slotId,
    SlotEdge edge,
    double factor,
    Offset offsetDelta,
  )?
  onSlotEdgeResize;
  final void Function(String slotId)? onPickImage;
  final void Function(String slotId)? onSlotDelete;
  final void Function(String slotId, String value)? onTextChanged;
  final List<AssetRecord> assetCatalog;

  /// The globally selected slot id — grids need it to know which cell (if any)
  /// is active, since one grid layer holds many cells. Image/text use the
  /// derived [selected] bool instead.
  final String? selectedSlotId;
  final void Function(String gridId, bool columns, List<double> fractions)?
  onGridFractions;
  final bool selected;
  final bool editing;
  final GlobalKey? fieldKey;

  /// See [PanelCanvas.showTemplatePhotos].
  final bool showTemplatePhotos;

  /// See [PanelCanvas.selectionLink] / [PanelCanvas.onSelectionSize].
  final LayerLink? selectionLink;
  final ValueChanged<Size>? onSelectionSize;

  const _LayerWidget({
    required this.layer,
    required this.content,
    required this.fontResolver,
    this.onSlotTap,
    this.onSlotDrag,
    this.onSlotScale,
    this.onSlotRotate,
    this.onSlotEdgeResize,
    this.onPickImage,
    this.onSlotDelete,
    this.onTextChanged,
    this.assetCatalog = const [],
    this.showTemplatePhotos = false,
    this.selectedSlotId,
    this.onGridFractions,
    this.selectionLink,
    this.onSelectionSize,
    this.selected = false,
    this.editing = false,
    this.fieldKey,
  });

  @override
  Widget build(BuildContext context) {
    return switch (layer) {
      // The chromed content is passed UNROTATED; _slot wraps the gesture
      // surface in the template + user rotations, so the touch region tracks
      // the painted element (handles included) instead of the layout box.
      // Edge stretch (stretchX/stretchY) multiplies the LAYOUT box each slot
      // sizes itself to — photos re-run their BoxFit and text re-wraps — so
      // the paint transforms stay uniform and nothing distorts.
      ImageLayer l => _slot(
        l.slotId,
        l.x,
        l.y,
        _chromed(
          l.slotId,
          _ImageSlot(
            layer: l,
            content: content,
            assetCatalog: assetCatalog,
            showTemplatePhotos: showTemplatePhotos,
            interactive: onSlotTap != null,
            selected: selected,
            onPick: onPickImage,
            width: l.width * content.stretchXFor(l.slotId),
            height: l.height * content.stretchYFor(l.slotId),
          ),
        ),
        templateRotation: l.rotation,
        baseSize: Size(l.width, l.height),
      ),
      TextLayer l => _slot(
        l.slotId,
        l.x,
        l.y,
        _chromed(
          l.slotId,
          _TextSlot(
            layer: l,
            content: content,
            fontResolver: fontResolver,
            editing: editing,
            fieldKey: fieldKey,
            onTextChanged: onTextChanged,
            wrapWidth: l.width * content.stretchXFor(l.slotId),
          ),
          verticalPills: false,
        ),
        // Text carries no template rotation; the TextField owns cursor/
        // selection gestures while editing.
        gestures: !editing,
        // The chrome/gesture box hugs the glyphs (see _TextSlot); this frame
        // keeps the model box as the layout/transform anchor and re-aligns
        // the hugged paragraph inside it per the text alignment.
        frameWidth: l.width * content.stretchXFor(l.slotId),
        frameAlignment: switch (content.alignmentFor(l.slotId) ?? l.alignment) {
          'center' => Alignment.topCenter,
          'right' => Alignment.topRight,
          _ => Alignment.topLeft,
        },
        // Text height is automatic: only the wrap width stretches, so the
        // top/bottom pills (and their zones) don't exist.
        baseSize: Size(l.width, 0),
        verticalEdges: false,
      ),
      ShapeLayer l => _positioned(
        l.x,
        l.y,
        Container(width: l.width, height: l.height, color: l.fill),
      ),
      // Stickers are full slot citizens keyed by their LAYER id (they carry no
      // slotId — nothing to fill): tap selects, then move/pinch/resize/rotate
      // like an image slot.
      StickerLayer l => _slot(
        l.id,
        l.x,
        l.y,
        _chromed(
          l.id,
          _StickerSlot(
            layer: l,
            assetCatalog: assetCatalog,
            width: l.width * content.stretchXFor(l.id),
            height: l.height * content.stretchYFor(l.id),
          ),
        ),
        baseSize: Size(l.width, l.height),
      ),
      GridLayer l => _buildGrid(l),
    };
  }

  /// A grid layer. Cells (fill + dividers) always render; once a cell is
  /// selected the whole grid gains move/resize/rotate — the same chrome and
  /// gesture recognizer the other slots use, keyed by the grid's LAYER id. The
  /// gesture surface sits BEHIND the cells, and the cells are translucent, so a
  /// drag anywhere on the grid falls through and moves/resizes it like an image.
  /// Only the opaque bits stay local: the pick icon (taps to fill/replace) and,
  /// when active, the dividers (drag to re-split) block the surface beneath them.
  Widget _buildGrid(GridLayer l) {
    final active =
        selectedSlotId != null &&
        l.cells.any((c) => c.slotId == selectedSlotId);
    final gScale = content.scaleFor(l.id);
    final gOffset = content.offsetFor(l.id);
    final pad = active ? kChromePad / gScale : 0.0;

    final cells = _GridSlot(
      grid: l,
      content: content,
      assetCatalog: assetCatalog,
      showTemplatePhotos: showTemplatePhotos,
      interactive: onSlotTap != null,
      selectedSlotId: selectedSlotId,
      onSlotTap: onSlotTap,
      onPickImage: onPickImage,
      onGridFractions: onGridFractions,
      width: l.width * content.stretchXFor(l.id),
      height: l.height * content.stretchYFor(l.id),
    );

    Widget inner = cells;
    if (active) {
      inner = Stack(
        clipBehavior: Clip.none,
        children: [
          // Whole-grid move/resize/rotate, behind the cells so only the chrome
          // ring/corners (outside the cell box) reach it.
          Positioned.fill(
            child: _SlotGestures(
              slotId: l.id,
              currentScale: gScale,
              currentRotation: content.rotationFor(l.id),
              templateRotation: l.rotation,
              currentStretchX: content.stretchXFor(l.id),
              currentStretchY: content.stretchYFor(l.id),
              baseSize: Size(l.width, l.height),
              selected: true,
              onTap: null,
              onDrag: onSlotDrag,
              onScaleChange: onSlotScale,
              onRotateChange: onSlotRotate,
              onEdgeResize: onSlotEdgeResize,
              onDelete: onSlotDelete,
              child: const SizedBox.expand(),
            ),
          ),
          _leaderChromed(gScale, cells),
        ],
      );
    }

    // Same transform chain as _slot: template rotation (top-left) then user
    // rotation (center) then scale; the offset/pad live in the Positioned.
    // The repaint island sits inside the transforms, like _slot's.
    inner = Transform.scale(
      scale: gScale,
      child: _userRotated(l.id, _rotated(l.rotation, _isolated(inner))),
    );
    return _positioned(l.x + gOffset.dx - pad, l.y + gOffset.dy - pad, inner);
  }

  /// Selection chrome (border + handle visuals) wraps the slot content
  /// inside the rotation/scale transforms, so it hugs the element exactly
  /// as drawn. It is visual only — gestures (including resize) live in
  /// _SlotGestures so there is a single recognizer and no arena contention.
  Widget _chromed(String slotId, Widget child, {bool verticalPills = true}) {
    if (!selected) return child;
    return _leaderChromed(
      content.scaleFor(slotId),
      child,
      verticalPills: verticalPills,
    );
  }

  /// The selected element's padded chrome box. Legacy mode (no
  /// [selectionLink]) draws the chrome in-canvas; overlay mode keeps the
  /// exact same padded LAYOUT — so _SlotGestures' zone math and the -pad
  /// shift in _slot are untouched — but no visuals, plus the leader the
  /// overlay's follower snaps to and the size report it needs.
  Widget _leaderChromed(
    double scale,
    Widget child, {
    bool verticalPills = true,
  }) {
    if (selectionLink == null) {
      return _SelectionChrome(
        scale: scale,
        verticalPills: verticalPills,
        child: child,
      );
    }
    return CompositedTransformTarget(
      link: selectionLink!,
      child: _MeasureSize(
        onChange: onSelectionSize,
        child: Padding(
          padding: EdgeInsets.all(kChromePad / scale),
          child: child,
        ),
      ),
    );
  }

  /// Slot layers carry the user's position/size adjustments and the
  /// tap/drag/pinch/resize handler. The chain, outer to inner, is:
  /// Transform.scale → _userRotated (center pivot) → _rotated (template, topLeft
  /// pivot) → _SlotGestures → chrome/content. The rotations wrap the gesture
  /// surface, so its hit region tracks the PAINTED element (corner/rotate
  /// handles included) rather than the unrotated layout box — otherwise a
  /// designer-rotated element's handles fall outside their own touch region.
  /// _SlotGestures un-rotates drag deltas back into template space. Transform.
  /// scale stays outermost so the hit area grows with a resized element.
  Widget _slot(
    String slotId,
    double x,
    double y,
    Widget child, {
    bool gestures = true,
    double templateRotation = 0,
    double? frameWidth,
    Alignment frameAlignment = Alignment.topLeft,
    Size? baseSize,
    bool verticalEdges = true,
  }) {
    final offset = content.offsetFor(slotId);
    final scale = content.scaleFor(slotId);
    // When selected the chrome floats a kChromePad margin around the element
    // (so corner zones overflow it and stay touchable); shift back by the
    // same pad so the element's center stays put on selection.
    final pad = selected ? kChromePad / scale : 0.0;
    Widget inner = child;
    if (gestures &&
        (onSlotTap != null ||
            onSlotDrag != null ||
            onSlotScale != null ||
            onSlotRotate != null ||
            onSlotDelete != null)) {
      inner = _SlotGestures(
        slotId: slotId,
        currentScale: scale,
        currentRotation: content.rotationFor(slotId),
        templateRotation: templateRotation,
        currentStretchX: content.stretchXFor(slotId),
        currentStretchY: content.stretchYFor(slotId),
        baseSize: baseSize,
        verticalEdges: verticalEdges,
        selected: selected,
        onTap: onSlotTap,
        onDrag: onSlotDrag,
        onScaleChange: onSlotScale,
        onRotateChange: onSlotRotate,
        onEdgeResize: onSlotEdgeResize,
        onDelete: onSlotDelete,
        child: inner,
      );
    }
    // Content that hugs its glyphs (text) still positions and transforms
    // through the MODEL box: this frame is model-width (plus the chrome pad,
    // which the -pad shift below cancels) and re-aligns the hugged child
    // inside it, so x/y, the scale/rotation pivots and the painted glyphs
    // are identical to a fixed-width child — only the chrome/gesture box
    // (inside the Align) hugs. The frame itself takes no hits: touches
    // outside the hugged child fall through to the layers beneath.
    if (frameWidth != null) {
      inner = SizedBox(
        width: frameWidth + 2 * pad,
        child: Align(alignment: frameAlignment, child: inner),
      );
    }
    // Rotations wrap the gesture surface (see the doc above). User rotation
    // pivots around the element center (Canva-style); template rotation keeps
    // its top-left origin (the Konva contract shared with the web editor).
    inner = _userRotated(slotId, _rotated(templateRotation, _isolated(inner)));
    // Always wrap in Transform.scale (identity at 1.0), never conditionally:
    // inserting it on the first resize would restructure the tree and remount
    // _SlotGestures mid-gesture — the one-time hitch on the first drag.
    final result = Transform.scale(scale: scale, child: inner);
    return _positioned(x + offset.dx - pad, y + offset.dy - pad, result);
  }

  Widget _positioned(double x, double y, Widget child) =>
      Positioned(left: x, top: y, child: child);

  /// Each slot is its own repaint island: dragging one element then only
  /// re-offsets its cached raster in the compositor instead of re-painting
  /// every photo and paragraph in the panel on each frame — the difference
  /// between a drag that glides and one that feels heavy. The boundary sits
  /// INSIDE the rotation/scale transforms (same box as the gesture surface,
  /// which already gates hits to it): outside them its size check would
  /// reject touches on a rotated element's handles, which fall past the
  /// unrotated layout box — RenderTransform skips that check, proxy boxes
  /// don't.
  Widget _isolated(Widget child) => RepaintBoundary(child: child);

  Widget _rotated(double degrees, Widget child) {
    if (degrees == 0) return child;
    return Transform.rotate(
      angle: degrees * math.pi / 180,
      alignment: Alignment.topLeft,
      child: child,
    );
  }

  /// The user's rotation override, pivoting around the element CENTER (default
  /// Transform.rotate alignment) so dragging the rotation handle spins the
  /// element in place. ALWAYS wraps (identity at 0°), never conditionally —
  /// like Transform.scale: inserting the Transform when rotation first goes
  /// non-zero would restructure the tree and remount _SlotGestures mid-gesture,
  /// the one-time hitch on the first rotation.
  Widget _userRotated(String slotId, Widget child) => Transform.rotate(
    angle: content.rotationFor(slotId) * math.pi / 180,
    child: child,
  );
}

/// The single gesture surface for a slot: tap, move, pinch, resize AND rotate,
/// all in one ScaleGestureRecognizer so nothing competes in the gesture arena
/// (nested recognizers were the source of dropped touches).
///
/// One finger near a corner (only when selected) resizes by tracking the
/// finger's distance to the element center in global coordinates. One finger
/// on the rotation handle (below bottom-center, only when selected) rotates by
/// tracking the finger's angle around that same center. One finger in the
/// interior moves. Two fingers pinch. d.scale is a ratio relative to the
/// gesture start, re-based whenever the finger count changes.
class _SlotGestures extends StatefulWidget {
  final String slotId;
  final double currentScale;

  /// The slot's current user rotation in degrees — the base a two-finger
  /// twist adds onto.
  final double currentRotation;

  /// The layer's own template rotation in degrees (designer-applied; images
  /// carry one, text doesn't). The element paints through this rotation too, so
  /// the handle touch zones must account for it — see [_SlotGesturesState._toRotated].
  final double templateRotation;
  // Move/resize/pinch/rotate are wired only when the slot is selected;
  // otherwise the detector exposes just the tap (to select) and lets drags
  // fall through to the canvas pan/zoom instead of moving an unselected
  // element.
  final bool selected;

  /// Current per-axis stretch factors (SlotContent.stretchX/stretchY) — the
  /// base an edge drag multiplies, mirroring [currentScale] for the corners.
  final double currentStretchX;
  final double currentStretchY;

  /// The layer's model size in template px, PRE-stretch — converts a stretch
  /// factor delta into layout px for the anchoring compensation. Null disables
  /// edge resize (non-slot usages).
  final Size? baseSize;

  /// False suppresses the top/bottom edge pills (text: height is automatic).
  final bool verticalEdges;
  final void Function(String slotId)? onTap;
  final void Function(String slotId, Offset delta)? onDrag;
  final void Function(String slotId, double scale)? onScaleChange;
  final void Function(String slotId, double degrees)? onRotateChange;

  /// One-finger drag on an edge pill — single-axis stretch. Reports the new
  /// absolute [factor] for that axis plus the position compensation that
  /// keeps the opposite edge fixed. See [PanelCanvas.onSlotEdgeResize].
  final void Function(
    String slotId,
    SlotEdge edge,
    double factor,
    Offset offsetDelta,
  )?
  onEdgeResize;

  /// Tap on the delete handle above the selected element — deletes it. Only
  /// meaningful while [selected] (the handle only exists then).
  final void Function(String slotId)? onDelete;
  final Widget child;

  const _SlotGestures({
    required this.slotId,
    required this.currentScale,
    required this.currentRotation,
    required this.templateRotation,
    required this.selected,
    this.currentStretchX = 1.0,
    this.currentStretchY = 1.0,
    this.baseSize,
    this.verticalEdges = true,
    required this.onTap,
    required this.onDrag,
    required this.onScaleChange,
    required this.onRotateChange,
    this.onEdgeResize,
    required this.onDelete,
    required this.child,
  });

  @override
  State<_SlotGestures> createState() => _SlotGesturesState();
}

class _SlotGesturesState extends State<_SlotGestures> {
  double _baseScale = 1.0;
  int _pointerCount = 0;
  bool _isResizing = false;
  double _startScale = 1.0;
  double? _startDistance;
  // Rotation handle drag: the user rotation when the drag began, and the angle
  // (radians) from the element center to the finger at that moment. The element
  // rotation tracks the change in that angle, so it follows the finger exactly.
  bool _isRotating = false;
  double _baseRotation = 0.0;
  double? _startAngle;
  // The element center, captured ONCE at gesture start: it is stationary
  // through a resize or rotation (scale and user rotation both pivot on it),
  // and recomputing it per-update goes wrong in overlay mode — the follower's
  // box size is measured post-frame, so mid-gesture it lags the transform by
  // a frame and localToGlobal drifts off the true center.
  Offset? _gestureCenter;
  // Edge-pill drag: the anchor is the OPPOSITE edge's midpoint, captured once
  // at gesture start in global coordinates (stationary by construction — the
  // offset compensation holds it fixed) together with the drag axis' global
  // direction. The stretch factor tracks the finger's projection onto that
  // axis, so the dragged edge follows the finger while the anchor stays put.
  SlotEdge? _activeEdge;
  double _edgeStartFactor = 1.0;
  double _edgeLastFactor = 1.0;
  double? _edgeStartProj;
  Offset? _edgeAnchorGlobal;
  Offset? _edgeAxisGlobal;

  /// Element center in global coordinates — the anchor resize distances and
  /// rotation angles are measured from. This widget lives INSIDE the rotation
  /// (and scale) transforms, so localToGlobal maps the layout-box center to
  /// where the element actually paints; hence this is the true visible center
  /// for any rotation.
  Offset? _centerGlobal() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  /// Rotates [v] by [rad] around the origin (for direction vectors like drag
  /// deltas, where the pivot is irrelevant).
  Offset _rotateVec(Offset v, double rad) {
    if (rad == 0) return v;
    final cos = math.cos(rad);
    final sin = math.sin(rad);
    return Offset(v.dx * cos - v.dy * sin, v.dx * sin + v.dy * cos);
  }

  /// A local drag delta lands in the element's ROTATED frame (this widget sits
  /// inside both rotations); rotate it back so the offset moves in template
  /// space and the element still follows the finger.
  Offset _dragToTemplate(Offset delta) => _rotateVec(
    delta,
    (widget.currentRotation + widget.templateRotation) * math.pi / 180,
  );

  /// The resize zones — see [_nearCornerZone]. The gesture surface is inside
  /// the rotations, so [local] arrives already un-rotated.
  bool _nearCorner(Offset local, Size size) =>
      _nearCornerZone(local, size, widget.currentScale);

  /// The rotation-handle zone — see [_nearRotateZone].
  bool _nearRotationHandle(Offset local, Size size) =>
      _nearRotateZone(local, size, widget.currentScale);

  // Delete-tap detection rides a raw Listener instead of a tap recognizer: a
  // tap recognizer would join the gesture arena and delay the scale
  // recognizer's accept until past touch slop, shifting onScaleStart's focal
  // point off the corner/rotate zones and off the resize anchor distance
  // (which is exactly calibrated to fire at pointer-down when scale is the
  // sole member). The Listener sees the raw events without competing.
  int _pointersDown = 0;
  int? _deletePointer;
  Offset _deleteDownGlobal = Offset.zero;

  /// Whether a touch at [local] lands on the delete handle's zone (only
  /// meaningful while selected — the handle only exists then). The top edge
  /// pill sits _kDeleteHandleRise below the handle and their zones overlap:
  /// the closer center wins, so a pill grab can't delete.
  bool _inDeleteZone(Offset local) {
    final size = context.size;
    if (!(widget.selected &&
        widget.onDelete != null &&
        size != null &&
        _nearDeleteZone(local, size, widget.currentScale))) {
      return false;
    }
    final edgeHit = _edgeZoneHit(local, size);
    return edgeHit == null ||
        edgeHit.$1 != SlotEdge.top ||
        _deleteHandleDistSq(local, size, widget.currentScale) <= edgeHit.$2;
  }

  /// The edge-pill zone a touch at [local] falls in, when edge resize is
  /// wired for this slot — see [_nearEdgeZone].
  (SlotEdge, double)? _edgeZoneHit(Offset local, Size size) {
    if (widget.onEdgeResize == null || widget.baseSize == null) return null;
    return _nearEdgeZone(
      local,
      size,
      widget.currentScale,
      vertical: widget.verticalEdges,
    );
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointersDown++;
    if (_pointersDown == 1 && _inDeleteZone(e.localPosition)) {
      _deletePointer = e.pointer;
      _deleteDownGlobal = e.position;
    } else {
      // A second finger (or a touch elsewhere): not a delete tap.
      _deletePointer = null;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.pointer == _deletePointer &&
        (e.position - _deleteDownGlobal).distance > kTouchSlop) {
      _deletePointer = null; // Moved: it's a drag, not a tap.
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    _pointersDown = math.max(0, _pointersDown - 1);
    if (e.pointer != _deletePointer) return;
    _deletePointer = null;
    widget.onDelete!(widget.slotId);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _pointersDown = math.max(0, _pointersDown - 1);
    if (e.pointer == _deletePointer) _deletePointer = null;
  }

  /// Plain taps — but a tap on the delete zone belongs to the Listener above
  /// (which deletes), so it must NOT also select / start editing here.
  /// [d.localPosition] arrives un-rotated, like every zone check (the
  /// detector sits inside the rotations).
  void _onTapUp(TapUpDetails d) {
    if (_inDeleteZone(d.localPosition)) return;
    widget.onTap?.call(widget.slotId);
  }

  void _onScaleStart(ScaleStartDetails d) {
    _baseScale = widget.currentScale;
    _baseRotation = widget.currentRotation;
    _startScale = widget.currentScale;
    _pointerCount = d.pointerCount;
    final size = context.size;
    _isResizing =
        d.pointerCount == 1 &&
        size != null &&
        _nearCorner(d.localFocalPoint, size);
    // Corners win outright; between an edge pill and the rotate/delete
    // handles — whose zones overlap the bottom/top pills — the closer
    // center wins, so every visible handle stays grabbable.
    var edgeHit = (!_isResizing && d.pointerCount == 1 && size != null)
        ? _edgeZoneHit(d.localFocalPoint, size)
        : null;
    if (edgeHit != null &&
        size != null &&
        edgeHit.$1 == SlotEdge.top &&
        widget.onDelete != null &&
        _nearDeleteZone(d.localFocalPoint, size, widget.currentScale) &&
        _deleteHandleDistSq(d.localFocalPoint, size, widget.currentScale) <=
            edgeHit.$2) {
      edgeHit = null;
    }
    final nearRotate =
        !_isResizing &&
        d.pointerCount == 1 &&
        size != null &&
        _nearRotationHandle(d.localFocalPoint, size);
    _isRotating =
        nearRotate &&
        (edgeHit == null ||
            _rotateHandleDistSq(d.localFocalPoint, size, widget.currentScale) <=
                edgeHit.$2);
    _activeEdge = (!_isResizing && !_isRotating) ? edgeHit?.$1 : null;
    _gestureCenter = (_isResizing || _isRotating) ? _centerGlobal() : null;
    if (_isResizing) {
      final center = _gestureCenter;
      _startDistance = center == null ? null : (d.focalPoint - center).distance;
    }
    if (_isRotating) {
      final center = _gestureCenter;
      _startAngle = center == null ? null : (d.focalPoint - center).direction;
    }
    if (_activeEdge != null) _startEdgeResize(d, size!, _activeEdge!);
  }

  /// Captures the edge drag's global anchor (opposite edge midpoint), axis
  /// direction and the finger's starting projection — all ONCE, for the same
  /// frame-lag reason as [_gestureCenter].
  void _startEdgeResize(ScaleStartDetails d, Size size, SlotEdge edge) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      _activeEdge = null;
      return;
    }
    final pad = kChromePad / widget.currentScale;
    final w = size.width - 2 * pad;
    final h = size.height - 2 * pad;
    // Local (unrotated) midpoints of the dragged edge's OPPOSITE edge, and
    // the local unit axis pointing from that anchor toward the dragged edge.
    final (anchorLocal, axisLocal) = switch (edge) {
      SlotEdge.right => (Offset(pad, pad + h / 2), const Offset(1, 0)),
      SlotEdge.left => (Offset(pad + w, pad + h / 2), const Offset(-1, 0)),
      SlotEdge.bottom => (Offset(pad + w / 2, pad), const Offset(0, 1)),
      SlotEdge.top => (Offset(pad + w / 2, pad + h), const Offset(0, -1)),
    };
    final anchorGlobal = box.localToGlobal(anchorLocal);
    // A generous local step keeps the normalized direction numerically clean.
    final axisGlobal =
        box.localToGlobal(anchorLocal + axisLocal * 100) - anchorGlobal;
    if (axisGlobal.distance < 1e-9) {
      _activeEdge = null;
      return;
    }
    final axisUnit = axisGlobal / axisGlobal.distance;
    final proj = _dot(d.focalPoint - anchorGlobal, axisUnit);
    if (proj < 1) {
      _activeEdge = null;
      return;
    }
    _edgeAnchorGlobal = anchorGlobal;
    _edgeAxisGlobal = axisUnit;
    _edgeStartProj = proj;
    final horizontal = edge == SlotEdge.left || edge == SlotEdge.right;
    _edgeStartFactor = horizontal
        ? widget.currentStretchX
        : widget.currentStretchY;
    _edgeLastFactor = _edgeStartFactor;
  }

  static double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

  /// The offset delta (template space) that keeps the anchor edge stationary
  /// while the layout box grows by [dLayout] px along its local axis. The
  /// Positioned pins the layout top-left, but the box CENTER — the pivot of
  /// Transform.scale and of the user rotation — shifts by e = dLayout/2, so a
  /// fixed local point paints displaced by S·Ru(e) − e; cancel it. Dragging
  /// the min edge (left/top) anchors the max edge, whose LOCAL position also
  /// moves by 2e through the template rotation (top-left pivot) — cancel
  /// that too. (Derivation: painted(p) = pos + C + S·Ru·(Rt·p − C).)
  Offset _edgeCompensation(double dLayout, SlotEdge edge) {
    final horizontal = edge == SlotEdge.left || edge == SlotEdge.right;
    final e = horizontal ? Offset(dLayout / 2, 0) : Offset(0, dLayout / 2);
    final s = widget.currentScale;
    final ru = widget.currentRotation * math.pi / 180;
    final rt = widget.templateRotation * math.pi / 180;
    var delta = _rotateVec(e, ru) * s - e;
    if (edge == SlotEdge.left || edge == SlotEdge.top) {
      delta -= _rotateVec(_rotateVec(e * 2, rt), ru) * s;
    }
    return delta;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount != _pointerCount) {
      // The recognizer re-bases d.scale/d.rotation to 1.0/0 whenever the
      // finger count changes; re-base our anchors with it.
      _baseScale = widget.currentScale;
      _baseRotation = widget.currentRotation;
      _pointerCount = d.pointerCount;
      // A second finger turns the gesture into a pinch/move (never resize or
      // handle-rotate — those are one-finger handle drags).
      if (d.pointerCount >= 2) {
        _isResizing = false;
        _isRotating = false;
        _activeEdge = null;
      }
    }
    if (_activeEdge != null && d.pointerCount == 1) {
      final edge = _activeEdge!;
      final anchor = _edgeAnchorGlobal;
      final axis = _edgeAxisGlobal;
      final startProj = _edgeStartProj;
      final base = widget.baseSize;
      if (anchor != null && axis != null && startProj != null && base != null) {
        final proj = _dot(d.focalPoint - anchor, axis);
        // Clamp BEFORE the compensation, so the anchor stays fixed even
        // while the factor is pinned at a limit.
        final factor = (_edgeStartFactor * proj / startProj).clamp(
          _kMinSlotScale,
          _kMaxSlotScale,
        );
        final horizontal = edge == SlotEdge.left || edge == SlotEdge.right;
        final dLayout =
            (horizontal ? base.width : base.height) *
            (factor - _edgeLastFactor);
        widget.onEdgeResize?.call(
          widget.slotId,
          edge,
          factor,
          _edgeCompensation(dLayout, edge),
        );
        _edgeLastFactor = factor;
      }
      return;
    }
    if (_isResizing && d.pointerCount == 1) {
      final center = _gestureCenter;
      if (center != null && _startDistance != null && _startDistance! >= 1) {
        final distance = (d.focalPoint - center).distance;
        widget.onScaleChange?.call(
          widget.slotId,
          (_startScale * distance / _startDistance!).clamp(
            _kMinSlotScale,
            _kMaxSlotScale,
          ),
        );
      }
      return;
    }
    if (_isRotating && d.pointerCount == 1) {
      final center = _gestureCenter;
      if (center != null && _startAngle != null) {
        final angle = (d.focalPoint - center).direction;
        widget.onRotateChange?.call(
          widget.slotId,
          _baseRotation + (angle - _startAngle!) * 180 / math.pi,
        );
      }
      return;
    }
    if (d.focalPointDelta != Offset.zero) {
      widget.onDrag?.call(widget.slotId, _dragToTemplate(d.focalPointDelta));
    }
    if (d.pointerCount >= 2 && d.scale != 1.0) {
      widget.onScaleChange?.call(
        widget.slotId,
        (_baseScale * d.scale).clamp(_kMinSlotScale, _kMaxSlotScale),
      );
    }
    // Two-finger twist rotates (Stories-style), matching the canvas-wide
    // surface so pinching ON the element behaves like pinching next to it.
    if (d.pointerCount >= 2 && d.rotation != 0) {
      widget.onRotateChange?.call(
        widget.slotId,
        _baseRotation + d.rotation * 180 / math.pi,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // The Listener handles delete taps outside the gesture arena (see the
    // fields above); it never competes with the recognizers below.
    return Listener(
      onPointerDown: widget.onDelete == null ? null : _onPointerDown,
      onPointerMove: widget.onDelete == null ? null : _onPointerMove,
      onPointerUp: widget.onDelete == null ? null : _onPointerUp,
      onPointerCancel: widget.onDelete == null ? null : _onPointerCancel,
      child: GestureDetector(
        // Opaque, not the default deferToChild: a text slot is mostly empty
        // space (glyphs only at the top) with IgnorePointer chrome, so
        // deferToChild would drop touches on the corners and gaps — which was
        // exactly why grabbing a handle so often did nothing.
        behavior: HitTestBehavior.opaque,
        // TapUp (not onTap) because a tap on the delete zone must be left to
        // the Listener instead of selecting.
        onTapUp: widget.onTap == null ? null : _onTapUp,
        // Wire move/resize/pinch ONLY when selected: an unwired scale
        // recognizer would still win the arena over the canvas pan, dragging
        // an unselected element. With these null, an unselected slot only
        // taps (to select) and drags fall through to the canvas pan/zoom.
        onScaleStart: widget.selected ? _onScaleStart : null,
        onScaleUpdate: widget.selected ? _onScaleUpdate : null,
        child: widget.child,
      ),
    );
  }
}

/// Editor-style selection chrome: a thin white frame with four round corner
/// handles, floated a kChromePad margin around the element so the handles
/// (and their touch zones in _SlotGestures) overflow the element and stay
/// reachable. Purely VISUAL (IgnorePointer) — it shows where to grab; the
/// resize itself is handled by _SlotGestures' corner zones. Sizes are divided
/// by the current scale to stay visually constant.
class _SelectionChrome extends StatelessWidget {
  final double scale;

  /// The element the chrome wraps (legacy in-canvas mode: the padded child
  /// sizes the stack). Null in overlay mode, where the parent — a SizedBox
  /// with the leader's measured size — imposes the padded box size instead.
  final Widget? child;

  /// False hides the top/bottom edge pills (text slots: height is automatic,
  /// only the wrap width stretches).
  final bool verticalPills;

  const _SelectionChrome({
    required this.scale,
    this.child,
    this.verticalPills = true,
  });

  @override
  Widget build(BuildContext context) {
    final pad = kChromePad / scale;
    final stroke = 4.0 / scale;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Padded element sizes the stack to element + 2*pad, giving the
        // wrapping _SlotGestures a hit region that extends past the element.
        if (child != null)
          Padding(padding: EdgeInsets.all(pad), child: child)
        else
          const SizedBox.expand(),
        Positioned(
          left: pad,
          top: pad,
          right: pad,
          bottom: pad,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: stroke),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth - 2 * pad;
                final h = constraints.maxHeight - 2 * pad;
                final drop = _kRotateHandleDrop / scale;
                final rise = _kDeleteHandleRise / scale;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Stem connecting the element's bottom-center to the handle.
                    Positioned(
                      left: pad + w / 2 - stroke / 2,
                      top: pad + h,
                      width: stroke,
                      height: drop,
                      child: const ColoredBox(color: Colors.white),
                    ),
                    _corner('tl', pad, pad),
                    _corner('tr', pad + w, pad),
                    _corner('bl', pad, pad + h),
                    _corner('br', pad + w, pad + h),
                    // Edge pills (single-axis stretch), gated by the same
                    // fit predicate as their hit zones — what you see is
                    // exactly what you can grab.
                    if (verticalPills && _edgePillsFit(w, scale)) ...[
                      _pill('t', pad + w / 2, pad, horizontal: true),
                      _pill('b', pad + w / 2, pad + h, horizontal: true),
                    ],
                    if (_edgePillsFit(h, scale)) ...[
                      _pill('l', pad, pad + h / 2, horizontal: false),
                      _pill('r', pad + w, pad + h / 2, horizontal: false),
                    ],
                    _glyphHandle(
                      'rotate',
                      Icons.rotate_right,
                      const Color(0xFF3F3F46),
                      pad + w / 2,
                      pad + h + drop,
                    ),
                    _glyphHandle(
                      'delete',
                      Icons.close,
                      const Color(0xFFEF4444),
                      pad + w / 2,
                      pad - rise,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// A round button with a glyph, centered at ([cx], [cy]) — the rotation
  /// handle below the element and the delete handle above it. Purely visual
  /// (the chrome is wrapped in IgnorePointer) — the interaction is recognized
  /// by _SlotGestures' matching zone (_nearRotateZone / _nearDeleteZone).
  Widget _glyphHandle(
    String key,
    IconData icon,
    Color color,
    double cx,
    double cy,
  ) {
    final dot = 60.0 / scale;
    return Positioned(
      left: cx - dot / 2,
      top: cy - dot / 2,
      width: dot,
      height: dot,
      child: Container(
        key: ValueKey('handle_$key'),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFFD4D4D8),
            width: 1.5 / scale,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 6 / scale,
              offset: Offset(0, 2 / scale),
            ),
          ],
        ),
        child: Icon(icon, size: 40 / scale, color: color),
      ),
    );
  }

  /// One edge pill centered at ([cx], [cy]) in the padded space: a capsule
  /// lying along its edge ([horizontal] on top/bottom, upright on the sides),
  /// visually matching the corner dots. Purely visual, like every handle —
  /// _SlotGestures' matching edge zone recognizes the drag.
  Widget _pill(String key, double cx, double cy, {required bool horizontal}) {
    final len = _kEdgePillLength / scale;
    final thick = _kEdgePillThickness / scale;
    final w = horizontal ? len : thick;
    final h = horizontal ? thick : len;
    return Positioned(
      left: cx - w / 2,
      top: cy - h / 2,
      width: w,
      height: h,
      child: Container(
        key: ValueKey('handle_edge_$key'),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(thick / 2),
          border: Border.all(
            color: const Color(0xFFD4D4D8),
            width: 1.5 / scale,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 6 / scale,
              offset: Offset(0, 2 / scale),
            ),
          ],
        ),
      ),
    );
  }

  /// One round corner handle centered at ([cx], [cy]) in the padded space.
  Widget _corner(String key, double cx, double cy) {
    final dot = 60.0 / scale;
    return Positioned(
      left: cx - dot / 2,
      top: cy - dot / 2,
      width: dot,
      height: dot,
      child: Container(
        key: ValueKey('handle_$key'),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFFD4D4D8),
            width: 1.5 / scale,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 6 / scale,
              offset: Offset(0, 2 / scale),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageSlot extends StatelessWidget {
  final ImageLayer layer;
  final SlotContent content;
  final List<AssetRecord> assetCatalog;

  /// Whether the canvas is interactive (tap handlers installed) — empty
  /// placeholders then advertise themselves with a photo icon.
  final bool interactive;

  /// Whether this image slot is the selected one (shows the replace overlay).
  final bool selected;

  /// Opens the gallery for this slot. Wired to the photo icon only — a tap on
  /// the image elsewhere selects it (move/resize) without opening the gallery.
  final void Function(String slotId)? onPick;

  /// Effective (edge-stretched) box; defaults to the layer's own dimensions.
  /// The photo cover-fits this box, so stretching crops/refits, never distorts.
  final double? width;
  final double? height;

  /// See [PanelCanvas.showTemplatePhotos].
  final bool showTemplatePhotos;

  const _ImageSlot({
    required this.layer,
    required this.content,
    this.assetCatalog = const [],
    this.showTemplatePhotos = false,
    this.interactive = false,
    this.selected = false,
    this.onPick,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final w = width ?? layer.width;
    final h = height ?? layer.height;
    final pick = (interactive && onPick != null)
        ? () => onPick!(layer.slotId)
        : null;
    final frame = resolveFrame(layer.frameAssetId, assetCatalog);

    if (frame == null) {
      // Bare photo: fills the whole slot box (unchanged behavior).
      return Opacity(
        opacity: layer.opacity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(layer.borderRadius),
          child: _photo(w, h, pick),
        ),
      );
    }

    // Framed photo: the user's photo lives in the frame's transparent window,
    // the frame paints over the whole box. The frame stretches to the box (its
    // aspect matches the layer's) so its window lands exactly on [win]. It
    // ignores pointer events so a tap still hits the photo/slot beneath it.
    final win = frame.windowIn(w, h);
    return Opacity(
      opacity: layer.opacity,
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          children: [
            Positioned.fromRect(
              rect: win,
              child: ClipRect(child: _photo(win.width, win.height, pick)),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Image(image: frame.image, fit: BoxFit.fill),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The photo (or empty placeholder) sized to a [w]×[h] box — the whole slot
  /// when unframed, or the frame's window when framed. The user's photo always
  /// wins; the designer's sample photo fills in only where the canvas opted in.
  Widget _photo(double w, double h, VoidCallback? pick) {
    final image =
        content.imageFor(layer.slotId) ??
        (showTemplatePhotos
            ? resolvePhoto(layer.imageAssetId, assetCatalog)
            : null);
    if (image != null) {
      return Stack(
        children: [
          Image(image: image, width: w, height: h, fit: BoxFit.cover),
          // A filled image is replaced by tapping the overlay icon (only while
          // selected); a tap anywhere else just moves it.
          if (selected && pick != null)
            Positioned.fill(
              child: Center(child: _PickIcon(onTap: pick)),
            ),
        ],
      );
    }
    return Container(
      width: w,
      height: h,
      color: const Color(0xFFE4E4E7),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tapping the icon opens the gallery; tapping the rest of the
          // placeholder falls through to select the slot.
          if (pick != null) _PickIcon(onTap: pick),
          Text(
            layer.slotId,
            style: const TextStyle(color: Color(0xFF71717A), fontSize: 40),
          ),
        ],
      ),
    );
  }
}

/// A photo grid: tiles its box into fixed cells (from the layer's fraction
/// tracks). Each cell is a fillable photo slot the user can pan/zoom within.
/// The grid element itself isn't moved/rotated by the user here (that's the
/// designer's job) — only the cell photos are edited.
class _GridSlot extends StatefulWidget {
  final GridLayer grid;
  final SlotContent content;
  final List<AssetRecord> assetCatalog;
  final bool interactive;
  final String? selectedSlotId;
  final void Function(String slotId)? onSlotTap;
  final void Function(String slotId)? onPickImage;

  /// Reported ONCE per divider drag, on release — not per pointer delta;
  /// the in-flight drag repaints locally (see [_GridSlotState]).
  final void Function(String gridId, bool columns, List<double> fractions)?
  onGridFractions;

  /// Effective (edge-stretched) box; defaults to the grid's own dimensions.
  /// Cell rects re-tile the stretched box, so cells refit — photos re-cover.
  final double? width;
  final double? height;

  /// See [PanelCanvas.showTemplatePhotos].
  final bool showTemplatePhotos;

  const _GridSlot({
    required this.grid,
    required this.content,
    this.assetCatalog = const [],
    this.showTemplatePhotos = false,
    this.interactive = false,
    this.selectedSlotId,
    this.onSlotTap,
    this.onPickImage,
    this.onGridFractions,
    this.width,
    this.height,
  });

  @override
  State<_GridSlot> createState() => _GridSlotState();
}

class _GridSlotState extends State<_GridSlot> {
  /// Fractions being live-edited by an in-flight divider drag. Deliberately
  /// LOCAL state: pushing every pointer delta through onGridFractions rebuilt
  /// the whole screen per frame (undo bookkeeping, save debounce, every
  /// panel's layers) and made the drag stutter. The drag repaints only this
  /// grid; the result is committed upward once, on release.
  List<double>? _dragColF, _dragRowF;

  GridLayer get grid => widget.grid;
  double get _w => widget.width ?? grid.width;
  double get _h => widget.height ?? grid.height;

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    // Effective (user-overridden) grid values; falling back to the template's.
    final gutter = content.gridGutter(grid.id, grid.gutter);
    final corner = content.gridCornerRadius(grid.id, grid.cornerRadius);
    final colF =
        _dragColF ?? content.gridColFractions(grid.id, grid.colFractions);
    final rowF =
        _dragRowF ?? content.gridRowFractions(grid.id, grid.rowFractions);

    // Dividers appear once one of this grid's cells is selected (so the user is
    // "in" the grid), and only when a fraction handler is wired.
    final active =
        widget.onGridFractions != null &&
        widget.selectedSlotId != null &&
        grid.cells.any((c) => c.slotId == widget.selectedSlotId);

    Rect rectOf(GridCell cell) => cellRect(
      grid,
      cell,
      colFractions: colF,
      rowFractions: rowF,
      gutter: gutter,
      width: _w,
      height: _h,
    );

    // The outer RepaintBoundary keeps a divider drag's per-frame repaints
    // from dirtying the panel's export boundary — without it, every OTHER
    // layer of the panel (photos, text) re-painted on every drag frame. The
    // per-cell boundaries then confine the repaint to the cells whose rect
    // actually changed (the two tracks beside the dragged divider).
    return RepaintBoundary(
      child: SizedBox(
        width: _w,
        height: _h,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Gutter colour paints behind the cells and shows through the
            // gaps; absent = transparent (the panel background shows
            // through).
            if (grid.gutterColor != null)
              Positioned.fill(child: ColoredBox(color: grid.gutterColor!)),
            for (final cell in grid.cells)
              Positioned.fromRect(
                rect: rectOf(cell),
                child: RepaintBoundary(
                  child: _GridCell(
                    slotId: cell.slotId,
                    radius: cell.borderRadius ?? corner,
                    // The user's photo wins; the designer's sample only fills
                    // in where the canvas opted in (the preview).
                    image:
                        content.imageFor(cell.slotId) ??
                        (widget.showTemplatePhotos
                            ? resolvePhoto(
                                cell.imageAssetId,
                                widget.assetCatalog,
                              )
                            : null),
                    selected: cell.slotId == widget.selectedSlotId,
                    interactive: widget.interactive,
                    onTap: widget.onSlotTap,
                    onPick: widget.onPickImage,
                  ),
                ),
              ),
            if (active) ..._dividers(colF, rowF, gutter),
          ],
        ),
      ),
    );
  }

  /// One draggable handle per interior column/row boundary. Handles sit in the
  /// grid's local (unrotated) frame, and a drag's local delta is in that same
  /// frame, so shifting a boundary is a direct px→fraction conversion — no
  /// rotation math even when the grid is rotated.
  ///
  /// A boundary only exists where a cell actually ENDS at it — a spanning
  /// cell crosses it and erases the line there. Each divider's strip covers
  /// just that extent (leaving the rest of the line free to move the grid),
  /// and its pill sits on the LARGEST single cell segment, so the handle
  /// always lies between the two cells it splits and two pills never stack
  /// into a "+" at the grid centre.
  List<Widget> _dividers(List<double> colF, List<double> rowF, double gutter) {
    const handleW = _kGridDividerStrip;
    Rect rectOf(GridCell cell) => cellRect(
      grid,
      cell,
      colFractions: colF,
      rowFractions: rowF,
      gutter: gutter,
      width: _w,
      height: _h,
    );

    // (strip start, strip end, pill centre) along the boundary's long axis —
    // null when no cell ends at track [i] (the line is fully erased by
    // spanning cells), which also drops the divider entirely.
    (double, double, double)? extentOf(bool columns, int i) {
      double? start, end;
      var largest = -1.0, pill = 0.0;
      for (final cell in grid.cells) {
        final span = columns ? cell.colSpan : cell.rowSpan;
        final first = columns ? cell.col : cell.row;
        if (first + (span < 1 ? 1 : span) - 1 != i) continue;
        final r = rectOf(cell);
        final (s, e) = columns ? (r.top, r.bottom) : (r.left, r.right);
        start = math.min(start ?? s, s);
        end = math.max(end ?? e, e);
        if (e - s > largest) {
          largest = e - s;
          pill = (s + e) / 2;
        }
      }
      return start == null ? null : (start, end!, pill);
    }

    double colCenter(int i) =>
        rectOf(GridCell(slotId: '', col: i, row: 0)).right + gutter / 2;
    double rowCenter(int j) =>
        rectOf(GridCell(slotId: '', col: 0, row: j)).bottom + gutter / 2;

    return [
      for (var i = 0; i < grid.cols - 1; i++)
        if (extentOf(true, i) case (final start, final end, final pill))
          Positioned(
            left: colCenter(i) - handleW / 2,
            top: start,
            width: handleW,
            height: end - start,
            child: _GridDivider(
              key: ValueKey('grid_div_col_$i'),
              vertical: true,
              pillCenter: pill - start,
              onDelta: (d) => _shift(true, colF, gutter, i, d),
              onEnd: () => _commit(true),
            ),
          ),
      for (var j = 0; j < grid.rows - 1; j++)
        if (extentOf(false, j) case (final start, final end, final pill))
          Positioned(
            left: start,
            top: rowCenter(j) - handleW / 2,
            width: end - start,
            height: handleW,
            child: _GridDivider(
              key: ValueKey('grid_div_row_$j'),
              vertical: false,
              pillCenter: pill - start,
              onDelta: (d) => _shift(false, rowF, gutter, j, d),
              onEnd: () => _commit(false),
            ),
          ),
    ];
  }

  /// Moves the boundary between tracks [i] and [i+1] by [deltaPx] (grid-local),
  /// transferring fraction between the two while keeping their sum — clamped so
  /// neither track collapses. Repaints only this grid (see [_dragColF]).
  void _shift(
    bool columns,
    List<double> fractions,
    double gutter,
    int i,
    double deltaPx,
  ) {
    final tracks = columns ? grid.cols : grid.rows;
    final box = columns ? _w : _h;
    final usable = math.max(1.0, box - gutter * (tracks + 1));
    final s = fractions.fold(0.0, (a, b) => a + b);
    final total = s == 0 ? 1.0 : s;
    final pairFrac = fractions[i] + fractions[i + 1];
    final pairPx = usable * (pairFrac / total);
    if (pairPx <= 0) return;
    final wi = (usable * (fractions[i] / total) + deltaPx).clamp(
      pairPx * 0.1,
      pairPx * 0.9,
    );
    final fi = wi / pairPx * pairFrac;
    final next = List<double>.from(fractions);
    next[i] = fi;
    next[i + 1] = pairFrac - fi;
    setState(() => columns ? _dragColF = next : _dragRowF = next);
  }

  /// Drag released: hand the final fractions to the screen (one undo step,
  /// one save) and drop the local override — the committed content now holds
  /// the same values, so nothing jumps.
  void _commit(bool columns) {
    final next = columns ? _dragColF : _dragRowF;
    if (next != null) widget.onGridFractions!(grid.id, columns, next);
    setState(() => columns ? _dragColF = null : _dragRowF = null);
  }
}

/// Thickness of a grid divider's draggable strip (template px, straddling the
/// boundary). Wider than the gutter on purpose: the strip is the divider's
/// whole touch target, so it borrows a margin from each neighboring cell.
const double _kGridDividerStrip = 72.0;

/// A thin, draggable divider between two grid tracks. The visual pill sits on
/// the boundary at [pillCenter] — the middle of the largest cell segment the
/// boundary actually splits, not necessarily the strip's middle; a pan reports
/// its local delta along the relevant axis.
class _GridDivider extends StatelessWidget {
  final bool vertical;

  /// Centre of the pill along the strip's long axis, in strip-local px.
  final double pillCenter;
  final void Function(double deltaPx) onDelta;

  /// The drag finished (released or cancelled) — commit the result.
  final VoidCallback onEnd;

  const _GridDivider({
    super.key,
    required this.vertical,
    required this.pillCenter,
    required this.onDelta,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    // A short capsule on the boundary hints at the drag direction.
    const long = 96.0, thick = 16.0, strip = _kGridDividerStrip;
    final pill = Container(
      width: vertical ? thick : long,
      height: vertical ? long : thick,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(thick / 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: vertical ? null : (d) => onDelta(d.delta.dy),
      onVerticalDragEnd: vertical ? null : (_) => onEnd(),
      onVerticalDragCancel: vertical ? null : onEnd,
      onHorizontalDragUpdate: vertical ? (d) => onDelta(d.delta.dx) : null,
      onHorizontalDragEnd: vertical ? (_) => onEnd() : null,
      onHorizontalDragCancel: vertical ? onEnd : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: vertical ? (strip - thick) / 2 : pillCenter - long / 2,
            top: vertical ? pillCenter - long / 2 : (strip - thick) / 2,
            child: pill,
          ),
        ],
      ),
    );
  }
}

/// One grid cell: a fixed rounded box holding the user's photo (cover-fit,
/// centred — no per-cell crop) or, when empty, a placeholder with the pick icon.
/// The cell is TRANSLUCENT and only taps (to select the grid); a drag falls
/// through to the whole-grid gesture surface behind, so the grid moves/resizes/
/// rotates like an image. Tapping a selected, filled cell's centre icon swaps
/// the photo; the pick icon itself is opaque, so it never drags the grid.
class _GridCell extends StatelessWidget {
  final String slotId;
  final double radius;
  final ImageProvider? image;
  final bool selected;
  final bool interactive;
  final void Function(String slotId)? onTap;
  final void Function(String slotId)? onPick;

  const _GridCell({
    required this.slotId,
    required this.radius,
    required this.image,
    required this.selected,
    required this.interactive,
    this.onTap,
    this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final pick = (interactive && onPick != null) ? () => onPick!(slotId) : null;
    return GestureDetector(
      // Translucent (not opaque): a tap selects the grid, but a drag passes
      // through to the whole-grid gesture surface behind so the grid moves —
      // the cell no longer captures the touch for a crop.
      behavior: HitTestBehavior.translucent,
      onTap: onTap == null ? null : () => onTap!(slotId),
      child: image != null ? _filled(pick) : _empty(pick),
    );
  }

  // The photo (and border) is IgnorePointer'd so it is not a hit target: a
  // translucent GestureDetector only falls through to the grid surface behind
  // when NOTHING below it is hit. The pick icon stays a real (opaque) target,
  // so it — and only it — absorbs the touch.
  Widget _filled(VoidCallback? pick) {
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image(image: image!, fit: BoxFit.cover),
                if (selected)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Replace overlay (only when selected).
        if (selected && pick != null) Center(child: _PickIcon(onTap: pick)),
      ],
    );
  }

  Widget _empty(VoidCallback? pick) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background + label are non-hittable so a drag falls through to move
        // the grid; only the pick icon is a real touch target.
        IgnorePointer(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: const ColoredBox(color: Color(0xFFE4E4E7)),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pick != null) _PickIcon(onTap: pick),
              IgnorePointer(
                child: Text(
                  slotId,
                  style: const TextStyle(
                    color: Color(0xFF71717A),
                    fontSize: 32,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The photo-picker affordance: a round, padded "add photo" icon that is its
/// own tap target so only it — not the whole slot — opens the gallery.
class _PickIcon extends StatelessWidget {
  final VoidCallback onTap;

  const _PickIcon({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      // Opaque so the padding around the glyph is part of the tap target.
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.add_photo_alternate_outlined,
          size: 96,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _TextSlot extends StatelessWidget {
  final TextLayer layer;
  final SlotContent content;
  final FontResolver fontResolver;
  final bool editing;
  final Key? fieldKey;
  final void Function(String slotId, String value)? onTextChanged;

  /// Effective wrap width (edge-stretched); defaults to the layer's own.
  /// Stretching re-wraps the paragraph — glyphs never distort.
  final double? wrapWidth;

  const _TextSlot({
    required this.layer,
    required this.content,
    required this.fontResolver,
    this.editing = false,
    this.fieldKey,
    this.onTextChanged,
    this.wrapWidth,
  });

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: layer.fontSize,
      fontWeight: _weight(content.weightFor(layer.slotId) ?? layer.fontWeight),
      color: content.colorFor(layer.slotId) ?? layer.color,
    );
    final style = fontResolver(
      content.fontFor(layer.slotId) ?? layer.fontFamily,
      base,
    );
    final align = switch (content.alignmentFor(layer.slotId) ??
        layer.alignment) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    };
    if (editing) {
      // The editor hugs the typed text just like the display Text below
      // (IntrinsicWidth re-runs on every text layout — RenderBox invalidates
      // cached intrinsics up the tree — so the box grows per keystroke).
      // minWidth keeps the caret visible on empty text; maxWidth preserves
      // the wrap width.
      return ConstrainedBox(
        key: fieldKey,
        constraints: BoxConstraints(
          minWidth: layer.fontSize,
          maxWidth: wrapWidth ?? layer.width,
        ),
        child: IntrinsicWidth(
          child: _InlineTextEditor(
            initial: content.textFor(layer.slotId) ?? '',
            hint: layer.slotId,
            style: style,
            textAlign: align,
            onChanged: (value) => onTextChanged?.call(layer.slotId, value),
          ),
        ),
      );
    }
    // Hug the glyphs (maxWidth keeps the wrap identical to a fixed-width
    // box): the selection chrome and resize handles then wrap the text
    // itself, not the model box. _slot's frame re-aligns the hugged
    // paragraph inside the model box so the glyphs never move.
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: wrapWidth ?? layer.width),
      child: Text(
        content.textFor(layer.slotId) ?? layer.slotId,
        style: style,
        textAlign: align,
      ),
    );
  }

  FontWeight _weight(int value) =>
      FontWeight.values[(value / 100).round().clamp(1, 9) - 1];
}

/// In-canvas text editing: a collapsed TextField styled exactly like the
/// Text it replaces, so the glyphs don't shift when editing starts. Stateful
/// because the controller must survive the per-keystroke rebuilds.
class _InlineTextEditor extends StatefulWidget {
  final String initial;
  final String hint;
  final TextStyle style;
  final TextAlign textAlign;
  final ValueChanged<String> onChanged;

  const _InlineTextEditor({
    required this.initial,
    required this.hint,
    required this.style,
    required this.textAlign,
    required this.onChanged,
  });

  @override
  State<_InlineTextEditor> createState() => _InlineTextEditorState();
}

class _InlineTextEditorState extends State<_InlineTextEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // TextField needs a Material ancestor; transparency keeps the canvas
    // pixels untouched. The ListenableBuilder drops the hint as soon as
    // there is text: the InputDecorator's intrinsic width is
    // max(text, hint), so a lingering (invisible) hint would hold the
    // hugging editor box open wider than the typed glyphs.
    return Material(
      type: MaterialType.transparency,
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => TextField(
          controller: _controller,
          autofocus: true,
          maxLines: null,
          style: widget.style,
          textAlign: widget.textAlign,
          decoration: InputDecoration.collapsed(
            hintText: _controller.text.isEmpty ? widget.hint : null,
            hintStyle: widget.style.copyWith(
              color: widget.style.color?.withValues(alpha: 0.4),
            ),
          ),
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}

/// A sticker: its PNG from the asset catalog, contain-fit in the layer box.
/// Unknown/unfetched assets fall back to the labeled placeholder so the layer
/// stays visible (and tappable) instead of vanishing.
class _StickerSlot extends StatelessWidget {
  final StickerLayer layer;
  final List<AssetRecord> assetCatalog;

  /// Effective (edge-stretched) box; defaults to the layer's own dimensions.
  final double? width;
  final double? height;

  const _StickerSlot({
    required this.layer,
    required this.assetCatalog,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    for (final a in assetCatalog) {
      if (a.id == layer.assetId && a.type == 'sticker') {
        return SizedBox(
          width: width ?? layer.width,
          height: height ?? layer.height,
          child: Image(image: a.image, fit: BoxFit.contain),
        );
      }
    }
    return _StickerPlaceholder(layer: layer, width: width, height: height);
  }
}

/// Fallback visual for a sticker whose asset isn't in the catalog (offline
/// cold start, or a stale template) — the same labeled placeholder the editor
/// shows.
class _StickerPlaceholder extends StatelessWidget {
  final StickerLayer layer;
  final double? width;
  final double? height;

  const _StickerPlaceholder({required this.layer, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? layer.width,
      height: height ?? layer.height,
      decoration: BoxDecoration(
        color: const Color(0xFFDDD6FE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF8B5CF6), width: 4),
      ),
      alignment: Alignment.center,
      child: Text(
        layer.assetId,
        style: const TextStyle(color: Color(0xFF6D28D9), fontSize: 32),
      ),
    );
  }
}

/// Floats the selected element's chrome — border, corner handles, rotation
/// handle — and their gestures ABOVE the canvas, in screen space. Mount it in
/// a Stack over the whole canvas area and give [PanelCanvas] the same [link]:
/// the selected element publishes a [CompositedTransformTarget] on its padded
/// chrome box, and this follower inherits its full transform chain (FittedBox
/// scale, screen zoom, template/user rotations, slot scale), so all the
/// chrome and zone geometry runs in the same leader-local coordinates as the
/// legacy in-canvas chrome. RenderFollowerLayer hit-tests WITHOUT a size gate
/// — the framework's one escape hatch from "hit tests stop at every
/// ancestor's bounds" — which is what makes handles that spill past the
/// canvas edge visible AND touchable.
///
/// The overlay claims ONLY the ring band and the handle zones (see
/// [_RingHitRegion]); interior touches fall through to the canvas beneath,
/// which keeps owning content interaction exactly as before: tap-select,
/// drag/pinch on the element body, pick icons, grid cells and dividers.
class CanvasSelectionOverlay extends StatelessWidget {
  final LayerLink link;

  /// The leader's padded box size in leader-local units, as reported by
  /// [PanelCanvas.onSelectionSize]. Arrives one frame after selection
  /// (post-layout), so mount the overlay only once it's known.
  final Size size;

  /// The id gestures report — the slot id, or the LAYER id for a grid.
  final String targetId;
  final double currentScale;
  final double currentRotation;
  final double templateRotation;

  /// Current per-axis stretch and the layer's model size — the edge pills'
  /// state, mirroring [currentScale] for the corners. [baseSize] null keeps
  /// edge resize off (see [_SlotGestures.baseSize]).
  final double currentStretchX;
  final double currentStretchY;
  final Size? baseSize;

  /// False hides/suppresses the top/bottom pills (text slots).
  final bool verticalEdges;
  final void Function(String slotId, Offset delta)? onDrag;
  final void Function(String slotId, double scale)? onScaleChange;
  final void Function(String slotId, double degrees)? onRotateChange;

  /// Drag on an edge pill — see [PanelCanvas.onSlotEdgeResize].
  final void Function(
    String slotId,
    SlotEdge edge,
    double factor,
    Offset offsetDelta,
  )?
  onEdgeResize;

  /// Tap on the chrome's delete handle (the ✕ above the element).
  final void Function(String slotId)? onDelete;

  const CanvasSelectionOverlay({
    super.key,
    required this.link,
    required this.size,
    required this.targetId,
    required this.currentScale,
    required this.currentRotation,
    required this.templateRotation,
    this.currentStretchX = 1.0,
    this.currentStretchY = 1.0,
    this.baseSize,
    this.verticalEdges = true,
    this.onDrag,
    this.onScaleChange,
    this.onRotateChange,
    this.onEdgeResize,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return CompositedTransformFollower(
      link: link,
      showWhenUnlinked: false,
      // NOT Align: everything below the follower runs in leader-local units,
      // where a big element's chrome box far exceeds the overlay's own
      // (screen-sized) constraints — Align would clamp the SizedBox to the
      // screen box and the chrome would hug a fraction of the element.
      // _LeaderSpace hands the child unbounded constraints and skips the
      // own-size hit-test gate for the same reason.
      child: _LeaderSpace(
        child: _RingHitRegion(
          scale: currentScale,
          verticalEdges: verticalEdges,
          child: _SlotGestures(
            slotId: targetId,
            currentScale: currentScale,
            currentRotation: currentRotation,
            templateRotation: templateRotation,
            currentStretchX: currentStretchX,
            currentStretchY: currentStretchY,
            baseSize: baseSize,
            verticalEdges: verticalEdges,
            selected: true,
            // Plain ring taps are no-ops (the element is already selected);
            // only the delete zone means anything, and interior taps never
            // reach here — _RingHitRegion lets them through to the canvas.
            onTap: null,
            onDrag: onDrag,
            onScaleChange: onScaleChange,
            onRotateChange: onRotateChange,
            onEdgeResize: onEdgeResize,
            onDelete: onDelete,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: _SelectionChrome(
                scale: currentScale,
                verticalPills: verticalEdges,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The space between the follower and the chrome: everything below runs in
/// LEADER-LOCAL units (template px), decoupled from the overlay's own
/// screen-sized box. Lays the child out with unbounded constraints — a big
/// element's chrome box exceeds the screen box in those units, and any
/// Align/OverflowBox would clamp or misgate it — paints it at the leader's
/// origin, and hit-tests it without the own-size gate (positions arriving
/// here are already in leader space, where this render object's own size is
/// meaningless).
class _LeaderSpace extends SingleChildRenderObjectWidget {
  const _LeaderSpace({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLeaderSpace();
}

class _RenderLeaderSpace extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  @override
  void performLayout() {
    child?.layout(const BoxConstraints());
    size = constraints.smallest;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    if (c != null) context.paintChild(c, offset);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final c = child;
    if (c == null) return false;
    return c.hitTest(result, position: position);
  }
}

/// Shapes the overlay's hit region to the selection chrome: claims the pad
/// band around the element plus the corner-handle zones (whose inner halves
/// overlap the element, as in the legacy chrome), and lets every other
/// interior touch fall through the follower to the canvas beneath. The
/// rotation handle sits below the element, inside the ring band, so it needs
/// no special case.
class _RingHitRegion extends SingleChildRenderObjectWidget {
  final double scale;
  final bool verticalEdges;

  const _RingHitRegion({
    required this.scale,
    this.verticalEdges = true,
    super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRingHitRegion(scale, verticalEdges);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRingHitRegion renderObject,
  ) {
    renderObject
      ..scale = scale
      ..verticalEdges = verticalEdges;
  }
}

class _RenderRingHitRegion extends RenderProxyBox {
  _RenderRingHitRegion(this.scale, this.verticalEdges);

  double scale;
  bool verticalEdges;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    final pad = kChromePad / scale;
    final inner = Rect.fromLTWH(
      pad,
      pad,
      size.width - 2 * pad,
      size.height - 2 * pad,
    );
    // The corner and edge-pill zones' inner halves overlap the element, so
    // the overlay claims them too; any other interior touch belongs to the
    // canvas beneath.
    if (inner.contains(position) &&
        !_nearCornerZone(position, size, scale) &&
        _nearEdgeZone(position, size, scale, vertical: verticalEdges) == null) {
      return false; // Interior: the canvas beneath owns it.
    }
    return super.hitTest(result, position: position);
  }
}

/// Reports the child's laid-out size, post-frame and only when it changes.
class _MeasureSize extends SingleChildRenderObjectWidget {
  final ValueChanged<Size>? onChange;

  const _MeasureSize({required this.onChange, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasureSize renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);

  ValueChanged<Size>? onChange;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (_reported == size) return;
    _reported = size;
    final s = size;
    // Post-frame: the listener setStates, which is illegal mid-layout.
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange?.call(s));
  }
}

/// Canvas-wide manipulation of the selected element (Stories/CapCut-style):
/// while something is selected, ONE finger dragged anywhere in the canvas
/// area moves it, a pinch anywhere resizes it, and a two-finger twist rotates
/// it. The user never needs to land a finger on the element itself — which is
/// what makes an element hanging past the canvas edge fully manipulable.
///
/// Mount it AROUND the canvas area (strip + selection overlay), only while a
/// slot is selected and not text-editing. It never steals from what's
/// beneath: the hit test is translucent and everything deeper joins the
/// gesture arena first, so pick-icon taps (tap wins the sweep on release),
/// grid dividers (single-axis drags accept at a tighter slop than scale),
/// the element's own interior and the chrome ring/handles all keep winning.
/// This surface only receives the drags and pinches nothing else claims.
///
/// Unlike the in-canvas recognizers it lives OUTSIDE the FittedBox/zoom
/// transforms, so its deltas arrive in screen px; [screenToTemplate] converts
/// them to template units. It is read lazily at gesture start — post-layout,
/// when the panel's fitted scale is measurable.
class SelectionGestureSurface extends StatefulWidget {
  /// The id gestures report — the slot id, or the LAYER id for a grid.
  final String targetId;
  final double currentScale;
  final double currentRotation;

  /// Screen px → template px factor: 1 / (FittedBox scale × screen zoom).
  final double Function() screenToTemplate;
  final void Function(String slotId, Offset delta)? onDrag;
  final void Function(String slotId, double scale)? onScaleChange;
  final void Function(String slotId, double degrees)? onRotateChange;
  final Widget child;

  const SelectionGestureSurface({
    super.key,
    required this.targetId,
    required this.currentScale,
    required this.currentRotation,
    required this.screenToTemplate,
    this.onDrag,
    this.onScaleChange,
    this.onRotateChange,
    required this.child,
  });

  @override
  State<SelectionGestureSurface> createState() =>
      _SelectionGestureSurfaceState();
}

class _SelectionGestureSurfaceState extends State<SelectionGestureSurface> {
  double _baseScale = 1.0;
  double _baseRotation = 0.0;
  int _pointerCount = 0;
  double _factor = 1.0;

  void _onScaleStart(ScaleStartDetails d) {
    _baseScale = widget.currentScale;
    _baseRotation = widget.currentRotation;
    _pointerCount = d.pointerCount;
    _factor = widget.screenToTemplate();
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount != _pointerCount) {
      // The recognizer re-bases d.scale/d.rotation whenever the finger count
      // changes; re-base our anchors with it.
      _baseScale = widget.currentScale;
      _baseRotation = widget.currentRotation;
      _pointerCount = d.pointerCount;
    }
    if (d.focalPointDelta != Offset.zero) {
      // Offsets are consumed in template units OUTSIDE the rotations (at the
      // element's Positioned), and screen axes are template-aligned — no
      // un-rotation needed, only the scale factor.
      widget.onDrag?.call(widget.targetId, d.focalPointDelta * _factor);
    }
    if (d.pointerCount >= 2 && d.scale != 1.0) {
      widget.onScaleChange?.call(
        widget.targetId,
        (_baseScale * d.scale).clamp(_kMinSlotScale, _kMaxSlotScale),
      );
    }
    if (d.pointerCount >= 2 && d.rotation != 0) {
      widget.onRotateChange?.call(
        widget.targetId,
        _baseRotation + d.rotation * 180 / math.pi,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Translucent: participates everywhere in the body area (even over
      // empty space) WITHOUT blocking deeper hit targets.
      behavior: HitTestBehavior.translucent,
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      child: widget.child,
    );
  }
}
