import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

const Color _accent = Color(0xFF3B82F6);

/// Bottom bar shown while a text slot is selected: pick a typeface or color
/// for that slot. The choice is a per-slot override stored in SlotContent,
/// never a mutation of the template.
class TextStyleBar extends StatelessWidget {
  final String currentFont;
  final Color currentColor;
  final String currentAlignment;
  final bool isBold;
  final ValueChanged<String> onFont;
  final ValueChanged<Color> onColor;
  final ValueChanged<String> onAlignment;
  final VoidCallback onBoldToggle;

  const TextStyleBar({
    super.key,
    required this.currentFont,
    required this.currentColor,
    required this.currentAlignment,
    required this.isBold,
    required this.onFont,
    required this.onColor,
    required this.onAlignment,
    required this.onBoldToggle,
  });

  @override
  Widget build(BuildContext context) {
    // Keep the active font selectable even if it's outside the curated list.
    final fonts = {currentFont, ...kFontChoices}.toList();
    return Material(
      color: const Color(0xFF27272A),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const SizedBox(width: 8),
                _IconToggle(
                  icon: Icons.format_align_left,
                  selected: currentAlignment == 'left',
                  onTap: () => onAlignment('left'),
                ),
                _IconToggle(
                  icon: Icons.format_align_center,
                  selected: currentAlignment == 'center',
                  onTap: () => onAlignment('center'),
                ),
                _IconToggle(
                  icon: Icons.format_align_right,
                  selected: currentAlignment == 'right',
                  onTap: () => onAlignment('right'),
                ),
                const Spacer(),
                _IconToggle(
                  icon: Icons.format_bold,
                  selected: isBold,
                  onTap: onBoldToggle,
                ),
                const SizedBox(width: 8),
              ],
            ),
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final font in fonts)
                    _FontChip(
                      font: font,
                      selected: font == currentFont,
                      onTap: () => onFont(font),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final color in kColorChoices)
                    _ColorDot(
                      color: color,
                      selected: color == currentColor,
                      onTap: () => onColor(color),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconToggle extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _IconToggle({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 44,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: selected ? _accent.withValues(alpha: 0.2) : null,
            border: Border.all(
              color: selected ? _accent : const Color(0xFF3F3F46),
              width: selected ? 2 : 1,
            ),
          ),
          child: Icon(icon, size: 22, color: Colors.white),
        ),
      ),
    );
  }
}

/// Bottom bar shown when no slot is selected: recolor the canvas background
/// (a user override of the template's background, included in the export).
class BackgroundColorBar extends StatelessWidget {
  final Color currentColor;
  final ValueChanged<Color> onColor;

  const BackgroundColorBar({
    super.key,
    required this.currentColor,
    required this.onColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF27272A),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Background',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final color in kColorChoices)
                    _ColorDot(
                      color: color,
                      selected: color == currentColor,
                      onTap: () => onColor(color),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FontChip extends StatelessWidget {
  final String font;
  final bool selected;
  final VoidCallback onTap;

  const _FontChip({
    required this.font,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Render each chip's label in its own typeface (same defensive pattern
    // as googleFontsResolver — fall back to the plain label on failure).
    TextStyle label = const TextStyle(color: Colors.white, fontSize: 18);
    try {
      label = GoogleFonts.getFont(font, textStyle: label);
    } catch (_) {}
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? _accent : const Color(0xFF3F3F46),
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(font, style: label, maxLines: 1),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? _accent : const Color(0xFF52525B),
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }
}
