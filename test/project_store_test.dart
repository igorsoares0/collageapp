import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collageapp/src/api/project_store.dart';
import 'package:collageapp/src/model/slot_content.dart';
import 'package:collageapp/src/model/template.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// A template exercising every layer type and every optional field, so the
/// toJson/fromJson round-trip covers the whole schema surface.
Template fullTemplate() => const Template(
  id: 't1',
  schemaVersion: 3,
  version: 7,
  name: 'Full',
  aspectRatio: '9:16',
  canvasWidth: 1080,
  canvasHeight: 1920,
  panels: [
    Panel(
      id: 'p1',
      backgroundColor: Color(0xFF123456),
      layers: [
        ImageLayer(
          id: 'img',
          hidden: false,
          slotId: 'img',
          x: 10,
          y: 20,
          width: 300,
          height: 400,
          rotation: 5,
          opacity: 0.8,
          borderRadius: 12,
          frameAssetId: 'frame_polaroid_v',
        ),
        TextLayer(
          id: 'txt',
          hidden: true,
          slotId: 'txt',
          x: 0,
          y: 640,
          width: 500,
          fontFamily: 'Inter',
          fontSize: 64,
          fontWeight: 700,
          color: Color(0xFFABCDEF),
          alignment: 'center',
        ),
        ShapeLayer(
          id: 'shape',
          hidden: false,
          x: 1,
          y: 2,
          width: 3,
          height: 4,
          fill: Color(0xFF00FF00),
        ),
        StickerLayer(
          id: 'stk',
          hidden: false,
          assetId: 'sticker_star',
          x: 5,
          y: 6,
          width: 7,
          height: 8,
        ),
        GridLayer(
          id: 'grid',
          hidden: false,
          x: 90,
          y: 90,
          width: 900,
          height: 900,
          rotation: 0,
          cols: 2,
          rows: 2,
          colFractions: [1, 2],
          rowFractions: [1, 1],
          gutter: 24,
          cornerRadius: 8,
          gutterColor: Color(0xFF111111),
          cells: [
            GridCell(slotId: 'g_c1', col: 0, row: 0),
            GridCell(
              slotId: 'g_c2',
              col: 1,
              row: 0,
              rowSpan: 2,
              borderRadius: 4,
            ),
          ],
        ),
      ],
    ),
  ],
);

