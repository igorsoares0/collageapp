import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
// `show`: a bare import would clash with the app's own model `Layer`.
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/widgets.dart';

import '../model/template.dart';

/// Captures the RepaintBoundary identified by [boundaryKey] as a PNG that is
/// [targetWidth] physical pixels wide (template space, e.g. 1080), regardless
/// of how small the canvas is rendered on screen: the pixelRatio compensates
/// for the boundary's logical size, so the export is always full resolution.
///
/// The boundary must be the TEMPLATE-UNIT canvas box (PanelCanvas.exportKey,
/// inside the FittedBox — toImage captures the boundary's local subtree, so
/// the ancestor scale never matters). A boundary outside the FittedBox has
/// the letterbox bands inside it whenever its box doesn't match the canvas
/// aspect, and the artwork exports smaller than [targetWidth].
Future<Uint8List> capturePng(GlobalKey boundaryKey, double targetWidth) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(
    pixelRatio: targetWidth / boundary.size.width,
  );
  try {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Crops [region] (in [source]'s own pixel space) into a new image.
///
/// RepaintBoundary.toImage can only capture a boundary WHOLE, so slicing a
/// continuous canvas means capturing it once and cropping here. Pure dart:ui —
/// GPU-backed and exact, with no image-decoding package involved.
///
/// The caller owns [source]; the returned image is the caller's to dispose.
Future<ui.Image> capturePngRegion(ui.Image source, Rect region) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
    source,
    region,
    Rect.fromLTWH(0, 0, region.width, region.height),
    Paint()..filterQuality = FilterQuality.high,
  );
  return recorder.endRecording().toImage(
    region.width.round(),
    region.height.round(),
  );
}

/// Exports a v4 continuous canvas as one PNG per slide (Modelo B).
///
/// [boundaryKey] must be a [CanvasView] export boundary — the whole document in
/// template units. The document is rastered ONCE and sliced, so the seams line
/// up by construction: adjacent slides are literally neighbouring pixels of the
/// same image. The panel model could only approximate that by eyeballing a
/// bleed across two independently exported canvases.
///
/// Each PNG is [targetSlideWidth] physical pixels wide, defaulting to the
/// document's own slide width (full authored resolution).
///
/// Memory: the intermediate raster is the WHOLE document — roughly 25 MB of
/// RGBA for 3x1080x1920, ~83 MB for ten slides. It is transient and disposed as
/// soon as the slices are cut.
Future<List<Uint8List>> capturePngSlices(
  GlobalKey boundaryKey,
  Document document, {
  double? targetSlideWidth,
}) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final target = targetSlideWidth ?? document.slideWidth;
  // The boundary is the document box in template units, so capturing at the
  // per-slide ratio makes every slice exactly `target` px wide.
  final ratio = target / document.slideWidth;
  final full = await boundary.toImage(pixelRatio: ratio);

  try {
    final slices = <Uint8List>[];
    for (var i = 0; i < document.slideCount; i++) {
      final rect = document.slideRect(i);
      // Crop rects live in the CAPTURED image's pixel space, so they scale by
      // the same ratio the capture used.
      final slice = await capturePngRegion(
        full,
        Rect.fromLTWH(
          rect.left * ratio,
          rect.top * ratio,
          rect.width * ratio,
          rect.height * ratio,
        ),
      );
      try {
        final bytes = await slice.toByteData(format: ui.ImageByteFormat.png);
        slices.add(bytes!.buffer.asUint8List());
      } finally {
        slice.dispose();
      }
    }
    return slices;
  } finally {
    full.dispose();
  }
}
