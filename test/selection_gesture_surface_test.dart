import 'package:collageapp/src/model/slot_content.dart';
import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/rendering/template_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextStyle testFontResolver(String family, TextStyle base) => base;

/// The canvas-wide gesture surface (SelectionGestureSurface): with a slot
/// selected, dragging/pinching/twisting ANYWHERE in the body area drives the
/// selected element — no finger ever needs to land on the element itself.
///
/// Geometry: 800x600 screen, 200x200 view box centered ((300,200)-(500,400)),
/// 400x400 template canvas → FittedBox scale 0.5, so screenToTemplate = 2.
void main() {
  final template = Template.fromJson({
    'id': 't_surface',
    'version': 1,
    'name': 'surface test',
    'aspectRatio': '1:1',
    'canvas': {'width': 400, 'height': 400},
    'layers': [
      {
        'id': 'img1',
        'type': 'image',
        'slotId': 'slot_1',
        'x': 100,
        'y': 100,
        'width': 200,
        'height': 200,
      },
    ],
  });

  Future<({SlotContent Function() content, int Function() taps})> pumpHarness(
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var content = const SlotContent();
    var taps = 0;

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
            return SelectionGestureSurface(
              targetId: 'slot_1',
              currentScale: content.scaleFor('slot_1'),
              currentRotation: content.rotationFor('slot_1'),
              screenToTemplate: () => 2.0,
              onDrag: drag,
              onScaleChange: scale,
              onRotateChange: rotate,
              child: Stack(
                children: [
                  Center(
                    child: SizedBox(
                      width: 200,
                      height: 200,
                      child: PanelCanvas(
                        panel: template.panels.first,
                        canvasWidth: 400,
                        canvasHeight: 400,
                        content: content,
                        fontResolver: testFontResolver,
                        selectedSlotId: 'slot_1',
                        onSlotTap: (_) => setState(() => taps++),
                        onSlotDrag: drag,
                        onSlotScale: scale,
                        onSlotRotate: rotate,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    return (content: () => content, taps: () => taps);
  }

  testWidgets('one-finger drag on empty space moves the selected element', (
    tester,
  ) async {
    final h = await pumpHarness(tester);

    // (100,100): dark empty area far from both the canvas box and the
    // element — only the surface is there to claim the drag.
    final gesture = await tester.startGesture(const Offset(100, 100));
    // First move eats the slop; the second is delivered in full.
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    final mid = h.content().offsetFor('slot_1');
    await gesture.moveBy(const Offset(50, 30));
    await tester.pump();
    await gesture.up();

    // 50 screen px × screenToTemplate 2 = 100 template px.
    expect(h.content().offsetFor('slot_1') - mid, const Offset(100, 60));
  });

  testWidgets('pinch anywhere resizes the selected element', (tester) async {
    final h = await pumpHarness(tester);

    // Two fingers on empty space. The recognizer re-bases its span when it
    // ACCEPTS the gesture (after the slop move), so the measured ratio is
    // relative to the post-acceptance span: 250 → 375 = scale 1.5.
    final g1 = await tester.startGesture(const Offset(200, 300));
    final g2 = await tester.startGesture(const Offset(400, 300));
    await g1.moveBy(const Offset(-50, 0)); // accept; span re-based to 250
    await tester.pump();
    await g2.moveBy(const Offset(125, 0)); // span 375
    await tester.pump();
    await g1.up();
    await g2.up();

    expect(h.content().scaleFor('slot_1'), closeTo(1.5, 0.05));
  });

  testWidgets('two-finger twist rotates the selected element', (tester) async {
    final h = await pumpHarness(tester);

    // The acceptance move keeps the finger line horizontal (angle re-bases
    // at 0°); the second move turns it vertical, same 250 span → +90°, no
    // scale change.
    final g1 = await tester.startGesture(const Offset(200, 300));
    final g2 = await tester.startGesture(const Offset(400, 300));
    await g1.moveBy(const Offset(-50, 0)); // accept; line (150→400,300), 0°
    await tester.pump();
    await g2.moveTo(const Offset(150, 550)); // line straight down, +90°
    await tester.pump();
    await g1.up();
    await g2.up();

    // The recognizer reports the raw atan2 difference, which can land on a
    // co-terminal angle (e.g. -270 instead of +90); Transform.rotate is
    // periodic, so assert modulo 360.
    final rotation = h.content().rotationFor('slot_1') % 360;
    expect((rotation + 360) % 360, closeTo(90, 1));
    expect(h.content().scaleFor('slot_1'), closeTo(1.0, 0.05));
  });

  testWidgets('taps still reach the canvas through the surface', (
    tester,
  ) async {
    final h = await pumpHarness(tester);

    // Element center on screen: canvas (200,200) → (400,300). The deeper tap
    // recognizer must win the arena sweep over the surface's scale.
    await tester.tapAt(const Offset(400, 300));
    await tester.pump();

    expect(h.taps(), 1);
    expect(h.content().offsetFor('slot_1'), Offset.zero);
  });
}
