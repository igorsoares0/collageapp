import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../rendering/template_canvas.dart' show googleFontsResolver;
import '../theme.dart';
import 'color_picker.dart';
import 'editor_toolbar.dart' show ContextBarHeader, ContextBarShell;

/// Typefaces offered for text slots. Mirrors the editor's EDITOR_FONTS so a
/// template's original font is always among the choices (and the current
/// font is prepended at render time if it falls outside this list).
const List<String> kFontChoices = [
  // Sans-serif
  'Inter',
  'Montserrat',
  'Poppins',
  'Roboto',
  'Raleway',
  'Work Sans',
  'Oswald',
  'Bebas Neue',
  'Anton',
  'Archivo Black',
  // Serif
  'Playfair Display',
  'Lora',
  'Merriweather',
  'Cormorant Garamond',
  'DM Serif Display',
  'Abril Fatface',
  // Script / handwriting
  'Dancing Script',
  'Caveat',
  'Pacifico',
  'Lobster',
];

/// Paid-plan-only families (~70% of the catalog). Mirrors PREMIUM_FONTS in the
/// web editor's lib/fonts.ts — a fixed product decision, not per-template. The
/// bar badges these; template_screen enforces the gate (a free user who picks
/// one lands on the paywall). A template already using a premium font still
/// renders for everyone — only picking a new one is gated.
const Set<String> kPremiumFonts = {
  'Raleway',
  'Work Sans',
  'Oswald',
  'Bebas Neue',
  'Anton',
  'Archivo Black',
  'Playfair Display',
  'Cormorant Garamond',
  'DM Serif Display',
  'Abril Fatface',
  'Dancing Script',
  'Caveat',
  'Pacifico',
  'Lobster',
};

/// Curated text-color palette: neutrals first, then vivid accents.
const List<Color> kColorChoices = [
  Color(0xFFFFFFFF),
  Color(0xFF111111),
  Color(0xFFA8A29E),
  Color(0xFFEF4444),
  Color(0xFFF97316),
  Color(0xFFF59E0B),
  Color(0xFF22C55E),
  Color(0xFF14B8A6),
  Color(0xFF3B82F6),
  Color(0xFF6366F1),
  Color(0xFFA855F7),
  Color(0xFFEC4899),
];

/// Contextual bar shown while a text slot is selected: the shared header
/// (eyebrow, Duplicate, Delete, Done), then alignment / bold / size on one
/// row, typeface specimens, and colour chips. Every choice is a per-slot
/// override stored in SlotContent, never a mutation of the template.
class TextStyleBar extends StatelessWidget {
  final String currentFont;
  final Color currentColor;
  final String currentAlignment;
  final bool isBold;
  final double scale;

  /// Whether the user owns pro — drives the rouge "Pro" on paid fonts. The
  /// actual gate lives in [onFont]'s handler (template_screen).
  final bool isPro;
  final ValueChanged<String> onFont;
  final ValueChanged<Color> onColor;
  final ValueChanged<String> onAlignment;
  final VoidCallback onBoldToggle;
  final ValueChanged<double> onScale;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onDone;

  /// The eyebrow's second half — what is selected ("TEXT · TITLE").
  final String? slotLabel;

  const TextStyleBar({
    super.key,
    required this.currentFont,
    required this.currentColor,
    required this.currentAlignment,
    required this.isBold,
    required this.scale,
    required this.isPro,
    required this.onFont,
    required this.onColor,
    required this.onAlignment,
    required this.onBoldToggle,
    required this.onScale,
    required this.onDuplicate,
    required this.onDelete,
    required this.onDone,
    this.slotLabel,
  });

  @override
  Widget build(BuildContext context) {
    // Keep the active font selectable even if it's outside the curated list.
    final fonts = {currentFont, ...kFontChoices}.toList();
    return Material(
      color: context.colors.paper,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ContextBarHeader(
            title: slotLabel == null ? 'Text' : 'Text · $slotLabel',
            onDuplicate: onDuplicate,
            onDelete: onDelete,
            onDone: onDone,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: SizedBox(
              height: 40,
              child: Row(
                children: [
                  _AlignSegment(
                    current: currentAlignment,
                    onAlignment: onAlignment,
                  ),
                  const SizedBox(width: 12),
                  _BoldToggle(selected: isBold, onTap: onBoldToggle),
                  const SizedBox(width: 14),
                  Text('A', style: AppType.serif(13)),
                  Expanded(
                    child: Slider(
                      value: scale.clamp(0.25, 3),
                      min: 0.25,
                      max: 3,
                      activeColor: context.colors.ink,
                      inactiveColor: context.colors.ink,
                      onChanged: onScale,
                    ),
                  ),
                  Text('A', style: AppType.serif(22)),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                for (final font in fonts)
                  _FontSpecimen(
                    font: font,
                    selected: font == currentFont,
                    locked: kPremiumFonts.contains(font) && !isPro,
                    onTap: () => onFont(font),
                  ),
              ],
            ),
          ),
          _ColorRow(currentColor: currentColor, onColor: onColor),
        ],
      ),
    );
  }
}

