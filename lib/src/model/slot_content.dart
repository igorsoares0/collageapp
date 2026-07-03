import 'package:flutter/widgets.dart';

import 'template.dart';

/// The user's tweaks to a grid layer (keyed by the grid's layer id). The
/// template is immutable, so a resized gutter / rounded corner / dragged
/// divider rides here like every other override. Any field left null falls back
/// to the grid's own template value.
class GridOverride {
  final double? gutter;
  final double? cornerRadius;
  final List<double>? colFractions;
  final List<double>? rowFractions;

  const GridOverride({
    this.gutter,
    this.cornerRadius,
    this.colFractions,
    this.rowFractions,
  });

  GridOverride copyWith({
    double? gutter,
    double? cornerRadius,
    List<double>? colFractions,
    List<double>? rowFractions,
  }) => GridOverride(
    gutter: gutter ?? this.gutter,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    colFractions: colFractions ?? this.colFractions,
    rowFractions: rowFractions ?? this.rowFractions,
  );
}

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

  /// User rotation override per slot, in degrees clockwise. This is added on
  /// top of the layer's own template rotation (image layers carry one; text
  /// layers don't), so the slot rotates from wherever the designer placed it.
  final Map<String, double> rotations;

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

  /// Per-grid tweaks (gutter/corner/fraction tracks), keyed by grid layer id.
  /// A missing entry means the grid renders exactly as the designer authored it.
  final Map<String, GridOverride> gridOverrides;

  /// Layers the user added on top of the template, keyed by panel id (in the
  /// order they were added — newest on top). Templates never gain layers; the
  /// app stacks these above the template's own and treats them exactly like
  /// template slots (same select/move/resize/style/hide/reorder/export path),
  /// so they carry their own SlotContent overrides under their slot ids.
  final Map<String, List<Layer>> addedLayers;

  /// Panels the user added after the template's own (in order). Each starts
  /// empty; its content lives in [addedLayers] under its id and its background
  /// in [panelBackgrounds], so an added panel behaves exactly like a template
  /// panel everywhere (canvas, layer sheet, export).
  final List<Panel> addedPanels;

  const SlotContent({
    this.texts = const {},
    this.images = const {},
    this.offsets = const {},
    this.scales = const {},
    this.rotations = const {},
    this.colors = const {},
    this.fonts = const {},
    this.alignments = const {},
    this.weights = const {},
    this.panelBackgrounds = const {},
    this.layerOrders = const {},
    this.hiddenLayers = const {},
    this.gridOverrides = const {},
    this.addedLayers = const {},
    this.addedPanels = const [],
  });

  String? textFor(String slotId) => texts[slotId];
  ImageProvider? imageFor(String slotId) => images[slotId];
  Offset offsetFor(String slotId) => offsets[slotId] ?? Offset.zero;
  double scaleFor(String slotId) => scales[slotId] ?? 1.0;

  /// The user's rotation override for [slotId] in degrees (0 = none). Added to
  /// the layer's own template rotation at render time.
  double rotationFor(String slotId) => rotations[slotId] ?? 0.0;

  Color? colorFor(String slotId) => colors[slotId];
  String? fontFor(String slotId) => fonts[slotId];
  String? alignmentFor(String slotId) => alignments[slotId];
  int? weightFor(String slotId) => weights[slotId];
  Color? backgroundFor(String panelId) => panelBackgrounds[panelId];

  /// Effective grid values for [gridId], falling back to the layer's own value
  /// when the user hasn't overridden that field.
  double gridGutter(String gridId, double fallback) =>
      gridOverrides[gridId]?.gutter ?? fallback;
  double gridCornerRadius(String gridId, double fallback) =>
      gridOverrides[gridId]?.cornerRadius ?? fallback;
  List<double> gridColFractions(String gridId, List<double> fallback) =>
      gridOverrides[gridId]?.colFractions ?? fallback;
  List<double> gridRowFractions(String gridId, List<double> fallback) =>
      gridOverrides[gridId]?.rowFractions ?? fallback;

  /// Whether [layerId] is hidden, given the template's own [templateHidden]
  /// flag as the fallback when the user hasn't overridden it.
  bool layerHidden(String layerId, bool templateHidden) =>
      hiddenLayers[layerId] ?? templateHidden;

  /// User-added layers for [panelId], stacked above the template's own.
  List<Layer> addedLayersFor(String panelId) =>
      addedLayers[panelId] ?? const [];

  /// Every user-added layer across all panels (slot/layer ids are globally
  /// unique, so this is safe for id-based lookups).
  List<Layer> get allAddedLayers => [
    for (final layers in addedLayers.values) ...layers,
  ];

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

  SlotContent withRotation(String slotId, double degrees) =>
      _copy(rotations: {...rotations, slotId: degrees});

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

  GridOverride _grid(String gridId) =>
      gridOverrides[gridId] ?? const GridOverride();

  SlotContent withGridGutter(String gridId, double value) => _copy(
    gridOverrides: {
      ...gridOverrides,
      gridId: _grid(gridId).copyWith(gutter: value),
    },
  );

  SlotContent withGridCornerRadius(String gridId, double value) => _copy(
    gridOverrides: {
      ...gridOverrides,
      gridId: _grid(gridId).copyWith(cornerRadius: value),
    },
  );

  SlotContent withGridColFractions(String gridId, List<double> value) => _copy(
    gridOverrides: {
      ...gridOverrides,
      gridId: _grid(gridId).copyWith(colFractions: value),
    },
  );

  SlotContent withGridRowFractions(String gridId, List<double> value) => _copy(
    gridOverrides: {
      ...gridOverrides,
      gridId: _grid(gridId).copyWith(rowFractions: value),
    },
  );

  SlotContent withLayerHidden(String layerId, bool hidden) =>
      _copy(hiddenLayers: {...hiddenLayers, layerId: hidden});

  SlotContent withLayerOrder(String panelId, List<String> ids) =>
      _copy(layerOrders: {...layerOrders, panelId: ids});

  SlotContent withAddedPanel(Panel panel) =>
      _copy(addedPanels: [...addedPanels, panel]);

  SlotContent withAddedLayer(String panelId, Layer layer) => _copy(
    addedLayers: {
      ...addedLayers,
      panelId: [...addedLayersFor(panelId), layer],
    },
  );

  /// Removes a user-added layer (and its order override, which would otherwise
  /// pin a now-missing id). Per-slot overrides under its slotId become inert
  /// once nothing references them, so they need no cleanup.
  SlotContent withoutAddedLayer(String panelId, String layerId) {
    final remaining = [
      for (final l in addedLayersFor(panelId))
        if (l.id != layerId) l,
    ];
    final order = layerOrders[panelId];
    return _copy(
      addedLayers: {...addedLayers, panelId: remaining},
      layerOrders: order == null
          ? null
          : {
              ...layerOrders,
              panelId: [
                for (final id in order)
                  if (id != layerId) id,
              ],
            },
    );
  }

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
    Map<String, double>? rotations,
    Map<String, Color>? colors,
    Map<String, String>? fonts,
    Map<String, String>? alignments,
    Map<String, int>? weights,
    Map<String, Color>? panelBackgrounds,
    Map<String, List<String>>? layerOrders,
    Map<String, bool>? hiddenLayers,
    Map<String, GridOverride>? gridOverrides,
    Map<String, List<Layer>>? addedLayers,
    List<Panel>? addedPanels,
  }) => SlotContent(
    texts: texts ?? this.texts,
    images: images ?? this.images,
    offsets: offsets ?? this.offsets,
    scales: scales ?? this.scales,
    rotations: rotations ?? this.rotations,
    colors: colors ?? this.colors,
    fonts: fonts ?? this.fonts,
    alignments: alignments ?? this.alignments,
    weights: weights ?? this.weights,
    panelBackgrounds: panelBackgrounds ?? this.panelBackgrounds,
    layerOrders: layerOrders ?? this.layerOrders,
    hiddenLayers: hiddenLayers ?? this.hiddenLayers,
    gridOverrides: gridOverrides ?? this.gridOverrides,
    addedLayers: addedLayers ?? this.addedLayers,
    addedPanels: addedPanels ?? this.addedPanels,
  );
}
