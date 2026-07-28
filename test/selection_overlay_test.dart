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

    // (565,205): on the chrome ring's top-right diagonal, past the canvas
    // edge (x=500) and outside every handle zone — with the edge pills the
    // straight ring bands between the corners now resize, so a plain ring
    // move has to start in a diagonal gap (60 screen px from the corner,
    // beyond the 45 the widened resize zones reach).
    final gesture = await tester.startGesture(const Offset(565, 205));
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

  // Edge pills: single-axis stretch anchored on the opposite edge.
  //
  // These need their OWN fixture. A pill only exists on a side long enough to
  // host it without colliding with the corner dots (_edgePillsFit) — 216
  // template px — and the shared 200x200 element sits just under that. So
  // this group uses a 240x240 one at the same origin: only the far edges
  // move. It paints at screen (425,250)-(545,370), center (485,310), so the
  // edge midpoints are left (425,310), right (545,310), top (485,250),
  // bottom (485,370). The factor tracks the finger's distance to the fixed
  // opposite edge: start 120 screen px, so +60 along the axis → 1.5. Growth
  // in template px is 240 × 0.5 = 120.
  final pillTemplate = Template.fromJson({
    'id': 't_pills',
    'version': 1,
    'name': 'pill test',
    'aspectRatio': '1:1',
    'canvas': {'width': 400, 'height': 400},
    'layers': [
      {
        'id': 'img1',
        'type': 'image',
        'slotId': 'slot_1',
        'x': 250,
        'y': 100,
        'width': 240,
        'height': 240,
      },
    ],
  });

  testWidgets('right pill stretches width only, left edge stays fixed', (
    tester,
  ) async {
    final h = await pumpHarness(tester, withTemplate: pillTemplate);

    final gesture = await tester.startGesture(const Offset(545, 310));
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(30, 0));
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
    final h = await pumpHarness(tester, withTemplate: pillTemplate);

    final gesture = await tester.startGesture(const Offset(425, 310));
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture.up();

    // Same factor as the right-pill case, but the layout box grows to the
    // RIGHT, so the offset shifts left by the full growth (120 template px)
    // to pin the right edge.
    expect(h.content().stretchXFor('slot_1'), closeTo(1.5, 0.05));
    expect(h.content().offsetFor('slot_1').dx, closeTo(-120, 5));
    expect(h.content().offsetFor('slot_1').dy, closeTo(0, 1));
  });

  testWidgets('bottom pill stretches height only, top edge stays fixed', (
    tester,
  ) async {
    final h = await pumpHarness(tester, withTemplate: pillTemplate);

    final gesture = await tester.startGesture(const Offset(485, 370));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.up();

    expect(h.content().stretchYFor('slot_1'), closeTo(1.5, 0.05));
    expect(h.content().stretchXFor('slot_1'), 1.0);
    expect(h.content().offsetFor('slot_1').dx, closeTo(0, 1));
    expect(h.content().offsetFor('slot_1').dy, closeTo(0, 1));
  });

  testWidgets('top pill stretches height, bottom edge stays fixed — and '
      'wins over the delete handle at its own center', (tester) async {
    final h = await pumpHarness(tester, withTemplate: pillTemplate);

    final gesture = await tester.startGesture(const Offset(485, 250));
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    await gesture.up();

    expect(h.deleted(), isEmpty);
    expect(h.content().stretchYFor('slot_1'), closeTo(1.5, 0.05));
    // The layout box grows DOWNWARD, so the offset shifts up by the full
    // growth (120 template px) to pin the bottom edge.
    expect(h.content().offsetFor('slot_1').dy, closeTo(-120, 5));
    expect(h.content().offsetFor('slot_1').dx, closeTo(0, 1));
  });

  testWidgets('stretching a ROTATED element keeps the opposite edge anchored', (
    tester,
  ) async {
    final h = await pumpHarness(
      tester,
      withTemplate: pillTemplate,
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
    // Needs the pill fixture: on the shared 200x200 element there is no
    // bottom pill to lose, so the arbitration would go untested.
    final h = await pumpHarness(tester, withTemplate: pillTemplate);

    // NOT the handle's own center: at _kRotateHandleDrop (100) beyond a
    // reach of _kResizeReach (96), the pill zone can no longer reach it, so
    // that point would prove nothing. (485,400) is 60 template px below the
    // bottom edge — inside the pill's zone (60 < 96) AND the handle's
    // (40 < _kCornerReach 72). The closer center, the handle's, must win.
    final gesture = await tester.startGesture(const Offset(485, 400));
    await gesture.moveBy(const Offset(45, -45));
    await tester.pump();
    await gesture.moveBy(const Offset(45, -45));
    await tester.pump();
    await gesture.up();

    // The finger swung from straight below the center (485,310) to straight
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

  group('small text (floored resize reach)', () {
    // A single 40px line, 200 template px wide: the shorter side (40) used to
    // cap the corner zones at 18 template px — SMALLER than the drawn 60px
    // corner dot, so grabbing a visible handle silently moved the element.
    // The floor (_kMinResizeReach) keeps the zones covering the dot.
    final smallText = Template.fromJson({
      'id': 't_small',
      'version': 1,
      'name': 'small text',
      'aspectRatio': '1:1',
      'canvas': {'width': 400, 'height': 400},
      'layers': [
        {
          'id': 'txt1',
          'type': 'text',
          'slotId': 'title',
          'x': 100,
          'y': 180,
          'width': 200,
          'fontFamily': 'Roboto',
          'fontSize': 40,
          'fontWeight': 400,
          'color': '#000000',
          'alignment': 'left',
        },
      ],
    });

    // Legacy in-canvas chrome, like the text group above: enough for the
    // zone math, which the overlay path shares. NOTE the in-canvas detector
    // also wires a tap recognizer, so the scale recognizer accepts (and
    // classifies its zone) only past touch slop — the first small moveBy in
    // these tests eats that slop, like the harness tests above.
    Future<SlotContent Function()> pumpSmall(
      WidgetTester tester, {
      Template? template,
      String text = 'aaa',
    }) async {
      tester.view.physicalSize = const Size(540, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var content = SlotContent(texts: {'title': text});
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: StatefulBuilder(
            builder: (context, setState) => Center(
              child: TemplateCanvas(
                template: template ?? smallText,
                fontResolver: testFontResolver,
                content: content,
                selectedSlotId: 'title',
                onSlotTap: (_) {},
                onSlotDrag: (id, d) => setState(() {
                  content = content.withOffset(id, content.offsetFor(id) + d);
                }),
                onSlotScale: (id, s) =>
                    setState(() => content = content.withScale(id, s)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return () => content;
    }

    testWidgets('a near-corner grab resizes instead of dragging', (
      tester,
    ) async {
      final content = await pumpSmall(tester);

      // Diagonally OFF the corner dot's center — a realistic finger miss.
      // The scale recognizer accepts one slop-crossing move later, ~50 px
      // from the corner: inside the floored zone, while the old 18-unit cap
      // put it in the move region and the text slid away instead.
      final corner = tester.getCenter(find.byKey(const ValueKey('handle_br')));
      final gesture = await tester.startGesture(corner + const Offset(15, 15));
      await gesture.moveBy(const Offset(20, 20)); // Crosses the touch slop.
      await tester.pump();
      await gesture.moveBy(const Offset(40, 40));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 40));
      await tester.pump();
      await gesture.up();

      expect(content().scaleFor('title'), greaterThan(1.0));
      expect(content().offsetFor('title'), Offset.zero);
    });

    testWidgets('dragging the middle still moves it', (tester) async {
      // A wide-short line — 320x40 as hugged by the glyphs: short enough
      // (40) for the floor to apply, wide enough that its middle stays out
      // of every corner zone. Only the ENDS resize; the middle still moves.
      final wideText = Template.fromJson({
        'id': 't_wide',
        'version': 1,
        'name': 'wide text',
        'aspectRatio': '1:1',
        'canvas': {'width': 400, 'height': 400},
        'layers': [
          {
            'id': 'txt1',
            'type': 'text',
            'slotId': 'title',
            'x': 20,
            'y': 180,
            'width': 360,
            'fontFamily': 'Roboto',
            'fontSize': 40,
            'fontWeight': 400,
            'color': '#000000',
            'alignment': 'left',
          },
        ],
      });
      final content = await pumpSmall(
        tester,
        template: wideText,
        text: 'aaaaaaaa',
      );

      final center = tester.getCenter(find.text('aaaaaaaa'));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(15, 20));
      await tester.pump();
      await gesture.moveBy(const Offset(15, 20));
      await tester.pump();
      await gesture.up();

      expect(content().scaleFor('title'), 1.0);
      expect(content().offsetFor('title'), isNot(Offset.zero));
    });

    // The overlay path: _RingHitRegion now claims the widened zones, so the
    // gestures and taps below never reach the canvas — they must work from
    // the overlay itself.
    Future<
      ({
        SlotContent Function() content,
        int Function() canvasTaps,
        int Function() overlayTaps,
        List<String> Function() deleted,
      })
    >
    pumpOverlay(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final link = LayerLink();
      var content = const SlotContent(texts: {'title': 'aaa'});
      var canvasTaps = 0;
      var overlayTaps = 0;
      final deleted = <String>[];
      Size? box;

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
              return Stack(
                children: [
                  Center(
                    child: SizedBox(
                      width: 200,
                      height: 200,
                      child: PanelCanvas(
                        panel: smallText.panels.first,
                        canvasWidth: 400,
                        canvasHeight: 400,
                        content: content,
                        fontResolver: testFontResolver,
                        selectedSlotId: 'title',
                        onSlotTap: (_) => setState(() => canvasTaps++),
                        onSlotDrag: drag,
                        onSlotScale: scale,
                        selectionLink: link,
                        onSelectionSize: (s) =>
                            setState(() => box = ('title', s).$2),
                      ),
                    ),
                  ),
                  if (box != null)
                    Positioned.fill(
                      child: CanvasSelectionOverlay(
                        link: link,
                        size: box!,
                        targetId: 'title',
                        currentScale: content.scaleFor('title'),
                        currentRotation: content.rotationFor('title'),
                        templateRotation: 0,
                        verticalEdges: false,
                        onDrag: drag,
                        onScaleChange: scale,
                        onDelete: deleted.add,
                        onTap: (_) => setState(() => overlayTaps++),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (
        content: () => content,
        canvasTaps: () => canvasTaps,
        overlayTaps: () => overlayTaps,
        deleted: () => deleted,
      );
    }

    testWidgets('overlay: near-corner grab resizes', (tester) async {
      final h = await pumpOverlay(tester);

      final corner = tester.getCenter(find.byKey(const ValueKey('handle_br')));
      final gesture = await tester.startGesture(corner + const Offset(12, 12));
      await gesture.moveBy(const Offset(30, 30));
      await tester.pump();
      await gesture.moveBy(const Offset(30, 30));
      await tester.pump();
      await gesture.up();

      expect(h.content().scaleFor('title'), greaterThan(1.0));
      expect(h.content().offsetFor('title'), Offset.zero);
    });

    testWidgets('overlay: a tap on the claimed body still reaches select/edit',
        (tester) async {
      final h = await pumpOverlay(tester);

      // Inside the text body near its bottom-right corner: claimed by the
      // widened corner zone, so the canvas' own tap-to-edit can't see it —
      // the overlay must hand it back through onTap.
      final corner = tester.getCenter(find.byKey(const ValueKey('handle_br')));
      await tester.tapAt(corner + const Offset(-15, -5));
      await tester.pump();

      expect(h.overlayTaps(), 1);
      expect(h.canvasTaps(), 0);
      expect(h.content().offsetFor('title'), Offset.zero);
      expect(h.deleted(), isEmpty);
    });

    testWidgets('overlay: the delete handle still deletes at its own center', (
      tester,
    ) async {
      final h = await pumpOverlay(tester);

      final del = tester.getCenter(find.byKey(const ValueKey('handle_delete')));
      await tester.tapAt(del);
      await tester.pump();

      expect(h.deleted(), ['title']);
      expect(h.overlayTaps(), 0);
    });
  });
}
