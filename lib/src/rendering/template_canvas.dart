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
class TemplateCanvas extends StatelessWidget {
  final Template template;
  final SlotContent content;
  final FontResolver fontResolver;

  /// When set, image slots become tappable (FittedBox/Transform map the hit
  /// test back to template space) and empty placeholders show a photo icon.
  final void Function(String slotId)? onImageSlotTap;

  /// When set, slot layers (image/text — the user's content) become
  /// draggable. [delta] arrives in template space: gesture events are
  /// transformed into the listener's local coordinates, so the FittedBox
  /// scale is already accounted for. Accumulate it into
  /// SlotContent.offsets. Shape/sticker layers are template design and
  /// stay fixed.
  final void Function(String slotId, Offset delta)? onSlotDrag;

  const TemplateCanvas({
    super.key,
    required this.template,
    this.content = const SlotContent(),
    this.fontResolver = googleFontsResolver,
    this.onImageSlotTap,
    this.onSlotDrag,
  });

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      child: SizedBox(
        width: template.canvasWidth,
        height: template.canvasHeight,
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
                  onImageSlotTap: onImageSlotTap,
                  onSlotDrag: onSlotDrag,
                ),
          ],
        ),
      ),
    );
  }
}

class _LayerWidget extends StatelessWidget {
  final Layer layer;
  final SlotContent content;
  final FontResolver fontResolver;
  final void Function(String slotId)? onImageSlotTap;
  final void Function(String slotId, Offset delta)? onSlotDrag;

  const _LayerWidget({
    required this.layer,
    required this.content,
    required this.fontResolver,
    this.onImageSlotTap,
    this.onSlotDrag,
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
              _ImageSlot(
                  layer: l, content: content, onTap: onImageSlotTap))),
      TextLayer l => _slot(
          l.slotId,
          l.x,
          l.y,
          _TextSlot(layer: l, content: content, fontResolver: fontResolver)),
      ShapeLayer l => _positioned(
          l.x, l.y, Container(width: l.width, height: l.height, color: l.fill)),
      StickerLayer l => _positioned(l.x, l.y, _StickerPlaceholder(layer: l)),
    };
  }

  /// Slot layers carry the user's position adjustment and, when enabled,
  /// a pan handler. Translation is applied before rotation, so dragging a
  /// rotated slot still follows the finger.
  Widget _slot(String slotId, double x, double y, Widget child) {
    final offset = content.offsetFor(slotId);
    final dragged = onSlotDrag == null
        ? child
        : GestureDetector(
            // d.delta is a localDelta: already in template space, with the
            // FittedBox scale factored out by the event transform.
            onPanUpdate: (d) => onSlotDrag!(slotId, d.delta),
            child: child,
          );
    return _positioned(x + offset.dx, y + offset.dy, dragged);
  }

  Widget _positioned(double x, double y, Widget child) =>
      Positioned(left: x, top: y, child: child);

  Widget _rotated(double degrees, Widget child) => Transform.rotate(
        angle: degrees * math.pi / 180,
        alignment: Alignment.topLeft,
        child: child,
      );
}

class _ImageSlot extends StatelessWidget {
  final ImageLayer layer;
  final SlotContent content;
  final void Function(String slotId)? onTap;

  const _ImageSlot({required this.layer, required this.content, this.onTap});

  @override
  Widget build(BuildContext context) {
    final image = content.imageFor(layer.slotId);
    final slot = Opacity(
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
                    if (onTap != null)
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
    if (onTap == null) return slot;
    return GestureDetector(onTap: () => onTap!(layer.slotId), child: slot);
  }
}

class _TextSlot extends StatelessWidget {
  final TextLayer layer;
  final SlotContent content;
  final FontResolver fontResolver;

  const _TextSlot({
    required this.layer,
    required this.content,
    required this.fontResolver,
  });

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: layer.fontSize,
      fontWeight: _weight(layer.fontWeight),
      color: layer.color,
    );
    final style = fontResolver(layer.fontFamily, base);
    return SizedBox(
      width: layer.width,
      child: Text(
        content.textFor(layer.slotId) ?? layer.slotId,
        style: style,
        textAlign: switch (layer.alignment) {
          'center' => TextAlign.center,
          'right' => TextAlign.right,
          _ => TextAlign.left,
        },
      ),
    );
  }

  FontWeight _weight(int value) =>
      FontWeight.values[(value / 100).round().clamp(1, 9) - 1];
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
