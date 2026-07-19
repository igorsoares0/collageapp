import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:gal/gal.dart';

/// Writes PNG bytes to the device photo gallery.
///
/// On Android the write goes through a native MethodChannel (see
/// MainActivity.kt) that stamps an explicit DATE_TAKEN, so a burst of carousel
/// panels keeps a deterministic chronological order no matter how the gallery
/// app sorts — gal can't set the timestamp, which is why the panels needed
/// wall-clock spacing before. Everywhere else falls back to gal (the timestamp
/// hint is ignored there).
class GallerySaver {
  static const _channel = MethodChannel('studio.collage.collageapp/gallery');

  static Future<void> save(
    Uint8List bytes, {
    required String name,
    DateTime? dateTaken,
  }) async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('saveImage', {
        'bytes': bytes,
        'name': name,
        'dateTakenMillis':
            (dateTaken ?? DateTime.now()).millisecondsSinceEpoch,
      });
      return;
    }
    await Gal.putImageBytes(bytes, name: name);
  }
}
