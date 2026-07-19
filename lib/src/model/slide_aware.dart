import 'dart:math' as math;

import 'template.dart';

/// The slide-aware layer over the v4 continuous canvas (Modelo B).
/// See docs/model-b-migration.md.
///
/// These are PURE DERIVATIONS. A layer never carries a slide index: which slide
/// it belongs to is computed from its geometry every time. That is the contract
/// that keeps the continuous canvas a superset — a panorama (one layer crossing
/// cuts) and independent pages (nothing crossing) live in the same [Document.layers].
///
/// Mirrored verbatim in the editor (lib/template/continuous.ts) so both sides
/// agree on where a slide ends.

/// A right edge lands exactly on the next slide's origin (x == slideWidth with
/// no gutter), which would read as "spans two slides". Treat the edge as
/// exclusive.
const double _edgeEpsilon = 1e-6;

/// Horizontal placement of any layer. Every variant carries x and width (a
/// [TextLayer] has no height, but it does have a width), so this is total.
({double x, double width}) layerSpanX(Layer layer) => switch (layer) {
  ImageLayer l => (x: l.x, width: l.width),
  TextLayer l => (x: l.x, width: l.width),
  ShapeLayer l => (x: l.x, width: l.width),
  StickerLayer l => (x: l.x, width: l.width),
  GridLayer l => (x: l.x, width: l.width),
};

extension SlideAware on Document {
  /// Distance from one slide's origin to the next.
  double get slidePitch => slideWidth + gutter;

  /// Which slide a point falls in, clamped to the document.
  int slideIndexAtX(double x) {
    final pitch = slidePitch;
    if (pitch <= 0) return 0;
    final raw = (x / pitch).floor();
    return raw.clamp(0, math.max(0, slideCount - 1));
  }

  /// The slide a layer BELONGS to, decided by its centre. Used for
  /// slide-scoped operations (reorder as a group, delete a slide's content) —
  /// a layer that merely spills over a cut still belongs to the slide holding
  /// most of it.
  int slideOf(Layer layer) {
    final span = layerSpanX(layer);
    return slideIndexAtX(span.x + span.width / 2);
  }

  /// The layers belonging to slide [i] — "page i" as a movable group.
  List<Layer> layersInSlide(int i) => [
    for (final l in layers)
      if (slideOf(l) == i) l,
  ];

  /// True when a layer actually crosses a cut line (a real panorama element).
  /// Reorder/delete must never silently tear one of these — the UI warns.
  bool spansSlides(Layer layer) {
    final span = layerSpanX(layer);
    final right = math.max(span.x, span.x + span.width - _edgeEpsilon);
    return slideIndexAtX(span.x) != slideIndexAtX(right);
  }
}
