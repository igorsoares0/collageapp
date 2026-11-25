import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// The user's appearance choice — System, Light or Dark — and its
/// persistence. Owned by `main()`, read by MaterialApp (`themeMode`) and
/// changed from Settings.
///
/// Stored as one word in a tiny file in app support (same place as the
/// template cache, no extra dependency). Any read or write failure falls back
/// to [ThemeMode.system]: the appearance is a preference, never a reason for
/// the app not to start.
class AppearanceController extends ValueNotifier<ThemeMode> {
  /// Injectable for tests; the app uses app-support/appearance.
  final Directory? dirOverride;

  AppearanceController({this.dirOverride, ThemeMode initial = ThemeMode.system})
    : super(initial);

  Future<File> _file() async {
    final dir = dirOverride ?? await getApplicationSupportDirectory();
    return File('${dir.path}/appearance');
  }

  /// Reads the saved choice (if any) into [value].
  Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      value = _parse((await file.readAsString()).trim());
    } catch (_) {
      // Keep the default.
    }
  }

  /// Applies [mode] right away and saves it for the next launch.
  Future<void> set(ThemeMode mode) async {
    value = mode;
    try {
      await (await _file()).writeAsString(mode.name, flush: true);
    } catch (_) {
      // Applied for this session; the next launch falls back to system.
    }
  }

  static ThemeMode _parse(String raw) => ThemeMode.values.firstWhere(
    (m) => m.name == raw,
    orElse: () => ThemeMode.system,
  );
}
