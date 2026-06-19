import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:collageapp/src/model/template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final json = jsonDecode(
    File('test/fixtures/fashion_story.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  test('parses the editor fixture template', () {
    final template = Template.fromJson(json);

    expect(template.id, 'fixture_fashion_story');
    expect(template.schemaVersion, 1);
    expect(template.version, 3);
    expect(template.canvasWidth, 1080);
    expect(template.canvasHeight, 1920);
    expect(template.layers, hasLength(6));

    final image = template.layers[1] as ImageLayer;
    expect(image.slotId, 'hero_image');
    expect(image.rotation, 4);
    expect(image.borderRadius, 48);

    final title = template.layers[2] as TextLayer;
    expect(title.fontFamily, 'Playfair Display');
    expect(title.fontWeight, 700);
    expect(title.color, const Color(0xFFFAFAF9));
    expect(title.alignment, 'center');

    final hiddenShape = template.layers[5] as ShapeLayer;
    expect(hiddenShape.hidden, isTrue);

    expect(template.slotIds, ['hero_image', 'title', 'subtitle']);
  });

  test('templates without schemaVersion default to 1', () {
    final legacy = Map<String, dynamic>.from(json)..remove('schemaVersion');
    expect(Template.fromJson(legacy).schemaVersion, 1);
  });

  test('unknown layer types are skipped, not fatal', () {
    final mutated = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
    (mutated['layers'] as List).add({'id': 'x', 'type': 'gradient'});
    expect(Template.fromJson(mutated).layers, hasLength(6));
  });

  test('malformed hex colors fall back to black', () {
    expect(parseHexColor('not-a-color'), const Color(0xFF000000));
    expect(parseHexColor('#FF0066'), const Color(0xFFFF0066));
  });

  test('canvas backgroundColor defaults to white when absent', () {
    expect(Template.fromJson(json).backgroundColor, const Color(0xFFFFFFFF));
  });

  test('canvas backgroundColor is parsed when present', () {
    final withBg = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
    (withBg['canvas'] as Map<String, dynamic>)['backgroundColor'] = '#1C1917';
    expect(Template.fromJson(withBg).backgroundColor, const Color(0xFF1C1917));
  });
}
