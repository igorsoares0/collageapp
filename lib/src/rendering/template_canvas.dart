import 'dart:math' as math;

import 'package:flutter/gestures.dart';
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
/// the canvas — shared by the pinch gesture and the corner handles.
const double _kMinSlotScale = 0.3;
const double _kMaxSlotScale = 4.0;

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
              // Canvas background, same as the editor's white stage.
              const Positioned.fill(child: ColoredBox(color: Colors.white)),
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

  /// Selection chrome (border + corner handles) wraps the slot content
  /// inside the rotation/scale transforms, so it hugs the element exactly
  /// as drawn.
  Widget _chromed(String slotId, Widget child) {
    if (!selected) return child;
    final scale = content.scaleFor(slotId);
    return _SelectionChrome(
      scale: scale,
      onResize: onSlotScale == null
          ? null
          : (factor) => onSlotScale!(
              slotId,
              (scale * factor).clamp(_kMinSlotScale, _kMaxSlotScale)),
      child: child,
    );
  }

  /// Slot layers carry the user's position/size adjustments and, when
  /// enabled, the tap/drag/pinch handlers. Translation is applied before
  /// rotation, so dragging a rotated slot still follows the finger; the
  /// pinch scale is anchored at the slot's center.
  Widget _slot(String slotId, double x, double y, Widget child,
      {bool gestures = true}) {
    final offset = content.offsetFor(slotId);
    final scale = content.scaleFor(slotId);
    Widget result = scale == 1.0
        ? child
        : Transform.scale(scale: scale, child: child);
    if (gestures &&
        (onSlotTap != null || onSlotDrag != null || onSlotScale != null)) {
      result = _SlotGestures(
        slotId: slotId,
        currentScale: scale,
        onTap: onSlotTap,
        onDrag: onSlotDrag,
        onScaleChange: onSlotScale,
        child: result,
      );
    }
    return _positioned(x + offset.dx, y + offset.dy, result);
  }

  Widget _positioned(double x, double y, Widget child) =>
      Positioned(left: x, top: y, child: child);

  Widget _rotated(double degrees, Widget child) => Transform.rotate(
        angle: degrees * math.pi / 180,
        alignment: Alignment.topLeft,
        child: child,
      );
}

/// One GestureDetector for both gestures: pan and pinch can't be separate
/// recognizers (they'd fight in the arena), so onScaleUpdate handles both —
/// one finger moves the focal point, two fingers also change [d.scale].
/// d.scale is a ratio relative to the gesture start, so the slot's scale at
/// gesture start is captured as the base; it is re-captured whenever the
/// finger count changes, because the recognizer re-bases its ratio then.
class _SlotGestures extends StatefulWidget {
  final String slotId;
  final double currentScale;
  final void Function(String slotId)? onTap;
  final void Function(String slotId, Offset delta)? onDrag;
  final void Function(String slotId, double scale)? onScaleChange;
  final Widget child;

  const _SlotGestures({
    required this.slotId,
    required this.currentScale,
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap:
          widget.onTap == null ? null : () => widget.onTap!(widget.slotId),
      onScaleStart: (d) {
        _baseScale = widget.currentScale;
        _pointerCount = d.pointerCount;
      },
      onScaleUpdate: (d) {
        if (d.pointerCount != _pointerCount) {
          _baseScale = widget.currentScale;
          _pointerCount = d.pointerCount;
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

/// Claims the pointer as soon as it lands, instead of waiting out the touch
/// slop. Resize handles need this: a regular pan recognizer ties with the
/// slot's own scale recognizer in the gesture arena and loses the resize.
class _EagerPanGestureRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

/// Editor-style selection chrome: accent border plus four corner handles.
/// It sits inside the slot's transform chain (follows rotation/scale), so
/// its sizes are divided by the current scale to stay visually constant.
/// Dragging a handle reports a resize [factor] per update: the projection
/// of the drag onto the corner's outward diagonal, relative to the slot's
/// half-diagonal.
class _SelectionChrome extends StatelessWidget {
  static const _accent = Color(0xFF3B82F6);

  final double scale;
  final void Function(double factor)? onResize;
  final Widget child;

  const _SelectionChrome({
    required this.scale,
    required this.onResize,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final stroke = 5.0 / scale;
    final handleSize = 56.0 / scale;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: _accent, width: stroke),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: LayoutBuilder(builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final halfDiagonal = math.sqrt(w * w + h * h) / 2;

            Widget handle(String corner, double sx, double sy) {
              // The visual square sits centered on the corner; the hit box
              // is twice as big and biased inward, because hits outside the
              // Stack bounds are clipped away.
              return Positioned(
                left: sx < 0 ? -handleSize : null,
                right: sx > 0 ? -handleSize : null,
                top: sy < 0 ? -handleSize : null,
                bottom: sy > 0 ? -handleSize : null,
                child: RawGestureDetector(
                  behavior: HitTestBehavior.opaque,
                  gestures: {
                    _EagerPanGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                            _EagerPanGestureRecognizer>(
                      _EagerPanGestureRecognizer.new,
                      (recognizer) => recognizer.onUpdate = onResize == null
                          ? null
                          : (d) {
                              final projection =
                                  (d.delta.dx * sx + d.delta.dy * sy) /
                                      math.sqrt2;
                              onResize!((halfDiagonal + projection) /
                                  halfDiagonal);
                            },
                    ),
                  },
                  child: SizedBox(
                    width: handleSize * 2,
                    height: handleSize * 2,
                    child: Center(
                      child: Container(
                        key: ValueKey('handle_$corner'),
                        width: handleSize,
                        height: handleSize,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: _accent, width: stroke),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }

            return Stack(
              clipBehavior: Clip.none,
              children: [
                handle('tl', -1, -1),
                handle('tr', 1, -1),
                handle('bl', -1, 1),
                handle('br', 1, 1),
              ],
            );
          }),
        ),
      ],
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
      fontWeight: _weight(layer.fontWeight),
      color: layer.color,
    );
    final style = fontResolver(layer.fontFamily, base);
    final align = switch (layer.alignment) {
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
