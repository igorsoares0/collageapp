import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme.dart';

const Color _surface = AppColors.surface;
const Color _accent = AppColors.accent;

/// The persistent bottom toolbar — the editor's home state, shown whenever
/// nothing is selected. Every primary creative action lives here as a big
/// labeled button; selecting an element swaps this bar for that element's
/// contextual bar (see [ContextBarShell]).
class EditorToolbar extends StatelessWidget {
  final VoidCallback onLayout;
  final VoidCallback onText;
  final VoidCallback onPhoto;
  final VoidCallback onSticker;
  final VoidCallback onBackground;
  final VoidCallback onPanel;
  final VoidCallback onLayers;

  const EditorToolbar({
    super.key,
    required this.onLayout,
    required this.onText,
    required this.onPhoto,
    required this.onSticker,
    required this.onBackground,
    required this.onPanel,
    required this.onLayers,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 76,
          // Centered when everything fits, scrollable on narrow screens.
          child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  ToolButton(
                    icon: Symbols.grid_view_rounded,
                    label: 'Layout',
                    onTap: onLayout,
                  ),
                  ToolButton(
                    icon: Symbols.text_fields_rounded,
                    label: 'Text',
                    onTap: onText,
                  ),
                  ToolButton(
                    icon: Symbols.image_rounded,
                    label: 'Photo',
                    onTap: onPhoto,
                  ),
                  ToolButton(
                    icon: Symbols.sticker_rounded,
                    label: 'Sticker',
                    onTap: onSticker,
                  ),
                  ToolButton(
                    icon: Symbols.format_color_fill_rounded,
                    label: 'Background',
                    onTap: onBackground,
                  ),
                  ToolButton(
                    icon: Symbols.auto_awesome_mosaic_rounded,
                    label: 'Panel',
                    onTap: onPanel,
                  ),
                  ToolButton(
                    icon: Symbols.layers_rounded,
                    label: 'Layers',
                    onTap: onLayers,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A big labeled icon button — the toolbar's building block, also reused for
/// actions inside contextual bars (e.g. the photo bar's Replace).
class ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const ToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24, color: AppColors.textPrimary),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Frame shared by the contextual bars: a header naming what is selected,
/// optional Duplicate/Delete, and an explicit Done that returns to the
/// toolbar — so the bottom bar never changes silently. [child] holds the
/// bar's controls.
class ContextBarShell extends StatelessWidget {
  final String title;
  final VoidCallback onDone;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final Widget? child;

  const ContextBarShell({
    super.key,
    required this.title,
    required this.onDone,
    this.onDuplicate,
    this.onDelete,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
              child: Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const Spacer(),
                  if (onDuplicate != null)
                    IconButton(
                      icon: const Icon(
                        Symbols.content_copy_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      tooltip: 'Duplicate',
                      onPressed: onDuplicate,
                    ),
                  if (onDelete != null)
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                      tooltip: 'Delete',
                      onPressed: onDelete,
                    ),
                  TextButton.icon(
                    onPressed: onDone,
                    icon: const Icon(Symbols.check_rounded, size: 18),
                    label: const Text('Done'),
                    style: TextButton.styleFrom(foregroundColor: _accent),
                  ),
                ],
              ),
            ),
            if (child != null) child!,
          ],
        ),
      ),
    );
  }
}