void main() {
  late Directory dir;
  late ProjectStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('project_store_test');
    store = ProjectStore(dirOverride: dir);
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Project projectWith(
    SlotContent content, {
    String id = 'p_1',
    DateTime? updatedAt,
  }) => Project(
    id: id,
    name: 'My collage',
    updatedAt: updatedAt ?? DateTime.utc(2026, 7, 7, 12),
    template: fullTemplate(),
    content: content,
  );

  test('template JSON round-trips every layer type and optional field', () {
    final t = fullTemplate();
    final back = Template.fromJson(
      jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>,
    );

    expect(back.id, t.id);
    expect(back.schemaVersion, 3);
    expect(back.version, 7);
    expect(back.aspectRatio, '9:16');
    expect(back.canvasWidth, 1080);
    expect(back.canvasHeight, 1920);
    expect(back.panels.single.backgroundColor, const Color(0xFF123456));

    final layers = back.panels.single.layers;
    final img = layers[0] as ImageLayer;
    expect(
      (img.x, img.y, img.width, img.height, img.rotation, img.opacity),
      (10, 20, 300, 400, 5, 0.8),
    );
    expect(img.frameAssetId, 'frame_polaroid_v');
    final txt = layers[1] as TextLayer;
    expect(txt.hidden, isTrue);
    expect(txt.color, const Color(0xFFABCDEF));
    expect((txt.fontFamily, txt.fontSize, txt.fontWeight), ('Inter', 64, 700));
    expect((layers[2] as ShapeLayer).fill, const Color(0xFF00FF00));
    expect((layers[3] as StickerLayer).assetId, 'sticker_star');
    final grid = layers[4] as GridLayer;
    expect(grid.colFractions, [1, 2]);
    expect(grid.gutterColor, const Color(0xFF111111));
    expect(grid.cells[1].rowSpan, 2);
    expect(grid.cells[1].borderRadius, 4);
    expect(grid.cells[0].borderRadius, isNull);
  });

  test('a project round-trips the full SlotContent, photos as files', () async {
    final photo = await store.saveImage(
      'p_1',
      'img_1.jpg',
      Uint8List.fromList([1, 2, 3]),
    );
    final content = SlotContent(
      texts: const {'txt': 'Hello'},
      images: {'img': FileImage(photo)},
      offsets: const {'img': Offset(12.5, -30)},
      scales: const {'img': 1.5},
      rotations: const {'img': 45},
      colors: const {'txt': Color(0xFF224466)},
      fonts: const {'txt': 'Lobster'},
      alignments: const {'txt': 'left'},
      weights: const {'txt': 700},
      panelBackgrounds: const {'p1': Color(0xFF888888)},
      layerOrders: const {
        'p1': ['txt', 'img'],
      },
      hiddenLayers: const {'shape': true},
      gridOverrides: const {
        'grid': GridOverride(gutter: 30, colFractions: [2, 1]),
      },
      addedLayers: const {
        'p1': [
          StickerLayer(
            id: 'sticker_1',
            hidden: false,
            assetId: 'sticker_star',
            x: 1,
            y: 2,
            width: 3,
            height: 4,
          ),
        ],
      },
      addedPanels: const [
        Panel(id: 'panel_2', backgroundColor: Color(0xFFFF0000), layers: []),
      ],
    );

    await store.save(projectWith(content));
    final loaded = (await store.load('p_1'))!;

    expect(loaded.name, 'My collage');
    expect(loaded.updatedAt, DateTime.utc(2026, 7, 7, 12));
    expect(loaded.template.panels.single.layers, hasLength(5));

    final c = loaded.content;
    expect(c.texts, {'txt': 'Hello'});
    expect((c.images['img']! as FileImage).file.path, endsWith('img_1.jpg'));
    expect(c.offsets, {'img': const Offset(12.5, -30)});
    expect(c.scales, {'img': 1.5});
    expect(c.rotations, {'img': 45});
    expect(c.colors, {'txt': const Color(0xFF224466)});
    expect(c.fonts, {'txt': 'Lobster'});
    expect(c.alignments, {'txt': 'left'});
    expect(c.weights, {'txt': 700});
    expect(c.panelBackgrounds, {'p1': const Color(0xFF888888)});
    expect(c.layerOrders, {
      'p1': ['txt', 'img'],
    });
    expect(c.hiddenLayers, {'shape': true});
    expect(c.gridOverrides['grid']!.gutter, 30);
    expect(c.gridOverrides['grid']!.colFractions, [2, 1]);
    expect(c.gridOverrides['grid']!.rowFractions, isNull);
    final sticker = c.addedLayersFor('p1').single as StickerLayer;
    expect(sticker.assetId, 'sticker_star');
    expect(c.addedPanels.single.id, 'panel_2');

    // Atomicity: the temp file never survives a completed save.
    expect(
      File('${dir.path}/projects/p_1/project.json.tmp').existsSync(),
      isFalse,
    );
  });

  test('a photo whose file vanished degrades to an empty slot', () async {
    final photo = await store.saveImage(
      'p_1',
      'img_1.jpg',
      Uint8List.fromList([1]),
    );
    await store.save(
      projectWith(SlotContent(images: {'img': FileImage(photo)})),
    );
    await photo.delete();
    final loaded = (await store.load('p_1'))!;
    expect(loaded.content.images, isEmpty);
  });

  test(
    'list returns projects newest first and skips corrupt entries',
    () async {
      await store.save(
        projectWith(
          const SlotContent(),
          id: 'p_old',
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await store.save(
        projectWith(
          const SlotContent(),
          id: 'p_new',
          updatedAt: DateTime.utc(2026, 6, 1),
        ),
      );
      // A corrupt neighbor must not take the list down.
      final corrupt = Directory('${dir.path}/projects/p_bad');
      await corrupt.create(recursive: true);
      await File('${corrupt.path}/project.json').writeAsString('{oops');

      final list = await store.list();
      expect([for (final s in list) s.id], ['p_new', 'p_old']);
    },
  );

  test(
    'load returns null for missing, corrupt and newer-version files',
    () async {
      expect(await store.load('nope'), isNull);

      final bad = Directory('${dir.path}/projects/p_bad');
      await bad.create(recursive: true);
      await File('${bad.path}/project.json').writeAsString('not json');
      expect(await store.load('p_bad'), isNull);

      // Written by a future app version: refuse instead of misreading.
      await store.save(projectWith(const SlotContent(), id: 'p_future'));
      final file = File('${dir.path}/projects/p_future/project.json');
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      json['projectVersion'] = kProjectVersion + 1;
      await file.writeAsString(jsonEncode(json));
      expect(await store.load('p_future'), isNull);
      expect(await store.list(), isEmpty);
    },
  );

  test('delete removes the document and its photos', () async {
    await store.saveImage('p_1', 'img_1.jpg', Uint8List.fromList([1]));
    await store.save(projectWith(const SlotContent()));
    await store.delete('p_1');
    expect(Directory('${dir.path}/projects/p_1').existsSync(), isFalse);
    expect(await store.list(), isEmpty);
  });

  test('cleanupImages drops orphans and keeps referenced photos', () async {
    final kept = await store.saveImage(
      'p_1',
      'keep.jpg',
      Uint8List.fromList([1]),
    );
    final orphan = await store.saveImage(
      'p_1',
      'orphan.jpg',
      Uint8List.fromList([2]),
    );
    await store.cleanupImages('p_1', {'keep.jpg'});
    expect(kept.existsSync(), isTrue);
    expect(orphan.existsSync(), isFalse);
  });
}
