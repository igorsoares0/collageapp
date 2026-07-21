import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/rendering/snap.dart';
import 'package:collageapp/src/screens/template_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextStyle testFontResolver(String family, TextStyle base) => base;

void main() {
  group('snapAxis', () {
    test('returns the nearest target within threshold', () {
      final r = snapAxis(points: [100, 200], targets: [95, 208], threshold: 10);
      expect(r.shift, -5); // 100 → 95 beats 200 → 208.
      expect(r.guide, 95);
    });

    test('ignores targets beyond threshold', () {
      final r = snapAxis(points: [100], targets: [150], threshold: 10);
      expect(r.shift, 0);
      expect(r.guide, isNull);
    });
  });

  group('snapDrag', () {
    // 200×200 element whose model box centers at (440, 860) on a 1080×1920
    // canvas — 100 template px off the canvas center in both axes.
    const box = Rect.fromLTWH(340, 760, 200, 200);
    const canvas = Size(1080, 1920);

    test('snaps the center onto the canvas center and reports both guides', () {
      final r = snapDrag(
        box: box,
        scale: 1,
        raw: const Offset(94, 106), // center lands 6 px off (540±, 960±)
        targets: SnapTargets.around(canvas, const []),
        threshold: 10,
        snapEdges: true,
      );
      expect(r.offset, const Offset(100, 100)); // exact center
      expect(r.guideXs, [540]);
      expect(r.guideYs, [960]);
    });

    test('snaps a scaled edge onto another element edge', () {
      // Scale 2 → painted half-width 200; left edge at 440+raw−200.
      final r = snapDrag(
        box: box,
        scale: 2,
        raw: const Offset(-233, 0), // left edge at 7 → near other's left 0…
        targets: SnapTargets.around(canvas, const [
          Rect.fromLTWH(0, 300, 100, 100),
        ]),
        threshold: 10,
        snapEdges: true,
      );
      // Left edge (207 pre-raw… 440−200−233 = 7) pulls onto the other
      // element's left edge at 0.
      expect(r.offset.dx, -240);
      expect(r.guideXs, [0]);
    });

    test('with snapEdges false only the center can snap', () {
      final r = snapDrag(
        box: box,
        scale: 1,
        raw: const Offset(-334, 0), // left edge lands at 6, center at 106
        targets: SnapTargets.around(canvas, const []),
        threshold: 10,
        snapEdges: false,
      );
      // The left edge is 6 px from the canvas edge, but edges are off and the
      // center (106) is beyond threshold from everything → no snap at all.
      expect(r.offset.dx, -334);
      expect(r.guideXs, isEmpty);
    });
  });

  testWidgets('dragging shows guides and snaps the element to the canvas '
      'center; releasing hides them', (tester) async {
    // 300×300 element centered at (420, 840) — (+120, +120) template px from
    // the canvas center, with NO edge/center pre-aligned to any guide, so the
    // first snap of a down-right sweep is the both-axis center alignment.
    final template = Template(
      id: 't',
      schemaVersion: 3,
      version: 1,
      name: 'T',
      aspectRatio: '9:16',
      canvasWidth: 1080,
      canvasHeight: 1920,
      panels: const [
        Panel(
          id: 'p',
          backgroundColor: Color(0xFFFFFFFF),
          layers: [
            ImageLayer(
              id: 'img',
              hidden: false,
              slotId: 'img',
              x: 270,
              y: 690,
              width: 300,
              height: 300,
              rotation: 0,
              opacity: 1,
              borderRadius: 0,
            ),
          ],
        ),
      ],
    );
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: TemplateScreen(draft: template, fontResolver: testFontResolver),
      ),
    );
    await tester.pumpAndSettle();

    final guides = find.byKey(const ValueKey('alignment-guides'));
    final slot = find.byWidgetPredicate(
      (w) => w is Container && w.color == const Color(0xFFE4E4E7),
    );
    expect(guides, findsNothing);

    // Select the slot: tap the placeholder below the pick icon.
    await tester.tapAt(tester.getCenter(slot) + const Offset(0, 40));
    await tester.pumpAndSettle();

    // Drag from empty canvas space (the canvas-wide selection surface moves
    // the element) diagonally towards alignment in small steps, until the
    // magnetic snap lands the element center EXACTLY on the canvas center.
    final canvasRect = tester.getRect(
      find.byKey(const ValueKey('slide-background-0')),
    );
    final gesture = await tester.startGesture(
      canvasRect.topLeft + const Offset(60, 60),
    );
    var centered = false;
    for (var i = 0; i < 60 && !centered; i++) {
      await gesture.moveBy(const Offset(3, 3));
      await tester.pump();
      centered = (tester.getCenter(slot) - canvasRect.center).distance < 1.0;
    }
    expect(centered, isTrue, reason: 'the sweep never snapped to the center');
    // And the guide lines are up while snapped.
    expect(guides, findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(guides, findsNothing);
  });
}
