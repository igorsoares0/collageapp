import 'dart:io';

import 'package:collageapp/src/api/entitlements.dart';
import 'package:collageapp/src/api/template_api.dart';
import 'package:collageapp/src/api/template_store.dart';
import 'package:collageapp/src/screens/gallery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

TextStyle testFontResolver(String family, TextStyle base) => base;

/// Home cards are cut to their template's own aspect and the artwork fills
/// them edge to edge — no letterbox, no caption bar, no neighbouring slide
/// peeking past the border. The grid is therefore ragged, and these tests
/// assert the geometry that makes that true.
void main() {
  group('aspectRatioOf', () {
    test('reads the named presets the index publishes', () {
      expect(aspectRatioOf('story'), closeTo(9 / 16, 1e-9));
      expect(aspectRatioOf('post'), closeTo(4 / 5, 1e-9));
      expect(aspectRatioOf('square'), 1.0);
      // Case and padding are not the publisher's contract to get right.
      expect(aspectRatioOf('  Story '), closeTo(9 / 16, 1e-9));
    });

    test('reads plain W:H', () {
      expect(aspectRatioOf('4:5'), closeTo(0.8, 1e-9));
      expect(aspectRatioOf('16:9'), closeTo(16 / 9, 1e-9));
    });

    test('falls back to story rather than guessing', () {
      for (final bad in ['', 'wat', '1:0', '0:1', '4:5:6', 'a:b']) {
        expect(aspectRatioOf(bad), closeTo(9 / 16, 1e-9), reason: bad);
      }
    });
  });

  group('grid', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('gallery_card_layout_test');
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

    // Three formats side by side, so a single uniform tile size cannot
    // satisfy all of them.
    const indexBody =
        '[{"id":"s1","name":"S1","schemaVersion":2,"aspectRatio":"story",'
        '"category":null,"premium":false,"thumbnailDataUrl":null},'
        '{"id":"p1","name":"P1","schemaVersion":2,"aspectRatio":"post",'
        '"category":null,"premium":true,"thumbnailDataUrl":null},'
        '{"id":"q1","name":"Q1","schemaVersion":2,"aspectRatio":"square",'
        '"category":null,"premium":false,"thumbnailDataUrl":null}]';

    String template(String id, int w, int h) =>
        '{"template":{"id":"$id","schemaVersion":2,"version":1,"name":"$id",'
        '"aspectRatio":"story","canvas":{"width":$w,"height":$h},'
        '"panels":[{"id":"p","backgroundColor":"#FFFFFF","layers":[]}]}}';

    TemplateStore store() => TemplateStore(
      api: TemplateApi(
        client: MockClient((req) async {
          final path = req.url.path;
          if (path == '/api/templates') return http.Response(indexBody, 200);
          if (path == '/api/assets') return http.Response('[]', 200);
          final dims = switch (path.split('/').last) {
            'p1' => (1080, 1350),
            'q1' => (1080, 1080),
            _ => (1080, 1920),
          };
          return http.Response(template('x', dims.$1, dims.$2), 200);
        }),
      ),
      cacheDirOverride: tmp,
    );

    /// Same real-IO pattern as the other gallery tests: the store reads and
    /// writes its cache with dart:io, so these run in runAsync and poll.
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

    Finder cardOf(String id) => find.byKey(ValueKey('template-card-$id'));

    testWidgets('each card is cut to its own template aspect', (tester) async {
      await tester.runAsync(() async {
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
          () => tester.any(cardOf('s1')),
          reason: 'the template grid never loaded',
        );

        // Let the staggered entrance finish — mid-flight every card carries
        // its own slide offset and the geometry below would measure that.
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        final story = tester.getRect(cardOf('s1'));
        final post = tester.getRect(cardOf('p1'));
        final square = tester.getRect(cardOf('q1'));
        // The shape IS the format — this is what replaced the caption bar.
        expect(story.width / story.height, closeTo(9 / 16, 0.01));
        expect(post.width / post.height, closeTo(4 / 5, 0.01));
        expect(square.width / square.height, closeTo(1.0, 0.01));

        // Two equal columns, so every card is the same width and the heights
        // are what differ.
        expect(post.width, closeTo(story.width, 0.5));
        expect(square.width, closeTo(story.width, 0.5));
        expect(story.height, greaterThan(post.height));

        // Masonry, not rows: the third card stacks under the SHORTER of the
        // two above it rather than waiting for a row break.
        expect(square.top, closeTo(post.bottom + 12, 0.5));
        expect(square.left, closeTo(post.left, 0.5));
      });
    });

    testWidgets('the premium card carries a PRO badge, the free ones do not', (
      tester,
    ) async {
      await tester.runAsync(() async {
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
          () => tester.any(cardOf('p1')),
          reason: 'the template grid never loaded',
        );

        expect(
          find.descendant(of: cardOf('p1'), matching: find.text('PRO')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: cardOf('s1'), matching: find.text('PRO')),
          findsNothing,
        );
      });
    });
  });
}
