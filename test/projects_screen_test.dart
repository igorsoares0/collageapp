import 'dart:io';

import 'package:collageapp/src/api/project_store.dart';
import 'package:collageapp/src/model/slot_content.dart';
import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/screens/projects_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keeps the requested family out of the thumbnail render — tests have no
/// network for google_fonts.
TextStyle testFontResolver(String family, TextStyle base) => base;

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

      // Thumbnail-only cards: no names in the list, so target them by key.
      expect(find.byKey(const ValueKey('project-p_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('project-p_2')), findsOneWidget);
      expect(find.text('Beach trip'), findsNothing);

      // Delete 'Beach trip': its corner bin, then the dialog's confirm.
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('project-p_1')),
          matching: find.byIcon(Icons.delete_outline),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Delete project?'), findsOneWidget);
      // The confirmation still names the project even though the card
      // doesn't.
      expect(find.textContaining('Beach trip'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await pumpUntil(
        tester,
        () => !tester.any(find.byKey(const ValueKey('project-p_1'))),
        reason: 'the deleted project never left the list',
      );

      expect(find.byKey(const ValueKey('project-p_1')), findsNothing);
      expect(find.byKey(const ValueKey('project-p_2')), findsOneWidget);
      expect(await store.list(), hasLength(1));
    });
  });

  testWidgets('thumbnail renders layers the user added while editing', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // A from-scratch project: the blank template's panel has no layers of
      // its own — everything lives in the content's addedLayers, which the
      // thumbnail must merge in (regression: it used to render the raw
      // template panel, dropping added text/photos).
      await store.save(
        Project(
          id: 'p_1',
          name: 'Scratch',
          updatedAt: DateTime.now(),
          template: Template.blank(),
          content: const SlotContent(
            texts: {'slot_t1': 'Hello'},
            addedLayers: {
              'panel_1': [
                TextLayer(
                  id: 'layer_t1',
                  hidden: false,
                  slotId: 'slot_t1',
                  x: 100,
                  y: 100,
                  width: 500,
                  fontFamily: 'Inter',
                  fontSize: 64,
                  fontWeight: 700,
                  color: Color(0xFF111111),
                  alignment: 'left',
                ),
              ],
            },
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProjectsList(store: store, fontResolver: testFontResolver),
          ),
        ),
      );
      await pumpUntil(
        tester,
        () => tester.any(find.text('Hello')),
        reason: 'the added text layer never appeared in the thumbnail',
      );
    });
  });

  testWidgets('thumbnail previews the WHOLE carousel — every slide, not just '
      'the first panel', (tester) async {
    await tester.runAsync(() async {
      // A multi-panel doc where each slide carries its own element (a seamless
      // panorama's content also lives on a later panel and reaches the first
      // slide only through the bleed). The card must show the full carousel, so
      // BOTH slides' content appears — not a single-panel crop that would show
      // only a blank cover or only one half.
      await store.save(
        Project(
          id: 'p_multi',
          name: 'Carousel',
          updatedAt: DateTime.now(),
          template: const Template(
            id: 'tpl',
            schemaVersion: 3,
            version: 1,
            name: 'Carousel',
            aspectRatio: '9:16',
            canvasWidth: 1080,
            canvasHeight: 1920,
            panels: [
              Panel(
                id: 'panel_1',
                backgroundColor: Color(0xFFFFFFFF),
                layers: [
                  TextLayer(
                    id: 'layer_a',
                    hidden: false,
                    slotId: 'slot_a',
                    x: 100,
                    y: 100,
                    width: 500,
                    fontFamily: 'Inter',
                    fontSize: 64,
                    fontWeight: 700,
                    color: Color(0xFF111111),
                    alignment: 'left',
                  ),
                ],
              ),
            ],
          ),
          content: const SlotContent(
            texts: {'slot_a': 'FirstSlide', 'slot_b': 'SecondSlide'},
            addedPanels: [
              Panel(
                id: 'panel_2',
                backgroundColor: Color(0xFFFFFFFF),
                layers: [],
              ),
            ],
            addedLayers: {
              'panel_2': [
                TextLayer(
                  id: 'layer_b',
                  hidden: false,
                  slotId: 'slot_b',
                  x: 100,
                  y: 100,
                  width: 500,
                  fontFamily: 'Inter',
                  fontSize: 64,
                  fontWeight: 700,
                  color: Color(0xFF111111),
                  alignment: 'left',
                ),
              ],
            },
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProjectsList(store: store, fontResolver: testFontResolver),
          ),
        ),
      );
      await pumpUntil(
        tester,
        () =>
            tester.any(find.text('FirstSlide')) &&
            tester.any(find.text('SecondSlide')),
        reason: 'the thumbnail did not render every slide of the carousel',
      );
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

      expect(find.byKey(const ValueKey('project-p_1')), findsOneWidget);
      expect(await store.list(), hasLength(1));
    });
  });
}