/// Square colour chips followed by the custom-picker trigger. Shared by the
/// text and background bars so both offer the same "any colour" affordance.
class _ColorRow extends StatelessWidget {
  final Color currentColor;
  final ValueChanged<Color> onColor;

  const _ColorRow({required this.currentColor, required this.onColor});

  @override
  Widget build(BuildContext context) {
    // The trigger is "selected" whenever the active colour is off the palette
    // — it's the only swatch representing that colour.
    final onPalette = kColorChoices.any(
      (c) => c.toARGB32() == currentColor.toARGB32(),
    );
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final color in kColorChoices)
            _ColorChip(
              color: color,
              selected: color.toARGB32() == currentColor.toARGB32(),
              onTap: () => onColor(color),
            ),
          const SizedBox(width: 4),
          ColorTrigger(
            color: currentColor,
            selected: !onPalette,
            onTap: () => showColorPickerSheet(
              context: context,
              initialColor: currentColor,
              onChanged: onColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Left / centre / right in one 1px-ink box; the selected cell is ink-filled.
class _AlignSegment extends StatelessWidget {
  final String current;
  final ValueChanged<String> onAlignment;

  const _AlignSegment({required this.current, required this.onAlignment});

  @override
  Widget build(BuildContext context) {
    Widget cell(String value, IconData icon, String label) {
      final selected = current == value;
      return Tooltip(
        message: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onAlignment(value),
          child: Container(
            width: 40,
            height: 38,
            color: selected ? context.colors.ink : Colors.transparent,
            child: Icon(
              icon,
              size: 20,
              weight: selected ? 300 : 200,
              color: selected ? context.colors.onInk : context.colors.ink,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(border: Border.all(color: context.colors.ink)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          cell('left', Symbols.format_align_left, 'Align left'),
          Container(width: 1, height: 38, color: context.colors.ink),
          cell('center', Symbols.format_align_center, 'Align centre'),
          Container(width: 1, height: 38, color: context.colors.ink),
          cell('right', Symbols.format_align_right, 'Align right'),
        ],
      ),
    );
  }
}

/// A 40×40 square with a Newsreader "B"; ink-filled when bold is on.
class _BoldToggle extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;

  const _BoldToggle({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Bold',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? context.colors.ink : Colors.transparent,
            border: Border.all(color: context.colors.ink),
          ),
          child: Text(
            'B',
            style: AppType.serif(
              20,
              color: selected ? context.colors.onInk : context.colors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// Contextual bar for the toolbar's Colour action: recolour the focused
/// slide's background (a user override of the template's background,
/// included in the export).
class BackgroundColorBar extends StatelessWidget {
  final Color currentColor;
  final ValueChanged<Color> onColor;
  final VoidCallback onDone;
  final String? slideLabel;

  const BackgroundColorBar({
    super.key,
    required this.currentColor,
    required this.onColor,
    required this.onDone,
    this.slideLabel,
  });

  @override
  Widget build(BuildContext context) {
    return ContextBarShell(
      title: slideLabel == null ? 'Background' : 'Background · $slideLabel',
      onDone: onDone,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _ColorRow(currentColor: currentColor, onColor: onColor),
      ),
    );
  }
}

/// A typeface specimen: "Aa" in that face over its name; the selected one
/// carries a 2px ink underline; paid faces show a rouge "Pro".
class _FontSpecimen extends StatelessWidget {
  final String font;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  const _FontSpecimen({
    required this.font,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Resolved through the cached googleFontsResolver (which also falls back
    // to the plain style on failure): the bar rebuilds on every frame of a
    // drag, and 20 uncached GoogleFonts.getFont calls per frame drag it down.
    final specimen = googleFontsResolver(
      font,
      TextStyle(color: context.colors.ink, fontSize: 24, height: 1.1),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: locked ? '$font, Pro' : font,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 66,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? context.colors.ink : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Column(
            children: [
              Text('Aa', style: specimen, maxLines: 1),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: font.split(' ').first),
                    if (locked)
                      TextSpan(
                        text: ' Pro',
                        style: TextStyle(color: context.colors.rouge),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: AppType.sans(11, color: context.colors.inkSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 28×28 square colour chip; the selected one gets a 1px ink outline at a
/// 2px offset.
class _ColorChip extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorChip({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: context.colors.rule),
            ),
          ),
        ),
      ),
    );
  }
}
