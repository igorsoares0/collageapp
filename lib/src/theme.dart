// CupertinoPageTransitionsBuilder lives here, not in material.dart.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Layer design tokens — a warm, editorial "printed magazine" identity.
///
/// Paper is the ground, ink is the ACTION colour (primary buttons, selection,
/// active ticks) and rouge is the PREMIUM/ACTIVE mark (active tab, "Pro",
/// destructive confirm). The two never trade roles.
///
/// Content colours (text ink, panel backgrounds, kColorChoices) are NOT
/// tokens: they ship inside the exported collage and live with the rendering
/// code.
abstract final class AppColors {
  /// Scaffold / app background.
  static const paper = Color(0xFFF3EEE5);

  /// Sheets, selected plan row, skeletons, empty slot fill.
  static const paperDeep = Color(0xFFEAE3D7);

  /// The editor's canvas surround — the "table" the canvas sits on.
  static const table = Color(0xFFE4DCCF);

  /// 1px hairlines, inactive ticks, disabled button fill.
  static const rule = Color(0xFFCFC5B5);

  /// Page-edge slivers behind template covers.
  static const ruleStrong = Color(0xFFA89D8D);

  /// Disabled; as text only at ≥24pt (inactive category words).
  static const stone = Color(0xFF8A8073);

  /// Small numerals / tertiary text.
  static const inkMuted = Color(0xFF6F665C);

  /// Secondary text (6.1:1 on paper).
  static const inkSoft = Color(0xFF5E564C);

  /// Primary text, primary buttons, selection rings, active ticks.
  static const ink = Color(0xFF1E1B17);

  /// ONLY: active-tab mark, "Pro" marks, "Make it yours" eyebrow,
  /// destructive confirm button.
  static const rouge = Color(0xFF7B2D26);

  /// Text/icons on [ink].
  static const onInk = paper;

  /// Disabled icons (e.g. redo with nothing to redo).
  static const disabledIcon = Color(0xFFB5AB9C);

  /// Behind bottom sheets.
  static const scrim = Color(0x6B1E1B17);
}

/// Base-4 spacing, the 20pt screen margin and the minimum touch target.
abstract final class AppSpace {
  static const s4 = 4.0;
  static const s8 = 8.0;
  static const s12 = 12.0;
  static const s16 = 16.0;
  static const s20 = 20.0;
  static const s24 = 24.0;
  static const s32 = 32.0;
  static const s48 = 48.0;
  static const s64 = 64.0;
  static const margin = 20.0;
  static const gutter = 10.0;
  static const minTarget = 44.0;
}

/// The chrome faces: Newsreader (display, titles, numerals) and Instrument
/// Sans (all UI). Off until `main()` turns them on — widget tests never load
/// google_fonts (no network), so there every style keeps the default face,
/// the same contract as the canvas's injectable FontResolver.
abstract final class AppFonts {
  static bool enabled = false;

  static TextStyle serif(TextStyle base) {
    if (!enabled) return base;
    try {
      return GoogleFonts.newsreader(textStyle: base);
    } catch (_) {
      return base;
    }
  }

  static TextStyle sans(TextStyle base) {
    if (!enabled) return base;
    try {
      return GoogleFonts.instrumentSans(textStyle: base);
    } catch (_) {
      return base;
    }
  }
}

TextStyle _serif(
  double size, {
  double height = 1.0,
  double tracking = 0,
  bool italic = false,
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.ink,
}) => AppFonts.serif(
  TextStyle(
    fontSize: size,
    height: height,
    letterSpacing: size * tracking,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    fontWeight: weight,
    color: color,
  ),
);

TextStyle _sans(
  double size, {
  double height = 1.4,
  double tracking = 0,
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.ink,
}) => AppFonts.sans(
  TextStyle(
    fontSize: size,
    height: height,
    letterSpacing: size * tracking,
    fontWeight: weight,
    color: color,
  ),
);

/// The type scale. Getters (not finals): [AppFonts.enabled] is flipped in
/// `main()`, and a cached final would freeze whichever face it saw first.
abstract final class AppType {
  /// Discover headline (44 / .98).
  static TextStyle get display => _serif(44, height: .98, tracking: -.025);

