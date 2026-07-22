// CupertinoPageTransitionsBuilder lives here, not in material.dart.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// "Darkroom" design tokens. The chrome stays near-black and neutral so the
/// user's photos carry the color; paper-white is the single action accent and
/// gold is reserved for premium/Pro signals — the two must never trade roles.
///
/// Content colors (text ink, panel backgrounds, kColorChoices) are NOT tokens:
/// they ship inside the exported collage and live with the rendering code.
abstract final class AppColors {
  /// Scaffold and canvas backdrop — the darkest step.
  static const ink = Color(0xFF0D0D0F);

  /// Bars, sheets and cards sitting on [ink].
  static const surface = Color(0xFF18181C);

  /// Elevated fills on [surface]: chips, inputs, thumbnails' backdrop.
  static const surfaceHigh = Color(0xFF232329);

  /// Brightest neutral fill: slider tracks, drag handles, thumb placeholders.
  static const surfaceBright = Color(0xFF34343C);

  /// Hairline borders and dividers.
  static const outline = Color(0xFF2E2E36);

  static const textPrimary = Color(0xFFF4F4F6);
  static const textSecondary = Color(0xFF9A9AA3);

  /// The one action accent: primary buttons, selection, active states.
  /// Paper-white with near-black ink on top — neutral chrome, VSCO-style.
  static const accent = Color(0xFFE9E9EF);
  static const onAccent = Color(0xFF1B1B1F);

  /// Premium only — PRO badges, locks, paywall. Never used for actions.
  static const gold = Color(0xFFE9C46A);
  static const onGold = Color(0xFF241A05);

  /// Destructive affordances (delete).
  static const danger = Color(0xFFEF4444);
}

/// Bricolage Grotesque carries the brand voice (titles, headlines); falls
/// back to the base style offline, same contract as [googleFontsResolver].
TextStyle _display(TextStyle base) {
  final style = base.copyWith(
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );
  try {
    return GoogleFonts.bricolageGrotesque(textStyle: style);
  } catch (_) {
    return style;
  }
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    primaryContainer: Color(0xFF2A2A31),
    onPrimaryContainer: AppColors.accent,
    secondary: AppColors.gold,
    onSecondary: AppColors.onGold,
    tertiary: AppColors.gold,
    onTertiary: AppColors.onGold,
    surface: AppColors.ink,
    onSurface: AppColors.textPrimary,
    onSurfaceVariant: AppColors.textSecondary,
    surfaceContainerLowest: AppColors.ink,
    surfaceContainerLow: AppColors.surface,
    surfaceContainer: AppColors.surface,
    surfaceContainerHigh: AppColors.surfaceHigh,
    surfaceContainerHighest: AppColors.surfaceHigh,
    outline: AppColors.outline,
    outlineVariant: AppColors.outline,
    error: AppColors.danger,
  );

  final base = ThemeData(colorScheme: scheme);

  // Instrument Sans for every UI role; offline the default face stays.
  TextTheme textTheme;
  try {
    textTheme = GoogleFonts.instrumentSansTextTheme(base.textTheme);
  } catch (_) {
    textTheme = base.textTheme;
  }
  textTheme = textTheme.copyWith(
    displayLarge: _display(textTheme.displayLarge!),
    displayMedium: _display(textTheme.displayMedium!),
    displaySmall: _display(textTheme.displaySmall!),
    headlineLarge: _display(textTheme.headlineLarge!),
    headlineMedium: _display(textTheme.headlineMedium!),
    headlineSmall: _display(textTheme.headlineSmall!),
    // AppBar titles read from titleLarge — brand face there too.
    titleLarge: _display(textTheme.titleLarge!),
    // Buttons read labelLarge; w600 keeps CTAs assertive without shouting.
    labelLarge: textTheme.labelLarge!.copyWith(fontWeight: FontWeight.w600),
  );

  return base.copyWith(
    textTheme: textTheme,
    scaffoldBackgroundColor: AppColors.ink,
    // M3 fade-forwards on Android, native slide on Apple platforms — the
    // default zoom transition is the single biggest "stock Flutter" tell.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: textTheme.titleLarge!.copyWith(fontSize: 20),
    ),
    tabBarTheme: base.tabBarTheme.copyWith(
      labelColor: AppColors.textPrimary,
      unselectedLabelColor: AppColors.textSecondary,
      indicatorColor: AppColors.accent,
      dividerColor: Colors.transparent,
      labelStyle: textTheme.titleSmall!.copyWith(fontWeight: FontWeight.w600),
      unselectedLabelStyle: textTheme.titleSmall,
    ),
    cardTheme: base.cardTheme.copyWith(
      color: AppColors.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.outline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.accent),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.onAccent,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      modalBackgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: AppColors.surfaceBright,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surfaceHigh,
      contentTextStyle: textTheme.bodyMedium,
      actionTextColor: AppColors.accent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: AppColors.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: AppColors.accent,
      thumbColor: AppColors.accent,
      inactiveTrackColor: AppColors.surfaceBright,
      overlayColor: AppColors.accent.withValues(alpha: 0.12),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.outline),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.textSecondary,
    ),
  );
}
