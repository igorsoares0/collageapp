// "Folio" design tokens — starting point for lib/src/theme.dart.
// Same public surface as the current file (AppColors + buildAppTheme) so the
// screens keep compiling; names that no longer fit are kept as aliases.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppColors {
  static const paper = Color(0xFFF3EEE5);
  static const paperDeep = Color(0xFFEAE3D7);
  static const table = Color(0xFFE4DCCF);
  static const rule = Color(0xFFCFC5B5);
  static const ruleStrong = Color(0xFFA89D8D);
  static const stone = Color(0xFF8A8073);
  static const inkMuted = Color(0xFF6F665C);
  static const inkSoft = Color(0xFF5E564C);
  static const ink = Color(0xFF1E1B17);
  static const rouge = Color(0xFF7B2D26);
  static const onInk = paper;
  static const disabledIcon = Color(0xFFB5AB9C);
  static const scrim = Color(0x6B1E1B17);

  // Aliases for existing call sites.
  static const surface = paper;
  static const surfaceHigh = paperDeep;
  static const surfaceBright = rule;
  static const outline = rule;
  static const textPrimary = ink;
  static const textSecondary = inkSoft;
  static const accent = ink; // action
  static const onAccent = onInk;
  static const gold = rouge; // premium signal now rouge
  static const onGold = onInk;
  static const danger = rouge;
}

abstract final class AppSpace {
  static const s4 = 4.0, s8 = 8.0, s12 = 12.0, s16 = 16.0, s20 = 20.0,
      s24 = 24.0, s32 = 32.0, s48 = 48.0, s64 = 64.0;
  static const margin = 20.0;
  static const gutter = 10.0;
  static const minTarget = 44.0;
}

TextStyle _serif(double size, {double height = 1.0, double tracking = 0, bool italic = false, FontWeight w = FontWeight.w400}) {
  final base = TextStyle(fontSize: size, height: height, letterSpacing: size * tracking, fontStyle: italic ? FontStyle.italic : FontStyle.normal, fontWeight: w, color: AppColors.ink);
  try { return GoogleFonts.newsreader(textStyle: base); } catch (_) { return base; }
}

TextStyle _sans(double size, {double height = 1.4, double tracking = 0, FontWeight w = FontWeight.w400, Color color = AppColors.ink}) {
  final base = TextStyle(fontSize: size, height: height, letterSpacing: size * tracking, fontWeight: w, color: color);
  try { return GoogleFonts.instrumentSans(textStyle: base); } catch (_) { return base; }
}

abstract final class AppType {
  static final display = _serif(44, height: .98, tracking: -.025);
  static final headlineL = _serif(46, height: .95, tracking: -.025);
  static final headline = _serif(40, height: .95, tracking: -.02);
  static final title = _serif(24, height: 1.05, tracking: -.015);
  static final captionTitle = _serif(18, height: 1.1);
  static final category = _serif(24);
  static TextStyle numeral(double size) => _serif(size, italic: true, tracking: -.02);
  static final body = _sans(15, height: 22 / 15);
  static final bodyS = _sans(13.5, height: 1.5, color: AppColors.inkSoft);
  static final label = _sans(15, w: FontWeight.w500);
  static final labelS = _sans(13, w: FontWeight.w500);
  static final caption = _sans(12, color: AppColors.inkSoft);
  static final eyebrow = _sans(11.5, height: 1.2, tracking: .16, w: FontWeight.w600);
  static final navLabel = _sans(11, tracking: .04, w: FontWeight.w600);
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.light(
    primary: AppColors.ink, onPrimary: AppColors.onInk,
    secondary: AppColors.rouge, onSecondary: AppColors.onInk,
    tertiary: AppColors.rouge, onTertiary: AppColors.onInk,
    surface: AppColors.paper, onSurface: AppColors.ink, onSurfaceVariant: AppColors.inkSoft,
    surfaceContainerLowest: AppColors.paper, surfaceContainerLow: AppColors.paper,
    surfaceContainer: AppColors.paperDeep, surfaceContainerHigh: AppColors.paperDeep,
    surfaceContainerHighest: AppColors.table,
    outline: AppColors.rule, outlineVariant: AppColors.rule, error: AppColors.rouge,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  TextTheme t;
  try { t = GoogleFonts.instrumentSansTextTheme(base.textTheme); } catch (_) { t = base.textTheme; }
  t = t.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink).copyWith(
    displayLarge: AppType.display, displayMedium: AppType.headlineL, displaySmall: AppType.headline,
    headlineLarge: AppType.headline, headlineMedium: AppType.title, headlineSmall: AppType.captionTitle,
    titleLarge: _serif(20, height: 1.1), bodyLarge: AppType.body, bodyMedium: _sans(14),
    labelLarge: AppType.label, labelSmall: AppType.eyebrow,
  );
  const square = RoundedRectangleBorder(borderRadius: BorderRadius.zero);
  return base.copyWith(
    textTheme: t,
    scaffoldBackgroundColor: AppColors.paper,
    splashFactory: NoSplash.splashFactory,
    highlightColor: AppColors.ink.withValues(alpha: .06),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.paper, foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0,
      centerTitle: true, titleTextStyle: AppType.eyebrow.copyWith(color: AppColors.ink),
    ),
    iconTheme: const IconThemeData(color: AppColors.ink, size: 24, weight: 200),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      backgroundColor: AppColors.ink, foregroundColor: AppColors.onInk,
      disabledBackgroundColor: AppColors.rule, disabledForegroundColor: AppColors.inkSoft,
      minimumSize: const Size.fromHeight(54), padding: const EdgeInsets.symmetric(horizontal: 20),
      shape: square, elevation: 0, textStyle: AppType.label, alignment: Alignment.centerLeft,
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.ink, side: const BorderSide(color: AppColors.ink),
      minimumSize: const Size.fromHeight(54), padding: const EdgeInsets.symmetric(horizontal: 20),
      shape: square, textStyle: AppType.label, alignment: Alignment.centerLeft,
    )),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
      foregroundColor: AppColors.ink, shape: square, textStyle: AppType.labelS.copyWith(decoration: TextDecoration.underline),
    )),
    cardTheme: base.cardTheme.copyWith(color: AppColors.paper, elevation: 0, margin: EdgeInsets.zero, surfaceTintColor: Colors.transparent, shape: square),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.paper, modalBackgroundColor: AppColors.paper,
      surfaceTintColor: Colors.transparent, showDragHandle: false, elevation: 0,
      modalBarrierColor: AppColors.scrim,
      shape: Border(top: BorderSide(color: AppColors.ink)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating, backgroundColor: AppColors.ink, elevation: 0,
      contentTextStyle: _sans(13, color: AppColors.onInk), actionTextColor: AppColors.rule,
      shape: square, insetPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    ),
    dialogTheme: base.dialogTheme.copyWith(backgroundColor: AppColors.paperDeep, surfaceTintColor: Colors.transparent, shape: square),
    sliderTheme: base.sliderTheme.copyWith(
      trackHeight: 1, activeTrackColor: AppColors.ink, inactiveTrackColor: AppColors.ink,
      thumbColor: AppColors.ink, overlayShape: SliderComponentShape.noOverlay,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6, elevation: 0, pressedElevation: 0),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.ink, linearTrackColor: AppColors.rule, linearMinHeight: 3),
    dividerTheme: const DividerThemeData(color: AppColors.rule, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(iconColor: AppColors.ink, textColor: AppColors.ink, titleTextStyle: _sans(15), contentPadding: EdgeInsets.zero, minVerticalPadding: 16),
  );
}