  /// Screen titles — Projects, Settings (46 / .95).
  static TextStyle get headlineL => _serif(46, height: .95, tracking: -.025);

  /// Preview title, Export headline, Paywall (40 / .95).
  static TextStyle get headline => _serif(40, height: .95, tracking: -.02);

  /// Featured name, sheet titles (22–30).
  static TextStyle title([double size = 24]) =>
      _serif(size, height: 1.05, tracking: -.015);

  /// Template names under tiles (18 / 1.1).
  static TextStyle get captionTitle => _serif(18, height: 1.1);

  /// Category index words (24).
  static TextStyle get category => _serif(24, height: 1.1);

  /// Italic numerals — slide counters, collection numbers.
  static TextStyle numeral(double size, {Color color = AppColors.ink}) =>
      _serif(size, italic: true, tracking: -.02, height: 1, color: color);

  /// Any serif at [size], for one-off headline pieces (the italic half of a
  /// two-part headline, the wordmark, the "B" of the bold toggle).
  static TextStyle serif(
    double size, {
    bool italic = false,
    double height = 1.0,
    double tracking = 0,
    Color color = AppColors.ink,
  }) => _serif(
    size,
    italic: italic,
    height: height,
    tracking: tracking,
    color: color,
  );

  /// Paragraphs (15 / 22).
  static TextStyle get body => _sans(15, height: 22 / 15);

  /// Secondary paragraphs in inkSoft (13.5 / 1.5).
  static TextStyle get bodyS =>
      _sans(13.5, height: 1.5, color: AppColors.inkSoft);

  /// Buttons, rows (15 / 500).
  static TextStyle get label => _sans(15, weight: FontWeight.w500, height: 1.2);

  /// Small buttons, bar actions (13 / 500).
  static TextStyle get labelS =>
      _sans(13, weight: FontWeight.w500, height: 1.2);

  /// Meta under tiles ("4:5 · 5 slides").
  static TextStyle get caption => _sans(12, color: AppColors.inkSoft);

  /// Section labels: 11.5 / 600 / +0.16em, rendered UPPERCASE by [Eyebrow].
  static TextStyle eyebrow({double size = 11.5, Color color = AppColors.ink}) =>
      _sans(
        size,
        height: 1.2,
        tracking: .16,
        weight: FontWeight.w600,
        color: color,
      );

  /// Bottom bar labels (11 / 600 / +0.04em).
  static TextStyle navLabel({Color color = AppColors.ink}) =>
      _sans(11, tracking: .04, weight: FontWeight.w600, color: color);

  /// Arbitrary sans, for the odd control that needs its own size.
  static TextStyle sans(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.ink,
    double height = 1.4,
    double tracking = 0,
  }) => _sans(
    size,
    weight: weight,
    color: color,
    height: height,
    tracking: tracking,
  );
}

/// The standard sheet motion: 340ms on cubic(.2,.7,.2,1).
const kSheetCurve = Cubic(.2, .7, .2, 1);
const kSheetDuration = Duration(milliseconds: 340);

