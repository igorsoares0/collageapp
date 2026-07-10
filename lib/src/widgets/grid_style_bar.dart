import 'package:flutter/material.dart';

import 'editor_toolbar.dart' show ContextBarShell;

/// Contextual bar shown while a grid cell is selected: adjust the whole
/// grid's spacing (gutter) and corner radius. Both are per-grid user
/// overrides stored in SlotContent — the template is never mutated.
/// (Dividers are dragged directly on the canvas.) Delete removes the whole
/// grid, mirroring the canvas ✕ handle.
class GridStyleBar extends StatelessWidget {
  final double gutter;
  final double cornerRadius;
  final double maxGutter;
  final double maxCorner;
  final ValueChanged<double> onGutter;
  final ValueChanged<double> onCorner;
  final VoidCallback onDelete;
  final VoidCallback onDone;

  const GridStyleBar({
    super.key,
    required this.gutter,
    required this.cornerRadius,
    required this.maxGutter,
    required this.maxCorner,
    required this.onGutter,
    required this.onCorner,
    required this.onDelete,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return ContextBarShell(
      title: 'Grid',
      onDelete: onDelete,
      onDone: onDone,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LabeledSlider(
            icon: Icons.space_bar,
            value: gutter.clamp(0, maxGutter),
            max: maxGutter,
            onChanged: onGutter,
          ),
          _LabeledSlider(
            icon: Icons.rounded_corner,
            value: cornerRadius.clamp(0, maxCorner),
            max: maxCorner,
            onChanged: onCorner,
          ),
        ],
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  final IconData icon;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  const _LabeledSlider({
    required this.icon,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(icon, size: 22, color: Colors.white70),
          Expanded(
            child: Slider(
              value: value,
              max: max <= 0 ? 1 : max,
              activeColor: const Color(0xFF3B82F6),
              onChanged: max <= 0 ? null : onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
