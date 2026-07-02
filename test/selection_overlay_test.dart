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
  Future<({SlotContent Function() content, int Function() taps})> pumpHarness(
    WidgetTester tester, {
    Template? withTemplate,
    double canvasSize = 400,
  }) async {
    final tpl = withTemplate ?? template;
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final link = LayerLink();
    var content = const SlotContent();
    var taps = 0;
    (String, Size)? box;

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
                      onDrag: drag,
                      onScaleChange: scale,
                      onRotateChange: rotate,
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
    return (content: () => content, taps: () => taps);
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

    // (530,300): on the chrome ring right of the element, past the canvas
    // edge (x=500) and outside every corner zone.
    final gesture = await tester.startGesture(const Offset(530, 300));
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

    // (450,300) is inside the element ON the canvas, away from every corner
    // zone: the overlay must NOT claim it, so the canvas tap-select fires.
    await tester.tapAt(const Offset(450, 300));
    await tester.pump();

    expect(h.taps(), 1);
    expect(h.content().offsetFor('slot_1'), Offset.zero);
  });
}
