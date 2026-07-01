import 'dart:convert';

import 'package:flutter/widgets.dart';

/// A frame's transparent window in normalized (0..1) image coords — mirrors the
/// editor's FrameWindow.
class FrameWindow {
  final double x, y, w, h;

  const FrameWindow({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  factory FrameWindow.fromJson(Map<String, dynamic> j) => FrameWindow(
    x: (j['x'] as num).toDouble(),
    y: (j['y'] as num).toDouble(),
    w: (j['w'] as num).toDouble(),
    h: (j['h'] as num).toDouble(),
  );
}

/// A catalog asset fetched from /api/assets (a frame or sticker uploaded in the
/// editor). The PNG arrives inline as a base64 data URL; [image] decodes it once
/// (memoized) so rebuilds don't thrash the image cache. Stickers carry a null
/// [window].
class AssetRecord {
  final String id;
  final String type;
  final String name;
  final String dataUrl;
  final double aspect;
  final FrameWindow? window;

  AssetRecord({
    required this.id,
    required this.type,
    required this.name,
    required this.dataUrl,
    required this.aspect,
    required this.window,
  });

  factory AssetRecord.fromJson(Map<String, dynamic> j) => AssetRecord(
    id: j['id'] as String,
    type: j['type'] as String,
    name: j['name'] as String,
    dataUrl: j['dataUrl'] as String,
    aspect: (j['aspect'] as num).toDouble(),
    window: j['window'] == null
        ? null
        : FrameWindow.fromJson(j['window'] as Map<String, dynamic>),
  );

  ImageProvider? _image;

  /// Decodes the base64 data URL once and caches the provider.
  ImageProvider get image => _image ??= MemoryImage(
    base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1)),
  );
}
