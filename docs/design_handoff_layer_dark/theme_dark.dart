// Dark theme for Collage Studio "Folio". Add to lib/src/theme.dart next to the
// existing light theme (which already defines AppType and buildAppTheme()).
// Wire up: MaterialApp(theme: buildAppTheme(), darkTheme: buildAppDarkTheme(), themeMode: ThemeMode.system)
import 'package:flutter/material.dart';
import 'theme.dart';

// Dark tokens — same roles, swapped values.
abstract final class AppColorsDark {
  static const paper = Color(0xFF171512);
  static const paperDeep = Color(0xFF211E1A);
  static const table = Color(0xFF0D0C0B);
  static const rule = Color(0xFF36312B);
  static const ruleStrong = Color(0xFF4C463F);
  static const stone = Color(0xFF7D7468);
  static const inkMuted = Color(0xFF9E9487);
  static const inkSoft = Color(0xFFB4AA9C);
  static const ink = Color(0xFFEEE7DB);
  static const rouge = Color(0xFFD0756A);
  static const onInk = paper;
  static const disabledIcon = Color(0xFF5C554C);
  static const scrim = Color(0x9E000000);
}

// Minimal dark theme: reuse buildAppTheme() and swap colours. For full parity,
// refactor AppType/buildAppTheme to take a palette parameter.
ThemeData buildAppDarkTheme() {
  final light = buildAppTheme();
  const c = AppColorsDark;
  const square = RoundedRectangleBorder(borderRadius: BorderRadius.zero);
  return light.copyWith(
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: c.ink, onPrimary: c.onInk, secondary: c.rouge, onSecondary: c.onInk,
      tertiary: c.rouge, onTertiary: c.onInk, surface: c.paper, onSurface: c.ink,
      onSurfaceVariant: c.inkSoft, surfaceContainer: c.paperDeep, surfaceContainerHigh: c.paperDeep,
      surfaceContainerHighest: c.table, outline: c.rule, outlineVariant: c.rule, error: c.rouge,
    ),
    scaffoldBackgroundColor: c.paper,
    textTheme: light.textTheme.apply(bodyColor: c.ink, displayColor: c.ink),
    appBarTheme: light.appBarTheme.copyWith(backgroundColor: c.paper, foregroundColor: c.ink,
      titleTextStyle: AppType.eyebrow.copyWith(color: c.ink)),
    iconTheme: const IconThemeData(color: c.ink, size: 24, weight: 200),
    filledButtonTheme: FilledButtonThemeData(style: light.filledButtonTheme.style!.copyWith(
      backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? c.rule : c.ink),
      foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? c.inkSoft : c.onInk),
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(style: light.outlinedButtonTheme.style!.copyWith(
      foregroundColor: const WidgetStatePropertyAll(c.ink),
      side: const WidgetStatePropertyAll(BorderSide(color: c.ink)),
    )),
    bottomSheetTheme: light.bottomSheetTheme.copyWith(backgroundColor: c.paper, modalBackgroundColor: c.paper,
      modalBarrierColor: c.scrim, shape: const Border(top: BorderSide(color: c.ink))),
    snackBarTheme: light.snackBarTheme.copyWith(backgroundColor: c.ink, actionTextColor: c.rule,
      contentTextStyle: light.snackBarTheme.contentTextStyle?.copyWith(color: c.onInk), shape: square),
    dialogTheme: light.dialogTheme.copyWith(backgroundColor: c.paperDeep),
    sliderTheme: light.sliderTheme.copyWith(activeTrackColor: c.ink, inactiveTrackColor: c.ink, thumbColor: c.ink),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: c.ink, linearTrackColor: c.rule, linearMinHeight: 3),
    dividerTheme: const DividerThemeData(color: c.rule, thickness: 1, space: 1),
    listTileTheme: light.listTileTheme.copyWith(iconColor: c.ink, textColor: c.ink),
    highlightColor: c.ink.withValues(alpha: .08),
  );
}
