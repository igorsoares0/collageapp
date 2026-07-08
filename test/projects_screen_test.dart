import 'dart:io';

import 'package:collageapp/src/api/project_store.dart';
import 'package:collageapp/src/model/slot_content.dart';
import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/screens/projects_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late ProjectStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('projects_screen_test');
    store = ProjectStore(dirOverride: dir);
  });

  tearDown(() async {
    // Windows can hold transient locks (AV scan) on freshly written files.
    for (var attempt = 0; ; attempt++) {
      try {
        await dir.delete(recursive: true);
        return;
      } on FileSystemException {
        if (attempt >= 4) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  /// Pumps until [done] (up to ~5s of real time). Inside runAsync the store's
  /// file IO completes during the real delays; a fixed delay would be a race
  /// under full-suite disk load, and pumpAndSettle alone never yields to the
  /// real event loop.
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() done, {
    required String reason,
  }) async {
    for (var i = 0; i < 500 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // A duration, so route/dialog transitions actually advance — a plain
      // pump() builds a frame at a frozen clock.
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(done(), isTrue, reason: reason);
    await tester.pumpAndSettle();
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: ProjectsScreen(store: store)));
    await pumpUntil(
      tester,
      () => !tester.any(find.byType(CircularProgressIndicator)),
      reason: 'the project list never finished loading',
    );
  }

  Future<void> seedProject(String id, String name) => store.save(
    Project(
      id: id,
      name: name,
      updatedAt: DateTime.now(),
      template: Template.blank(),
      content: const SlotContent(),
    ),
  );

  // Each test runs entirely inside runAsync: the store does real file IO,
  // whose completions never fire in the default fake-async test zone. In the
  // real zone, pumps and taps still work and every await simply completes.

  testWidgets('shows the empty state when nothing was saved', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      expect(find.textContaining('Nothing here yet'), findsOneWidget);
    });
  });

  testWidgets('lists saved projects and deletes one after confirming', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedProject('p_1', 'Beach trip');
      await seedProject('p_2', 'Birthday');
      await pumpScreen(tester);

      expect(find.text('Beach trip'), findsOneWidget);
      expect(find.text('Birthday'), findsOneWidget);

      // Delete 'Beach trip': its trailing bin, then the dialog's confirm.
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Beach trip'),
          matching: find.byIcon(Icons.delete_outline),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Delete project?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await pumpUntil(
        tester,
        () => !tester.any(find.text('Beach trip')),
        reason: 'the deleted project never left the list',
      );

      expect(find.text('Beach trip'), findsNothing);
      expect(find.text('Birthday'), findsOneWidget);
      expect(await store.list(), hasLength(1));
    });
  });

  testWidgets('cancelling the dialog keeps the project', (tester) async {
    await tester.runAsync(() async {
      await seedProject('p_1', 'Beach trip');
      await pumpScreen(tester);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await pumpUntil(
        tester,
        () => !tester.any(find.text('Delete project?')),
        reason: 'the dialog never closed',
      );

      expect(find.text('Beach trip'), findsOneWidget);
      expect(await store.list(), hasLength(1));
    });
  });
}
