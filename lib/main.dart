import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/api/appearance.dart';
import 'src/api/entitlements.dart';
import 'src/screens/gallery_screen.dart';
import 'src/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Chrome faces via google_fonts. Off in widget tests (no network there).
  AppFonts.enabled = true;
  final entitlements = EntitlementsService();
  // Fire-and-forget: the gallery renders immediately and the locks resolve
  // as soon as RevenueCat answers (or stay on when it can't).
  unawaited(entitlements.init());
  // Awaited (a tiny local file): the first frame must already be in the
  // chosen appearance, or a dark-mode user sees a flash of paper.
  final appearance = AppearanceController();
  await appearance.load();
  runApp(LayerApp(entitlements: entitlements, appearance: appearance));
}

class LayerApp extends StatelessWidget {
  final EntitlementsService entitlements;
  final AppearanceController appearance;

  const LayerApp({
    super.key,
    required this.entitlements,
    required this.appearance,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appearance,
      builder: (context, mode, _) => MaterialApp(
        title: 'Layer',
        theme: buildAppTheme(),
        darkTheme: buildAppDarkTheme(),
        themeMode: mode,
        // Screens without an AppBar (Discover, Projects) still need the
        // status bar to match the edition: light icons on dark paper.
        builder: (context, child) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          final colors = context.colors;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value:
                (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                    .copyWith(
                      statusBarColor: Colors.transparent,
                      systemNavigationBarColor: colors.paper,
                      systemNavigationBarIconBrightness: dark
                          ? Brightness.light
                          : Brightness.dark,
                    ),
            child: child!,
          );
        },
        home: GalleryScreen(entitlements: entitlements, appearance: appearance),
      ),
    );
  }
}
