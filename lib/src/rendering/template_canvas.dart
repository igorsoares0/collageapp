import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../model/slot_content.dart';
import '../model/template.dart';

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
const double _kChromePad = 64.0;

/// Radius of each corner's resize touch zone (pre-scale template px / scale).
/// Starting a one-finger drag within this distance of a corner resizes;
/// anywhere else moves.
const double _kCornerReach = 56.0;

class TemplateCanvas extends StatelessWidget {
  final Template template;
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
  });

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      child: SizedBox(
        width: template.canvasWidth,
        height: template.canvasHeight,
        // The deselect detector wraps the whole canvas: slot detectors are
        // deeper and win the gesture arena, so this only fires for taps on
        // the background, shapes and stickers. (A detector on the white
        // backdrop wouldn't work — any full-bleed shape layer above it
        // swallows the hit test.)
        child: GestureDetector(
          onTap: onCanvasTap,
          child: Stack(
            children: [
              // Canvas background: the user's override if set, else the
              // template's backgroundColor (defaults to white).
              Positioned.fill(
                child: ColoredBox(
                  key: const ValueKey('canvas-background'),
                  color: content.backgroundColor ?? template.backgroundColor,
                ),
              ),
              for (final layer in template.layers)
                if (!layer.hidden)
                  _LayerWidget(
                    layer: layer,
                    content: content,
                    fontResolver: fontResolver,
                    onSlotTap: onSlotTap,
                    onSlotDrag: onSlotDrag,
                    onSlotScale: onSlotScale,
                    onTextChanged: onTextChanged,
                    selected: layer is ImageLayer &&
                            layer.slotId == selectedSlotId ||
                        layer is TextLayer && layer.slotId == selectedSlotId,
                    editing: layer is TextLayer &&
                        layer.slotId == editingSlotId,
                  ),
            ],
          ),
        ),
      ),
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
  final void Function(String slotId, String value)? onTextChanged;
  final bool selected;
  final bool editing;

  const _LayerWidget({
    required this.layer,
    required this.content,
    required this.fontResolver,
    this.onSlotTap,
    this.onSlotDrag,
    this.onSlotScale,
    this.onTextChanged,
    this.selected = false,
    this.editing = false,
  });

  @override
  Widget build(BuildContext context) {
    return switch (layer) {
      ImageLayer l => _slot(
          l.slotId,
          l.x,
          l.y,
          _rotated(
              l.rotation,
              _chromed(
                  l.slotId,
                  _ImageSlot(
                      layer: l,
                      content: content,
                      interactive: onSlotTap != null)))),
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
                  onTextChanged: onTextChanged)),
          // The TextField owns cursor/selection gestures while editing.
          gestures: !editing),
      ShapeLayer l => _positioned(
          l.x, l.y, Container(width: l.width, height: l.height, color: l.fill)),
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
  /// tap/drag/pinch/resize handler. _SlotGestures sits INSIDE Transform.scale
  /// so its hit area grows with the element (otherwise a scaled-up element
  /// would extend past its own touch region). Translation is applied before
  /// rotation, so dragging a rotated slot still follows the finger.
  Widget _slot(String slotId, double x, double y, Widget child,
      {bool gestures = true}) {
    final offset = content.offsetFor(slotId);
    final scale = content.scaleFor(slotId);
    // When selected the chrome floats a _kChromePad margin around the element
    // (so corner zones overflow it and stay touchable); shift back by the
    // same pad so the element's center stays put on selection.
    final pad = selected ? _kChromePad / scale : 0.0;
    Widget inner = child;
    if (gestures &&
        (onSlotTap != null || onSlotDrag != null || onSlotScale != null)) {
      inner = _SlotGestures(
        slotId: slotId,
        currentScale: scale,
        resizeEnabled: selected,
        onTap: onSlotTap,
        onDrag: onSlotDrag,
        onScaleChange: onSlotScale,
        child: inner,
      );
    }
    // Always wrap in Transform.scale (identity at 1.0), never conditionally:
    // inserting it on the first resize would restructure the tree and remount
    // _SlotGestures mid-gesture — the one-time hitch on the first drag.
    final result = Transform.scale(scale: scale, child: inner);
    return _positioned(x + offset.dx - pad, y + offset.dy - pad, result);
  }

  Widget _positioned(double x, double y, Widget child) =>
      Positioned(left: x, top: y, child: child);

  Widget _rotated(double degrees, Widget child) => Transform.rotate(
        angle: degrees * math.pi / 180,
        alignment: Alignment.topLeft,
        child: child,
      );
}

/// The single gesture surface for a slot: tap, move, pinch AND resize, all
/// in one ScaleGestureRecognizer so nothing competes in the gesture arena
/// (nested resize/move recognizers were the source of dropped touches).
///
/// One finger near the element's edge (the resize band, only when selected)
/// resizes by tracking the finger's distance to the element center in global
/// coordinates — the edge sticks to the finger, size-independent. One finger
/// in the interior moves. Two fingers pinch. d.scale is a ratio relative to
/// the gesture start, re-based whenever the finger count changes.
class _SlotGestures extends StatefulWidget {
  final String slotId;
  final double currentScale;
  final bool resizeEnabled;
  final void Function(String slotId)? onTap;
  final void Function(String slotId, Offset delta)? onDrag;
  final void Function(String slotId, double scale)? onScaleChange;
  final Widget child;

