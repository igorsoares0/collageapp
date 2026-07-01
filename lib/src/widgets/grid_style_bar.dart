import 'package:flutter/material.dart';

/// Bottom bar shown while a grid cell is selected: adjust the whole grid's
/// spacing (gutter) and corner radius. Both are per-grid user overrides stored
/// in SlotContent — the template is never mutated. (Dividers are dragged
/// directly on the canvas.)
class GridStyleBar extends StatelessWidget {
  final double gutter;
  final double cornerRadius;
  final double maxGutter;
  final double maxCorner;
  final ValueChanged<double> onGutter;
  final ValueChanged<double> onCorner;

  const GridStyleBar({
    super.key,
    required this.gutter,
    required this.cornerRadius,
    required this.maxGutter,
    required this.maxCorner,
    required this.onGutter,
    required this.onCorner,
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
                  'Grade',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
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
