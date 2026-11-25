// CupertinoPageTransitionsBuilder lives here, not in material.dart.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:google_fonts/google_fonts.dart';

/// Layer design tokens — a warm, editorial "printed magazine" identity, in a
/// light and a dark edition with the same roles.
///
/// Paper is the ground, ink is the ACTION colour (primary buttons, selection,
/// active ticks) and rouge is the PREMIUM/ACTIVE mark (active tab, "Pro",
/// destructive confirm). The two never trade roles. In dark, ink becomes
/// ivory and primary buttons invert (ivory fill, dark label).
///
/// Read the active edition with `context.colors` — never hard-code one, or
/// that widget stops following the theme.
///
/// Content colours (text ink, panel backgrounds, kColorChoices) are NOT
/// tokens: they ship inside the exported collage and live with the rendering
/// code.
@immutable
class LayerColors extends ThemeExtension<LayerColors> {
  final Brightness brightness;

  /// Scaffold / app background.
  final Color paper;

  /// Sheets, selected plan row, skeletons, empty slot fill.
  final Color paperDeep;

  /// The editor's canvas surround — the "table" the canvas sits on.
  final Color table;

  /// 1px hairlines, inactive ticks, disabled button fill.
  final Color rule;

  /// Page-edge slivers behind template covers.
  final Color ruleStrong;

  /// Disabled; as text only at ≥24pt (inactive category words).
  final Color stone;

  /// Small numerals / tertiary text.
  final Color inkMuted;

  /// Secondary text.
  final Color inkSoft;

  /// Primary text, primary buttons, selection rings, active ticks.
  final Color ink;

  /// ONLY: active-tab mark, "Pro" marks, "Make it yours" eyebrow,
  /// destructive confirm button.
  final Color rouge;

  /// Text/icons on [ink].
  final Color onInk;

  /// Disabled icons (e.g. redo with nothing to redo).
  final Color disabledIcon;

  /// Behind bottom sheets.
  final Color scrim;

  const LayerColors({
    required this.brightness,
    required this.paper,
    required this.paperDeep,
    required this.table,
    required this.rule,
    required this.ruleStrong,
    required this.stone,
    required this.inkMuted,
    required this.inkSoft,
    required this.ink,
    required this.rouge,
    required this.onInk,
    required this.disabledIcon,
    required this.scrim,
  });

  static const light = LayerColors(
    brightness: Brightness.light,
    paper: Color(0xFFF3EEE5),
    paperDeep: Color(0xFFEAE3D7),
    table: Color(0xFFE4DCCF),
    rule: Color(0xFFCFC5B5),
    ruleStrong: Color(0xFFA89D8D),
    stone: Color(0xFF8A8073),
    inkMuted: Color(0xFF6F665C),
    inkSoft: Color(0xFF5E564C),
    ink: Color(0xFF1E1B17),
    rouge: Color(0xFF7B2D26),
    onInk: Color(0xFFF3EEE5),
    disabledIcon: Color(0xFFB5AB9C),
    scrim: Color(0x6B1E1B17),
  );

  /// The dark edition: same roles, swapped values. The table is the darkest
  /// step so artwork pops; rouge is lifted to stay legible on dark paper.
  static const dark = LayerColors(
    brightness: Brightness.dark,
    paper: Color(0xFF171512),
    paperDeep: Color(0xFF211E1A),
    table: Color(0xFF0D0C0B),
    rule: Color(0xFF36312B),
    ruleStrong: Color(0xFF4C463F),
    stone: Color(0xFF7D7468),
    inkMuted: Color(0xFF9E9487),
    inkSoft: Color(0xFFB4AA9C),
    ink: Color(0xFFEEE7DB),
    rouge: Color(0xFFD0756A),
    onInk: Color(0xFF171512),
    disabledIcon: Color(0xFF5C554C),
    scrim: Color(0x9E000000),
  );

  bool get isDark => brightness == Brightness.dark;

  @override
  LayerColors copyWith() => this;

