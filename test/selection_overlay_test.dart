import 'package:collageapp/src/model/slot_content.dart';
import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/rendering/template_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextStyle testFontResolver(String family, TextStyle base) => base;

/// The screen-space selection overlay (CanvasSelectionOverlay): chrome and
/// ring/handle gestures follow the selected element through a LayerLink, so
/// they stay touchable even where the element spills PAST the canvas edge —
/// in-canvas hit tests stop at the canvas bounds, the follower's don't.
///
/// Geometry used throughout: 800x600 screen, a 200x200 view box centered on
/// it (canvas box = (300,200)-(500,400)), a 400x400 template canvas →
/// FittedBox scale 0.5. The image slot sits at (250,100) 200x200, so its
/// right 50 template px (25 screen px) hang PAST the canvas right edge. With
/// scale 1 the padded chrome box is 360x360 at template (170,20); its screen
/// origin is (385,210) and the element's center is at screen (475,300).
void main() {
  final template = Template.fromJson({
    'id': 't_overlay',
    'version': 1,
    'name': 'overlay test',
    'aspectRatio': '1:1',
    'canvas': {'width': 400, 'height': 400},
    'layers': [
      {
        'id': 'img1',
        'type': 'image',
        'slotId': 'slot_1',
        'x': 250,
        'y': 100,
        'width': 200,
        'height': 200,
      },
    ],
  });

  // Pumps the screen-shaped harness: PanelCanvas publishing the selection
  // leader, CanvasSelectionOverlay stacked above it — the same wiring
  // TemplateScreen uses. Returns closures reading the live SlotContent and
  // the canvas-tap count.
  Future<
    ({
      SlotContent Function() content,
      int Function() taps,
      List<String> Function() deleted,
    })
  >
  pumpHarness(
    WidgetTester tester, {
    Template? withTemplate,
    double canvasSize = 400,
    SlotContent initialContent = const SlotContent(),
  }) async {
    final tpl = withTemplate ?? template;
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final link = LayerLink();
    var content = initialContent;
    var taps = 0;
    final deleted = <String>[];
    (String, Size)? box;
    final imageLayer = tpl.panels.first.layers.first as ImageLayer;

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: StatefulBuilder(
          builder: (context, setState) {
            void drag(String id, Offset d) => setState(() {
              content = content.withOffset(id, content.offsetFor(id) + d);
            });
            void scale(String id, double s) => setState(() {
              content = content.withScale(id, s);
            });
            void rotate(String id, double deg) => setState(() {
              content = content.withRotation(id, deg);
            });
            // Mirrors TemplateScreen._edgeResizeSelected: the new factor and
            // the anchoring offset compensation land in one edit.
            void edgeResize(String id, SlotEdge edge, double f, Offset dOff) =>
                setState(() {
                  final horizontal =
                      edge == SlotEdge.left || edge == SlotEdge.right;
                  content =
                      (horizontal
                              ? content.withStretchX(id, f)
                              : content.withStretchY(id, f))
                          .withOffset(id, content.offsetFor(id) + dOff);
                });
            return Stack(
              children: [
                Center(
                  child: SizedBox(
                    width: 200,
                    height: 200,
                    child: PanelCanvas(
                      panel: tpl.panels.first,
                      canvasWidth: canvasSize,
                      canvasHeight: canvasSize,
                      content: content,
                      fontResolver: testFontResolver,
                      selectedSlotId: 'slot_1',
                      onSlotTap: (_) => setState(() => taps++),
                      onSlotDrag: drag,
                      onSlotScale: scale,
                      onSlotRotate: rotate,
                      selectionLink: link,
                      onSelectionSize: (s) =>
                          setState(() => box = ('slot_1', s)),
                    ),
                  ),
                ),
                if (box != null)
                  Positioned.fill(
                    child: CanvasSelectionOverlay(
                      link: link,
                      size: box!.$2,
                      targetId: 'slot_1',
                      currentScale: content.scaleFor('slot_1'),
                      currentRotation: content.rotationFor('slot_1'),
                      templateRotation: 0,
                      currentStretchX: content.stretchXFor('slot_1'),
                      currentStretchY: content.stretchYFor('slot_1'),
                      baseSize: Size(imageLayer.width, imageLayer.height),
                      onDrag: drag,
                      onScaleChange: scale,
                      onRotateChange: rotate,
                      onEdgeResize: edgeResize,
                      onDelete: deleted.add,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
    // The leader box size lands in a post-frame callback; the overlay mounts
    // on the frame after.
    await tester.pumpAndSettle();
    return (content: () => content, taps: () => taps, deleted: () => deleted);
  }

  testWidgets('corner resize works past the canvas edge', (tester) async {
    final h = await pumpHarness(tester);

    // The element's bottom-right corner paints at screen (525,350) — 25 px
    // BEYOND the canvas box, where the in-canvas chrome could never be hit.
    final gesture = await tester.startGesture(const Offset(525, 350));
    await gesture.moveBy(const Offset(30, 30));
    await tester.pump();
    await gesture.moveBy(const Offset(30, 30));
    await tester.pump();
    await gesture.up();

    // Resize tracks finger distance to the element center (475,300):
    // start 70.71, end |(110,110)| = 155.56 → scale 2.2.
    expect(h.content().scaleFor('slot_1'), closeTo(2.2, 0.05));
  });

  testWidgets('ring drag past the canvas edge moves the element', (
    tester,
  ) async {
    final h = await pumpHarness(tester);

    // (560,240): on the chrome ring's top-right diagonal, past the canvas
    // edge (x=500) and outside every handle zone — with the edge pills the
    // straight ring bands between the corners now resize, so a plain ring
    // move has to start in a diagonal gap.
    final gesture = await tester.startGesture(const Offset(560, 240));
    // First move eats the touch slop; the second is delivered in full.
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    final mid = h.content().offsetFor('slot_1');
    await gesture.moveBy(const Offset(50, 30));
    await tester.pump();
    await gesture.up();

    // Deltas arrive in leader-local units: 50 screen px / 0.5 = 100.
    expect(h.content().offsetFor('slot_1') - mid, const Offset(100, 60));
  });

  testWidgets('chrome takes the leader size even past the overlay box '
      '(big grid-sized elements)', (tester) async {
    // A near-canvas-sized element: its padded chrome box is 760 leader-local
    // units — BIGGER than the 800x600 screen box the overlay is laid out in.
    // Anything that clamps the follower child to the overlay's constraints
    // (Align, OverflowBox) shrinks the chrome to a fraction of the element.
    final big = Template.fromJson({
      'id': 't_big',
      'version': 1,
      'name': 'big element',
      'aspectRatio': '1:1',
      'canvas': {'width': 800, 'height': 800},
      'layers': [
        {
          'id': 'img1',
          'type': 'image',
          'slotId': 'slot_1',
          'x': 300,
          'y': 300,
          'width': 600,
          'height': 600,
        },
      ],
    });
    final h = await pumpHarness(tester, withTemplate: big, canvasSize: 800);

    // FittedBox scale 0.25; the element's bottom-right corner paints at
    // screen (525,425) — past the canvas box (500,400). Only a full-sized
    // chrome box reaches it.
    final gesture = await tester.startGesture(const Offset(525, 425));
    await gesture.moveBy(const Offset(30, 30));
    await tester.pump();
    await gesture.moveBy(const Offset(30, 30));
    await tester.pump();
    await gesture.up();

    // Distance to the element center (450,350): start 106.07, end 190.92 →
    // scale 1.8.
    expect(h.content().scaleFor('slot_1'), closeTo(1.8, 0.05));
  });

  testWidgets('interior touches fall through the overlay to the canvas', (
    tester,
  ) async {
    final h = await pumpHarness(tester);

    // (475,300) is the element's center ON the canvas, away from every
    // corner/edge zone: the overlay must NOT claim it, so the canvas
    // tap-select fires.
    await tester.tapAt(const Offset(475, 300));
    await tester.pump();

    expect(h.taps(), 1);
    expect(h.content().offsetFor('slot_1'), Offset.zero);
  });

  testWidgets('tapping the delete handle reports onDelete', (tester) async {
    final h = await pumpHarness(tester);

    // The delete handle floats 68 leader-local units above the element's
    // top-center — template (350,100) → screen (475,250) — so it paints at
    // screen (475,216). The tap must fire onDelete, not select or move.
    await tester.tapAt(const Offset(475, 216));
    await tester.pump();

    expect(h.deleted(), ['slot_1']);
    expect(h.taps(), 0);
    expect(h.content().offsetFor('slot_1'), Offset.zero);
  });

  // Edge pills: single-axis stretch anchored on the opposite edge. Element
  // edges paint at screen: left (425,300), right (525,300), top (475,250),
  // bottom (475,350). The factor tracks the finger's distance to the fixed
  // opposite edge: start 100 screen px, so +50 along the axis → 1.5.
  testWidgets('right pill stretches width only, left edge stays fixed', (
    tester,
  ) async {
    final h = await pumpHarness(tester);

    final gesture = await tester.startGesture(const Offset(525, 300));
    await gesture.moveBy(const Offset(25, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(25, 0));
    await tester.pump();
    await gesture.up();

    expect(h.content().stretchXFor('slot_1'), closeTo(1.5, 0.05));
    expect(h.content().stretchYFor('slot_1'), 1.0);
    expect(h.content().scaleFor('slot_1'), 1.0);
    // At scale 1 the layout box already grows rightward from its pinned
    // top-left, so holding the left edge needs no offset at all.
    expect(h.content().offsetFor('slot_1').dx, closeTo(0, 1));
    expect(h.content().offsetFor('slot_1').dy, closeTo(0, 1));
  });

  testWidgets('left pill stretches width only, right edge stays fixed', (
    tester,
  ) async {
    final h = await pumpHarness(tester);

    final gesture = await tester.startGesture(const Offset(425, 300));
    await gesture.moveBy(const Offset(-25, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-25, 0));
    await tester.pump();
    await gesture.up();

    // Same factor as the right-pill case, but the layout box grows to the
    // RIGHT, so the offset shifts left by the full growth (100 template px)
    // to pin the right edge.
    expect(h.content().stretchXFor('slot_1'), closeTo(1.5, 0.05));
    expect(h.content().offsetFor('slot_1').dx, closeTo(-100, 5));
    expect(h.content().offsetFor('slot_1').dy, closeTo(0, 1));
  });

  testWidgets('bottom pill stretches height only, top edge stays fixed', (
    tester,
  ) async {
    final h = await pumpHarness(tester);

    final gesture = await tester.startGesture(const Offset(475, 350));
    await gesture.moveBy(const Offset(0, 25));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 25));
    await tester.pump();
    await gesture.up();

    expect(h.content().stretchYFor('slot_1'), closeTo(1.5, 0.05));
    expect(h.content().stretchXFor('slot_1'), 1.0);
    expect(h.content().offsetFor('slot_1').dx, closeTo(0, 1));
    expect(h.content().offsetFor('slot_1').dy, closeTo(0, 1));
  });

  testWidgets('top pill stretches height, bottom edge stays fixed — and '
      'wins over the delete handle at its own center', (tester) async {
    final h = await pumpHarness(tester);

    final gesture = await tester.startGesture(const Offset(475, 250));
    await gesture.moveBy(const Offset(0, -25));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -25));
    await tester.pump();
    await gesture.up();

    expect(h.deleted(), isEmpty);
    expect(h.content().stretchYFor('slot_1'), closeTo(1.5, 0.05));
    // The layout box grows DOWNWARD, so the offset shifts up by the full
    // growth (100 template px) to pin the bottom edge.
    expect(h.content().offsetFor('slot_1').dy, closeTo(-100, 5));
    expect(h.content().offsetFor('slot_1').dx, closeTo(0, 1));
  });

  testWidgets('stretching a ROTATED element keeps the opposite edge anchored', (
    tester,
  ) async {
    final h = await pumpHarness(
      tester,
      initialContent: const SlotContent(rotations: {'slot_1': 30}),
    );

    // The left pill sits ON the anchor edge: if the compensation math is
    // right, its painted position survives the whole stretch untouched.
    final leftKey = find.byKey(const ValueKey('handle_edge_l'));
    final before = tester.getCenter(leftKey);
    final rightPill = tester.getCenter(
      find.byKey(const ValueKey('handle_edge_r')),
    );
    final along = rightPill - before;
    final axis = along / along.distance;

    final gesture = await tester.startGesture(rightPill);
    await gesture.moveBy(axis * 30);
    await tester.pump();
    await gesture.moveBy(axis * 30);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(h.content().stretchXFor('slot_1'), greaterThan(1.2));
    expect(h.content().stretchYFor('slot_1'), 1.0);
    expect((tester.getCenter(leftKey) - before).distance, lessThan(3));
  });

  testWidgets('the rotation handle still wins over the bottom pill', (
    tester,
  ) async {
    final h = await pumpHarness(tester);

    // (475,384) is the rotation handle's center — 34 screen px below the
    // bottom pill, inside BOTH zones; the closer center (rotate) wins.
    final gesture = await tester.startGesture(const Offset(475, 384));
    await gesture.moveBy(const Offset(36, -42));
    await tester.pump();
    await gesture.moveBy(const Offset(36, -42));
    await tester.pump();
    await gesture.up();

    // The finger swung from straight below the center (475,300) to straight
    // right of it: 90° → 0°, i.e. −90 degrees of user rotation.
    expect(h.content().rotationFor('slot_1'), closeTo(-90, 2));
    expect(h.content().stretchYFor('slot_1'), 1.0);
  });

  group('text slots', () {
    final textTemplate = Template.fromJson({
      'id': 't_text',
      'version': 1,
      'name': 'text test',
      'aspectRatio': '1:1',
      'canvas': {'width': 400, 'height': 400},
      'layers': [
        {
          'id': 'txt1',
          'type': 'text',
          'slotId': 'title',
          'x': 50,
          'y': 60,
          'width': 300,
          'fontFamily': 'Roboto',
          'fontSize': 60,
          'fontWeight': 400,
          'color': '#000000',
          'alignment': 'left',
        },
      ],
    });

    // Legacy in-canvas chrome (no overlay link): pills render inside the
    // canvas, which is all these cases need. The Ahem test font makes every
    // glyph a 60px square, so the four words wrap to four lines — tall
    // enough (240 template px) for the side pills to fit.
    Future<SlotContent Function()> pumpText(WidgetTester tester) async {
      tester.view.physicalSize = const Size(540, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var content = const SlotContent(texts: {'title': 'aaa bbb ccc ddd'});
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: StatefulBuilder(
            builder: (context, setState) => Center(
              child: TemplateCanvas(
                template: textTemplate,
                fontResolver: testFontResolver,
                content: content,
                selectedSlotId: 'title',
                onSlotTap: (_) {},
                onSlotDrag: (_, _) {},
                onSlotScale: (_, _) {},
                onSlotEdgeResize: (id, edge, f, dOff) => setState(() {
                  final horizontal =
                      edge == SlotEdge.left || edge == SlotEdge.right;
                  content =
                      (horizontal
                              ? content.withStretchX(id, f)
                              : content.withStretchY(id, f))
                          .withOffset(id, content.offsetFor(id) + dOff);
                }),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return () => content;
    }

    testWidgets('show only the side pills (height is automatic)', (
      tester,
    ) async {
      await pumpText(tester);

      expect(find.byKey(const ValueKey('handle_edge_l')), findsOneWidget);
      expect(find.byKey(const ValueKey('handle_edge_r')), findsOneWidget);
      expect(find.byKey(const ValueKey('handle_edge_t')), findsNothing);
      expect(find.byKey(const ValueKey('handle_edge_b')), findsNothing);
    });

    testWidgets('dragging the right pill widens the wrap width', (
      tester,
    ) async {
      final content = await pumpText(tester);

      final pill = tester.getCenter(
        find.byKey(const ValueKey('handle_edge_r')),
      );
      final gesture = await tester.startGesture(pill);
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.up();

      expect(content().stretchXFor('title'), greaterThan(1.1));
      // Wrap-width change only — no uniform scale, no vertical stretch.
      expect(content().scaleFor('title'), 1.0);
      expect(content().stretchYFor('title'), 1.0);
    });
  });
}
