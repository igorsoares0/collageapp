import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderExcludeSemantics;
import 'package:material_symbols_icons/symbols.dart';

import '../theme.dart';

/// Shared Layer chrome primitives: buttons, links, eyebrows, ticks, page
/// edges, the push-screen top bar, sheets and messages. Square-cornered,
/// shadowless; separation is tone and 1px rules.

/// A section label: Instrument Sans 600, +0.16em, UPPERCASE.
class Eyebrow extends StatelessWidget {
  final String text;
  final Color color;
  final double size;
  final TextAlign? textAlign;

  const Eyebrow(
    this.text, {
    super.key,
    this.color = AppColors.ink,
    this.size = 11.5,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    textAlign: textAlign,
    style: AppType.eyebrow(size: size, color: color),
  );
}

/// A two-part serif headline: roman [roman], then [italic] in italic —
/// "Make something *worth keeping.*". [breakLine] puts the italic half on its
/// own line.
class SerifHeadline extends StatelessWidget {
  final String roman;
  final String italic;
  final TextStyle style;
  final bool breakLine;
  final TextAlign? textAlign;

  const SerifHeadline({
    super.key,
    required this.roman,
    required this.italic,
    required this.style,
    this.breakLine = false,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: breakLine ? '$roman\n' : roman),
        TextSpan(
          text: italic,
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
      ],
    ),
    textAlign: textAlign,
    style: style,
  );
}

/// The ink slab: label left, direction icon right. Full width by default,
/// height 54 (52 dense). Disabled = rule fill, inkSoft text. Built on
/// [FilledButton] so it keeps Material semantics/focus.
class PrimaryButton extends StatelessWidget {
  final String label;
  final Widget? labelWidget;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;
  final Color background;

  const PrimaryButton({
    super.key,
    required this.label,
    this.labelWidget,
    this.icon = Symbols.arrow_forward,
    required this.onPressed,
    this.height = 54,
    this.background = AppColors.ink,
  });

  /// The destructive confirm — same slab in rouge.
  const PrimaryButton.destructive({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = 54,
  }) : labelWidget = null,
       icon = null,
       background = AppColors.rouge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: AppColors.onInk,
          disabledBackgroundColor: AppColors.rule,
          disabledForegroundColor: AppColors.inkSoft,
          minimumSize: Size(0, height),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: AppType.label,
        ).copyWith(overlayColor: _pressOverlay(AppColors.paper)),
        child: _ButtonRow(
          label: labelWidget ?? Text(label),
          icon: icon,
          centered: icon == null,
        ),
      ),
    );
  }
}

/// The outlined twin of [PrimaryButton]: 1px ink border, transparent.
class SecondaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;

  const SecondaryButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.height = 54,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          disabledForegroundColor: AppColors.inkSoft,
          side: BorderSide(
            color: onPressed == null ? AppColors.rule : AppColors.ink,
          ),
          minimumSize: Size(0, height),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: AppType.label,
        ).copyWith(overlayColor: _pressOverlay(AppColors.ink)),
        child: _ButtonRow(
          label: Text(label),
          icon: icon,
          centered: icon == null,
        ),
      ),
    );
  }
}

/// The compact ink button ("Export" in the editor bar): 38 high, 13/500.
class CompactButton extends StatelessWidget {
  final String label;
  final Widget? child;
  final VoidCallback? onPressed;

  const CompactButton({
    super.key,
    required this.label,
    this.child,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.ink,
        foregroundColor: AppColors.onInk,
        disabledBackgroundColor: AppColors.rule,
        disabledForegroundColor: AppColors.inkSoft,
        minimumSize: const Size(64, 38),
        fixedSize: const Size.fromHeight(38),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        tapTargetSize: MaterialTapTargetSize.padded,
        textStyle: AppType.labelS,
      ).copyWith(overlayColor: _pressOverlay(AppColors.paper)),
      child: child ?? Text(label),
    );
  }
}

WidgetStateProperty<Color?> _pressOverlay(Color tone) =>
    WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.pressed)
          ? tone.withValues(alpha: .08)
          : null,
    );

class _ButtonRow extends StatelessWidget {
  final Widget label;
  final IconData? icon;
  final bool centered;

  const _ButtonRow({required this.label, this.icon, this.centered = false});

  @override
  Widget build(BuildContext context) {
    if (centered) return Center(child: label);
    return Row(
      children: [
        Expanded(child: label),
        if (icon != null) Icon(icon, size: 20, weight: 300),
      ],
    );
  }
}