  /// Editions switch whole, never blended: a half-dark frame mid-transition
  /// would show colour pairs the design never checked.
  @override
  LayerColors lerp(LayerColors? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

/// `context.colors` — the active [LayerColors] edition. Falls back to light
/// where no Layer theme is installed (widget tests pump bare MaterialApps).
extension LayerColorsOf on BuildContext {
  LayerColors get colors =>
      Theme.of(this).extension<LayerColors>() ?? LayerColors.light;
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
  Color? color,
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
  Color? color,
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
  static TextStyle numeral(double size, {Color? color}) =>
      _serif(size, italic: true, tracking: -.02, height: 1, color: color);

  /// Any serif at [size], for one-off headline pieces (the italic half of a
  /// two-part headline, the wordmark, the "B" of the bold toggle).
  static TextStyle serif(
    double size, {
    bool italic = false,
    double height = 1.0,
    double tracking = 0,
    Color? color,
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
  static TextStyle get bodyS => _sans(13.5, height: 1.5);

  /// Buttons, rows (15 / 500).
  static TextStyle get label => _sans(15, weight: FontWeight.w500, height: 1.2);

  /// Small buttons, bar actions (13 / 500).
  static TextStyle get labelS =>
      _sans(13, weight: FontWeight.w500, height: 1.2);

  /// Meta under tiles ("4:5 · 5 slides").
  static TextStyle get caption => _sans(12);

  /// Section labels: 11.5 / 600 / +0.16em, rendered UPPERCASE by [Eyebrow].
  static TextStyle eyebrow({double size = 11.5, Color? color}) => _sans(
    size,
    height: 1.2,
    tracking: .16,
    weight: FontWeight.w600,
    color: color,
  );

  /// Bottom bar labels (11 / 600 / +0.04em).
  static TextStyle navLabel({Color? color}) =>
      _sans(11, tracking: .04, weight: FontWeight.w600, color: color);

  /// Arbitrary sans, for the odd control that needs its own size.
  static TextStyle sans(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
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

/// The light Layer theme.
ThemeData buildAppTheme() => _buildTheme(LayerColors.light);

/// The dark Layer theme — same components, the dark edition of the tokens.
ThemeData buildAppDarkTheme() => _buildTheme(LayerColors.dark);

ThemeData _buildTheme(LayerColors c) {
  final scheme = ColorScheme(
    brightness: c.brightness,
    primary: c.ink,
    onPrimary: c.onInk,
    primaryContainer: c.paperDeep,
    onPrimaryContainer: c.ink,
    secondary: c.rouge,
    onSecondary: c.onInk,
    tertiary: c.rouge,
    onTertiary: c.onInk,
    surface: c.paper,
    onSurface: c.ink,
    onSurfaceVariant: c.inkSoft,
    surfaceContainerLowest: c.paper,
    surfaceContainerLow: c.paper,
    surfaceContainer: c.paperDeep,
    surfaceContainerHigh: c.paperDeep,
    surfaceContainerHighest: c.table,
    outline: c.rule,
    outlineVariant: c.rule,
    error: c.rouge,
    onError: c.onInk,
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
      .apply(bodyColor: c.ink, displayColor: c.ink)
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
      )
      // AppType styles carry no colour of their own: the edition's ink.
      .apply(bodyColor: c.ink, displayColor: c.ink);

  const square = RoundedRectangleBorder(borderRadius: BorderRadius.zero);
  final pressed = WidgetStateProperty.resolveWith<Color?>(
    (states) => states.contains(WidgetState.pressed)
        ? c.ink.withValues(alpha: .08)
        : null,
  );

  // Status and navigation bars match the paper: dark icons on light paper,
  // light icons on dark.
  final overlay =
      (c.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: c.paper,
            systemNavigationBarIconBrightness: c.isDark
                ? Brightness.light
                : Brightness.dark,
          );

  return base.copyWith(
    extensions: [c],
    textTheme: textTheme,
    scaffoldBackgroundColor: c.paper,
    canvasColor: c.paper,
    // No ink ripples: pressed states are a flat tone, like print.
    splashFactory: NoSplash.splashFactory,
    highlightColor: c.ink.withValues(alpha: .06),
    // M3 fade-forwards on Android, native slide on Apple platforms.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.paper,
      foregroundColor: c.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: overlay,
      centerTitle: true,
      titleTextStyle: AppType.eyebrow(),
      iconTheme: IconThemeData(color: c.ink, weight: 200),
    ),
    iconTheme: IconThemeData(color: c.ink, size: 24, weight: 200),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: c.ink,
        disabledForegroundColor: c.disabledIcon,
        shape: square,
        minimumSize: const Size.square(AppSpace.minTarget),
      ).copyWith(overlayColor: pressed),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.ink,
        foregroundColor: c.onInk,
        disabledBackgroundColor: c.rule,
        disabledForegroundColor: c.inkSoft,
        minimumSize: const Size(64, 54),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: square,
        elevation: 0,
        textStyle: AppType.label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        side: BorderSide(color: c.ink),
        minimumSize: const Size(64, 54),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: square,
        textStyle: AppType.label,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.ink,
        shape: square,
        textStyle: AppType.labelS,
      ),
    ),
    cardTheme: base.cardTheme.copyWith(
      color: c.paper,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: square,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.paper,
      modalBackgroundColor: c.paper,
      surfaceTintColor: Colors.transparent,
      showDragHandle: false,
      elevation: 0,
      modalElevation: 0,
      modalBarrierColor: c.scrim,
      shape: Border(top: BorderSide(color: c.ink)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.ink,
      elevation: 0,
      contentTextStyle: AppType.sans(13, color: c.onInk),
      actionTextColor: c.rule,
      shape: square,
      insetPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: c.paperDeep,
      surfaceTintColor: Colors.transparent,
      shape: square,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(side: BorderSide(color: c.ink)),
      textStyle: AppType.label,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      trackHeight: 1,
      activeTrackColor: c.ink,
      inactiveTrackColor: c.ink,
      thumbColor: c.ink,
      overlayShape: SliderComponentShape.noOverlay,
      thumbShape: const BarSliderThumbShape(),
      trackShape: const RectangularSliderTrackShape(),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.ink,
      linearTrackColor: c.rule,
      linearMinHeight: 3,
    ),
    dividerTheme: DividerThemeData(color: c.rule, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: c.ink,
      textColor: c.ink,
      titleTextStyle: AppType.sans(15),
      subtitleTextStyle: AppType.sans(13, color: c.inkSoft),
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 16,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.ink,
      selectionHandleColor: c.ink,
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
      Paint()..color = sliderTheme.thumbColor ?? LayerColors.light.ink,
    );
  }
}
