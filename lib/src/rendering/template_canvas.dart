import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../model/asset_record.dart';
import '../model/slot_content.dart';
import '../model/template.dart';
import 'frame_assets.dart';

/// Resolves a template fontFamily name into a TextStyle. The default uses
/// GoogleFonts (runtime download, spec §20); tests inject a plain resolver
/// because google_fonts fails asynchronously without network/assets.
typedef FontResolver = TextStyle Function(String family, TextStyle base);

TextStyle googleFontsResolver(String family, TextStyle base) {
  try {
    return GoogleFonts.getFont(family, textStyle: base);
  } catch (_) {
    return base;
  }
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
/// doesn't move on selection. Must exceed _kCornerReach.
const double _kChromePad = 80.0;

/// Radius of each corner's resize touch zone (pre-scale template px / scale).
/// Starting a one-finger drag within this distance of a corner resizes;
/// anywhere else moves. Generous so the handles are easy to grab even when the
/// whole canvas is scaled down to fit the screen.
const double _kCornerReach = 72.0;

/// How far below the element's bottom edge the rotation handle floats (pre-
/// scale template px / scale). Kept under [_kChromePad] so the handle — and its
/// touch zone — stay inside the chrome's hit region that _SlotGestures covers.
const double _kRotateHandleDrop = 44.0;

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

  /// Tap on an image slot's photo icon — the ONLY way to open the gallery, so
  /// tapping the element itself just selects it (for move/resize). Empty slots
  /// show the icon inline; a filled, selected slot shows a "replace" overlay.
  final void Function(String slotId)? onPickImage;

  /// Remote asset catalog (frames/stickers). A slot's frameAssetId resolves
  /// against this plus the bundled seeds; empty = seeds only.
  final List<AssetRecord> assetCatalog;

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
    this.onPickImage,
    this.editingFieldKey,
    this.assetCatalog = const [],
  });

  @override
  Widget build(BuildContext context) {
    // Stack order and visibility honour the user's per-layer overrides
    // (SlotContent), falling back to the template's own order/hidden flags.
    final byId = {for (final l in panel.layers) l.id: l};
    final orderedIds = content.orderedLayerIds(panel.id, [
      for (final l in panel.layers) l.id,
    ]);
    final visibleLayers = [
      for (final id in orderedIds)
        if (byId[id] case final layer?)
          if (!content.layerHidden(layer.id, layer.hidden)) layer,
    ];
    return FittedBox(
      child: SizedBox(
        width: canvasWidth,
        height: canvasHeight,
        // The deselect detector wraps the whole canvas: slot detectors are
        // deeper and win the gesture arena, so this only fires for taps on
        // the background, shapes and stickers. (A detector on the white
        // backdrop wouldn't work — any full-bleed shape layer above it
        // swallows the hit test.)
        child: GestureDetector(
          onTap: onCanvasTap,
          child: Stack(
            children: [
              // Panel background: the user's per-panel override if set, else
              // the panel's own backgroundColor (defaults to white).
              Positioned.fill(
                child: ColoredBox(
                  key: const ValueKey('canvas-background'),
                  color:
                      content.backgroundFor(panel.id) ?? panel.backgroundColor,
                ),
              ),
              for (final layer in visibleLayers)
                _LayerWidget(
                  layer: layer,
                  content: content,
                  fontResolver: fontResolver,
                  onSlotTap: onSlotTap,
                  onSlotDrag: onSlotDrag,
                  onSlotScale: onSlotScale,
                  onSlotRotate: onSlotRotate,
                  onPickImage: onPickImage,
                  onTextChanged: onTextChanged,
                  assetCatalog: assetCatalog,
                  selected:
                      layer is ImageLayer && layer.slotId == selectedSlotId ||
                      layer is TextLayer && layer.slotId == selectedSlotId,
                  editing: layer is TextLayer && layer.slotId == editingSlotId,
                  fieldKey: layer is TextLayer && layer.slotId == editingSlotId
                      ? editingFieldKey
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Convenience wrapper that renders a template's FIRST panel — used by tests
/// and any single-panel context. Multi-panel screens use [PanelCanvas] per
/// panel directly.
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
  final List<AssetRecord> assetCatalog;

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
    this.assetCatalog = const [],
  });

  @override
  Widget build(BuildContext context) {
    return PanelCanvas(
      panel: template.panels.first,
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
      assetCatalog: assetCatalog,
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
  final void Function(String slotId)? onPickImage;
  final void Function(String slotId, String value)? onTextChanged;
  final List<AssetRecord> assetCatalog;
  final bool selected;
  final bool editing;
  final GlobalKey? fieldKey;

  const _LayerWidget({
    required this.layer,
    required this.content,
    required this.fontResolver,
    this.onSlotTap,
    this.onSlotDrag,
    this.onSlotScale,
    this.onSlotRotate,
    this.onPickImage,
    this.onTextChanged,
    this.assetCatalog = const [],
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
            interactive: onSlotTap != null,
            selected: selected,
            onPick: onPickImage,
          ),
        ),
        templateRotation: l.rotation,
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
          ),
        ),
        // Text carries no template rotation; the TextField owns cursor/
        // selection gestures while editing.
        gestures: !editing,
      ),
      ShapeLayer l => _positioned(
        l.x,
        l.y,
        Container(width: l.width, height: l.height, color: l.fill),
      ),
      StickerLayer l => _positioned(l.x, l.y, _StickerPlaceholder(layer: l)),
    };
  }

  /// Selection chrome (border + handle visuals) wraps the slot content
  /// inside the rotation/scale transforms, so it hugs the element exactly
  /// as drawn. It is visual only — gestures (including resize) live in
  /// _SlotGestures so there is a single recognizer and no arena contention.
  Widget _chromed(String slotId, Widget child) {
    if (!selected) return child;
    return _SelectionChrome(scale: content.scaleFor(slotId), child: child);
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
  }) {
    final offset = content.offsetFor(slotId);
    final scale = content.scaleFor(slotId);
    // When selected the chrome floats a _kChromePad margin around the element
    // (so corner zones overflow it and stay touchable); shift back by the
    // same pad so the element's center stays put on selection.
    final pad = selected ? _kChromePad / scale : 0.0;
    Widget inner = child;
    if (gestures &&
        (onSlotTap != null ||
            onSlotDrag != null ||
            onSlotScale != null ||
            onSlotRotate != null)) {
      inner = _SlotGestures(
        slotId: slotId,
        currentScale: scale,
        currentRotation: content.rotationFor(slotId),
        templateRotation: templateRotation,
        selected: selected,
        onTap: onSlotTap,
        onDrag: onSlotDrag,
        onScaleChange: onSlotScale,
        onRotateChange: onSlotRotate,
        child: inner,
      );
    }
    // Rotations wrap the gesture surface (see the doc above). User rotation
    // pivots around the element center (Canva-style); template rotation keeps
    // its top-left origin (the Konva contract shared with the web editor).
    inner = _userRotated(slotId, _rotated(templateRotation, inner));
    // Always wrap in Transform.scale (identity at 1.0), never conditionally:
    // inserting it on the first resize would restructure the tree and remount
    // _SlotGestures mid-gesture — the one-time hitch on the first drag.
    final result = Transform.scale(scale: scale, child: inner);
    return _positioned(x + offset.dx - pad, y + offset.dy - pad, result);
  }

  Widget _positioned(double x, double y, Widget child) =>
      Positioned(left: x, top: y, child: child);

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
  /// element in place.
  Widget _userRotated(String slotId, Widget child) {
    final degrees = content.rotationFor(slotId);
    if (degrees == 0) return child;
    return Transform.rotate(angle: degrees * math.pi / 180, child: child);
  }
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
  final void Function(String slotId)? onTap;
  final void Function(String slotId, Offset delta)? onDrag;
  final void Function(String slotId, double scale)? onScaleChange;
  final void Function(String slotId, double degrees)? onRotateChange;
  final Widget child;

  const _SlotGestures({
    required this.slotId,
    required this.currentScale,
    required this.currentRotation,
    required this.templateRotation,
    required this.selected,
    required this.onTap,
    required this.onDrag,
    required this.onScaleChange,
    required this.onRotateChange,
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

  /// True when [local] is within reach of one of the element's four corners —
  /// the resize zones. Corners are axis-aligned here: the gesture surface is
  /// inside the rotations, so [local] arrives already un-rotated.
  bool _nearCorner(Offset local, Size size) {
    final pad = _kChromePad / widget.currentScale;
    final reach = _kCornerReach / widget.currentScale;
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

  /// True when [local] is within reach of the rotation handle, which floats
  /// below the element's bottom-center (axis-aligned, as with [_nearCorner]).
  bool _nearRotationHandle(Offset local, Size size) {
    final pad = _kChromePad / widget.currentScale;
    final reach = _kCornerReach / widget.currentScale;
    final w = size.width - 2 * pad;
    final h = size.height - 2 * pad;
    final handle = Offset(
      pad + w / 2,
      pad + h + _kRotateHandleDrop / widget.currentScale,
    );
    return (local - handle).distanceSquared <= reach * reach;
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
    // The rotation handle wins only where it sits (below bottom-center); a
    // corner grab still resizes, everything else moves.
    _isRotating =
        !_isResizing &&
        d.pointerCount == 1 &&
        size != null &&
        _nearRotationHandle(d.localFocalPoint, size);
    if (_isResizing) {
      final center = _centerGlobal();
      _startDistance = center == null ? null : (d.focalPoint - center).distance;
    }
    if (_isRotating) {
      final center = _centerGlobal();
      _startAngle = center == null ? null : (d.focalPoint - center).direction;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount != _pointerCount) {
      _baseScale = widget.currentScale;
      _pointerCount = d.pointerCount;
      // A second finger turns the gesture into a pinch/move (never resize or
      // rotate — those are one-finger handle drags).
      if (d.pointerCount >= 2) {
        _isResizing = false;
        _isRotating = false;
      }
    }
    if (_isResizing && d.pointerCount == 1) {
      final center = _centerGlobal();
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
      final center = _centerGlobal();
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
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Opaque, not the default deferToChild: a text slot is mostly empty
      // space (glyphs only at the top) with IgnorePointer chrome, so
      // deferToChild would drop touches on the corners and gaps — which was
      // exactly why grabbing a handle so often did nothing.
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap == null ? null : () => widget.onTap!(widget.slotId),
      // Wire move/resize/pinch ONLY when selected: an unwired scale recognizer
      // would still win the arena over the canvas pan, dragging an unselected
      // element. With these null, an unselected slot only taps (to select) and
      // drags fall through to the canvas pan/zoom.
      onScaleStart: widget.selected ? _onScaleStart : null,
      onScaleUpdate: widget.selected ? _onScaleUpdate : null,
      child: widget.child,
    );
  }
}

/// Editor-style selection chrome: a thin white frame with four round corner
/// handles, floated a _kChromePad margin around the element so the handles
/// (and their touch zones in _SlotGestures) overflow the element and stay
/// reachable. Purely VISUAL (IgnorePointer) — it shows where to grab; the
/// resize itself is handled by _SlotGestures' corner zones. Sizes are divided
/// by the current scale to stay visually constant.
class _SelectionChrome extends StatelessWidget {
  final double scale;
  final Widget child;

  const _SelectionChrome({required this.scale, required this.child});

  @override
  Widget build(BuildContext context) {
    final pad = _kChromePad / scale;
    final stroke = 4.0 / scale;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Padded element sizes the stack to element + 2*pad, giving the
        // wrapping _SlotGestures a hit region that extends past the element.
        Padding(padding: EdgeInsets.all(pad), child: child),
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
                    _rotateHandle(pad + w / 2, pad + h + drop),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// The rotation handle: a round button with a rotate glyph, centered at
  /// ([cx], [cy]). Purely visual (the chrome is wrapped in IgnorePointer) —
  /// the drag is recognized by _SlotGestures' _nearRotationHandle zone, which
  /// is positioned to match.
  Widget _rotateHandle(double cx, double cy) {
    final dot = 60.0 / scale;
    return Positioned(
      left: cx - dot / 2,
      top: cy - dot / 2,
      width: dot,
      height: dot,
      child: Container(
        key: const ValueKey('handle_rotate'),
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
        child: Icon(
          Icons.rotate_right,
          size: 40 / scale,
          color: const Color(0xFF3F3F46),
        ),
      ),
    );
  }

  /// One round corner handle centered at ([cx], [cy]) in the padded space.
  Widget _corner(String key, double cx, double cy) {
    final dot = 52.0 / scale;
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

  const _ImageSlot({
    required this.layer,
    required this.content,
    this.assetCatalog = const [],
    this.interactive = false,
    this.selected = false,
    this.onPick,
  });

  @override
  Widget build(BuildContext context) {
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
          child: _photo(layer.width, layer.height, pick),
        ),
      );
    }

    // Framed photo: the user's photo lives in the frame's transparent window,
    // the frame paints over the whole box. The frame stretches to the box (its
    // aspect matches the layer's) so its window lands exactly on [win]. It
    // ignores pointer events so a tap still hits the photo/slot beneath it.
    final win = frame.windowIn(layer.width, layer.height);
    return Opacity(
      opacity: layer.opacity,
      child: SizedBox(
        width: layer.width,
        height: layer.height,
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
  /// when unframed, or the frame's window when framed.
  Widget _photo(double w, double h, VoidCallback? pick) {
    final image = content.imageFor(layer.slotId);
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

  const _TextSlot({
    required this.layer,
    required this.content,
    required this.fontResolver,
    this.editing = false,
    this.fieldKey,
    this.onTextChanged,
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
      return SizedBox(
        key: fieldKey,
        width: layer.width,
        child: _InlineTextEditor(
          initial: content.textFor(layer.slotId) ?? '',
          hint: layer.slotId,
          style: style,
          textAlign: align,
          onChanged: (value) => onTextChanged?.call(layer.slotId, value),
        ),
      );
    }
    return SizedBox(
      width: layer.width,
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
    // pixels untouched.
    return Material(
      type: MaterialType.transparency,
      child: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: null,
        style: widget.style,
        textAlign: widget.textAlign,
        decoration: InputDecoration.collapsed(
          hintText: widget.hint,
          hintStyle: widget.style.copyWith(
            color: widget.style.color?.withValues(alpha: 0.4),
          ),
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}

/// Stickers are backend assets (spec §19); until asset storage exists this
/// renders the same labeled placeholder as the editor.
class _StickerPlaceholder extends StatelessWidget {
  final StickerLayer layer;

  const _StickerPlaceholder({required this.layer});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: layer.width,
      height: layer.height,
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