/// An underlined text action ("Restore purchases", "Skip — edit text first").
/// The underline sits ~5px under the baseline, drawn as a 1px rule so it can
/// be offset (TextDecoration can't be). Tap target ≥ 44 high.
class TextLink extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double size;
  final Color color;

  const TextLink(
    this.label, {
    super.key,
    required this.onTap,
    this.size = 14,
    this.color = AppColors.ink,
  });

  @override
  Widget build(BuildContext context) {
    final c = onTap == null ? AppColors.stone : color;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpace.minTarget),
          child: Center(
            widthFactor: 1,
            child: Container(
              padding: const EdgeInsets.only(bottom: 3),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c)),
              ),
              child: Text(
                label,
                style: AppType.sans(size, weight: FontWeight.w500, color: c),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Page ticks under a pageable strip: [width]×1 rule each, the active one
/// [width]×3 ink, [gap] apart.
class Ticks extends StatelessWidget {
  final int count;
  final int active;
  final double width;
  final double gap;

  const Ticks({
    super.key,
    required this.count,
    required this.active,
    this.width = 14,
    this.gap = 4,
  });

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 250);
    return SizedBox(
      height: 3,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) SizedBox(width: gap),
            AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              width: width,
              height: i == active ? 3 : 1,
              color: i == active ? AppColors.ink : AppColors.rule,
            ),
          ],
        ],
      ),
    );
  }
}

/// The signature "page edges": behind a multi-slide cover, one (≤3 slides) or
/// two (more) 1px-outlined slivers offset 4 and 8px up-right. None for a
/// single panel. The slivers overflow the child's box; leave 8px of room
/// above and to the right.
class PageEdges extends StatelessWidget {
  final int slides;
  final Widget child;

  const PageEdges({super.key, required this.slides, required this.child});

  @override
  Widget build(BuildContext context) {
    final edges = slides <= 1 ? 0 : (slides <= 3 ? 1 : 2);
    if (edges == 0) return child;
    Widget sliver(double d) => Positioned.fill(
      child: Transform.translate(
        offset: Offset(d, -d),
        child: const DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.paper,
            border: Border.fromBorderSide(
              BorderSide(color: AppColors.ruleStrong),
            ),
          ),
        ),
      ),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (edges >= 2) sliver(8),
        sliver(4),
        Positioned.fill(child: child),
      ],
    );
  }
}

/// The rouge "Pro" mark. Fades out in place when [visible] flips false — the
/// moment a purchase lands — and then leaves the tree. It sits at the end of
/// its row, so nothing reflows around it.
class ProMark extends StatelessWidget {
  final bool visible;
  final double size;
  final bool serif;

  const ProMark({
    super.key,
    this.visible = true,
    this.size = 11.5,
    this.serif = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      child: visible
          ? Text(
              serif ? 'Pro' : 'PRO',
              key: const ValueKey('pro-mark'),
              style: serif
                  ? AppType.serif(size, italic: true, color: AppColors.rouge)
                  : AppType.eyebrow(size: size, color: AppColors.rouge),
            )
          : const SizedBox.shrink(key: ValueKey('no-pro-mark')),
    );
  }
}

/// A 1px hairline, ink or rule.
class Hairline extends StatelessWidget {
  final Color color;
  final double thickness;

  const Hairline({super.key, this.color = AppColors.rule, this.thickness = 1});

  @override
  Widget build(BuildContext context) =>
      Container(height: thickness, color: color);
}

/// Push-screen top bar: back (24, padding 10) left, a centred eyebrow, an
/// optional trailing widget (else an empty 44 so the eyebrow stays centred).
class LayerTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String? eyebrow;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onBack;

  const LayerTopBar({
    super.key,
    this.eyebrow,
    this.leading,
    this.trailing,
    this.onBack,
  });

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.paper,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              const SizedBox(width: 4),
              leading ??
                  BackButton(
                    onPressed: onBack,
                    style: IconButton.styleFrom(foregroundColor: AppColors.ink),
                  ),
              Expanded(
                child: eyebrow == null
                    ? const SizedBox.shrink()
                    : Eyebrow(eyebrow!, textAlign: TextAlign.center),
              ),
              trailing ?? const SizedBox(width: 48),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens a Layer bottom sheet: paper (or paperDeep for confirms), 1px ink top
/// rule, no radius, no handle; padding 22 20 34. [title] in Newsreader on the
/// left, a "CLOSE" eyebrow on the right.
Future<T?> showLayerSheet<T>({
  required BuildContext context,
  String? title,
  Widget? titleWidget,
  required WidgetBuilder builder,
  bool deep = false,
  bool isScrollControlled = false,
  EdgeInsets padding = const EdgeInsets.fromLTRB(20, 22, 20, 34),
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: deep ? AppColors.paperDeep : AppColors.paper,
    barrierColor: AppColors.scrim,
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            curve: kSheetCurve,
            duration: kSheetDuration,
            reverseDuration: Duration(milliseconds: 240),
          ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null || titleWidget != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child:
                        titleWidget ?? Text(title!, style: AppType.title(26)),
                  ),
                  SheetCloseButton(
                    onTap: () => Navigator.of(sheetContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            Flexible(child: builder(sheetContext)),
          ],
        ),
      ),
    ),
  );
}

