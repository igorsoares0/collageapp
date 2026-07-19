import 'dart:math' as math;
import 'dart:ui';

/// Highest template schema this renderer understands. Templates above this
/// are filtered out during sync instead of being rendered incorrectly.
/// Mirror of CURRENT_SCHEMA_VERSION in the editor (lib/template/types.ts).
/// v2 added multi-panel ("panels"); v3 added the grid layer ("type":"grid").
const int kSupportedSchemaVersion = 3;

/// One slide of a carousel template: its own background and layer stack. All
/// panels share the template's canvas size. Classic single-canvas templates
/// (v1) are read as a one-panel list.
class Panel {
  final String id;
  final Color backgroundColor;
  final List<Layer> layers;

  const Panel({
    required this.id,
    required this.backgroundColor,
    required this.layers,
  });

  factory Panel.fromJson(Map<String, dynamic> json) {
    final bg = json['backgroundColor'];
    return Panel(
      id: json['id'] as String,
      backgroundColor: bg is String
          ? parseHexColor(bg)
          : const Color(0xFFFFFFFF),
      layers: _parseLayers(json['layers']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'backgroundColor': colorToHex(backgroundColor),
    'layers': [for (final l in layers) l.toJson()],
  };

  /// Slot ids of this panel's layers that accept user content, in stack order.
  /// A grid contributes one slot per cell (each cell is a fillable photo slot).
  List<String> get slotIds => [
    for (final layer in layers)
      ...switch (layer) {
        ImageLayer l => [l.slotId],
        TextLayer l => [l.slotId],
        GridLayer l => [for (final c in l.cells) c.slotId],
        _ => const <String>[],
      },
  ];
}

List<Layer> _parseLayers(dynamic value) => (value as List<dynamic>)
    .map((l) => Layer.fromJson(l as Map<String, dynamic>))
    .whereType<Layer>()
    .toList();

/// Template JSON contract — see "Collage Studio - Product & Architecture
/// Specification.md" §5–13. Templates are data; this app only interprets them.
class Template {
  final String id;
  final int schemaVersion;
  final int version;
  final String name;
  final String aspectRatio;
  final double canvasWidth;
  final double canvasHeight;

  /// One or more panels (carousel slides). Always non-empty.
  final List<Panel> panels;

  const Template({
    required this.id,
    required this.schemaVersion,
    required this.version,
    required this.name,
    required this.aspectRatio,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.panels,
  });

  /// An empty single-panel document for the create-from-scratch flow: no
  /// layers, white background, latest schema. Everything the user builds on it
  /// rides in SlotContent overrides (added layers/panels), exactly like edits
  /// to a published template.
  factory Template.blank({
    String aspectRatio = '9:16',
    double canvasWidth = 1080,
    double canvasHeight = 1920,
  }) => Template(
    id: 'draft',
    schemaVersion: kSupportedSchemaVersion,
    version: 1,
    name: 'New collage',
    aspectRatio: aspectRatio,
    canvasWidth: canvasWidth,
    canvasHeight: canvasHeight,
    panels: const [
      Panel(id: 'panel_1', backgroundColor: Color(0xFFFFFFFF), layers: []),
    ],
  );

  factory Template.fromJson(Map<String, dynamic> json) {
    final canvas = json['canvas'] as Map<String, dynamic>;
    final panelsJson = json['panels'];
    final List<Panel> panels;
    if (panelsJson is List) {
      // v2 multi-panel.
      panels = panelsJson
          .map((p) => Panel.fromJson(p as Map<String, dynamic>))
          .toList();
    } else {
      // Classic v1: the single canvas becomes one panel.
      final bg = canvas['backgroundColor'];
      panels = [
        Panel(
          id: 'panel_0',
          backgroundColor: bg is String
              ? parseHexColor(bg)
              : const Color(0xFFFFFFFF),
          layers: _parseLayers(json['layers']),
        ),
      ];
    }
    return Template(
      id: json['id'] as String,
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      version: (json['version'] as num).toInt(),
      name: json['name'] as String,
      aspectRatio: json['aspectRatio'] as String,
      canvasWidth: (canvas['width'] as num).toDouble(),
      canvasHeight: (canvas['height'] as num).toDouble(),
      panels: panels,
    );
  }

  /// Inverse of [fromJson], always in the multi-panel (v2+) shape — v1
  /// templates never round-trip through here (the app doesn't author them).
  Map<String, dynamic> toJson() => {
    'id': id,
    'schemaVersion': schemaVersion,
    'version': version,
    'name': name,
    'aspectRatio': aspectRatio,
    'canvas': {'width': canvasWidth, 'height': canvasHeight},
    'panels': [for (final p in panels) p.toJson()],
  };

  /// All layers across every panel — convenient for slotId-based lookups
  /// (slotIds are unique across the whole template).
  List<Layer> get layers => [for (final p in panels) ...p.layers];

  /// Slot ids of layers that accept user content, across all panels.
  List<String> get slotIds => [for (final p in panels) ...p.slotIds];
}

/// v4: the continuous canvas (Modelo B). See docs/model-b-migration.md.
///
/// STATUS: model only. Nothing reads this yet — [kSupportedSchemaVersion] is
/// deliberately still 3, so a v4 template is filtered out during sync rather
/// than half-rendered. The dual v3/v4 read path lands in the next phase, once
/// the renderer can actually draw a continuous canvas.
///
/// Instead of N independent [Panel]s, one canvas [slideCount] slides wide with
/// every layer in a SINGLE coordinate system (x from 0 to [contentWidth]).
/// Slides are just cut lines; the slicing happens at export. This is a SUPERSET
/// of the panel model: independent slides are the degenerate case where no
/// layer crosses a cut, and a panorama is one layer whose x spans several.
///
/// Mirror of ContinuousTemplate in the editor (lib/template/types.ts).
class Document {
  final String id;
  final int schemaVersion;
  final int version;
  final String name;
  final String aspectRatio;

  final double slideWidth;
  final double slideHeight;
  final int slideCount;

  /// Space BETWEEN slides; 0 for a seamless carousel.
  final double gutter;

  /// The one naturally per-slide datum. Length == [slideCount].
  final List<Color> slideBackgrounds;

  /// Continuous coordinates: 0 .. [contentWidth]. No layer carries a slide
  /// index — see slide_aware.dart, where that is derived from geometry.
  final List<Layer> layers;

  const Document({
    required this.id,
    required this.schemaVersion,
    required this.version,
    required this.name,
    required this.aspectRatio,
    required this.slideWidth,
    required this.slideHeight,
    required this.slideCount,
    required this.gutter,
    required this.slideBackgrounds,
    required this.layers,
  });

  /// Total width: N slides plus the N-1 gutters BETWEEN them (no outer gutter).
  double get contentWidth =>
      slideCount * slideWidth + math.max(0, slideCount - 1) * gutter;

  /// The region slide [i] occupies in continuous space — the export crop rect
  /// and the editor's cut guides both come from here.
  Rect slideRect(int i) =>
      Rect.fromLTWH(i * (slideWidth + gutter), 0, slideWidth, slideHeight);

  /// Background of slide [i], white when the list is short (defensive: a
  /// malformed template must not crash the renderer).
  Color backgroundFor(int i) => i >= 0 && i < slideBackgrounds.length
      ? slideBackgrounds[i]
      : const Color(0xFFFFFFFF);

  factory Document.fromJson(Map<String, dynamic> json) {
    final canvas = json['canvas'] as Map<String, dynamic>;
    final backgrounds = json['slideBackgrounds'];
    return Document(
      id: json['id'] as String,
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 4,
      version: (json['version'] as num).toInt(),
      name: json['name'] as String,
      aspectRatio: json['aspectRatio'] as String,
      slideWidth: (canvas['slideWidth'] as num).toDouble(),
      slideHeight: (canvas['slideHeight'] as num).toDouble(),
      slideCount: (canvas['slideCount'] as num).toInt(),
      gutter: (canvas['gutter'] as num?)?.toDouble() ?? 0,
      slideBackgrounds: backgrounds is List
          ? [
              for (final b in backgrounds)
                b is String ? parseHexColor(b) : const Color(0xFFFFFFFF),
            ]
          : const [],
      layers: _parseLayers(json['layers']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'schemaVersion': schemaVersion,
    'version': version,
    'name': name,
    'aspectRatio': aspectRatio,
    'canvas': {
      'slideWidth': slideWidth,
      'slideHeight': slideHeight,
      'slideCount': slideCount,
      'gutter': gutter,
    },
    'slideBackgrounds': [for (final c in slideBackgrounds) colorToHex(c)],
    'layers': [for (final l in layers) l.toJson()],
  };

  /// Slot ids that accept user content, in stack order. A grid contributes one
  /// slot per cell, exactly as in the panel model.
  List<String> get slotIds => [
    for (final layer in layers)
      ...switch (layer) {
        ImageLayer l => [l.slotId],
        TextLayer l => [l.slotId],
        GridLayer l => [for (final c in l.cells) c.slotId],
        _ => const <String>[],
      },
  ];
}

sealed class Layer {
  final String id;

  /// Editor-side flag, but respected here so the render matches what the
  /// designer saw when publishing (WYSIWYG between editor and app).
  final bool hidden;

  const Layer({required this.id, required this.hidden});

  /// The editor-schema JSON for this layer — exact inverse of [fromJson].
  Map<String, dynamic> toJson();

  /// Returns null for unknown layer types (defensive; the schemaVersion gate
  /// should prevent this, but a skipped layer beats a crash).
  static Layer? fromJson(Map<String, dynamic> json) {
    final editor = json['editor'] as Map<String, dynamic>?;
    final hidden = editor?['hidden'] == true;
    switch (json['type']) {
      case 'image':
        return ImageLayer(
          id: json['id'] as String,
          hidden: hidden,
          slotId: json['slotId'] as String,
          x: (json['x'] as num).toDouble(),
          y: (json['y'] as num).toDouble(),
          width: (json['width'] as num).toDouble(),
          height: (json['height'] as num).toDouble(),
          rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
          opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
          borderRadius: (json['borderRadius'] as num?)?.toDouble() ?? 0,
          frameAssetId: json['frameAssetId'] as String?,
          imageAssetId: json['imageAssetId'] as String?,
        );
      case 'text':
        return TextLayer(
          id: json['id'] as String,
          hidden: hidden,
          slotId: json['slotId'] as String,
          x: (json['x'] as num).toDouble(),
          y: (json['y'] as num).toDouble(),
          width: (json['width'] as num).toDouble(),
          fontFamily: json['fontFamily'] as String,
          fontSize: (json['fontSize'] as num).toDouble(),
          fontWeight: (json['fontWeight'] as num).toInt(),
          color: parseHexColor(json['color'] as String),
          alignment: json['alignment'] as String,
        );
      case 'shape':
        return ShapeLayer(
          id: json['id'] as String,
          hidden: hidden,
          x: (json['x'] as num).toDouble(),
          y: (json['y'] as num).toDouble(),
          width: (json['width'] as num).toDouble(),
          height: (json['height'] as num).toDouble(),
          fill: parseHexColor(json['fill'] as String),
        );
      case 'sticker':
        return StickerLayer(
          id: json['id'] as String,
          hidden: hidden,
          assetId: json['assetId'] as String,
          x: (json['x'] as num).toDouble(),
          y: (json['y'] as num).toDouble(),
          width: (json['width'] as num).toDouble(),
          height: (json['height'] as num).toDouble(),
        );
      case 'grid':
        final gutterColor = json['gutterColor'];
        return GridLayer(
          id: json['id'] as String,
          hidden: hidden,
          x: (json['x'] as num).toDouble(),
          y: (json['y'] as num).toDouble(),
          width: (json['width'] as num).toDouble(),
          height: (json['height'] as num).toDouble(),
          rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
          cols: (json['cols'] as num).toInt(),
          rows: (json['rows'] as num).toInt(),
          colFractions: _doubleList(json['colFractions']),
          rowFractions: _doubleList(json['rowFractions']),
          gutter: (json['gutter'] as num?)?.toDouble() ?? 0,
          cornerRadius: (json['cornerRadius'] as num?)?.toDouble() ?? 0,
          gutterColor: gutterColor is String
              ? parseHexColor(gutterColor)
              : null,
          cells: (json['cells'] as List<dynamic>)
              .map((c) => GridCell.fromJson(c as Map<String, dynamic>))
              .toList(),
        );
      default:
        return null;
    }
  }
}

class ImageLayer extends Layer {
  final String slotId;
  final double x, y, width, height, rotation, opacity, borderRadius;

  /// Optional decorative frame (polaroid, etc.) painted over the user's photo;
  /// null = bare photo. Resolved against the frame catalog at render time.
  final String? frameAssetId;

  /// Optional designer-placed sample photo (a "photo" asset delivered with the
  /// template). Shown only where the canvas opts in (the preview) — the editor
  /// keeps the placeholder so the user's own photo is the content.
  final String? imageAssetId;

  const ImageLayer({
    required super.id,
    required super.hidden,
    required this.slotId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.rotation,
    required this.opacity,
    required this.borderRadius,
    this.frameAssetId,
    this.imageAssetId,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'image',
    'id': id,
    'editor': {'hidden': hidden},
    'slotId': slotId,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'rotation': rotation,
    'opacity': opacity,
    'borderRadius': borderRadius,
    if (frameAssetId != null) 'frameAssetId': frameAssetId,
    if (imageAssetId != null) 'imageAssetId': imageAssetId,
  };
}

class TextLayer extends Layer {
  final String slotId;
  final double x, y, width, fontSize;
  final String fontFamily;
  final int fontWeight;
  final Color color;
  final String alignment;

  const TextLayer({
    required super.id,
    required super.hidden,
    required this.slotId,
    required this.x,
    required this.y,
    required this.width,
    required this.fontFamily,
    required this.fontSize,
    required this.fontWeight,
    required this.color,
    required this.alignment,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'text',
    'id': id,
    'editor': {'hidden': hidden},
    'slotId': slotId,
    'x': x,
    'y': y,
    'width': width,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'fontWeight': fontWeight,
    'color': colorToHex(color),
    'alignment': alignment,
  };
}

class ShapeLayer extends Layer {
  final double x, y, width, height;
  final Color fill;

  const ShapeLayer({
    required super.id,
    required super.hidden,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.fill,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'shape',
    'id': id,
    'editor': {'hidden': hidden},
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'fill': colorToHex(fill),
  };
}

class StickerLayer extends Layer {
  final String assetId;
  final double x, y, width, height;

  const StickerLayer({
    required super.id,
    required super.hidden,
    required this.assetId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'sticker',
    'id': id,
    'editor': {'hidden': hidden},
    'assetId': assetId,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };
}

/// One fillable photo slot of a grid. Its pixel rect is derived from the grid's
/// fraction tracks by [cellRect]; the user's photo (keyed by [slotId], like an
/// ImageLayer) is drawn cover-fit inside it and can be panned/zoomed within.
class GridCell {
  final String slotId;
  final int col, row, colSpan, rowSpan;

  /// Per-cell corner radius override; null = use the grid's cornerRadius.
  final double? borderRadius;

  /// Optional designer-placed sample photo (see ImageLayer.imageAssetId).
  final String? imageAssetId;

  const GridCell({
    required this.slotId,
    required this.col,
    required this.row,
    this.colSpan = 1,
    this.rowSpan = 1,
    this.borderRadius,
    this.imageAssetId,
  });

  factory GridCell.fromJson(Map<String, dynamic> json) => GridCell(
    slotId: json['slotId'] as String,
    col: (json['col'] as num).toInt(),
    row: (json['row'] as num).toInt(),
    colSpan: (json['colSpan'] as num?)?.toInt() ?? 1,
    rowSpan: (json['rowSpan'] as num?)?.toInt() ?? 1,
    borderRadius: (json['borderRadius'] as num?)?.toDouble(),
    imageAssetId: json['imageAssetId'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'slotId': slotId,
    'col': col,
    'row': row,
    'colSpan': colSpan,
    'rowSpan': rowSpan,
    if (borderRadius != null) 'borderRadius': borderRadius,
    if (imageAssetId != null) 'imageAssetId': imageAssetId,
  };
}

/// A unified photo grid (schemaVersion 3): one placeable/rotatable element that
/// tiles its box into cells sized by fraction tracks and separated by a uniform
/// gutter. Mirrors GridLayer in the editor (lib/template/types.ts). The user
/// fills each cell and pans/zooms the photo within it; the designer sets the
/// layout. Rotation follows the Konva contract (clockwise, top-left pivot).
class GridLayer extends Layer {
  final double x, y, width, height, rotation, gutter, cornerRadius;
  final int cols, rows;
  final List<double> colFractions, rowFractions;
  final Color? gutterColor;
  final List<GridCell> cells;

  const GridLayer({
    required super.id,
    required super.hidden,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.rotation,
    required this.cols,
    required this.rows,
    required this.colFractions,
    required this.rowFractions,
    required this.gutter,
    required this.cornerRadius,
    required this.gutterColor,
    required this.cells,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'grid',
    'id': id,
    'editor': {'hidden': hidden},
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'rotation': rotation,
    'cols': cols,
    'rows': rows,
    'colFractions': colFractions,
    'rowFractions': rowFractions,
    'gutter': gutter,
    'cornerRadius': cornerRadius,
    if (gutterColor != null) 'gutterColor': colorToHex(gutterColor!),
    'cells': [for (final c in cells) c.toJson()],
  };
}

/// Pixel rect of [cell] inside [grid]'s local box (origin at the grid's x/y).
/// A track's size is its fraction of the usable length (box minus every
/// gutter); gutters sit on both outer edges and between tracks, and a spanning
/// cell also eats the internal gutters it straddles. Mirrors cellRect() in the
/// editor (lib/template/grid.ts) so both sides tile a grid identically.
/// [colFractions]/[rowFractions] overrides let a user tweak (Phase 3) recompute
/// without mutating the layer.
Rect cellRect(
  GridLayer grid,
  GridCell cell, {
  List<double>? colFractions,
  List<double>? rowFractions,
  double? gutter,
  double? width,
  double? height,
}) {
  final colF = colFractions ?? grid.colFractions;
  final rowF = rowFractions ?? grid.rowFractions;
  final cs = cell.colSpan < 1 ? 1 : cell.colSpan;
  final rs = cell.rowSpan < 1 ? 1 : cell.rowSpan;
  final g = gutter ?? grid.gutter;

  final usableW = math.max(0.0, (width ?? grid.width) - g * (grid.cols + 1));
  final usableH = math.max(0.0, (height ?? grid.height) - g * (grid.rows + 1));
  final sc = _sum(colF) == 0 ? 1.0 : _sum(colF);
  final sr = _sum(rowF) == 0 ? 1.0 : _sum(rowF);

  final x = g * (cell.col + 1) + usableW * (_sumRange(colF, 0, cell.col) / sc);
  final y = g * (cell.row + 1) + usableH * (_sumRange(rowF, 0, cell.row) / sr);
  final w =
      usableW * (_sumRange(colF, cell.col, cell.col + cs) / sc) + g * (cs - 1);
  final h =
      usableH * (_sumRange(rowF, cell.row, cell.row + rs) / sr) + g * (rs - 1);
  return Rect.fromLTWH(x, y, w, h);
}

double _sum(List<double> xs) => xs.fold(0.0, (a, b) => a + b);
double _sumRange(List<double> xs, int start, int end) {
  var total = 0.0;
  for (var i = start; i < end && i < xs.length; i++) {
    total += xs[i];
  }
  return total;
}

List<double> _doubleList(dynamic value) =>
    (value as List<dynamic>).map((e) => (e as num).toDouble()).toList();

/// Formats a color as the editor's "#RRGGBB" — the inverse of
/// [parseHexColor]. Alpha is dropped; template colors are opaque by contract.
String colorToHex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Parses "#RRGGBB" (the editor's color format). Falls back to black so a
/// malformed color degrades visibly instead of crashing the render.
Color parseHexColor(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null || cleaned.length != 6) {
    return const Color(0xFF000000);
  }
  return Color(0xFF000000 | value);
}