ThemeData buildAppTheme() {
  const scheme = ColorScheme.light(
    primary: AppColors.ink,
    onPrimary: AppColors.onInk,
    primaryContainer: AppColors.paperDeep,
    onPrimaryContainer: AppColors.ink,
    secondary: AppColors.rouge,
    onSecondary: AppColors.onInk,
    tertiary: AppColors.rouge,
    onTertiary: AppColors.onInk,
    surface: AppColors.paper,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.inkSoft,
    surfaceContainerLowest: AppColors.paper,
    surfaceContainerLow: AppColors.paper,
    surfaceContainer: AppColors.paperDeep,
    surfaceContainerHigh: AppColors.paperDeep,
    surfaceContainerHighest: AppColors.table,
    outline: AppColors.rule,
    outlineVariant: AppColors.rule,
    error: AppColors.rouge,
    onError: AppColors.onInk,
  );

  final base = ThemeData(colorScheme: scheme);

  // Instrument Sans for every UI role; offline / in tests the default face.
  var textTheme = base.textTheme;
  if (AppFonts.enabled) {
    try {
      textTheme = GoogleFonts.instrumentSansTextTheme(base.textTheme);
    } catch (_) {}
  }
  textTheme = textTheme
      .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink)
      .copyWith(
        displayLarge: AppType.display,
        displayMedium: AppType.headlineL,
        displaySmall: AppType.headline,
        headlineLarge: AppType.headline,
        headlineMedium: AppType.title(),
        headlineSmall: AppType.captionTitle,
        titleLarge: AppType.title(20),
        bodyLarge: AppType.body,
        bodyMedium: AppType.sans(14),
        labelLarge: AppType.label,
        labelSmall: AppType.eyebrow(),
      );

  const square = RoundedRectangleBorder(borderRadius: BorderRadius.zero);
  final pressed = WidgetStateProperty.resolveWith<Color?>(
    (states) => states.contains(WidgetState.pressed)
        ? AppColors.ink.withValues(alpha: .08)
        : null,
  );

  return base.copyWith(
    textTheme: textTheme,
    scaffoldBackgroundColor: AppColors.paper,
    canvasColor: AppColors.paper,
    // No ink ripples: pressed states are a flat tone, like print.
    splashFactory: NoSplash.splashFactory,
    highlightColor: AppColors.ink.withValues(alpha: .06),
    // M3 fade-forwards on Android, native slide on Apple platforms.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.paper,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: AppType.eyebrow(),
      iconTheme: const IconThemeData(color: AppColors.ink, weight: 200),
    ),
    iconTheme: const IconThemeData(color: AppColors.ink, size: 24, weight: 200),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.ink,
        disabledForegroundColor: AppColors.disabledIcon,
        shape: square,
        minimumSize: const Size.square(AppSpace.minTarget),
      ).copyWith(overlayColor: pressed),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.ink,
        foregroundColor: AppColors.onInk,
        disabledBackgroundColor: AppColors.rule,
        disabledForegroundColor: AppColors.inkSoft,
        minimumSize: const Size(64, 54),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: square,
        elevation: 0,
        textStyle: AppType.label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.ink),
        minimumSize: const Size(64, 54),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: square,
        textStyle: AppType.label,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.ink,
        shape: square,
        textStyle: AppType.labelS,
      ),
    ),
    cardTheme: base.cardTheme.copyWith(
      color: AppColors.paper,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: square,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.paper,
      modalBackgroundColor: AppColors.paper,
      surfaceTintColor: Colors.transparent,
      showDragHandle: false,
      elevation: 0,
      modalElevation: 0,
      modalBarrierColor: AppColors.scrim,
      shape: Border(top: BorderSide(color: AppColors.ink)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      elevation: 0,
      contentTextStyle: AppType.sans(13, color: AppColors.onInk),
      actionTextColor: AppColors.rule,
      shape: square,
      insetPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: AppColors.paperDeep,
      surfaceTintColor: Colors.transparent,
      shape: square,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: AppColors.ink),
      ),
      textStyle: AppType.label,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      trackHeight: 1,
      activeTrackColor: AppColors.ink,
      inactiveTrackColor: AppColors.ink,
      thumbColor: AppColors.ink,
      overlayShape: SliderComponentShape.noOverlay,
      thumbShape: const BarSliderThumbShape(),
      trackShape: const RectangularSliderTrackShape(),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.ink,
      linearTrackColor: AppColors.rule,
      linearMinHeight: 3,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.rule,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: AppColors.ink,
      textColor: AppColors.ink,
      titleTextStyle: AppType.sans(15),
      subtitleTextStyle: AppType.sans(13, color: AppColors.inkSoft),
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 16,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.ink,
      selectionHandleColor: AppColors.ink,
    ),
  );
}

/// The slider thumb: a 2×17 ink bar on the 1px track.
class BarSliderThumbShape extends SliderComponentShape {
  const BarSliderThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(12, 24);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    context.canvas.drawRect(
      Rect.fromCenter(center: center, width: 2, height: 17),
      Paint()..color = sliderTheme.thumbColor ?? AppColors.ink,
    );
  }
}
