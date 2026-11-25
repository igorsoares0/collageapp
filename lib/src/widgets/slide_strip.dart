import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../model/asset_record.dart';
import '../model/slot_content.dart';
import '../model/template.dart';
import '../rendering/template_canvas.dart';
import '../theme.dart';
import 'layer_ui.dart';

/// The whole document in miniature: ONE continuous canvas (slides flush, no
/// gaps, anything crossing a cut continues), the active slide outlined 1px
/// ink at a 3px offset, optional italic numerals beneath, and an optional
/// dashed "+ Slide" frame at the end.
///
/// Tap a slide = [onSelect]; long-press = [onLongPress]. Each slide's hit
/// target is keyed `'$keyPrefix$i'`.
class SlideStrip extends StatefulWidget {
  final Document document;
  final SlotContent content;
  final FontResolver fontResolver;
  final List<AssetRecord> assetCatalog;
  final bool showTemplatePhotos;

  /// Rendered height of one slide.
  final double slideHeight;
  final int active;
  final bool numerals;
  final ValueChanged<int> onSelect;
  final ValueChanged<int>? onLongPress;
  final VoidCallback? onAdd;
  final String keyPrefix;
  final EdgeInsets padding;

  const SlideStrip({
    super.key,
    required this.document,
    this.content = const SlotContent(),
    required this.fontResolver,
    this.assetCatalog = const [],
    this.showTemplatePhotos = false,
    required this.slideHeight,
    required this.active,
    this.numerals = false,
    required this.onSelect,
    this.onLongPress,
    this.onAdd,
    this.keyPrefix = 'strip-slide-',
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  State<SlideStrip> createState() => _SlideStripState();
}

class _SlideStripState extends State<SlideStrip> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(SlideStrip old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _revealActive();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the focused slide in view when it changes from elsewhere (the
  /// canvas was panned, a slide was added).
  void _revealActive() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final doc = widget.document;
      final scale = widget.slideHeight / doc.slideHeight;
      final pitch = (doc.slideWidth + doc.gutter) * scale;
      final slideW = doc.slideWidth * scale;
      final left = widget.padding.left + 4 + widget.active * pitch;
      final view = _scroll.position.viewportDimension;
      final offset = _scroll.offset;
      double? target;
      if (left < offset) {
        target = left - 16;
      } else if (left + slideW > offset + view) {
        target = left + slideW - view + 16;
      }
      if (target == null) return;
      final clamped = target.clamp(0.0, _scroll.position.maxScrollExtent);
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(clamped);
      } else {
        _scroll.animateTo(
          clamped,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;
    final h = widget.slideHeight;
    final scale = h / doc.slideHeight;
    final slideW = doc.slideWidth * scale;
    final pitch = (doc.slideWidth + doc.gutter) * scale;
    final docW = doc.contentWidth * scale;
    const pad = 4.0;

    final strip = SizedBox(
      width: docW + 2 * pad,
      height: h + 2 * pad,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: pad,
            top: pad,
            width: docW,
            height: h,
            child: RepaintBoundary(
              child: IgnorePointer(
                child: Miniature(
                  child: CanvasView(
                    document: doc,
                    content: widget.content,
                    fontResolver: widget.fontResolver,
                    assetCatalog: widget.assetCatalog,
                    showTemplatePhotos: widget.showTemplatePhotos,
                  ),
                ),
              ),
            ),
          ),
          for (var i = 0; i < doc.slideCount; i++)
            Positioned(
              left: pad + i * pitch - 3,
              top: pad - 3,
              width: slideW + 6,
              height: h + 6,
              child: Semantics(
                button: true,
                selected: i == widget.active,
                label: 'Slide ${i + 1}',
                child: GestureDetector(
                  key: ValueKey('${widget.keyPrefix}$i'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onSelect(i),
                  onLongPress: widget.onLongPress == null
                      ? null
                      : () => widget.onLongPress!(i),
                  child: i == widget.active
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.fromBorderSide(
                              BorderSide(color: context.colors.ink),
                            ),
                          ),
                        )
                      : const SizedBox.expand(),
                ),
              ),
            ),
        ],
      ),
    );

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        strip,
        if (widget.numerals)
          SizedBox(
            width: docW + 2 * pad,
            height: 22,
            child: Stack(
              children: [
                for (var i = 0; i < doc.slideCount; i++)
                  Positioned(
                    left: pad + i * pitch,
                    width: slideW,
                    top: 4,
                    child: IgnorePointer(
                      child: Text(
                        twoDigits(i + 1),
                        textAlign: TextAlign.center,
                        style: AppType.numeral(
                          12,
                          color: i == widget.active
                              ? context.colors.ink
                              : context.colors.inkMuted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );

    return SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      padding: widget.padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          column,
          if (widget.onAdd != null) ...[
            const SizedBox(width: 10),
            _AddSlide(
              width: slideW.clamp(36.0, 64.0),
              height: h,
              onTap: widget.onAdd!,
            ),
          ],
        ],
      ),
    );
  }
}

class _AddSlide extends StatelessWidget {
  final double width;
  final double height;
  final VoidCallback onTap;

  const _AddSlide({
    required this.width,
    required this.height,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Add slide',
      child: GestureDetector(
        key: const ValueKey('strip-add-slide'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: width,
                height: height,
                child: DashedBox(
                  color: context.colors.inkSoft,
                  child: Center(
                    child: Icon(
                      Symbols.add,
                      size: 18,
                      weight: 200,
                      color: context.colors.inkSoft,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Eyebrow('Slide', size: 11, color: context.colors.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}
