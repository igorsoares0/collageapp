import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:collageapp/src/model/template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final json =
      jsonDecode(File('test/fixtures/fashion_story.json').readAsStringSync())
          as Map<String, dynamic>;

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

  test('classic v1 template reads as a single panel', () {
    final template = Template.fromJson(json);
    expect(template.panels, hasLength(1));
    expect(template.panels.first.id, 'panel_0');
    expect(template.panels.first.layers, hasLength(6));
  });

  test('panel backgroundColor defaults to white when absent', () {
    expect(
      Template.fromJson(json).panels.first.backgroundColor,
      const Color(0xFFFFFFFF),
    );
  });

  test('panel backgroundColor is parsed from the classic canvas field', () {
    final withBg = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
    (withBg['canvas'] as Map<String, dynamic>)['backgroundColor'] = '#1C1917';
    expect(
      Template.fromJson(withBg).panels.first.backgroundColor,
      const Color(0xFF1C1917),
    );
  });

  test('v2 multi-panel template parses panels with per-panel backgrounds', () {
    final layers = (json['layers'] as List);
    final v2 = {
      'id': 'multi',
      'schemaVersion': 2,
      'version': 1,
      'name': 'Carousel',
      'aspectRatio': 'story',
      'canvas': {'width': 1080, 'height': 1920},
      'panels': [
        {'id': 'p1', 'backgroundColor': '#111111', 'layers': layers},
        {'id': 'p2', 'backgroundColor': '#2563EB', 'layers': <dynamic>[]},
      ],
    };
    final template = Template.fromJson(v2);
    expect(template.panels, hasLength(2));
    expect(template.panels[0].backgroundColor, const Color(0xFF111111));
    expect(template.panels[1].backgroundColor, const Color(0xFF2563EB));
    // layers/slotIds getters flatten across panels.
    expect(template.layers, hasLength(6));
    expect(template.slotIds, ['hero_image', 'title', 'subtitle']);
  });

  test('imageAssetId (designer sample photo) round-trips on image layers '
      'and grid cells', () {
    final image =
        Layer.fromJson({
              'type': 'image',
              'id': 'l1',
              'slotId': 's1',
              'x': 0,
              'y': 0,
              'width': 100,
              'height': 100,
              'imageAssetId': 'photo_1',
            })!
            as ImageLayer;
    expect(image.imageAssetId, 'photo_1');
    expect(image.toJson()['imageAssetId'], 'photo_1');

    final cell = GridCell.fromJson({
      'slotId': 'cell_1',
      'col': 0,
      'row': 0,
      'imageAssetId': 'photo_2',
    });
    expect(cell.imageAssetId, 'photo_2');
    expect(cell.toJson()['imageAssetId'], 'photo_2');

    // Absent stays absent (older templates), including in toJson.
    final bare = GridCell.fromJson({'slotId': 'cell_2', 'col': 1, 'row': 0});
    expect(bare.imageAssetId, isNull);
    expect(bare.toJson().containsKey('imageAssetId'), isFalse);
  });
}
