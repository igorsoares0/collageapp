import 'package:flutter/widgets.dart';

/// User content injected into template slots (spec §12). Templates never
/// contain user content; this map is the app-side counterpart of slotIds.
/// [offsets] (template space) and [scales] are user position/size
/// adjustments; [colors] and [fonts] override a text slot's styling. The
/// template itself stays immutable — every tweak travels with the user's
/// content, so accessors fall back to the layer's own value when absent.
class SlotContent {
  final Map<String, String> texts;
  final Map<String, ImageProvider> images;
  final Map<String, Offset> offsets;
  final Map<String, double> scales;
  final Map<String, Color> colors;
  final Map<String, String> fonts;
  final Map<String, String> alignments;
  final Map<String, int> weights;

  /// Per-panel override of each panel's background color, keyed by panel id;
  /// a missing entry means use that panel's own template background.
  final Map<String, Color> panelBackgrounds;

  /// Per-panel stack-order override, keyed by panel id; the value is the
  /// panel's layer ids in stack order (index 0 = bottom). A missing entry
  /// means render the panel's layers in their natural template order.
  final Map<String, List<String>> layerOrders;

  /// Per-layer visibility override, keyed by layer id; true = hidden. A
  /// missing entry means defer to the layer's own `hidden` flag from the
  /// template. Lets the user hide/show any element without mutating the
  /// template (the change rides into the export like every other override).
  final Map<String, bool> hiddenLayers;

  const SlotContent({
    this.texts = const {},
    this.images = const {},
    this.offsets = const {},
    this.scales = const {},
    this.colors = const {},
    this.fonts = const {},
    this.alignments = const {},
    this.weights = const {},
    this.panelBackgrounds = const {},
    this.layerOrders = const {},
    this.hiddenLayers = const {},
  });

  String? textFor(String slotId) => texts[slotId];
  ImageProvider? imageFor(String slotId) => images[slotId];
  Offset offsetFor(String slotId) => offsets[slotId] ?? Offset.zero;
  double scaleFor(String slotId) => scales[slotId] ?? 1.0;
  Color? colorFor(String slotId) => colors[slotId];
  String? fontFor(String slotId) => fonts[slotId];
  String? alignmentFor(String slotId) => alignments[slotId];
  int? weightFor(String slotId) => weights[slotId];
  Color? backgroundFor(String panelId) => panelBackgrounds[panelId];

  /// Whether [layerId] is hidden, given the template's own [templateHidden]
  /// flag as the fallback when the user hasn't overridden it.
  bool layerHidden(String layerId, bool templateHidden) =>
      hiddenLayers[layerId] ?? templateHidden;

  /// The panel's layer ids in effective stack order (index 0 = bottom),
  /// applying the user's reorder override over [naturalOrder]. Any layer the
  /// override doesn't mention (e.g. one added after the override was made)
  /// keeps its natural position appended at the end, so a stale override can
  /// never drop a layer from the render.
  List<String> orderedLayerIds(String panelId, List<String> naturalOrder) {
    final override = layerOrders[panelId];
    if (override == null) return naturalOrder;
    final known = naturalOrder.toSet();
    final result = [
      for (final id in override)
        if (known.contains(id)) id,
    ];
    for (final id in naturalOrder) {
      if (!result.contains(id)) result.add(id);
    }
    return result;
  }

  SlotContent withText(String slotId, String value) =>
      _copy(texts: {...texts, slotId: value});

  SlotContent withImage(String slotId, ImageProvider value) =>
      _copy(images: {...images, slotId: value});

  SlotContent withOffset(String slotId, Offset value) =>
      _copy(offsets: {...offsets, slotId: value});

  SlotContent withScale(String slotId, double value) =>
      _copy(scales: {...scales, slotId: value});

  SlotContent withColor(String slotId, Color value) =>
      _copy(colors: {...colors, slotId: value});

  SlotContent withFont(String slotId, String value) =>
      _copy(fonts: {...fonts, slotId: value});

  SlotContent withAlignment(String slotId, String value) =>
      _copy(alignments: {...alignments, slotId: value});

  SlotContent withWeight(String slotId, int value) =>
      _copy(weights: {...weights, slotId: value});

  SlotContent withPanelBackground(String panelId, Color value) =>
      _copy(panelBackgrounds: {...panelBackgrounds, panelId: value});

  SlotContent withLayerHidden(String layerId, bool hidden) =>
      _copy(hiddenLayers: {...hiddenLayers, layerId: hidden});

  SlotContent withLayerOrder(String panelId, List<String> ids) =>
      _copy(layerOrders: {...layerOrders, panelId: ids});

  /// Moves [layerId] one step toward the front ([toFront] true) or back
  /// within its panel's stack. A no-op at the corresponding end. [naturalOrder]
  /// seeds the order when no override exists yet.
  SlotContent withLayerMoved(
    String panelId,
    List<String> naturalOrder,
    String layerId, {
    required bool toFront,
  }) {
    final ids = orderedLayerIds(panelId, naturalOrder);
    final i = ids.indexOf(layerId);
    if (i < 0) return this;
    // Front = top of the stack = higher index.
    final j = toFront ? i + 1 : i - 1;
    if (j < 0 || j >= ids.length) return this;
    final next = [...ids];
    next[i] = ids[j];
    next[j] = ids[i];
    return withLayerOrder(panelId, next);
  }

  SlotContent _copy({
    Map<String, String>? texts,
    Map<String, ImageProvider>? images,
    Map<String, Offset>? offsets,
    Map<String, double>? scales,
    Map<String, Color>? colors,
    Map<String, String>? fonts,
    Map<String, String>? alignments,
    Map<String, int>? weights,
    Map<String, Color>? panelBackgrounds,
    Map<String, List<String>>? layerOrders,
    Map<String, bool>? hiddenLayers,
  }) => SlotContent(
    texts: texts ?? this.texts,
    images: images ?? this.images,
    offsets: offsets ?? this.offsets,
    scales: scales ?? this.scales,
    colors: colors ?? this.colors,
    fonts: fonts ?? this.fonts,
    alignments: alignments ?? this.alignments,
    weights: weights ?? this.weights,
    panelBackgrounds: panelBackgrounds ?? this.panelBackgrounds,
    layerOrders: layerOrders ?? this.layerOrders,
    hiddenLayers: hiddenLayers ?? this.hiddenLayers,
  );
}
