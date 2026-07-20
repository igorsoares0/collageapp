import 'package:collageapp/src/model/slide_ops.dart';
import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/rendering/template_canvas.dart';
import 'package:collageapp/src/screens/template_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reordering in the layers sheet must change what the CANVAS paints.
///
/// The sheet reads its own list back through the reorder override, so it
/// showed the new order whether or not the canvas honoured it — the sheet
/// looking right proves nothing. These tests assert the paint order.

TextStyle _testFontResolver(String family, TextStyle base) => base;

/// Two overlapping text layers on one slide. 'bottom' is first in the layer
/// list, so it paints first (underneath); 'top' paints over it.
final _template = Template(
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
        TextLayer(
          id: 'l_bottom',
          hidden: false,
          slotId: 'bottom',
          x: 100,
          y: 800,
          width: 600,
          fontFamily: 'Inter',
          fontSize: 64,
          fontWeight: 400,
          color: Color(0xFF111111),
          alignment: 'left',
        ),
        TextLayer(
          id: 'l_top',
          hidden: false,
          slotId: 'top',
          x: 100,
          y: 900,
          width: 600,
          fontFamily: 'Inter',
          fontSize: 64,
          fontWeight: 400,
          color: Color(0xFF111111),
          alignment: 'left',
        ),
      ],
    ),
  ],
);

/// The slot labels the canvas paints, in stack order (index 0 = bottom).
List<String> _canvasOrder(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(
    find.descendant(of: find.byType(CanvasView), matching: find.byType(Text)),
  ))
    if (t.data case final d?)
      if (d == 'top' || d == 'bottom') d,
];

/// A [Document] of [slideCount] slides, each holding layers named `s<i>_<n>`
/// placed inside that slide.
Document _doc(int slideCount, int perSlide) => Document(
  id: 'd',
  schemaVersion: 4,
  version: 1,
  name: 'D',
  aspectRatio: '9:16',
  slideWidth: 1000,
  slideHeight: 1920,
  slideCount: slideCount,
  gutter: 0,
  slideBackgrounds: [
    for (var i = 0; i < slideCount; i++) const Color(0xFFFFFFFF),
  ],
  layers: [
    for (var i = 0; i < slideCount; i++)
      for (var n = 0; n < perSlide; n++)
        ShapeLayer(
          id: 's${i}_$n',
          hidden: false,
          x: i * 1000.0 + 100,
          y: 100,
          width: 200,
          height: 200,
          fill: const Color(0xFF000000),
        ),
  ],
);

void main() {
  group('reorderLayersInSlide', () {
    test('restacks one slide and leaves the others exactly as they were', () {
      final doc = _doc(3, 3);
      final next = reorderLayersInSlide(doc, 1, ['s1_2', 's1_0', 's1_1']);
      expect(
        [for (final l in next.layers) l.id],
        [
          's0_0', 's0_1', 's0_2', // untouched
          's1_2', 's1_0', 's1_1', // restacked
          's2_0', 's2_1', 's2_2', // untouched
        ],
      );
    });

    test('an id the list omits keeps its place rather than vanishing', () {
      final doc = _doc(1, 3);
      final next = reorderLayersInSlide(doc, 0, ['s0_2', 's0_0']);
      // Every layer survives; the unmentioned one lands on top.
      expect([for (final l in next.layers) l.id], ['s0_2', 's0_0', 's0_1']);
    });

    test('ids from another slide are ignored, not spliced in', () {
      final doc = _doc(2, 2);
      final next = reorderLayersInSlide(doc, 0, ['s1_0', 's0_1', 's0_0']);
      expect(
        [for (final l in next.layers) l.id],
        ['s0_1', 's0_0', 's1_0', 's1_1'],
      );
    });
  });

  testWidgets('a drag in the layers sheet restacks the canvas', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: TemplateScreen(draft: _template, fontResolver: _testFontResolver),
      ),
    );
    await tester.pumpAndSettle();

    expect(_canvasOrder(tester), ['bottom', 'top']);

    // Open the layers sheet and drag the front row (listed first, since the
    // sheet shows front-to-back) down past the other one.
    await tester.tap(find.text('Layers'));
    await tester.pumpAndSettle();
    final handles = find.byIcon(Icons.drag_indicator);
    expect(handles, findsNWidgets(2));
    // ReorderableListView tracks the pointer frame by frame; a single
    // tester.drag() jumps past its bookkeeping and drops in place.
    final g = await tester.startGesture(tester.getCenter(handles.first));
    await tester.pump(const Duration(milliseconds: 600));
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(0, 10));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();

    // Close the sheet and read the canvas back.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(_canvasOrder(tester), [
      'top',
      'bottom',
    ], reason: 'the reorder never reached the canvas');
  });
}
