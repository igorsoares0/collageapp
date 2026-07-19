import 'dart:convert';
import 'dart:ui';

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

  // The slide-aware derivations (slideOf / spansSlides / layersInSlide / ...)
  // are covered by continuous_parity_test.dart, which checks them against the
  // contract shared byte-for-byte with the editor. Asserting them again here
  // would fork the contract into a second, quieter source of truth.

  test('GATE: the app still refuses v4 — kSupportedSchemaVersion stays 3', () {
    // Phase 1 is model-only. Bumping this before the renderer can DRAW a
    // continuous canvas would let a v4 template through to be half-rendered.
    expect(kSupportedSchemaVersion, 3);
  });
}
