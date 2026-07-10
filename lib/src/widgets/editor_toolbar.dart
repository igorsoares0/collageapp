import 'package:flutter/material.dart';

const Color _surface = Color(0xFF27272A);
const Color _accent = Color(0xFF3B82F6);

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
                    icon: Icons.grid_view,
                    label: 'Layout',
                    onTap: onLayout,
                  ),
                  ToolButton(icon: Icons.title, label: 'Text', onTap: onText),
                  ToolButton(
                    icon: Icons.image_outlined,
                    label: 'Photo',
                    onTap: onPhoto,
                  ),
                  ToolButton(
                    icon: Icons.star_outline,
                    label: 'Sticker',
                    onTap: onSticker,
                  ),
                  ToolButton(
                    icon: Icons.format_color_fill,
                    label: 'Background',
                    onTap: onBackground,
                  ),
                  ToolButton(
                    icon: Icons.splitscreen_outlined,
                    label: 'Panel',
                    onTap: onPanel,
                  ),
                  ToolButton(
                    icon: Icons.layers_outlined,
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
              Icon(icon, size: 24, color: Colors.white),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
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
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const Spacer(),
                  if (onDuplicate != null)
                    IconButton(
                      icon: const Icon(
                        Icons.content_copy,
                        size: 18,
                        color: Colors.white70,
                      ),
                      tooltip: 'Duplicate',
                      onPressed: onDuplicate,
                    ),
                  if (onDelete != null)
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: Colors.white70,
                      ),
                      tooltip: 'Delete',
                      onPressed: onDelete,
                    ),
                  TextButton.icon(
                    onPressed: onDone,
                    icon: const Icon(Icons.check, size: 18),
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