  const _SlotGestures({
    required this.slotId,
    required this.currentScale,
    required this.resizeEnabled,
    required this.onTap,
    required this.onDrag,
    required this.onScaleChange,
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

  /// Element center in global coordinates. This widget sits inside
  /// Transform.scale, so localToGlobal already accounts for the scale; the
  /// center is the scale's fixed point, hence stable while resizing.
  Offset? _centerGlobal() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  /// True when [local] (in this widget's padded coordinate space) is within
  /// reach of one of the element's four corners — the resize zones.
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Opaque, not the default deferToChild: a text slot is mostly empty
      // space (glyphs only at the top) with IgnorePointer chrome, so
      // deferToChild would drop touches on the corners and gaps — which was
      // exactly why grabbing a handle so often did nothing.
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap == null ? null : () => widget.onTap!(widget.slotId),
      onScaleStart: (d) {
        _baseScale = widget.currentScale;
        _startScale = widget.currentScale;
        _pointerCount = d.pointerCount;
        final size = context.size;
        _isResizing = widget.resizeEnabled &&
            d.pointerCount == 1 &&
            size != null &&
            _nearCorner(d.localFocalPoint, size);
        if (_isResizing) {
          final center = _centerGlobal();
          _startDistance =
              center == null ? null : (d.focalPoint - center).distance;
        }
      },
      onScaleUpdate: (d) {
        if (d.pointerCount != _pointerCount) {
          _baseScale = widget.currentScale;
          _pointerCount = d.pointerCount;
          // A second finger turns the gesture into a pinch/move.
          if (d.pointerCount >= 2) _isResizing = false;
        }
        if (_isResizing && d.pointerCount == 1) {
          final center = _centerGlobal();
          if (center != null && _startDistance != null && _startDistance! >= 1) {
            final distance = (d.focalPoint - center).distance;
            widget.onScaleChange?.call(
              widget.slotId,
              (_startScale * distance / _startDistance!)
                  .clamp(_kMinSlotScale, _kMaxSlotScale),
            );
          }
          return;
        }
        if (d.focalPointDelta != Offset.zero) {
          widget.onDrag?.call(widget.slotId, d.focalPointDelta);
        }
        if (d.pointerCount >= 2 && d.scale != 1.0) {
          widget.onScaleChange?.call(
            widget.slotId,
            (_baseScale * d.scale).clamp(_kMinSlotScale, _kMaxSlotScale),
          );
        }
      },
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
            child: LayoutBuilder(builder: (context, constraints) {
              final w = constraints.maxWidth - 2 * pad;
              final h = constraints.maxHeight - 2 * pad;
              return Stack(
                children: [
                  _corner('tl', pad, pad),
                  _corner('tr', pad + w, pad),
                  _corner('bl', pad, pad + h),
                  _corner('br', pad + w, pad + h),
                ],
              );
            }),
          ),
        ),
      ],
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
          border: Border.all(color: const Color(0xFFD4D4D8), width: 1.5 / scale),
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

  /// Whether the canvas is interactive (tap handlers installed) — empty
  /// placeholders then advertise themselves with a photo icon.
  final bool interactive;

  const _ImageSlot({
    required this.layer,
    required this.content,
    this.interactive = false,
  });

  @override
  Widget build(BuildContext context) {
    final image = content.imageFor(layer.slotId);
    return Opacity(
      opacity: layer.opacity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(layer.borderRadius),
        child: image != null
            ? Image(
                image: image,
                width: layer.width,
                height: layer.height,
                fit: BoxFit.cover,
              )
            : Container(
                width: layer.width,
                height: layer.height,
                color: const Color(0xFFE4E4E7),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (interactive)
                      const Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 96,
                        color: Color(0xFF71717A),
                      ),
                    Text(
                      layer.slotId,
                      style: const TextStyle(
                        color: Color(0xFF71717A),
                        fontSize: 40,
                      ),
                    ),
                  ],
                ),
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
  final void Function(String slotId, String value)? onTextChanged;

  const _TextSlot({
    required this.layer,
    required this.content,
    required this.fontResolver,
    this.editing = false,
    this.onTextChanged,
  });

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: layer.fontSize,
      fontWeight: _weight(content.weightFor(layer.slotId) ?? layer.fontWeight),
      color: content.colorFor(layer.slotId) ?? layer.color,
    );
    final style =
        fontResolver(content.fontFor(layer.slotId) ?? layer.fontFamily, base);
    final align = switch (content.alignmentFor(layer.slotId) ?? layer.alignment) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    };
    if (editing) {
      return SizedBox(
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
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

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
