import 'package:flutter/widgets.dart';

/// User content injected into template slots (spec §12). Templates never
/// contain user content; this map is the app-side counterpart of slotIds.
/// [offsets] (template space) and [scales] are user position/size
/// adjustments — the template itself stays immutable, the tweak travels
/// with the user's content.
class SlotContent {
  final Map<String, String> texts;
  final Map<String, ImageProvider> images;
  final Map<String, Offset> offsets;
  final Map<String, double> scales;

  const SlotContent({
    this.texts = const {},
    this.images = const {},
    this.offsets = const {},
    this.scales = const {},
  });

  String? textFor(String slotId) => texts[slotId];
  ImageProvider? imageFor(String slotId) => images[slotId];
  Offset offsetFor(String slotId) => offsets[slotId] ?? Offset.zero;
  double scaleFor(String slotId) => scales[slotId] ?? 1.0;

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

  SlotContent _copy({
    Map<String, String>? texts,
    Map<String, ImageProvider>? images,
    Map<String, Offset>? offsets,
    Map<String, double>? scales,
  }) =>
      SlotContent(
        texts: texts ?? this.texts,
        images: images ?? this.images,
        offsets: offsets ?? this.offsets,
        scales: scales ?? this.scales,
      );
}
