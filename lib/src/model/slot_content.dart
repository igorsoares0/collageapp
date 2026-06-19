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

  const SlotContent({
    this.texts = const {},
    this.images = const {},
    this.offsets = const {},
    this.scales = const {},
    this.colors = const {},
    this.fonts = const {},
    this.alignments = const {},
    this.weights = const {},
  });

  String? textFor(String slotId) => texts[slotId];
  ImageProvider? imageFor(String slotId) => images[slotId];
  Offset offsetFor(String slotId) => offsets[slotId] ?? Offset.zero;
  double scaleFor(String slotId) => scales[slotId] ?? 1.0;
  Color? colorFor(String slotId) => colors[slotId];
  String? fontFor(String slotId) => fonts[slotId];
  String? alignmentFor(String slotId) => alignments[slotId];
  int? weightFor(String slotId) => weights[slotId];

  SlotContent withText(String slotId, String value) => _copy(
        texts: {...texts, slotId: value},
      );

  SlotContent withImage(String slotId, ImageProvider value) => _copy(
        images: {...images, slotId: value},
      );

  SlotContent withOffset(String slotId, Offset value) => _copy(
        offsets: {...offsets, slotId: value},
      );

  SlotContent withScale(String slotId, double value) => _copy(
        scales: {...scales, slotId: value},
      );

  SlotContent withColor(String slotId, Color value) => _copy(
        colors: {...colors, slotId: value},
      );

  SlotContent withFont(String slotId, String value) => _copy(
        fonts: {...fonts, slotId: value},
      );

  SlotContent withAlignment(String slotId, String value) => _copy(
        alignments: {...alignments, slotId: value},
      );

  SlotContent withWeight(String slotId, int value) => _copy(
        weights: {...weights, slotId: value},
      );

  SlotContent _copy({
    Map<String, String>? texts,
    Map<String, ImageProvider>? images,
    Map<String, Offset>? offsets,
    Map<String, double>? scales,
    Map<String, Color>? colors,
    Map<String, String>? fonts,
    Map<String, String>? alignments,
    Map<String, int>? weights,
  }) =>
      SlotContent(
        texts: texts ?? this.texts,
        images: images ?? this.images,
        offsets: offsets ?? this.offsets,
        scales: scales ?? this.scales,
        colors: colors ?? this.colors,
        fonts: fonts ?? this.fonts,
        alignments: alignments ?? this.alignments,
        weights: weights ?? this.weights,
      );
}
