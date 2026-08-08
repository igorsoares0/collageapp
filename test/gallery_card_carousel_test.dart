import 'dart:io';

import 'package:collageapp/src/api/entitlements.dart';
import 'package:collageapp/src/api/template_api.dart';
import 'package:collageapp/src/api/template_store.dart';
import 'package:collageapp/src/rendering/template_canvas.dart';
import 'package:collageapp/src/screens/gallery_screen.dart';
import 'package:collageapp/src/screens/template_preview_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

TextStyle testFontResolver(String family, TextStyle base) => base;

/// Home cards render the real template document, not the stored thumbnail —
/// multi-panel ones as mini carousels that swipe sideways, single-panel ones
/// as a plain canvas. See _CardCarousel in gallery_screen.dart.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('gallery_card_carousel_test');
  });

  tearDown(() async {
    for (var attempt = 0; ; attempt++) {
      try {
        await tmp.delete(recursive: true);
        return;
      } on FileSystemException {
        if (attempt >= 4) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  const indexBody =
      '[{"id":"tpl_multi","name":"Multi","schemaVersion":2,'
      '"aspectRatio":"9:16","category":null,"premium":false,'
      '"thumbnailDataUrl":null},'
      '{"id":"tpl_single","name":"Single","schemaVersion":2,'
      '"aspectRatio":"9:16","category":null,"premium":false,'
      '"thumbnailDataUrl":null}]';

  String panel(String id, String fill) =>
      '{"id":"$id","backgroundColor":"#FFFFFF","layers":['
      '{"type":"shape","id":"s_$id","x":100,"y":100,'
      '"width":300,"height":300,"fill":"$fill"}]}';

  String template(String id, List<String> panels) =>
      '{"template":{"id":"$id","schemaVersion":2,"version":1,"name":"$id",'
      '"aspectRatio":"story","canvas":{"width":1080,"height":1920},'
      '"panels":[${panels.join(',')}]}}';

  TemplateStore store() => TemplateStore(
    api: TemplateApi(
      client: MockClient(
        (req) async => switch (req.url.path) {
          '/api/templates' => http.Response(indexBody, 200),
          '/api/assets' => http.Response('[]', 200),
          '/api/templates/tpl_multi' => http.Response(
            template('tpl_multi', [
              panel('p1', '#FF0066'),
              panel('p2', '#00CC77'),
            ]),
            200,
          ),
          _ => http.Response(
            template('tpl_single', [panel('p1', '#3366FF')]),
            200,
          ),
        },
      ),
    ),
    cacheDirOverride: tmp,
  );

  /// Same real-IO pattern as paywall_gate_test: the store reads and writes
  /// its cache with dart:io, so tests run in runAsync and wait by polling.
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() done, {
    required String reason,
  }) async {
    for (var i = 0; i < 500 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(done(), isTrue, reason: reason);
  }

  // Cards carry no visible name anymore — locate them by their per-template
  // key (see _TemplateCard in gallery_screen.dart).
  Finder cardOf(String id) => find.byKey(ValueKey('template-card-$id'));

  Future<void> pumpGallery(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: GalleryScreen(
          entitlements: EntitlementsService(),
          store: store(),
          fontResolver: testFontResolver,
        ),
      ),
    );
    await pumpUntil(
      tester,
      () => tester.any(cardOf('tpl_multi')),
      reason: 'the template grid never loaded',
    );
  }

  testWidgets('a multi-panel card swipes through its panels', (tester) async {
    await tester.runAsync(() async {
      await pumpGallery(tester);

      // The carousel appears once the cached template resolves.
      final pageView = find.descendant(
        of: cardOf('tpl_multi'),
        matching: find.byType(PageView),
      );
      await pumpUntil(
        tester,
        () => tester.any(pageView),
        reason: 'the multi-panel card never grew its carousel',
      );

      final scrollable = find.descendant(
        of: cardOf('tpl_multi'),
        matching: find.byType(Scrollable),
      );
      ScrollPosition position() =>
          tester.state<ScrollableState>(scrollable).position;
      expect(position().pixels, 0);

      // Swipe sideways (with velocity — a slow half-hearted drag snaps
      // back): the card advances to the second panel.
      await tester.fling(pageView, const Offset(-200, 0), 1000);
      await pumpUntil(
        tester,
        () => position().pixels > 0 && !position().isScrollingNotifier.value,
        reason: 'the swipe never advanced the card to the next panel',
      );
    });
  });

  testWidgets('a single-panel card renders live, without a carousel', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await pumpGallery(tester);

      // It renders the real document, like the preview does — the stored
      // thumbnail is saved at 240px and a card asks for about twice that, so
      // pinning it here is what made the home look soft next to the preview.
      final live = find.descendant(
        of: cardOf('tpl_single'),
        matching: find.byType(SlideView),
      );
      await pumpUntil(
        tester,
        () => tester.any(live),
        reason: 'the single-panel card never rendered its canvas',
      );

      // But no carousel: one panel has nothing to swipe, and a PageView here
      // would be a viewport that can never scroll.
      expect(
        find.descendant(
          of: cardOf('tpl_single'),
          matching: find.byType(PageView),
        ),
        findsNothing,
      );
    });
  });

  testWidgets('tapping a carousel card still opens the preview', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await pumpGallery(tester);
      await pumpUntil(
        tester,
        () => tester.any(
          find.descendant(of: cardOf('tpl_multi'), matching: find.byType(PageView)),
        ),
        reason: 'the multi-panel card never grew its carousel',
      );

      // The tap lands on the carousel area, not the label: the PageView must
      // not swallow it.
      await tester.tap(
        find.descendant(of: cardOf('tpl_multi'), matching: find.byType(PageView)),
        warnIfMissed: false,
      );
      await pumpUntil(
        tester,
        () => tester.any(find.byType(TemplatePreviewScreen)),
        reason: 'tapping the card never opened the preview',
      );
    });
  });
}
