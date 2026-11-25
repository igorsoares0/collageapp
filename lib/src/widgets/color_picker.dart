import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme.dart';
import 'layer_ui.dart';
import 'text_style_bar.dart' show kColorChoices;

/// Colors the user has picked this session, most-recent first. In-memory only
/// (spec: no new storage dependency) — cleared on app restart. Capped so the
/// row stays a single scroll-free strip.
final List<Color> _recentColors = <Color>[];
const int _maxRecent = 8;

void _rememberColor(Color color) {
  final rgb = color.withAlpha(0xFF);
  _recentColors.removeWhere((c) => c.toARGB32() == rgb.toARGB32());
  _recentColors.insert(0, rgb);
  if (_recentColors.length > _maxRecent) {
    _recentColors.removeRange(_maxRecent, _recentColors.length);
  }
}

/// Opens the custom color picker as a modal sheet. [onChanged] fires live as
/// the user drags so the canvas updates behind the sheet; the chosen color is
/// added to the session's recents when the sheet closes.
Future<void> showColorPickerSheet({
  required BuildContext context,
  required Color initialColor,
  required ValueChanged<Color> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.paper,
    barrierColor: context.colors.scrim,
    builder: (_) =>
        _ColorPickerSheet(initial: initialColor, onChanged: onChanged),
  );
}

/// A rainbow-ringed swatch showing the active color. Sits at the end of a
/// bar's curated-color row and opens the full picker when tapped — the one
/// affordance for "any color", distinct from the flat curated dots.
class ColorTrigger extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const ColorTrigger({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Custom colour',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? context.colors.ink : Colors.transparent,
              ),
            ),
            child: Container(
              width: 28,
              height: 28,
              // The ring reads as "spectrum"; the centre shows the colour.
              decoration: const BoxDecoration(
                gradient: SweepGradient(colors: _hueWheel),
              ),
              child: Center(
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: color,
                    border: Border.all(color: context.colors.paper, width: 2),
                  ),
                  child: Icon(
                    Symbols.colorize,
                    size: 9,
                    color: _readableInk(color),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorPickerSheet extends StatefulWidget {
  final Color initial;
  final ValueChanged<Color> onChanged;

  const _ColorPickerSheet({required this.initial, required this.onChanged});

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late HSVColor _hsv;
  late final TextEditingController _hexController;
  final FocusNode _hexFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial.withAlpha(0xFF));
    _hexController = TextEditingController(text: _hexOf(_hsv.toColor()));
  }

  @override
  void dispose() {
    _rememberColor(_hsv.toColor());
    _hexController.dispose();
    _hexFocus.dispose();
    super.dispose();
  }

  void _emit(HSVColor next, {bool syncHex = true}) {
    setState(() => _hsv = next);
    final color = next.toColor();
    if (syncHex && !_hexFocus.hasFocus) {
      _hexController.text = _hexOf(color);
    }
    widget.onChanged(color);
  }

  void _setColor(Color color, {bool syncHex = true}) {
    // HSVColor loses hue/saturation for pure greys; keep the current hue so the
    // SV thumb and hue slider don't jump when the user picks black or white.
    final hsv = HSVColor.fromColor(color);
    final next = hsv.saturation == 0 ? hsv.withHue(_hsv.hue) : hsv;
    _emit(next, syncHex: syncHex);
  }

  void _onHexSubmitted(String raw) {
    final parsed = _parseHex(raw);
    if (parsed != null) {
      _setColor(parsed, syncHex: false);
    }
    // Snap the field back to the canonical form (or revert bad input).
    _hexController.text = _hexOf(_hsv.toColor());
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 22,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Colour', style: AppType.title(26))),
                SheetCloseButton(onTap: () => Navigator.of(context).pop()),
              ],
            ),
            const SizedBox(height: 8),
            // Saturation / value square.
            ClipRect(
              child: AspectRatio(
                aspectRatio: 1.6,
                child: _SVArea(hsv: _hsv, onChanged: _emit),
              ),
            ),
            const SizedBox(height: 16),
            _HueSlider(hue: _hsv.hue, onChanged: (h) => _emit(_hsv.withHue(h))),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color,
                    border: Border.all(color: context.colors.ink),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _hexField()),
              ],
            ),
            if (_recentColors.isNotEmpty) ...[
              const SizedBox(height: 16),
              _swatchRow('Recent', _recentColors),
            ],
            const SizedBox(height: 12),
            _swatchRow('Palette', kColorChoices),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _hexField() {
    return TextField(
      controller: _hexController,
      focusNode: _hexFocus,
      textCapitalization: TextCapitalization.characters,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        fontFeatures: [const FontFeature.tabularFigures()],
        letterSpacing: 1,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
        LengthLimitingTextInputFormatter(7),
      ],
      decoration: InputDecoration(
        prefixText: _hexController.text.startsWith('#') ? null : '#',
        isDense: true,
        filled: true,
        fillColor: context.colors.paperDeep,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: context.colors.rule),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: context.colors.rule),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: context.colors.ink),
        ),
      ),
      onSubmitted: _onHexSubmitted,
      onEditingComplete: () => _onHexSubmitted(_hexController.text),
    );
  }

  Widget _swatchRow(String label, List<Color> colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(label, size: 11, color: context.colors.inkSoft),
        const SizedBox(height: 8),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: colors.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final c = colors[i];
              final isCurrent = c.toARGB32() == _hsv.toColor().toARGB32();
              return GestureDetector(
                onTap: () => _setColor(c),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: c,
                    border: Border.all(
                      color: isCurrent
                          ? context.colors.ink
                          : context.colors.rule,
                      width: isCurrent ? 2 : 1,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The saturation (x) / value (y) selection square for the current hue.
class _SVArea extends StatelessWidget {
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  const _SVArea({required this.hsv, required this.onChanged});

  void _handle(Offset local, Size size) {
    final s = (local.dx / size.width).clamp(0.0, 1.0);
    final v = 1 - (local.dy / size.height).clamp(0.0, 1.0);
    onChanged(hsv.withSaturation(s).withValue(v));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => _handle(d.localPosition, size),
          onPanUpdate: (d) => _handle(d.localPosition, size),
          onTapDown: (d) => _handle(d.localPosition, size),
          child: CustomPaint(painter: _SVPainter(hsv)),
        );
      },
    );
  }
}

