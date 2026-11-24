import 'dart:ui';

import 'slide_aware.dart';
import 'template.dart';

/// One place a photo goes: a plain image element or one cell of a grid, with
/// its box in the document's continuous coordinates.
class PhotoSlot {
  final String slotId;
  final Rect rect;
  final int slide;

  const PhotoSlot({
    required this.slotId,
    required this.rect,
    required this.slide,
  });
}

/// Every photo slot of [doc] in FILL ORDER — the order "Add N photos" fills
/// them and the numbers the editor paints on empty frames: slide by slide,
/// then top to bottom, then left to right (reading order). Hidden layers are
/// skipped; grid cells count individually.
///
/// Rows are compared with a small tolerance so two frames whose tops differ
/// by a hair still read left-to-right instead of flipping on the pixel.
List<PhotoSlot> imageSlotsInFillOrder(Document doc) {
  final slots = <PhotoSlot>[];
  for (final layer in doc.layers) {
    if (layer.hidden) continue;
    switch (layer) {
      case ImageLayer l:
        final rect = Rect.fromLTWH(l.x, l.y, l.width, l.height);
        slots.add(
          PhotoSlot(
            slotId: l.slotId,
            rect: rect,
            slide: doc.slideIndexAtX(rect.center.dx),
          ),
        );
      case GridLayer g:
        for (final cell in g.cells) {
          final rect = _cellRect(g, cell);
          slots.add(
            PhotoSlot(
              slotId: cell.slotId,
              rect: rect,
              slide: doc.slideIndexAtX(rect.center.dx),
            ),
          );
        }
      default:
    }
  }
  final tolerance = doc.slideHeight * 0.02;
  slots.sort((a, b) {
    if (a.slide != b.slide) return a.slide.compareTo(b.slide);
    final dy = a.rect.top - b.rect.top;
    if (dy.abs() > tolerance) return dy.sign.toInt();
    return a.rect.left.compareTo(b.rect.left);
  });
  return slots;
}

/// Slot id → 1-based fill number, for the editor's numbered placeholders.
Map<String, int> fillNumbers(Document doc) => {
  for (final (i, s) in imageSlotsInFillOrder(doc).indexed) s.slotId: i + 1,
};

/// The photo slots with LIGHT text set over them — their empty placeholder
/// reads as a dark frame so that text stays legible before a photo lands.
Set<String> slotsUnderLightText(Document doc) {
  final light = <String>{};
  final texts = [
    for (final l in doc.layers)
      if (l is TextLayer && !l.hidden && l.color.computeLuminance() > 0.5) l,
  ];
  if (texts.isEmpty) return light;
  for (final slot in imageSlotsInFillOrder(doc)) {
    for (final t in texts) {
      final anchor = Offset(t.x + t.width / 2, t.y + t.fontSize / 2);
      if (slot.rect.contains(anchor)) {
        light.add(slot.slotId);
        break;
      }
    }
  }
  return light;
}

Rect _cellRect(GridLayer g, GridCell cell) {
  List<double> fractions(List<double> f, int n) {
    if (f.length == n && f.every((v) => v > 0)) {
      final sum = f.fold<double>(0, (a, b) => a + b);
      return [for (final v in f) v / sum];
    }
    return List.filled(n, n == 0 ? 0 : 1 / n);
  }

  final cols = fractions(g.colFractions, g.cols);
  final rows = fractions(g.rowFractions, g.rows);
  double start(List<double> f, int i) =>
      f.take(i.clamp(0, f.length)).fold<double>(0, (a, b) => a + b);
  double span(List<double> f, int i, int n) =>
      f.skip(i.clamp(0, f.length)).take(n).fold<double>(0, (a, b) => a + b);

  return Rect.fromLTWH(
    g.x + start(cols, cell.col) * g.width,
    g.y + start(rows, cell.row) * g.height,
    span(cols, cell.col, cell.colSpan) * g.width,
    span(rows, cell.row, cell.rowSpan) * g.height,
  );
}
