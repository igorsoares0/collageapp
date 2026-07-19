import 'dart:ui' as ui;

import 'package:collageapp/src/model/slot_content.dart';
import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/rendering/template_canvas.dart';
import 'package:flutter/material.dart';
// `show`: a bare import would clash with the app's own model `Layer`.
import 'package:flutter/rendering.dart' show RenderBox, RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';

/// CanvasView — the v4 continuous renderer (Modelo B, phase 2c).
///
/// The payoff test is the last one: render the whole document ONCE and slice
/// it, proving a panorama really crosses slides (instead of being faked by the
/// bleed) and that the slices line up by construction.

TextStyle testFontResolver(String family, TextStyle base) => base;

const slideW = 300.0;
const slideH = 400.0;
const bgs = [Color(0xFFFF0000), Color(0xFF00FF00), Color(0xFF0000FF)];

ShapeLayer band(String id, double x, double width, Color fill, {double height = 200}) =>
    ShapeLayer(id: id, hidden: false, x: x, y: 0, width: width, height: height, fill: fill);

Document doc({required List<Layer> layers, int slideCount = 3, double gutter = 0}) =>
    Document(
      id: 'd',
      schemaVersion: 4,
      version: 1,
      name: 'Doc',
      aspectRatio: '9:16',
      slideWidth: slideW,
      slideHeight: slideH,
      slideCount: slideCount,
      gutter: gutter,
      slideBackgrounds: bgs.take(slideCount).toList(),
      layers: layers,
    );

Widget host(Widget child, {Size size = const Size(900, 400)}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(child: SizedBox(width: size.width, height: size.height, child: child)),
);

Future<Color> pixelAt(ui.Image image, int x, int y) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final o = (y * image.width + x) * 4;
  final b = data.buffer.asUint8List();
  return Color.fromARGB(b[o + 3], b[o], b[o + 1], b[o + 2]);
}

Future<ui.Image> crop(ui.Image src, Rect r) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
    src,
    r,
    Rect.fromLTWH(0, 0, r.width, r.height),
    Paint()..filterQuality = FilterQuality.high,
  );
  return recorder.endRecording().toImage(r.width.round(), r.height.round());
}

int _ch(double v) => (v * 255.0).round() & 0xff;

bool near(Color a, Color b, {int tol = 6}) =>
    (_ch(a.r) - _ch(b.r)).abs() <= tol &&
    (_ch(a.g) - _ch(b.g)).abs() <= tol &&
    (_ch(a.b) - _ch(b.b)).abs() <= tol;

