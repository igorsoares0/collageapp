import 'package:flutter/widgets.dart';

/// User content injected into template slots (spec §12). Templates never
/// contain user content; this map is the app-side counterpart of slotIds.
/// [offsets] are user position adjustments in template space — the template
/// itself stays immutable, the tweak travels with the user's content.
class SlotContent {
  final Map<String, String> texts;
  final Map<String, ImageProvider> images;
  final Map<String, Offset> offsets;

  const SlotContent({
    this.texts = const {},
    this.images = const {},
    this.offsets = const {},
  });

  String? textFor(String slotId) => texts[slotId];
  ImageProvider? imageFor(String slotId) => images[slotId];
  Offset offsetFor(String slotId) => offsets[slotId] ?? Offset.zero;

  SlotContent withText(String slotId, String value) => SlotContent(
        texts: {...texts, slotId: value},
        images: images,
        offsets: offsets,
      );

  SlotContent withImage(String slotId, ImageProvider value) => SlotContent(
        texts: texts,
        images: {...images, slotId: value},
        offsets: offsets,
      );

  SlotContent withOffset(String slotId, Offset value) => SlotContent(
        texts: texts,
        images: images,
        offsets: {...offsets, slotId: value},
      );
}
