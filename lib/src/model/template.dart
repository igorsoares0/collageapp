import 'dart:ui';

/// Highest template schema this renderer understands. Templates above this
/// are filtered out during sync instead of being rendered incorrectly.
/// Mirror of CURRENT_SCHEMA_VERSION in the editor (lib/template/types.ts).
/// v2 added multi-panel ("panels"); single-panel templates stay v1.
const int kSupportedSchemaVersion = 2;

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

  /// Slot ids of this panel's layers that accept user content, in stack order.
  List<String> get slotIds => [
    for (final layer in layers)
      if (layer is ImageLayer)
        layer.slotId
      else if (layer is TextLayer)
        layer.slotId,
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

  /// All layers across every panel — convenient for slotId-based lookups
  /// (slotIds are unique across the whole template).
  List<Layer> get layers => [for (final p in panels) ...p.layers];

  /// Slot ids of layers that accept user content, across all panels.
  List<String> get slotIds => [for (final p in panels) ...p.slotIds];
}

sealed class Layer {
  final String id;

  /// Editor-side flag, but respected here so the render matches what the
  /// designer saw when publishing (WYSIWYG between editor and app).
  final bool hidden;

  const Layer({required this.id, required this.hidden});

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
      default:
        return null;
    }
  }
}

class ImageLayer extends Layer {
  final String slotId;
  final double x, y, width, height, rotation, opacity, borderRadius;

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
  });
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
