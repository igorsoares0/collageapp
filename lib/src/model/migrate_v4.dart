import 'dart:ui';

import 'template.dart';
import 'slot_content.dart';

/// v3 (panels) -> v4 (continuous canvas) migration. See docs/model-b-migration.md.
///
/// STATUS: pure function. Nothing calls this yet — wiring it into
/// ProjectStore.load is a later step, and it is the only step in the whole
/// migration that can damage a saved project, so it lands on its own.
///
/// The saved document is not just the template: it is the template PLUS the
/// user's SlotContent overlay (added panels, added layers, per-panel
/// backgrounds, reorder overrides). All of that has to fold into one continuous
/// coordinate space, which is why this takes both and returns both.

/// A migrated document and the overlay that survives it.
class MigrationResult {
  final Document document;

  /// [content] with every PANEL-scoped override folded into [document] and
  /// removed. Slot-scoped overrides (texts, images, offsets, scales, rotations,
  /// colors, fonts, hidden flags, grid tweaks…) are keyed by slotId/layerId and
  /// pass through untouched — that is why a migrated project keeps the user's
  /// edits.
  final SlotContent content;

  const MigrationResult(this.document, this.content);
}

/// Translates [layer] horizontally by [dx].
///
/// Goes through the layer's own JSON rather than a hand-written copy per
/// subclass: toJson/fromJson are exact inverses, so every field survives —
/// including the ones easy to forget (frameAssetId, imageAssetId, a grid's
/// cells and fraction tracks) and any field added later. A hand-rolled copy
/// silently drops whatever the author forgets.
Layer translateLayerX(Layer layer, double dx) {
  final json = layer.toJson();
  json['x'] = (json['x'] as num).toDouble() + dx;
  final moved = Layer.fromJson(json);
  if (moved == null) {
    // Unreachable: we just serialized a layer this same code can parse.
    throw StateError('layer ${layer.id} did not survive its own JSON');
  }
  return moved;
}

/// Folds a panel-based document into the continuous canvas.
///
/// Panels in the v3 model are contiguous (a carousel with no space between
/// slides), so the migrated gutter is 0 and slide `i` starts at
/// `i * canvasWidth`.
MigrationResult migrateToV4(Template template, SlotContent content) {
  final slideWidth = template.canvasWidth;
  final slideHeight = template.canvasHeight;

  // The document the user actually sees: the template's panels followed by any
  // the user appended while editing.
  final panels = [...template.panels, ...content.addedPanels];

  final layers = <Layer>[];
  final backgrounds = <Color>[];

  for (final (i, panel) in panels.indexed) {
    final offsetX = i * slideWidth;

    // Effective stack for this panel: the template's own layers plus the
    // user's additions, in the order the user last left them.
    final stack = [...panel.layers, ...content.addedLayersFor(panel.id)];
    final byId = {for (final l in stack) l.id: l};
    final ordered = content.orderedLayerIds(
      panel.id,
      [for (final l in stack) l.id],
    );

    for (final id in ordered) {
      final layer = byId[id];
      // orderedLayerIds only ever returns ids from the natural order, but a
      // corrupted override must not crash a user's project.
      if (layer == null) continue;
      layers.add(translateLayerX(layer, offsetX));
    }

    backgrounds.add(content.backgroundFor(panel.id) ?? panel.backgroundColor);
  }

  final document = Document(
    id: template.id,
    schemaVersion: 4,
    version: template.version,
    name: template.name,
    aspectRatio: template.aspectRatio,
    slideWidth: slideWidth,
    slideHeight: slideHeight,
    slideCount: panels.length,
    gutter: 0,
    slideBackgrounds: backgrounds,
    layers: layers,
  );

  // Panel-scoped overrides are now expressed by the document itself: the
  // layers carry their absolute x, the stack order IS the list order, and the
  // backgrounds moved to slideBackgrounds. Carrying them forward would leave a
  // second, stale source of truth keyed by panel ids that no longer exist.
  return MigrationResult(document, content.withoutPanelScopedOverrides());
}
