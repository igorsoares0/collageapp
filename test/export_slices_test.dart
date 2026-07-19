import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:collageapp/src/model/slot_content.dart';
import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/rendering/export.dart';
import 'package:collageapp/src/rendering/template_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// capturePngSlices — the sliced export (Modelo B, phase 3a).
///
/// The seam test is the point: an element straddling a cut must continue
/// pixel-for-pixel from one slide's right edge into the next slide's left edge.
/// That is the guarantee the panel model could never give, because each panel
/// was a separate raster aligned by eye through the bleed.

TextStyle testFontResolver(String family, TextStyle base) => base;

const slideW = 300.0;
const slideH = 400.0;
const bgs = [Color(0xFFFF0000), Color(0xFF00FF00), Color(0xFF0000FF)];
const black = Color(0xFF000000);

ShapeLayer band(String id, double x, double width, Color fill) =>
    ShapeLayer(id: id, hidden: false, x: x, y: 0, width: width, height: slideH, fill: fill);

Document doc(List<Layer> layers) => Document(
  id: 'd',
  schemaVersion: 4,
  version: 1,
  name: 'Doc',
  aspectRatio: '9:16',
  slideWidth: slideW,
  slideHeight: slideH,
  slideCount: 3,
  gutter: 0,
  slideBackgrounds: bgs,
  layers: layers,
);

int _ch(double v) => (v * 255.0).round() & 0xff;
bool near(Color a, Color b, {int tol = 6}) =>
    (_ch(a.r) - _ch(b.r)).abs() <= tol &&
    (_ch(a.g) - _ch(b.g)).abs() <= tol &&
    (_ch(a.b) - _ch(b.b)).abs() <= tol;

Future<ui.Image> decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  return (await codec.getNextFrame()).image;
}

Future<Color> pixelAt(ui.Image img, int x, int y) async {
  final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final o = (y * img.width + x) * 4;
  final b = data.buffer.asUint8List();
  return Color.fromARGB(b[o + 3], b[o], b[o + 1], b[o + 2]);
}

Future<void> pumpDoc(WidgetTester tester, GlobalKey key, Document d) async {
  tester.view.physicalSize = const Size(900, 400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 900,
          height: 400,
          child: CanvasView(
            document: d,
            content: const SlotContent(),
            fontResolver: testFontResolver,
            exportKey: key,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('one PNG per slide, each exactly one slide wide', (tester) async {
    final key = GlobalKey();
    final d = doc([band('pano', 0, 900, black)]);
    await pumpDoc(tester, key, d);

    final sizes = await tester.runAsync(() async {
      final pngs = await capturePngSlices(key, d);
      expect(pngs.length, 3);
      return [
        for (final png in pngs)
          await decode(png).then((i) => Size(i.width.toDouble(), i.height.toDouble())),
      ];
    });

    for (final s in sizes!) {
      expect(s, const Size(slideW, slideH));
    }
  });

  testWidgets('SEAM: an element straddling a cut continues across slices', (tester) async {
    final key = GlobalKey();
    // A black band from x=250 to x=350 — it straddles the 0|1 cut at x=300.
    final d = doc([band('straddle', 250, 100, black)]);
    await pumpDoc(tester, key, d);

    final probes = await tester.runAsync(() async {
      final pngs = await capturePngSlices(key, d);
      final s0 = await decode(pngs[0]);
      final s1 = await decode(pngs[1]);

      return {
        // Slide 0: black must run right up to its LAST column.
        's0_before': await pixelAt(s0, 240, 200), // left of the band
        's0_inband': await pixelAt(s0, 260, 200),
        's0_lastpx': await pixelAt(s0, s0.width - 1, 200),
        // Slide 1: black must start at its FIRST column and stop at x=50.
        's1_firstpx': await pixelAt(s1, 0, 200),
        's1_inband': await pixelAt(s1, 40, 200),
        's1_after': await pixelAt(s1, 60, 200), // right of the band
      };
    });

    // The band is continuous across the seam: slide 0 ends black, slide 1
    // begins black. Stitch them and the element is unbroken.
    expect(near(probes!['s0_lastpx']!, black), isTrue, reason: 'slide 0 must end inside the band');
    expect(near(probes['s1_firstpx']!, black), isTrue, reason: 'slide 1 must begin inside the band');
    expect(near(probes['s0_inband']!, black), isTrue);
    expect(near(probes['s1_inband']!, black), isTrue);
    // ...and it really is a band, not a fill: outside it, each slide's own
    // background shows.
    expect(near(probes['s0_before']!, bgs[0]), isTrue);
    expect(near(probes['s1_after']!, bgs[1]), isTrue);
  });

  testWidgets('each slice keeps its own background', (tester) async {
    final key = GlobalKey();
    final d = doc(const []);
    await pumpDoc(tester, key, d);

    final centers = await tester.runAsync(() async {
      final pngs = await capturePngSlices(key, d);
      return [
        for (final png in pngs)
          await decode(png).then((i) => pixelAt(i, i.width ~/ 2, i.height ~/ 2)),
      ];
    });

    for (var i = 0; i < 3; i++) {
      expect(near(centers![i], bgs[i]), isTrue, reason: 'slide $i background');
    }
  });

  testWidgets('exports at a requested resolution, not the on-screen size', (tester) async {
    final key = GlobalKey();
    final d = doc([band('pano', 0, 900, black)]);
    await pumpDoc(tester, key, d);

    // Ask for 1080-wide slides from a canvas rendered 300 units per slide.
    final sizes = await tester.runAsync(() async {
      final pngs = await capturePngSlices(key, d, targetSlideWidth: 1080);
      return [
        for (final png in pngs)
          await decode(png).then((i) => Size(i.width.toDouble(), i.height.toDouble())),
      ];
    });

    for (final s in sizes!) {
      expect(s.width, 1080);
      // Aspect preserved: 400/300 * 1080 = 1440.
      expect(s.height, 1440);
    }
  });

  testWidgets('a single-slide document exports one PNG', (tester) async {
    final key = GlobalKey();
    final d = Document(
      id: 'd',
      schemaVersion: 4,
      version: 1,
      name: 'One',
      aspectRatio: '9:16',
      slideWidth: slideW,
      slideHeight: slideH,
      slideCount: 1,
      gutter: 0,
      slideBackgrounds: const [Color(0xFF123456)],
      layers: const [],
    );

    tester.view.physicalSize = const Size(300, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 400,
            child: CanvasView(
              document: d,
              content: const SlotContent(),
              fontResolver: testFontResolver,
              exportKey: key,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final result = await tester.runAsync(() async {
      final pngs = await capturePngSlices(key, d);
      final img = await decode(pngs.single);
      return (count: pngs.length, color: await pixelAt(img, 150, 200));
    });

    expect(result!.count, 1);
    expect(near(result.color, const Color(0xFF123456)), isTrue);
  });
}
