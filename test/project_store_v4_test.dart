import 'dart:convert';
import 'dart:io';

import 'package:collageapp/src/api/project_store.dart';
import 'package:collageapp/src/model/slide_aware.dart';
import 'package:collageapp/src/model/slot_content.dart';
import 'package:collageapp/src/model/template.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// ProjectStore.loadAsDocument — the dual v3/v4 read path (Modelo B, phase 2b).
///
/// The property that matters most here is that loading writes NOTHING: a v3
/// project migrated on read must leave its file untouched, so the current
/// renderer keeps working and nothing is stranded in a format it can't draw.

Template carousel() => const Template(
  id: 't1',
  schemaVersion: 3,
  version: 2,
  name: 'Carousel',
  aspectRatio: '9:16',
  canvasWidth: 1000,
  canvasHeight: 1920,
  panels: [
    Panel(
      id: 'p0',
      backgroundColor: Color(0xFF111111),
      layers: [
        ImageLayer(
          id: 'img',
          hidden: false,
          slotId: 'img',
          x: 100,
          y: 20,
          width: 300,
          height: 400,
          rotation: 0,
          opacity: 1,
          borderRadius: 0,
        ),
      ],
    ),
    Panel(
      id: 'p1',
      backgroundColor: Color(0xFF222222),
      layers: [
        TextLayer(
          id: 'txt',
          hidden: false,
          slotId: 'txt',
          x: 50,
          y: 640,
          width: 500,
          fontFamily: 'Inter',
          fontSize: 40,
          fontWeight: 700,
          color: Color(0xFFFFFFFF),
          alignment: 'left',
        ),
      ],
    ),
  ],
);

void main() {
  late Directory dir;
  late ProjectStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('project_store_v4_test');
    store = ProjectStore(dirOverride: dir);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<void> saveCarousel({SlotContent content = const SlotContent()}) async {
    await store.save(
      Project(
        id: 'proj1',
        name: 'My carousel',
        updatedAt: DateTime.utc(2026, 7, 19),
        template: carousel(),
        content: content,
      ),
    );
    await store.pendingWrites;
  }

  File projectFile() => File('${dir.path}/projects/proj1/project.json');

  test('migrates a saved v3 project on read', () async {
    await saveCarousel();

    final loaded = await store.loadAsDocument('proj1');
    expect(loaded, isNotNull);
    expect(loaded!.migrated, isTrue);
    expect(loaded.id, 'proj1');
    expect(loaded.name, 'My carousel');

    final d = loaded.document;
    expect(d.slideCount, 2);
    expect(d.slideWidth, 1000);
    expect(d.contentWidth, 2000);
    expect(d.layers.length, 2);
    // Panel 1's text reflowed into slide 1.
    final txt = d.layers.firstWhere((l) => l.id == 'txt') as TextLayer;
    expect(txt.x, 1050);
    expect(d.slideOf(txt), 1);
    expect(d.slideBackgrounds, [
      const Color(0xFF111111),
      const Color(0xFF222222),
    ]);
  });

  test('SAFETY: loading as a document does not rewrite the file', () async {
    await saveCarousel();
    final before = await projectFile().readAsString();
    final modifiedBefore = await projectFile().lastModified();

    await store.loadAsDocument('proj1');
    await store.pendingWrites;

    expect(
      await projectFile().readAsString(),
      before,
      reason: 'the v3 file must survive a v4 read byte-for-byte',
    );
    expect(await projectFile().lastModified(), modifiedBefore);

    // And the classic path still reads it, so the app keeps working.
    final classic = await store.load('proj1');
    expect(classic, isNotNull);
    expect(classic!.template.panels.length, 2);
  });

  test('user overrides survive the migrated read', () async {
    await saveCarousel(
      content: const SlotContent()
          .withText('txt', 'hello world')
          .withOffset('img', const Offset(7, 8))
          .withPanelBackground('p1', const Color(0xFF00FF00)),
    );

    final loaded = await store.loadAsDocument('proj1');
    expect(loaded, isNotNull);
    // Slot-scoped overrides pass through untouched.
    expect(loaded!.content.textFor('txt'), 'hello world');
    expect(loaded.content.offsetFor('img'), const Offset(7, 8));
    // The panel-scoped one folded into the document instead of being lost.
    expect(loaded.content.backgroundFor('p1'), isNull);
    expect(loaded.document.backgroundFor(1), const Color(0xFF00FF00));
  });

  test('reads a natively-v4 project without migrating', () async {
    // Hand-write the forward shape: a `document` instead of a `template`.
    final projDir = Directory('${dir.path}/projects/proj_v4');
    await projDir.create(recursive: true);
    await File('${projDir.path}/project.json').writeAsString(
      jsonEncode({
        'projectVersion': kProjectVersion,
        'id': 'proj_v4',
        'name': 'Native v4',
        'updatedAt': DateTime.utc(2026, 7, 19).toIso8601String(),
        'document': {
          'id': 'doc',
          'schemaVersion': 4,
          'version': 1,
          'name': 'Native v4',
          'aspectRatio': '9:16',
          'canvas': {
            'slideWidth': 1080,
            'slideHeight': 1920,
            'slideCount': 3,
            'gutter': 0,
          },
          'slideBackgrounds': ['#FFFFFF', '#EEEEEE', '#DDDDDD'],
          'layers': [
            {
              'id': 'pano',
              'type': 'shape',
              'shape': 'rectangle',
              'x': 0,
              'y': 0,
              'width': 3240,
              'height': 1920,
              'fill': '#FF0000',
            },
          ],
        },
        'content': <String, dynamic>{},
      }),
    );

    final loaded = await store.loadAsDocument('proj_v4');
    expect(loaded, isNotNull);
    expect(loaded!.migrated, isFalse, reason: 'already v4, nothing to migrate');
    expect(loaded.document.slideCount, 3);
    expect(loaded.document.contentWidth, 3240);
    // The panorama layer spans every slide — the case the panel model
    // could only fake with a bleed.
    final pano = loaded.document.layers.single;
    expect(loaded.document.spansSlides(pano), isTrue);
  });

  test('missing and corrupt projects return null, not a crash', () async {
    expect(await store.loadAsDocument('nope'), isNull);

    final bad = Directory('${dir.path}/projects/broken');
    await bad.create(recursive: true);
    await File('${bad.path}/project.json').writeAsString('{not json');
    expect(await store.loadAsDocument('broken'), isNull);
  });

  test('refuses a project written by a newer app version', () async {
    final projDir = Directory('${dir.path}/projects/future');
    await projDir.create(recursive: true);
    await File('${projDir.path}/project.json').writeAsString(
      jsonEncode({
        'projectVersion': kProjectVersion + 1,
        'id': 'future',
        'name': 'From the future',
        'updatedAt': DateTime.utc(2026, 7, 19).toIso8601String(),
        'template': carousel().toJson(),
        'content': <String, dynamic>{},
      }),
    );
    expect(await store.loadAsDocument('future'), isNull);
  });
}
