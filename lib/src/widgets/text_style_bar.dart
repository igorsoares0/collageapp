import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../rendering/template_canvas.dart' show googleFontsResolver;
import '../theme.dart';
import 'editor_toolbar.dart' show ContextBarShell;

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

const Color _accent = AppColors.coral;

/// Contextual bar shown while a text slot is selected: alignment/bold, a
/// size slider (driving the slot's scale override — same thing the pinch
/// does, but discoverable), plus typeface and color for that slot. Every
/// choice is a per-slot override stored in SlotContent, never a mutation of
/// the template. Duplicate/Delete/Done live in the first row (a separate
/// header would push the bar past the fixed strip height), so this bar
/// builds its own frame instead of [ContextBarShell].
class TextStyleBar extends StatelessWidget {
  final String currentFont;
  final Color currentColor;
  final String currentAlignment;
  final bool isBold;
  final double scale;
  final ValueChanged<String> onFont;
  final ValueChanged<Color> onColor;
  final ValueChanged<String> onAlignment;
  final VoidCallback onBoldToggle;
  final ValueChanged<double> onScale;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onDone;

  const TextStyleBar({
    super.key,
    required this.currentFont,
    required this.currentColor,
    required this.currentAlignment,
    required this.isBold,
    required this.scale,
    required this.onFont,
    required this.onColor,
    required this.onAlignment,
    required this.onBoldToggle,
    required this.onScale,
    required this.onDuplicate,
    required this.onDelete,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    // Keep the active font selectable even if it's outside the curated list.
    final fonts = {currentFont, ...kFontChoices}.toList();
    return Material(
      color: AppColors.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const SizedBox(width: 8),
                _IconToggle(
                  icon: Symbols.format_align_left_rounded,
                  selected: currentAlignment == 'left',
                  onTap: () => onAlignment('left'),
                ),
                _IconToggle(
                  icon: Symbols.format_align_center_rounded,
                  selected: currentAlignment == 'center',
                  onTap: () => onAlignment('center'),
                ),
                _IconToggle(
                  icon: Symbols.format_align_right_rounded,
                  selected: currentAlignment == 'right',
                  onTap: () => onAlignment('right'),
                ),
                _IconToggle(
                  icon: Symbols.format_bold_rounded,
                  selected: isBold,
                  onTap: onBoldToggle,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(
                    Symbols.content_copy_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  tooltip: 'Duplicate',
                  onPressed: onDuplicate,
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  tooltip: 'Delete',
                  onPressed: onDelete,
                ),
                // Label-only (no check icon): this row is the tightest of all
                // the bars on narrow screens.
                TextButton(
                  onPressed: onDone,
                  style: TextButton.styleFrom(foregroundColor: _accent),
                  child: const Text('Done'),
                ),
                const SizedBox(width: 4),
              ],
            ),
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  const Icon(
                    Symbols.format_size_rounded,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  Expanded(
                    child: Slider(
                      value: scale.clamp(0.25, 3),
                      min: 0.25,
                      max: 3,
                      activeColor: _accent,
                      onChanged: onScale,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
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
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
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
              color: selected ? _accent : AppColors.outline,
              width: selected ? 2 : 1,
            ),
          ),
          child: Icon(icon, size: 22, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

/// Contextual bar for the toolbar's Background action: recolor the focused
/// panel's background (a user override of the template's background, included
/// in the export).
class BackgroundColorBar extends StatelessWidget {
  final Color currentColor;
  final ValueChanged<Color> onColor;
  final VoidCallback onDone;

  const BackgroundColorBar({
    super.key,
    required this.currentColor,
    required this.onColor,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return ContextBarShell(
      title: 'Background',
      onDone: onDone,
      child: SizedBox(
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
    // Render each chip's label in its own typeface. Resolved through the
    // cached googleFontsResolver (which also falls back to the plain label
    // on failure): the bar rebuilds on every frame of a drag, and 20
    // uncached GoogleFonts.getFont calls per frame drag it down.
    final label = googleFontsResolver(
      font,
      const TextStyle(color: Colors.white, fontSize: 18),
    );
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
              color: selected ? _accent : AppColors.outline,
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
              color: selected ? _accent : AppColors.surfaceBright,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }
}
