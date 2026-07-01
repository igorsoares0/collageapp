import 'package:flutter/widgets.dart';

import '../model/asset_record.dart';

/// A photo frame (polaroid, etc.): a bundled PNG with a transparent window the
/// user's photo shows through. Mirrors the editor's FRAME_ASSETS catalog
/// (collageweb/lib/template/factory.ts) — the window rectangles are measured
/// from the same source PNGs, in normalized (0..1) frame coordinates.
///
/// The frame image is stretched to fill the whole image-slot box (its aspect
/// matches the layer's, which the editor snaps on apply), so its transparent
/// window lands exactly on [windowIn]; the photo is drawn/clipped there and the
/// frame paints over the top.
class FrameAsset {
  final String id;
  final String asset;
  final double aspect; // frame image width / height
  final double winX, winY, winW, winH;

  const FrameAsset({
    required this.id,
    required this.asset,
    required this.aspect,
    required this.winX,
    required this.winY,
    required this.winW,
    required this.winH,
  });

  /// The transparent window as a pixel rect inside a [w]×[h] slot box.
  Rect windowIn(double w, double h) =>
      Rect.fromLTWH(winX * w, winY * h, winW * w, winH * h);
}

const List<FrameAsset> kFrameAssets = [
  FrameAsset(
    id: 'frame_polaroid_v',
    asset: 'assets/frames/pol-vert.png',
    aspect: 1424 / 2010,
    winX: 0.0492,
    winY: 0.0244,
    winW: 0.9024,
    winH: 0.8199,
  ),
  FrameAsset(
    id: 'frame_polaroid_h',
    asset: 'assets/frames/pol-hor.png',
    aspect: 2039 / 2010,
    winX: 0.0387,
    winY: 0.0244,
    winW: 0.9201,
    winH: 0.8214,
  ),
  FrameAsset(
    id: 'frame_quad',
    asset: 'assets/frames/quad.png',
    aspect: 1424 / 2010,
    winX: 0.0344,
    winY: 0.0244,
    winW: 0.9298,
    winH: 0.9468,
  ),
];

final Map<String, FrameAsset> _byId = {for (final f in kFrameAssets) f.id: f};

/// The seed frame for [id], or null when unset/unknown.
FrameAsset? frameAsset(String? id) => id == null ? null : _byId[id];

/// A frame ready to render, whatever its source. Seeds (bundled assets) and
/// uploaded catalog frames (base64 → MemoryImage) collapse to the same shape so
/// [_ImageSlot] doesn't care which it is.
class ResolvedFrame {
  final ImageProvider image;
  final double aspect;
  final double winX, winY, winW, winH;

  const ResolvedFrame({
    required this.image,
    required this.aspect,
    required this.winX,
    required this.winY,
    required this.winW,
    required this.winH,
  });

  Rect windowIn(double w, double h) =>
      Rect.fromLTWH(winX * w, winY * h, winW * w, winH * h);
}

/// Resolves [id] against the bundled seeds first (so older templates and the
/// offline path keep working), then the remote [catalog]. Null when unset or
/// unknown — the slot then draws a bare photo (the field is additive).
ResolvedFrame? resolveFrame(String? id, List<AssetRecord> catalog) {
  if (id == null) return null;
  final seed = _byId[id];
  if (seed != null) {
    return ResolvedFrame(
      image: AssetImage(seed.asset),
      aspect: seed.aspect,
      winX: seed.winX,
      winY: seed.winY,
      winW: seed.winW,
      winH: seed.winH,
    );
  }
  for (final a in catalog) {
    if (a.id == id && a.type == 'frame' && a.window != null) {
      final win = a.window!;
      return ResolvedFrame(
        image: a.image,
        aspect: a.aspect,
        winX: win.x,
        winY: win.y,
        winW: win.w,
        winH: win.h,
      );
    }
  }
  return null;
}
