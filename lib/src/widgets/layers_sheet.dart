import 'package:flutter/material.dart';

import '../model/slot_content.dart';
import '../model/template.dart';

const Color _accent = Color(0xFF3B82F6);
const Color _surface = Color(0xFF27272A);
const Color _muted = Color(0xFF71717A);

/// Bottom sheet listing one panel's layers so the user can manage the stack
/// without leaving the canvas: tap a fillable layer to select it (handy when
/// elements overlap and are hard to tap directly), reorder its z-position, or
/// hide/show it. Every change is a per-layer override in [SlotContent] — the
/// template is never mutated, and the edits ride into the export.
class LayersSheet extends StatelessWidget {
  final Panel panel;
  final SlotContent content;

  /// Tapping a fillable layer (image/text) selects its slot. Decorative
  /// layers (shapes/stickers) have no slot and are not selectable.
  final void Function(String slotId) onSelect;

  /// Toggles the layer's visibility override.
  final void Function(Layer layer) onToggleHidden;

  /// Moves the layer one step toward the front ([toFront] true) or back.
  final void Function(Layer layer, {required bool toFront}) onReorder;

  const LayersSheet({
    super.key,
    required this.panel,
    required this.content,
    required this.onSelect,
    required this.onToggleHidden,
    required this.onReorder,
  });

  static String? _slotIdOf(Layer layer) => switch (layer) {
    ImageLayer l => l.slotId,
    TextLayer l => l.slotId,
    _ => null,
  };

  static (IconData, String) _describe(Layer layer) => switch (layer) {
    ImageLayer l => (Icons.image_outlined, l.slotId),
    TextLayer l => (Icons.title, l.slotId),
    ShapeLayer _ => (Icons.crop_square, 'Shape'),
    StickerLayer l => (Icons.star_outline, l.assetId),
  };

  @override
  Widget build(BuildContext context) {
    // Stack order (index 0 = bottom); display front-to-back so the topmost
    // row is the frontmost element, matching the editor's layer panel.
    final ordered = content.orderedLayerIds(panel.id, [
      for (final l in panel.layers) l.id,
    ]);
    final byId = {for (final l in panel.layers) l.id: l};
    final display = [
      for (final id in ordered.reversed)
        if (byId[id] case final layer?) layer,
    ];

    return Material(
      color: _surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Layers',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: display.length,
                itemBuilder: (context, i) {
                  final layer = display[i];
                  // i==0 is the frontmost row: can't move further forward.
                  return _LayerRow(
                    layer: layer,
                    hidden: content.layerHidden(layer.id, layer.hidden),
                    selectable: _slotIdOf(layer) != null,
                    canMoveFront: i > 0,
                    canMoveBack: i < display.length - 1,
                    onSelect: () {
                      final slotId = _slotIdOf(layer);
                      if (slotId != null) onSelect(slotId);
                    },
                    onToggleHidden: () => onToggleHidden(layer),
                    onMoveFront: () => onReorder(layer, toFront: true),
                    onMoveBack: () => onReorder(layer, toFront: false),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LayerRow extends StatelessWidget {
  final Layer layer;
  final bool hidden;
  final bool selectable;
  final bool canMoveFront;
  final bool canMoveBack;
  final VoidCallback onSelect;
  final VoidCallback onToggleHidden;
  final VoidCallback onMoveFront;
  final VoidCallback onMoveBack;

  const _LayerRow({
    required this.layer,
    required this.hidden,
    required this.selectable,
    required this.canMoveFront,
    required this.canMoveBack,
    required this.onSelect,
    required this.onToggleHidden,
    required this.onMoveFront,
    required this.onMoveBack,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, label) = LayersSheet._describe(layer);
    final dim = hidden ? 0.4 : 1.0;
    return InkWell(
      onTap: selectable ? onSelect : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Opacity(
              opacity: dim,
              child: Icon(icon, size: 22, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Opacity(
                opacity: dim,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    // Hint that decorative layers aren't tappable to select.
                    fontStyle: selectable ? FontStyle.normal : FontStyle.italic,
                  ),
                ),
              ),
            ),
            _RowButton(
              icon: Icons.keyboard_arrow_up,
              tooltip: 'Bring forward',
              enabled: canMoveFront,
              onTap: onMoveFront,
            ),
            _RowButton(
              icon: Icons.keyboard_arrow_down,
              tooltip: 'Send backward',
              enabled: canMoveBack,
              onTap: onMoveBack,
            ),
            _RowButton(
              icon: hidden ? Icons.visibility_off_outlined : Icons.visibility,
              tooltip: hidden ? 'Show' : 'Hide',
              color: hidden ? _muted : _accent,
              onTap: onToggleHidden,
            ),
          ],
        ),
      ),
    );
  }
}

class _RowButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final Color? color;
  final VoidCallback onTap;

  const _RowButton({
    required this.icon,
    required this.tooltip,
    this.enabled = true,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 22),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      color: color ?? Colors.white,
      disabledColor: const Color(0xFF3F3F46),
      onPressed: enabled ? onTap : null,
    );
  }
}
