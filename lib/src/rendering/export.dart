import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Captures the RepaintBoundary identified by [boundaryKey] as a PNG that is
/// [targetWidth] physical pixels wide (template space, e.g. 1080), regardless
/// of how small the canvas is rendered on screen: the pixelRatio compensates
/// for the FittedBox scale, so the export is always full resolution.
Future<Uint8List> capturePng(GlobalKey boundaryKey, double targetWidth) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image =
      await boundary.toImage(pixelRatio: targetWidth / boundary.size.width);
  try {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
