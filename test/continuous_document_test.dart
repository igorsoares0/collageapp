import 'dart:convert';
import 'dart:ui';

import 'package:collageapp/src/model/slide_aware.dart';
import 'package:collageapp/src/model/template.dart';
import 'package:flutter_test/flutter_test.dart';

/// v4 continuous canvas (Modelo B), phase 1: the model and the slide-aware
/// derivations exist and agree with lib/template/continuous.ts. Nothing is
/// wired into the render/load path yet — see the gate test at the bottom.

ShapeLayer shape(String id, double x, double width) => ShapeLayer(
  id: id,
  hidden: false,
  x: x,
  y: 0,
  width: width,
  height: 100,
  fill: const Color(0xFF000000),
);

Document doc({
  double slideWidth = 1000,
  double gutter = 0,
  int slideCount = 3,
  List<Layer> layers = const [],
}) => Document(
  id: 'doc',
  schemaVersion: 4,
  version: 1,
  name: 'Doc',
  aspectRatio: '9:16',
  slideWidth: slideWidth,
  slideHeight: 1920,
  slideCount: slideCount,
  gutter: gutter,
  slideBackgrounds: const [
    Color(0xFFFFFFFF),
    Color(0xFFEEEEEE),
    Color(0xFFDDDDDD),
  ],
  layers: layers,
);

void main() {
  group('Document (v4 shape)', () {
    test('parses the continuous canvas wire shape', () {
      final json =
          jsonDecode('''
        {
          "id": "tpl_1",
          "schemaVersion": 4,
          "version": 2,
          "name": "Panorama",
          "aspectRatio": "9:16",
          "canvas": {
            "slideWidth": 1080,
            "slideHeight": 1920,
            "slideCount": 3,
            "gutter": 0
          },
          "slideBackgrounds": ["#FFFFFF", "#EEEEEE", "#DDDDDD"],
          "layers": [
            {"id": "l1", "type": "shape", "shape": "rectangle",
             "x": 0, "y": 0, "width": 3240, "height": 1920, "fill": "#FF0000"}
          ]
        }
      ''')
              as Map<String, dynamic>;

      final d = Document.fromJson(json);
      expect(d.id, 'tpl_1');
      expect(d.schemaVersion, 4);
      expect(d.slideCount, 3);
      expect(d.slideWidth, 1080);
      expect(d.gutter, 0);
      expect(d.slideBackgrounds.length, 3);
      expect(d.slideBackgrounds[1], const Color(0xFFEEEEEE));
      // One layer spanning all three slides — the panorama case.
      expect(d.layers.length, 1);
      expect(d.contentWidth, 3240);
    });

    test('round-trips through toJson', () {
      final before = doc(layers: [shape('a', 10, 20)]);
      final after = Document.fromJson(
        jsonDecode(jsonEncode(before.toJson())) as Map<String, dynamic>,
      );
      expect(after.slideCount, before.slideCount);
      expect(after.slideWidth, before.slideWidth);
      expect(after.gutter, before.gutter);
      expect(after.contentWidth, before.contentWidth);
      expect(after.slideBackgrounds, before.slideBackgrounds);
      expect(after.layers.length, 1);
    });

    test('contentWidth counts only the gutters BETWEEN slides', () {
      expect(doc(slideWidth: 1000, gutter: 0).contentWidth, 3000);
      // 3 slides, 2 interior gutters — no outer margin.
      expect(doc(slideWidth: 1000, gutter: 50).contentWidth, 3100);
      expect(doc(slideWidth: 1000, gutter: 50, slideCount: 1).contentWidth, 1000);
    });

    test('slideRect walks the pitch', () {
      final d = doc(slideWidth: 1000, gutter: 50);
      expect(d.slideRect(0), const Rect.fromLTWH(0, 0, 1000, 1920));
      expect(d.slideRect(1), const Rect.fromLTWH(1050, 0, 1000, 1920));
      expect(d.slideRect(2), const Rect.fromLTWH(2100, 0, 1000, 1920));
    });

    test('backgroundFor is defensive past the end', () {
      final d = doc();
      expect(d.backgroundFor(1), const Color(0xFFEEEEEE));
      expect(d.backgroundFor(99), const Color(0xFFFFFFFF));
      expect(d.backgroundFor(-1), const Color(0xFFFFFFFF));
    });
  });

  group('slide-aware derivations', () {
    test('slideOf uses the layer centre', () {
      final d = doc(slideWidth: 1000);
      expect(d.slideOf(shape('a', 0, 100)), 0);
      expect(d.slideOf(shape('b', 1400, 100)), 1);
      expect(d.slideOf(shape('c', 2500, 100)), 2);
      // Straddles the 0/1 cut but its centre is in slide 1 -> belongs to 1.
      expect(d.slideOf(shape('d', 900, 400)), 1);
    });

    test('slideIndexAtX clamps to the document', () {
      final d = doc(slideWidth: 1000);
      expect(d.slideIndexAtX(-500), 0);
      expect(d.slideIndexAtX(0), 0);
      expect(d.slideIndexAtX(2500), 2);
      expect(d.slideIndexAtX(99999), 2);
    });

    test('a layer exactly filling one slide does NOT span', () {
      // The edge case the epsilon exists for: right edge == next slide origin.
      final d = doc(slideWidth: 1000, gutter: 0);
      expect(d.spansSlides(shape('exact', 0, 1000)), isFalse);
      expect(d.spansSlides(shape('exact2', 1000, 1000)), isFalse);
    });

    test('spansSlides detects a real panorama', () {
      final d = doc(slideWidth: 1000, gutter: 0);
      expect(d.spansSlides(shape('pano', 0, 3000)), isTrue);
      expect(d.spansSlides(shape('straddle', 900, 200)), isTrue);
      expect(d.spansSlides(shape('inside', 100, 200)), isFalse);
    });

    test('layersInSlide groups a slide as a movable unit', () {
      final a = shape('a', 100, 100); // slide 0
      final b = shape('b', 1100, 100); // slide 1
      final c = shape('c', 1500, 100); // slide 1
      final d = doc(slideWidth: 1000, layers: [a, b, c]);
      expect(d.layersInSlide(0).map((l) => l.id), ['a']);
      expect(d.layersInSlide(1).map((l) => l.id), ['b', 'c']);
      expect(d.layersInSlide(2), isEmpty);
    });

    test('degenerate case: independent slides, nothing crossing', () {
      // Model B is a superset — this is the old panel model expressed in it.
      final d = doc(
        slideWidth: 1000,
        layers: [shape('p0', 0, 1000), shape('p1', 1000, 1000), shape('p2', 2000, 1000)],
      );
      expect(d.layers.every((l) => !d.spansSlides(l)), isTrue);
      expect([for (final l in d.layers) d.slideOf(l)], [0, 1, 2]);
    });
  });

  test('GATE: the app still refuses v4 — kSupportedSchemaVersion stays 3', () {
    // Phase 1 is model-only. Bumping this before the renderer can DRAW a
    // continuous canvas would let a v4 template through to be half-rendered.
    expect(kSupportedSchemaVersion, 3);
  });
}
