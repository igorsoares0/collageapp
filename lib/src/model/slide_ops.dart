import 'dart:ui';

import 'migrate_v4.dart' show translateLayerX;
import 'slide_aware.dart';
import 'template.dart';

/// Slide management on the continuous canvas (Modelo B, phase 4a).
///
/// This is the half of the slide-aware layer that MUTATES. The derivations in
/// slide_aware.dart answer "which slide is this in?"; these answer "move that
/// slide". They live apart from slide_aware.dart on purpose: those derivations
/// are mirrored byte-for-byte with the editor's continuous.ts and guarded by
/// the parity contract, while these operations are app-side only.
///
/// The rule throughout: a layer that CROSSES a cut line belongs to no single
/// slide, so slide-scoped operations leave it alone rather than tearing it.
/// Callers surface that to the user ("this element crosses slides") instead of
/// silently mangling a panorama — see [spanningLayers].

/// Layers that cross a cut line, and so cannot move with any one slide.
/// A caller about to reorder or delete should warn when this is non-empty.
List<Layer> spanningLayers(Document doc) => [
  for (final l in doc.layers)
    if (doc.spansSlides(l)) l,
];

Document _rebuild(
  Document doc, {
  required int slideCount,
  required List<Color> slideBackgrounds,
  required List<Layer> layers,
}) => Document(
  id: doc.id,
  schemaVersion: doc.schemaVersion,
  version: doc.version,
  name: doc.name,
  aspectRatio: doc.aspectRatio,
  slideWidth: doc.slideWidth,
  slideHeight: doc.slideHeight,
  slideCount: slideCount,
  gutter: doc.gutter,
  slideBackgrounds: slideBackgrounds,
  layers: layers,
);

/// Inserts an empty slide at [at] (defaults to the end).
///
/// Everything from [at] onward shifts one pitch to the right; nothing else
/// moves, so appending — the common case — reflows nothing at all.
Document addSlide(
  Document doc, {
  int? at,
  Color background = const Color(0xFFFFFFFF),
}) {
  final index = (at ?? doc.slideCount).clamp(0, doc.slideCount);
  final pitch = doc.slidePitch;

  final layers = [
    for (final layer in doc.layers)
      if (doc.spansSlides(layer) || doc.slideOf(layer) < index)
        layer
      else
        translateLayerX(layer, pitch),
  ];

  final backgrounds = [...doc.slideBackgrounds]
    ..insert(index.clamp(0, doc.slideBackgrounds.length), background);

  return _rebuild(
    doc,
    slideCount: doc.slideCount + 1,
    slideBackgrounds: backgrounds,
    layers: layers,
  );
}

/// Deletes slide [index] together with the layers that belong to it, pulling
/// every later slide one pitch left.
///
/// Refuses to empty the document: removing the last remaining slide returns
/// [doc] unchanged, since a document with zero slides has nothing to render.
Document removeSlide(Document doc, int index) {
  if (doc.slideCount <= 1) return doc;
  if (index < 0 || index >= doc.slideCount) return doc;
  final pitch = doc.slidePitch;

  final layers = <Layer>[];
  for (final layer in doc.layers) {
    // A spanning layer belongs to no slide; it survives and stays put, so a
    // panorama is never silently cut in half by a slide delete.
    if (doc.spansSlides(layer)) {
      layers.add(layer);
      continue;
    }
    final slide = doc.slideOf(layer);
    if (slide == index) continue; // deleted along with its slide
    layers.add(slide > index ? translateLayerX(layer, -pitch) : layer);
  }

  final backgrounds = [...doc.slideBackgrounds];
  if (index < backgrounds.length) backgrounds.removeAt(index);

  return _rebuild(
    doc,
    slideCount: doc.slideCount - 1,
    slideBackgrounds: backgrounds,
    layers: layers,
  );
}