/// The "CLOSE" eyebrow in a sheet's title row.
class SheetCloseButton extends StatelessWidget {
  final VoidCallback onTap;

  const SheetCloseButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Close',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppSpace.minTarget,
          minWidth: AppSpace.minTarget,
        ),
        child: const Center(
          widthFactor: 1,
          child: Eyebrow('Close', size: 11, color: AppColors.inkSoft),
        ),
      ),
    ),
  );
}

/// A flat ink message strip above the nav, with an "OK" eyebrow in rule.
void showLayerMessage(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      action: SnackBarAction(
        label: 'OK',
        textColor: AppColors.rule,
        onPressed: () {},
      ),
    ),
  );
}

/// "Edited 2 hours ago" style relative time for project rows.
String relativeTime(DateTime when, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final d = n.difference(when);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) {
    return d.inMinutes == 1 ? '1 minute ago' : '${d.inMinutes} minutes ago';
  }
  if (d.inHours < 24 && n.day == when.day) {
    return d.inHours == 1 ? '1 hour ago' : '${d.inHours} hours ago';
  }
  final yesterday = DateTime(n.year, n.month, n.day - 1);
  if (when.year == yesterday.year &&
      when.month == yesterday.month &&
      when.day == yesterday.day) {
    return 'Yesterday';
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final date = '${when.day} ${months[when.month - 1]}';
  return when.year == n.year ? date : '$date ${when.year}';
}

/// Two-digit numeral ("01", "12").
String twoDigits(int n) => n.toString().padLeft(2, '0');

/// A box with a dashed 1px border — empty pages, "+ Slide", empty photo
/// slots. [inset] draws the dashes that far inside the box.
class DashedBox extends StatelessWidget {
  final Color color;
  final double dash;
  final double gap;
  final double inset;
  final Color? fill;
  final Widget? child;

  const DashedBox({
    super.key,
    this.color = AppColors.inkSoft,
    this.dash = 4,
    this.gap = 3,
    this.inset = 0,
    this.fill,
    this.child,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashedRectPainter(
      color: color,
      dash: dash,
      gap: gap,
      inset: inset,
      fill: fill,
    ),
    child: child,
  );
}

class _DashedRectPainter extends CustomPainter {
  final Color color;
  final double dash;
  final double gap;
  final double inset;
  final Color? fill;

  const _DashedRectPainter({
    required this.color,
    required this.dash,
    required this.gap,
    required this.inset,
    required this.fill,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (fill != null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = fill!);
    }
    final r = (Offset.zero & size).deflate(inset + 0.5);
    if (r.width <= 0 || r.height <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    void line(Offset a, Offset b) {
      final total = (b - a).distance;
      final dir = (b - a) / total;
      for (var t = 0.0; t < total; t += dash + gap) {
        final end = (t + dash).clamp(0, total).toDouble();
        canvas.drawLine(a + dir * t, a + dir * end, paint);
      }
    }

    line(r.topLeft, r.topRight);
    line(r.topRight, r.bottomRight);
    line(r.bottomRight, r.bottomLeft);
    line(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) =>
      old.color != color ||
      old.dash != dash ||
      old.gap != gap ||
      old.inset != inset ||
      old.fill != fill;
}

/// A slim ink spinner for loading states.
class LayerSpinner extends StatelessWidget {
  const LayerSpinner({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 22,
    height: 22,
    child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.ink),
  );
}

/// A picture of content, not content: a miniature of the document (the
/// slide strip) paints its subtree normally but keeps it out of the
/// accessibility tree and out of the "onstage" walk that inspectors and
/// widget finders use. Without this, every text, image and slide of the
/// document exists twice on screen as far as tooling (and screen readers)
/// can tell — once on the canvas, once in its thumbnail.
class Miniature extends SingleChildRenderObjectWidget {
  const Miniature({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderExcludeSemantics();

  @override
  SingleChildRenderObjectElement createElement() => _MiniatureElement(this);
}

class _MiniatureElement extends SingleChildRenderObjectElement {
  _MiniatureElement(Miniature super.widget);

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    // Deliberately empty: the subtree is a depiction, never interacted with
    // (it sits under IgnorePointer) and never read.
  }
}
