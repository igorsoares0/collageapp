import 'dart:io';

import 'package:collageapp/src/api/appearance.dart';
import 'package:collageapp/src/api/entitlements.dart';
import 'package:collageapp/src/screens/settings_screen.dart';
import 'package:collageapp/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('appearance_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('AppearanceController', () {
    test('starts on system and survives a restart', () async {
      final first = AppearanceController(dirOverride: tmp);
      await first.load();
      expect(first.value, ThemeMode.system);

      await first.set(ThemeMode.dark);
      expect(first.value, ThemeMode.dark);

      final next = AppearanceController(dirOverride: tmp);
      await next.load();
      expect(next.value, ThemeMode.dark);
    });

    test('a garbled file reads as system, not a crash', () async {
      await File('${tmp.path}/appearance').writeAsString('purple');
      final c = AppearanceController(dirOverride: tmp);
      await c.load();
      expect(c.value, ThemeMode.system);
    });
  });

  testWidgets('Settings switches the app between light and dark', (
    tester,
  ) async {
    final appearance = AppearanceController(
      dirOverride: tmp,
      initial: ThemeMode.light,
    );
    tester.view.physicalSize = const Size(540, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ValueListenableBuilder<ThemeMode>(
        valueListenable: appearance,
        builder: (context, mode, _) => MaterialApp(
          theme: buildAppTheme(),
          darkTheme: buildAppDarkTheme(),
          themeMode: mode,
          home: SettingsScreen(
            entitlements: EntitlementsService(),
            appearance: appearance,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Color paper() =>
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor ??
        Theme.of(tester.element(find.byType(Scaffold))).scaffoldBackgroundColor;

    expect(find.text('Match system'), findsOneWidget);
    expect(paper(), LayerColors.light.paper);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('appearance-dark')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(appearance.value, ThemeMode.dark);
    expect(paper(), LayerColors.dark.paper);
    // The active edition is what widgets read.
    expect(
      tester.element(find.text('Settings')).colors.ink,
      LayerColors.dark.ink,
    );

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('appearance-light')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(paper(), LayerColors.light.paper);
  });
}