class _SVPainter extends CustomPainter {
  final HSVColor hsv;
  const _SVPainter(this.hsv);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hueColor = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();

    // Base hue, then white→hue (left→right), then transparent→black (top→down).
    canvas.drawRect(rect, Paint()..color = hueColor);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Colors.white, Colors.transparent],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );

    // Thumb.
    final thumb = Offset(
      hsv.saturation * size.width,
      (1 - hsv.value) * size.height,
    );
    canvas.drawCircle(
      thumb,
      9,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      thumb,
      9,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_SVPainter old) => old.hsv != hsv;
}

/// Horizontal hue spectrum slider.
class _HueSlider extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;

  const _HueSlider({required this.hue, required this.onChanged});

  void _handle(Offset local, Size size) {
    onChanged((local.dx / size.width).clamp(0.0, 1.0) * 360);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (d) => _handle(d.localPosition, size),
            onPanUpdate: (d) => _handle(d.localPosition, size),
            onTapDown: (d) => _handle(d.localPosition, size),
            child: CustomPaint(painter: _HuePainter(hue)),
          );
        },
      ),
    );
  }
}

class _HuePainter extends CustomPainter {
  final double hue;
  const _HuePainter(this.hue);

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, radius);
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = const LinearGradient(
          colors: _hueWheel,
        ).createShader(Offset.zero & size),
    );

    // Thumb: a vertical capsule the width of the track's height.
    final cx = (hue / 360) * size.width;
    final thumbRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx.clamp(4.0, size.width - 4), size.height / 2),
        width: 8,
        height: size.height + 4,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(thumbRect, Paint()..color = Colors.white);
    canvas.drawRRect(
      thumbRect,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_HuePainter old) => old.hue != hue;
}

/// Full hue sweep for gradients (endpoints repeat red so the wheel closes).
const List<Color> _hueWheel = [
  Color(0xFFFF0000),
  Color(0xFFFFFF00),
  Color(0xFF00FF00),
  Color(0xFF00FFFF),
  Color(0xFF0000FF),
  Color(0xFFFF00FF),
  Color(0xFFFF0000),
];

String _hexOf(Color c) {
  final v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

Color? _parseHex(String raw) {
  var s = raw.trim().replaceAll('#', '');
  if (s.length == 3) {
    // Expand shorthand (#abc → #aabbcc).
    s = s.split('').map((ch) => '$ch$ch').join();
  }
  if (s.length != 6) return null;
  final v = int.tryParse(s, radix: 16);
  if (v == null) return null;
  return Color(0xFF000000 | v);
}

/// Near-black or near-white ink for a legible glyph on [background].
Color _readableInk(Color background) {
  final luminance = background.computeLuminance();
  return luminance > 0.5 ? const Color(0xFF1B1B1F) : Colors.white;
}
