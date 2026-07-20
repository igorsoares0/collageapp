import 'package:collageapp/src/model/slot_content.dart';
import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/rendering/template_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The selection chrome must stay grabbable when the canvas is zoomed OUT.
///
/// Every chrome dimension is `constant / scale`, which keeps it visually
/// constant however far the ELEMENT is scaled. But the chrome renders through
/// the canvas zoom as well, and that was not in the divisor — pinched out, the
/// handles shrank with the canvas to a few px and could not be hit.
///
/// These tests measure in SCREEN px, which is the only unit the complaint
/// exists in: asserting the template-space numbers would pass while a finger
/// still had nothing to grab.

TextStyle testFontResolver(String family, TextStyle base) => base;

const _slotId = 'slot_1';

/// A canvas holding one selected image slot, rendered THROUGH [zoom] the way
/// the editor's InteractiveViewer does.
Widget _canvas({required double zoom, LayerLink? link, ValueChanged<Size>? onSize}) {
  final doc = Document(
    id: 'd',
    schemaVersion: 4,
    version: 1,
    name: 'Doc',
    aspectRatio: '9:16',
    slideWidth: 1080,
    slideHeight: 1920,
    slideCount: 1,
    gutter: 0,
    slideBackgrounds: const [Color(0xFFFFFFFF)],
    layers: const [
      ImageLayer(
        id: 'layer_1',
        hidden: false,
        slotId: _slotId,
        x: 340,
        y: 760,
        width: 400,
        height: 400,
        rotation: 0,
        opacity: 1,
        borderRadius: 0,
      ),
    ],
  );
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(
        child: Transform.scale(
          scale: zoom,
          child: SizedBox(
            width: 400,
            height: 711,
            child: CanvasView(
              document: doc,
              content: const SlotContent(),
              fontResolver: testFontResolver,
              selectedSlotId: _slotId,
              viewScale: zoom,
              selectionLink: link,
              onSelectionSize: onSize,
              onSlotTap: (_) {},
              onSlotDrag: (_, __) {},
              onSlotScale: (_, __) {},
              onSlotRotate: (_, __) {},
              onSlotDelete: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  /// The delete handle's on-screen diameter — a proxy for the whole chrome,
  /// since every glyph shares the same divisor.
  ///
  /// `getRect`, NOT `getSize`: getSize returns the box's own LOCAL size, which
  /// here is template px and grows by exactly the compensation factor — it
  /// would report success no matter what the finger actually finds. getRect
  /// goes through localToGlobal, so the FittedBox and the zoom are applied and
  /// the number is real screen px.
  double handleScreenSize(WidgetTester tester) {
    final handle = find.byKey(const ValueKey('handle_delete'));
    expect(handle, findsOneWidget, reason: 'the delete handle must be drawn');
    return tester.getRect(handle).width;
  }

  Future<double> measure(WidgetTester tester, double zoom) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_canvas(zoom: zoom));
    await tester.pumpAndSettle();
    return handleScreenSize(tester);
  }

  testWidgets('THE POINT: a handle keeps its on-screen size when zoomed out', (
    tester,
  ) async {
    final atRest = await measure(tester, 1.0);
    final pinchedOut = await measure(tester, 0.25);

    expect(
      pinchedOut,
      closeTo(atRest, atRest * 0.05),
      reason:
          'at 0.25 zoom the handle used to render a quarter of its size — '
          'a few px, impossible to grab. It must stay put on screen.',
    );
  });

  testWidgets('and when zoomed IN, so handles never swallow the element', (
    tester,
  ) async {
    final atRest = await measure(tester, 1.0);
    final zoomedIn = await measure(tester, 3.0);
    expect(zoomedIn, closeTo(atRest, atRest * 0.05));
  });

  testWidgets('the chrome PAD grows too, not just the glyph', (tester) async {
    // The pad is what makes a handle touchable: the overlay's hit region gates
    // on the padded box, so a big glyph inside the old pad would be drawn and
    // still not hittable. The pad shows up as the leader box being bigger than
    // the element it wraps.
    Size? size;
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final link = LayerLink();
    await tester.pumpWidget(
      _canvas(zoom: 1.0, link: link, onSize: (s) => size = s),
    );
    await tester.pumpAndSettle();
    final atRest = size!;

    await tester.pumpWidget(
      _canvas(zoom: 0.25, link: LayerLink(), onSize: (s) => size = s),
    );
    await tester.pumpAndSettle();
    final pinchedOut = size!;

    // Element is 400x400 in template units either way; only the pad differs.
    expect(
      pinchedOut.width - 400,
      closeTo((atRest.width - 400) * 4, 1.0),
      reason: 'at a quarter of the zoom the pad must be 4x as wide in '
          'template units to cover the same band on screen',
    );
  });
}
