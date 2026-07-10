import 'package:flutter/material.dart';

import '../model/asset_record.dart';
import '../model/slot_content.dart';
import '../model/template.dart';

const Color _accent = Color(0xFF3B82F6);
const Color _surface = Color(0xFF27272A);
const Color _muted = Color(0xFF71717A);
const Color _thumbFill = Color(0xFF3F3F46);

/// Bottom sheet listing one panel's layers so the user can manage the stack
/// without leaving the canvas: tap a fillable layer to select it (handy when
/// elements overlap and are hard to tap directly), drag a row by its handle
/// to restack, or hide/show it. Rows carry a small thumbnail (the photo,
/// sticker art, or a type glyph) so layers are recognizable at a glance.
/// Every change is a per-layer override in [SlotContent] — the template is
/// never mutated, and the edits ride into the export.
class LayersSheet extends StatelessWidget {
  final Panel panel;
  final SlotContent content;

  /// Resolves sticker assetIds to their art for the row thumbnails.
  final List<AssetRecord> assetCatalog;

  /// Tapping a selectable layer (image/text/sticker) selects it — image and
  /// text by slot id, stickers by their layer id (they carry no slot). Shapes
  /// are template decoration and are not selectable.
  final void Function(String slotId) onSelect;

  /// Toggles the layer's visibility override.
  final void Function(Layer layer) onToggleHidden;

  /// Receives the panel's complete new stack order (index 0 = bottom) after
  /// a drag-reorder.
  final void Function(List<String> orderedIds) onReorderList;

  /// Ids of layers the user added (and may therefore delete). Template layers
  /// are absent here — they can be hidden but not removed.
  final Set<String> removableLayerIds;

  /// Deletes a user-added layer. Required only for [removableLayerIds].
  final void Function(Layer layer)? onRemove;

  const LayersSheet({
    super.key,
    required this.panel,
    required this.content,
    required this.onSelect,
    required this.onToggleHidden,
    required this.onReorderList,
    this.assetCatalog = const [],
    this.removableLayerIds = const {},
    this.onRemove,
  });

  static String? _slotIdOf(Layer layer) => switch (layer) {
    ImageLayer l => l.slotId,
    TextLayer l => l.slotId,
    StickerLayer l => l.id,
    _ => null,
  };

  static (IconData, String) _describe(Layer layer) => switch (layer) {
    ImageLayer l => (Icons.image_outlined, l.slotId),
    TextLayer l => (Icons.title, l.slotId),
    ShapeLayer _ => (Icons.crop_square, 'Shape'),
    StickerLayer l => (Icons.star_outline, l.assetId),
    GridLayer l => (Icons.grid_view, '${l.cols}×${l.rows} grid'),
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
              child: Row(
                children: [
                  Text(
                    'Layers',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Spacer(),
                  Text(
                    'Drag to reorder · top is front',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: display.length,
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final next = [...display];
                  next.insert(newIndex, next.removeAt(oldIndex));
                  // The list shows front-first; the stack stores bottom-first.
                  onReorderList([for (final l in next.reversed) l.id]);
                },
                itemBuilder: (context, i) {
                  final layer = display[i];
                  return _LayerRow(
                    key: ValueKey(layer.id),
                    index: i,
                    layer: layer,
                    thumb: _LayerThumb(
                      layer: layer,
                      content: content,
                      assetCatalog: assetCatalog,
                    ),
                    hidden: content.layerHidden(layer.id, layer.hidden),
                    selectable: _slotIdOf(layer) != null,
                    onSelect: () {
                      final slotId = _slotIdOf(layer);
                      if (slotId != null) onSelect(slotId);
                    },
                    onToggleHidden: () => onToggleHidden(layer),
                    onRemove:
                        removableLayerIds.contains(layer.id) && onRemove != null
                        ? () => onRemove!(layer)
                        : null,
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
  final int index;
  final Layer layer;
  final Widget thumb;
  final bool hidden;
  final bool selectable;
  final VoidCallback onSelect;
  final VoidCallback onToggleHidden;

  /// Non-null only for user-added layers, which can be deleted.
  final VoidCallback? onRemove;

  const _LayerRow({
    super.key,
    required this.index,
    required this.layer,
    required this.thumb,
    required this.hidden,
    required this.selectable,
    required this.onSelect,
    required this.onToggleHidden,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final (_, label) = LayersSheet._describe(layer);
    final dim = hidden ? 0.4 : 1.0;
    return Material(
      // ReorderableListView requires opaque row material while dragging.
      color: _surface,
      child: InkWell(
        onTap: selectable ? onSelect : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Opacity(opacity: dim, child: thumb),
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
                      fontStyle: selectable
                          ? FontStyle.normal
                          : FontStyle.italic,
                    ),
                  ),
                ),
              ),
              _RowButton(
                icon: hidden ? Icons.visibility_off_outlined : Icons.visibility,
                tooltip: hidden ? 'Show' : 'Hide',
                color: hidden ? _muted : _accent,
                onTap: onToggleHidden,
              ),
              if (onRemove != null)
                _RowButton(
                  icon: Icons.delete_outline,
                  tooltip: 'Delete',
                  color: const Color(0xFFEF4444),
                  onTap: onRemove!,
                ),
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Icon(Icons.drag_indicator, size: 22, color: _muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 36×36 preview of the layer: the slot's photo, the sticker's art, or a
/// glyph for text/grids/shapes.
class _LayerThumb extends StatelessWidget {
  final Layer layer;
  final SlotContent content;
  final List<AssetRecord> assetCatalog;

  const _LayerThumb({
    required this.layer,
    required this.content,
    required this.assetCatalog,
  });

  @override
  Widget build(BuildContext context) {
    Widget inner;
    switch (layer) {
      case ImageLayer l:
        final image = content.imageFor(l.slotId);
        inner = image != null
            ? Image(image: image, fit: BoxFit.cover)
            : const Icon(Icons.image_outlined, size: 20, color: Colors.white70);
      case StickerLayer l:
        ImageProvider? art;
        for (final a in assetCatalog) {
          if (a.id == l.assetId) {
            art = a.image;
            break;
          }
        }
        inner = art != null
            ? Padding(
                padding: const EdgeInsets.all(3),
                child: Image(image: art, fit: BoxFit.contain),
              )
            : const Icon(Icons.star_outline, size: 20, color: Colors.white70);
      case TextLayer l:
        final color = content.colorFor(l.slotId) ?? l.color;
        inner = Center(
          child: Text(
            'T',
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      case GridLayer _:
        inner = const Icon(Icons.grid_view, size: 20, color: Colors.white70);
      default:
        inner = const Icon(Icons.crop_square, size: 20, color: Colors.white70);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 36,
        height: 36,
        child: ColoredBox(color: _thumbFill, child: inner),
      ),
    );
  }
}

class _RowButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onTap;

  const _RowButton({
    required this.icon,
    required this.tooltip,
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
      onPressed: onTap,
    );
  }
}
