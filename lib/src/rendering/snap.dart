import 'dart:ui';

/// Magnetic alignment for dragging elements (the Canva-style smart guides).
///
/// The caller accumulates the RAW (unsnapped) drag offset for the gesture and
/// asks [snapDrag] where the element should actually land: if one of its snap
/// points (edges/center) falls within [threshold] of a guide position, the
/// offset is corrected so the element sits exactly on the guide, and that
/// guide's position is reported so the canvas can draw the line. Tracking the
/// raw offset outside is what lets the element escape a guide: the snapped
/// position never feeds back into the gesture.

/// The best single-axis correction: the smallest |target − point| within
/// [threshold] over all combinations. [shift] moves the points onto [guide];
/// both are 0/null when nothing is in range.
({double shift, double? guide}) snapAxis({
  required List<double> points,
  required List<double> targets,
  required double threshold,
}) {
  var best = double.infinity;
  var shift = 0.0;
  double? guide;
  for (final p in points) {
    for (final t in targets) {
      final d = t - p;
      if (d.abs() <= threshold && d.abs() < best) {
        best = d.abs();
        shift = d;
        guide = t;
      }
    }
  }
  return (shift: shift, guide: guide);
}

/// Snaps a dragged element to the canvas edges/center and to other elements'
/// edges/centers.
///
/// [box] is the element's unrotated layout box in template units; its painted
/// bounds are the box scaled by [scale] around its center and shifted by the
/// user offset. [raw] is the accumulated unsnapped offset for this gesture.
/// [others] are the painted bounds of the panel's other (unrotated) elements.
/// [snapEdges] is false when the element carries a user rotation — its painted
/// edges no longer match the axis-aligned box, but the center (the rotation
/// pivot) still does, so center guides stay available.
///
/// Returns the corrected offset plus the matched guide positions (at most one
/// per axis) in template units.
({Offset offset, List<double> guideXs, List<double> guideYs}) snapDrag({
  required Rect box,
  required double scale,
  required Offset raw,
  required Size canvas,
  required List<Rect> others,
  required double threshold,
  required bool snapEdges,
}) {
  final center = box.center + raw;
  final halfW = box.width * scale / 2;
  final halfH = box.height * scale / 2;

  final pointsX = snapEdges
      ? [center.dx - halfW, center.dx, center.dx + halfW]
      : [center.dx];
  final pointsY = snapEdges
      ? [center.dy - halfH, center.dy, center.dy + halfH]
      : [center.dy];

  final targetsX = [
    0.0,
    canvas.width / 2,
    canvas.width,
    for (final r in others) ...[r.left, r.center.dx, r.right],
  ];
  final targetsY = [
    0.0,
    canvas.height / 2,
    canvas.height,
    for (final r in others) ...[r.top, r.center.dy, r.bottom],
  ];

  final x = snapAxis(points: pointsX, targets: targetsX, threshold: threshold);
  final y = snapAxis(points: pointsY, targets: targetsY, threshold: threshold);

  return (
    offset: raw + Offset(x.shift, y.shift),
    guideXs: [if (x.guide != null) x.guide!],
    guideYs: [if (y.guide != null) y.guide!],
  );
}

/// Snaps a rotation gesture's RAW angle to the nearest multiple of [step]
/// (0°, 45°, 90°, …) when within [reach]. Stateless on purpose: the raw
/// angle arrives every frame, so the element locks onto straight angles and
/// escapes the moment the raw angle leaves the reach.
double snapRotation(double degrees, {double step = 45, double reach = 5}) {
  final nearest = (degrees / step).round() * step;
  return (degrees - nearest).abs() <= reach ? nearest.toDouble() : degrees;
}
