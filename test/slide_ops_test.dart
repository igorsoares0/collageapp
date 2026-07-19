import 'dart:ui';

import 'package:collageapp/src/model/slide_aware.dart';
import 'package:collageapp/src/model/slide_ops.dart';
import 'package:collageapp/src/model/template.dart';
import 'package:flutter_test/flutter_test.dart';

/// Slide operations on the continuous canvas (Modelo B, phase 4a).
///
/// The behaviour that matters: a slide moves WITH its content (that is what
/// makes independent pages feel native on a continuous canvas), and a layer
/// crossing a cut is never torn.

const w = 1000.0;
const white = Color(0xFFFFFFFF);

ShapeLayer box(String id, double x, {double width = 100}) => ShapeLayer(
  id: id,
  hidden: false,
  x: x,
  y: 0,
  width: width,
  height: 100,
  fill: const Color(0xFF000000),
);

Document doc({
  int slideCount = 3,
  double gutter = 0,
  List<Layer> layers = const [],
  List<Color>? backgrounds,
}) => Document(
  id: 'd',
  schemaVersion: 4,
  version: 1,
  name: 'Doc',
  aspectRatio: '9:16',
  slideWidth: w,
  slideHeight: 1920,
  slideCount: slideCount,
  gutter: gutter,
  slideBackgrounds:
      backgrounds ??
      const [Color(0xFF111111), Color(0xFF222222), Color(0xFF333333)],
  layers: layers,
);

double xOf(Document d, String id) =>
    (d.layers.firstWhere((l) => l.id == id) as ShapeLayer).x;

void main() {
  group('addSlide', () {
    test('appending reflows nothing', () {
      final before = doc(layers: [box('a', 100), box('b', 1100)]);
      final after = addSlide(before);

      expect(after.slideCount, 4);
      expect(xOf(after, 'a'), 100);
      expect(xOf(after, 'b'), 1100);
      expect(after.slideBackgrounds.length, 4);
      expect(after.backgroundFor(3), white);
    });

    test('inserting in the middle pushes later slides right', () {
      final before = doc(layers: [box('a', 100), box('b', 1100), box('c', 2100)]);
      final after = addSlide(before, at: 1, background: const Color(0xFF00FF00));

      expect(after.slideCount, 4);
      expect(xOf(after, 'a'), 100, reason: 'slide 0 is untouched');
      expect(xOf(after, 'b'), 2100, reason: 'was slide 1, now slide 2');
      expect(xOf(after, 'c'), 3100, reason: 'was slide 2, now slide 3');
      expect(after.backgroundFor(1), const Color(0xFF00FF00));
      expect(after.backgroundFor(2), const Color(0xFF222222));
    });
  });

  group('removeSlide', () {
    test('drops the slide and its layers, pulling later ones left', () {
      final before = doc(layers: [box('a', 100), box('b', 1100), box('c', 2100)]);
      final after = removeSlide(before, 1);

      expect(after.slideCount, 2);
      expect(after.layers.map((l) => l.id), ['a', 'c']);
      expect(xOf(after, 'a'), 100);
      expect(xOf(after, 'c'), 1100, reason: 'slide 2 became slide 1');
      expect(after.slideBackgrounds, [
        const Color(0xFF111111),
        const Color(0xFF333333),
      ]);
    });

    test('refuses to empty the document', () {
      final single = doc(slideCount: 1, backgrounds: const [white]);
      expect(removeSlide(single, 0), same(single));
    });

    test('out-of-range index is a no-op', () {
      final d = doc();
      expect(removeSlide(d, 9), same(d));
      expect(removeSlide(d, -1), same(d));
    });
  });

  group('reorderSlide', () {
    test('a slide carries its content', () {
      final before = doc(layers: [box('a', 100), box('b', 1100), box('c', 2100)]);
      // Pull slide 2 to the front: order becomes [2, 0, 1].
      final after = reorderSlide(before, 2, 0);

      expect(after.slideCount, 3);
      expect(xOf(after, 'c'), 100, reason: 'slide 2 -> position 0');
      expect(xOf(after, 'a'), 1100, reason: 'slide 0 -> position 1');
      expect(xOf(after, 'b'), 2100, reason: 'slide 1 -> position 2');
    });

    test('backgrounds travel with their slide', () {
      final after = reorderSlide(doc(), 2, 0);
      expect(after.slideBackgrounds, [
        const Color(0xFF333333),
        const Color(0xFF111111),
        const Color(0xFF222222),
      ]);
    });

    test('z-order (list order) is preserved', () {
      final before = doc(layers: [box('a', 100), box('b', 1100), box('c', 2100)]);
      final after = reorderSlide(before, 2, 0);
      expect(after.layers.map((l) => l.id), ['a', 'b', 'c']);
    });

    test('swapping neighbours moves both', () {
      final before = doc(layers: [box('a', 100), box('b', 1100)]);
      final after = reorderSlide(before, 0, 1);
      expect(xOf(after, 'a'), 1100);
      expect(xOf(after, 'b'), 100);
    });

    test('no-op cases return the document untouched', () {
      final d = doc();
      expect(reorderSlide(d, 1, 1), same(d));
      expect(reorderSlide(d, 5, 0), same(d));
      expect(reorderSlide(d, 0, 5), same(d));
    });

    test('respects a gutter', () {
      final before = doc(gutter: 50, layers: [box('a', 0), box('b', 1050)]);
      final after = reorderSlide(before, 0, 1);
      expect(xOf(after, 'a'), 1050);
      expect(xOf(after, 'b'), 0);
    });
  });

  group('layers crossing a cut are never torn', () {
    // x 900..1200 straddles the 0|1 boundary at x=1000.
    Layer pano() => box('pano', 900, width: 300);

    test('reorder leaves them where they are', () {
      final before = doc(layers: [box('a', 100), pano()]);
      expect(before.spansSlides(before.layers[1]), isTrue, reason: 'setup');

      final after = reorderSlide(before, 0, 2);
      expect(xOf(after, 'pano'), 900, reason: 'a panorama is not dragged along');
    });

    test('delete keeps them instead of cutting one in half', () {
      final before = doc(layers: [pano()]);
      final after = removeSlide(before, 0);
      expect(after.layers.map((l) => l.id), ['pano']);
      expect(xOf(after, 'pano'), 900);
    });

    test('insert does not shift them', () {
      final before = doc(layers: [pano()]);
      final after = addSlide(before, at: 0);
      expect(xOf(after, 'pano'), 900);
    });

    test('spanningLayers reports exactly the crossing ones', () {
      final d = doc(layers: [box('a', 100), pano(), box('c', 2100)]);
      expect(spanningLayers(d).map((l) => l.id), ['pano']);
    });
  });

  group('other operations', () {
    test('setSlideBackground repaints one slide only', () {
      final after = setSlideBackground(doc(), 1, const Color(0xFFFF0000));
      expect(after.slideBackgrounds, [
        const Color(0xFF111111),
        const Color(0xFFFF0000),
        const Color(0xFF333333),
      ]);
    });

    test('addLayerToSlide places slide-local coords into continuous space', () {
      final before = doc();
      final after = addLayerToSlide(before, 2, box('new', 50));

      expect(after.layers.length, 1);
      expect(xOf(after, 'new'), 2050, reason: '50 within slide 2');
      expect(after.slideOf(after.layers.single), 2);
    });

    test('a new layer lands on top of the stack', () {
      final before = doc(layers: [box('under', 0)]);
      final after = addLayerToSlide(before, 0, box('over', 10));
      expect(after.layers.map((l) => l.id), ['under', 'over']);
    });
  });
}