void main() {
  testWidgets('paints one background per slide, at its slide rect', (tester) async {
    await tester.pumpWidget(
      host(
        CanvasView(
          document: doc(layers: const []),
          content: const SlotContent(),
          fontResolver: testFontResolver,
        ),
      ),
    );

    for (var i = 0; i < 3; i++) {
      expect(find.byKey(ValueKey('slide-background-$i')), findsOneWidget);
    }
    // The document is one canvas contentWidth wide, not three boxes.
    final box = tester.renderObject<RenderBox>(
      find.byType(CanvasView),
    );
    expect(box.hasSize, isTrue);
  });

  testWidgets('a spanning layer is rendered ONCE, not echoed as a bleed', (tester) async {
    await tester.pumpWidget(
      host(
        CanvasView(
          document: doc(layers: [band('pano', 0, 900, const Color(0xFF000000))]),
          content: const SlotContent(),
          fontResolver: testFontResolver,
        ),
      ),
    );

    // In the panel model this needed a ghost copy per neighbouring panel; here
    // there is exactly one widget for the one layer.
    final shapes = find.byWidgetPredicate(
      (w) => w is ColoredBox && w.color == const Color(0xFF000000),
    );
    expect(shapes, findsOneWidget);
  });

  testWidgets('hidden layers are filtered out', (tester) async {
    await tester.pumpWidget(
      host(
        CanvasView(
          document: doc(layers: [band('a', 0, 100, const Color(0xFF00FFFF))]),
          content: const SlotContent().withLayerHidden('a', true),
          fontResolver: testFontResolver,
        ),
      ),
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == const Color(0xFF00FFFF),
      ),
      findsNothing,
    );
  });

  testWidgets('cut guides are opt-in and never inside the export boundary', (tester) async {
    final exportKey = GlobalKey();

    Widget build({required bool guides}) => host(
      CanvasView(
        document: doc(layers: const []),
        content: const SlotContent(),
        fontResolver: testFontResolver,
        showCutGuides: guides,
        exportKey: exportKey,
      ),
    );

    await tester.pumpWidget(build(guides: false));
    expect(find.byKey(const ValueKey('cut-guides')), findsNothing);

    await tester.pumpWidget(build(guides: true));
    final guides = find.byKey(const ValueKey('cut-guides'));
    expect(guides, findsOneWidget);
    // The guides must sit OUTSIDE the export RepaintBoundary, or they would
    // land in the exported PNG.
    expect(
      find.descendant(of: find.byKey(exportKey), matching: guides),
      findsNothing,
    );
  });

  testWidgets('single-slide documents draw no cut guides', (tester) async {
    await tester.pumpWidget(
      host(
        CanvasView(
          document: doc(layers: const [], slideCount: 1),
          content: const SlotContent(),
          fontResolver: testFontResolver,
          showCutGuides: true,
        ),
        size: const Size(300, 400),
      ),
    );
    expect(find.byKey(const ValueKey('cut-guides')), findsNothing);
  });

  group('editing on the continuous canvas', () {
    TextLayer label(String id, double x) => TextLayer(
      id: id,
      hidden: false,
      slotId: 'slot_$id',
      x: x,
      y: 150,
      width: 200,
      fontFamily: 'Inter',
      fontSize: 24,
      fontWeight: 400,
      color: const Color(0xFF000000),
      alignment: 'left',
    );

    // Two labels: one on slide 0, one on slide 2. Slides are 300 wide here, so
    // slide 2 starts at x=600. The second label is the interesting one — in the
    // panel model every panel restarted at x=0, so a gesture landing correctly
    // at a continuous x=610 is what proves hit testing survived the move to one
    // coordinate space.
    Document twoLabels() => doc(layers: [label('a', 10), label('c', 610)]);
    const texts = SlotContent(
      texts: {'slot_a': 'FirstSlide', 'slot_c': 'ThirdSlide'},
    );

    /// The document is 900 units wide; the default 800px test surface would
    /// push slide 2 off-screen where it cannot be tapped.
    void sizeSurface(WidgetTester tester) {
      tester.view.physicalSize = const Size(900, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('tapping a slot on a LATER slide reports that slot', (
      tester,
    ) async {
      sizeSurface(tester);
      final tapped = <String>[];
      await tester.pumpWidget(
        host(
          CanvasView(
            document: twoLabels(),
            content: texts,
            fontResolver: testFontResolver,
            onSlotTap: tapped.add,
          ),
        ),
      );

      await tester.tap(find.text('ThirdSlide'));
      await tester.pump();
      expect(tapped, ['slot_c']);

      await tester.tap(find.text('FirstSlide'));
      await tester.pump();
      expect(tapped, ['slot_c', 'slot_a']);
    });

    testWidgets('tapping the background deselects', (tester) async {
      sizeSurface(tester);
      var canvasTaps = 0;
      await tester.pumpWidget(
        host(
          CanvasView(
            document: twoLabels(),
            content: texts,
            fontResolver: testFontResolver,
            onCanvasTap: () => canvasTaps++,
          ),
        ),
      );

      // A point well away from either label.
      await tester.tapAt(tester.getCenter(find.byType(CanvasView)));
      await tester.pump();
      expect(canvasTaps, 1);
    });

    testWidgets('alignment guides render outside the export boundary', (
      tester,
    ) async {
      sizeSurface(tester);
      final exportKey = GlobalKey();
      await tester.pumpWidget(
        host(
          CanvasView(
            document: twoLabels(),
            content: texts,
            fontResolver: testFontResolver,
            exportKey: exportKey,
            // A guide in CONTINUOUS units, on slide 2.
            guideXs: const [2000],
          ),
        ),
      );

      final guides = find.byKey(const ValueKey('alignment-guides'));
      expect(guides, findsOneWidget);
      expect(
        find.descendant(of: find.byKey(exportKey), matching: guides),
        findsNothing,
        reason: 'a guide inside the boundary would land in the exported PNG',
      );
    });
  });

  testWidgets('THE POINT: render continuous, slice per slide, panorama survives', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final exportKey = GlobalKey();
    final document = doc(
      // A black band across the TOP HALF of all three slides: the seamless
      // panorama the bleed could only fake. The bottom half stays each slide's
      // own background, so one capture proves both behaviours at once.
      layers: [band('pano', 0, 900, const Color(0xFF000000), height: 200)],
    );

    await tester.pumpWidget(
      host(
        CanvasView(
          document: document,
          content: const SlotContent(),
          fontResolver: testFontResolver,
          exportKey: exportKey,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final results = await tester.runAsync(() async {
      final boundary =
          exportKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      // ONE capture of the whole continuous canvas.
      final full = await boundary.toImage(pixelRatio: 1);
      final tops = <Color>[];
      final bottoms = <Color>[];
      final sizes = <Size>[];
      for (var i = 0; i < document.slideCount; i++) {
        final slice = await crop(full, document.slideRect(i));
        sizes.add(Size(slice.width.toDouble(), slice.height.toDouble()));
        tops.add(await pixelAt(slice, slice.width ~/ 2, 100));
        bottoms.add(await pixelAt(slice, slice.width ~/ 2, 300));
        slice.dispose();
      }
      full.dispose();
      return (tops: tops, bottoms: bottoms, sizes: sizes);
    });

    // Every slice is exactly one slide.
    for (final s in results!.sizes) {
      expect(s, const Size(slideW, slideH));
    }
    // The panorama shows in ALL THREE slices — one layer, genuinely spanning.
    for (var i = 0; i < 3; i++) {
      expect(
        near(results.tops[i], const Color(0xFF000000)),
        isTrue,
        reason: 'slide $i top should be the panorama, got ${results.tops[i]}',
      );
    }
    // ...while each slice keeps its OWN background below it.
    for (var i = 0; i < 3; i++) {
      expect(
        near(results.bottoms[i], bgs[i]),
        isTrue,
        reason: 'slide $i background should be ${bgs[i]}, got ${results.bottoms[i]}',
      );
    }
  });
}