/// Moves slide [from] to position [to], carrying its layers as a group.
///
/// This is what makes "independent pages" feel native on a continuous canvas:
/// the user reorders a slide and its content follows, exactly as reordering a
/// panel used to. Layers crossing a cut stay where they are — see the file
/// comment.
Document reorderSlide(Document doc, int from, int to) {
  if (from == to) return doc;
  if (from < 0 || from >= doc.slideCount) return doc;
  if (to < 0 || to >= doc.slideCount) return doc;

  // order[newIndex] == oldIndex
  final order = [for (var i = 0; i < doc.slideCount; i++) i]
    ..removeAt(from)
    ..insert(to, from);
  final newIndexOf = {
    for (var newIndex = 0; newIndex < order.length; newIndex++)
      order[newIndex]: newIndex,
  };
  final pitch = doc.slidePitch;

  final layers = [
    for (final layer in doc.layers)
      if (doc.spansSlides(layer))
        layer
      else
        () {
          final old = doc.slideOf(layer);
          final shift = (newIndexOf[old]! - old) * pitch;
          return shift == 0 ? layer : translateLayerX(layer, shift);
        }(),
  ];

  final backgrounds = [
    for (final old in order)
      old < doc.slideBackgrounds.length
          ? doc.slideBackgrounds[old]
          : const Color(0xFFFFFFFF),
  ];

  return _rebuild(
    doc,
    slideCount: doc.slideCount,
    slideBackgrounds: backgrounds,
    layers: layers,
  );
}

/// Repaints slide [index].
Document setSlideBackground(Document doc, int index, Color color) {
  if (index < 0 || index >= doc.slideCount) return doc;
  final backgrounds = [
    for (var i = 0; i < doc.slideCount; i++)
      i == index ? color : doc.backgroundFor(i),
  ];
  return _rebuild(
    doc,
    slideCount: doc.slideCount,
    slideBackgrounds: backgrounds,
    layers: doc.layers,
  );
}

/// Removes the layer with [layerId], if present.
Document removeLayer(Document doc, String layerId) => _rebuild(
  doc,
  slideCount: doc.slideCount,
  slideBackgrounds: doc.slideBackgrounds,
  layers: [
    for (final l in doc.layers)
      if (l.id != layerId) l,
  ],
);

/// Appends [layer] exactly where it already is.
///
/// For layers whose x is ALREADY in continuous space — duplicating an existing
/// element, or anything derived from one. Using [addLayerToSlide] for those
/// would add the slide offset a second time and fling the copy off to the right.
Document appendLayer(Document doc, Layer layer) => _rebuild(
  doc,
  slideCount: doc.slideCount,
  slideBackgrounds: doc.slideBackgrounds,
  layers: [...doc.layers, layer],
);

/// Restacks slide [slide]'s layers into [orderedIds] (index 0 = bottom).
///
/// On the continuous canvas the list order IS the stack order, so a reorder is
/// a permutation of [Document.layers] — NOT an override kept beside them. (The
/// panel model's SlotContent.layerOrders is the v3 mechanism; migrate_v4 bakes
/// it into this list and it has no effect here.)
///
/// Only the positions this slide's layers already occupy are rewritten, so the
/// document's cross-slide order is untouched — a slide's stack is a local
/// concern, and slides don't overlap on screen anyway. Ids [orderedIds] omits
/// keep their natural order at the top, so a stale list can never drop a layer.
Document reorderLayersInSlide(
  Document doc,
  int slide,
  List<String> orderedIds,
) {
  final mine = doc.layersInSlide(slide);
  if (mine.isEmpty) return doc;
  final pending = {for (final l in mine) l.id: l};
  final restacked = <Layer>[
    for (final id in orderedIds)
      if (pending.remove(id) case final layer?) layer,
  ];
  for (final layer in mine) {
    if (pending.containsKey(layer.id)) restacked.add(layer);
  }

  final layers = [...doc.layers];
  var next = 0;
  for (var i = 0; i < layers.length; i++) {
    if (doc.slideOf(layers[i]) == slide) layers[i] = restacked[next++];
  }
  return _rebuild(
    doc,
    slideCount: doc.slideCount,
    slideBackgrounds: doc.slideBackgrounds,
    layers: layers,
  );
}

/// Appends [layer] to the document, positioning it relative to slide [slide].
///
/// The layer arrives in SLIDE-LOCAL coordinates (what an "add at x=100 of this
/// slide" caller naturally has) and is placed into continuous space here, so
/// callers never do pitch arithmetic themselves.
Document addLayerToSlide(Document doc, int slide, Layer layer) {
  final index = slide.clamp(0, doc.slideCount - 1);
  return _rebuild(
    doc,
    slideCount: doc.slideCount,
    slideBackgrounds: doc.slideBackgrounds,
    // Appended last: index 0 is the bottom of the stack, so a new element
    // lands on top, matching the panel model's addedLayers behaviour.
    layers: [...doc.layers, translateLayerX(layer, index * doc.slidePitch)],
  );
}
