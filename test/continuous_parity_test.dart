import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:collageapp/src/model/slide_aware.dart';
import 'package:collageapp/src/model/template.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifies the Dart mirror (lib/src/model/slide_aware.dart) against the shared
/// contract in test/fixtures/continuous_parity.json — a byte-identical copy of
/// collageweb/lib/template/continuous-parity.json, which the editor checks
/// itself against via `npm run parity`.
///
/// The point: the two renderers cannot drift on where a slide begins and ends
/// without one of the two checks going red. Changing the contract means editing
/// the JSON in both repos, which makes the cross-repo impact explicit.

Document canvasDoc(Map<String, dynamic> c, {List<Layer> layers = const []}) =>
    Document(
      id: 'parity',
      schemaVersion: 4,
      version: 1,
      name: 'Parity',
      aspectRatio: '9:16',
      slideWidth: (c['slideWidth'] as num).toDouble(),
      slideHeight: (c['slideHeight'] as num).toDouble(),
      slideCount: (c['slideCount'] as num).toInt(),
      gutter: (c['gutter'] as num).toDouble(),
      slideBackgrounds: const [Color(0xFFFFFFFF)],
      layers: layers,
    );

/// These derivations read only id/x/width; a shape stands in for any layer.
Layer stub(Map<String, dynamic> l) => ShapeLayer(
  id: l['id'] as String,
  hidden: false,
  x: (l['x'] as num).toDouble(),
  y: 0,
  width: (l['width'] as num).toDouble(),
  height: 100,
  fill: const Color(0xFF000000),
);

void main() {
  final contract =
      jsonDecode(
            File('test/fixtures/continuous_parity.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final canvases = contract['canvases'] as Map<String, dynamic>;
  Map<String, dynamic> canvasOf(String key) {
    final c = canvases[key];
    if (c == null) throw StateError('unknown canvas "$key" in the contract');
    return c as Map<String, dynamic>;
  }

  group('contentWidth', () {
    for (final c in contract['contentWidth'] as List) {
      final case_ = c as Map<String, dynamic>;
      test(case_['name'] as String, () {
        final d = canvasDoc(canvasOf(case_['canvas'] as String));
        expect(d.contentWidth, (case_['expected'] as num).toDouble());
      });
    }
  });

  group('slideRect', () {
    for (final c in contract['slideRect'] as List) {
      final case_ = c as Map<String, dynamic>;
      test(case_['name'] as String, () {
        final d = canvasDoc(canvasOf(case_['canvas'] as String));
        final e = case_['expected'] as Map<String, dynamic>;
        expect(
          d.slideRect((case_['i'] as num).toInt()),
          Rect.fromLTWH(
            (e['x'] as num).toDouble(),
            (e['y'] as num).toDouble(),
            (e['width'] as num).toDouble(),
            (e['height'] as num).toDouble(),
          ),
        );
      });
    }
  });

  group('slideIndexAtX', () {
    for (final c in contract['slideIndexAtX'] as List) {
      final case_ = c as Map<String, dynamic>;
      test(case_['name'] as String, () {
        final d = canvasDoc(canvasOf(case_['canvas'] as String));
        expect(
          d.slideIndexAtX((case_['x'] as num).toDouble()),
          case_['expected'],
        );
      });
    }
  });

  group('slideOf', () {
    for (final c in contract['slideOf'] as List) {
      final case_ = c as Map<String, dynamic>;
      test(case_['name'] as String, () {
        final d = canvasDoc(canvasOf(case_['canvas'] as String));
        expect(
          d.slideOf(stub(case_['layer'] as Map<String, dynamic>)),
          case_['expected'],
        );
      });
    }
  });

  group('spansSlides', () {
    for (final c in contract['spansSlides'] as List) {
      final case_ = c as Map<String, dynamic>;
      test(case_['name'] as String, () {
        final d = canvasDoc(canvasOf(case_['canvas'] as String));
        expect(
          d.spansSlides(stub(case_['layer'] as Map<String, dynamic>)),
          case_['expected'],
        );
      });
    }
  });

  group('layersInSlide', () {
    for (final c in contract['layersInSlide'] as List) {
      final case_ = c as Map<String, dynamic>;
      test(case_['name'] as String, () {
        final layers = [
          for (final l in case_['layers'] as List)
            stub(l as Map<String, dynamic>),
        ];
        final d = canvasDoc(canvasOf(case_['canvas'] as String), layers: layers);
        final expected = case_['expected'] as Map<String, dynamic>;
        for (final entry in expected.entries) {
          expect(
            d.layersInSlide(int.parse(entry.key)).map((l) => l.id).toList(),
            (entry.value as List).cast<String>(),
            reason: 'slide ${entry.key}',
          );
        }
      });
    }
  });
}
