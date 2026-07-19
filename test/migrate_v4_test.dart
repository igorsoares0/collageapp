import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:collageapp/src/model/migrate_v4.dart';
import 'package:collageapp/src/model/slide_aware.dart';
import 'package:collageapp/src/model/slot_content.dart';
import 'package:collageapp/src/model/template.dart';
import 'package:flutter_test/flutter_test.dart';

/// v3 -> v4 migration (Modelo B, phase 2a). This is the only step of the whole
/// migration that can damage a saved project, so the cases here are the ones
/// that actually occur in real documents — content on non-first panels, user
/// added panels/layers, per-panel backgrounds, reorder overrides, and grids.

const w = 1000.0;
const h = 1920.0;

ImageLayer image(String id, {required double x, String? assetId}) => ImageLayer(
  id: id,
  hidden: false,
  slotId: 'slot_$id',
  x: x,
  y: 10,
  width: 200,
  height: 300,
  rotation: 5,
  opacity: 0.9,
  borderRadius: 12,
  frameAssetId: 'frame_1',
  imageAssetId: assetId,
);

TextLayer text(String id, {required double x}) => TextLayer(
  id: id,
  hidden: false,
  slotId: 'slot_$id',
  x: x,
  y: 20,
  width: 400,
  fontFamily: 'Inter',
  fontSize: 32,
  fontWeight: 600,
  color: const Color(0xFF112233),
  alignment: 'center',
);

GridLayer grid(String id, {required double x}) => GridLayer(
  id: id,
  hidden: false,
  x: x,
  y: 0,
  width: 500,
  height: 500,
  rotation: 0,
  cols: 2,
  rows: 2,
  colFractions: const [1, 2],
  rowFractions: const [1, 1],
  gutter: 8,
  cornerRadius: 4,
  gutterColor: const Color(0xFFAABBCC),
  cells: const [
    GridCell(slotId: 'cell_1', col: 0, row: 0),
    GridCell(slotId: 'cell_2', col: 1, row: 0, rowSpan: 2),
  ],
);

Panel panel(String id, List<Layer> layers, {Color bg = const Color(0xFFFFFFFF)}) =>
    Panel(id: id, backgroundColor: bg, layers: layers);

Template template(List<Panel> panels) => Template(
  id: 'tpl',
  schemaVersion: 3,
  version: 7,
  name: 'Carousel',
  aspectRatio: '9:16',
  canvasWidth: w,
  canvasHeight: h,
  panels: panels,
);

void main() {
  group('reflow', () {
    test('panel i shifts its layers by i * canvasWidth', () {
      final t = template([
        panel('p0', [image('a', x: 100)]),
        panel('p1', [image('b', x: 100)]),
        panel('p2', [image('c', x: 100)]),
      ]);

      final r = migrateToV4(t, const SlotContent());
      final xs = [for (final l in r.document.layers) (l as ImageLayer).x];
      expect(xs, [100, 1100, 2100]);
      expect(r.document.slideCount, 3);
      expect(r.document.contentWidth, 3000);
      expect(r.document.gutter, 0, reason: 'v3 panels are contiguous');
    });

    test('each migrated layer lands in its original slide', () {
      final t = template([
        panel('p0', [image('a', x: 100)]),
        panel('p1', [image('b', x: 100)]),
        panel('p2', [image('c', x: 100)]),
      ]);
      final d = migrateToV4(t, const SlotContent()).document;
      expect([for (final l in d.layers) d.slideOf(l)], [0, 1, 2]);
      // A migrated v3 project is the degenerate case: nothing crosses a cut.
      expect(d.layers.every((l) => !d.spansSlides(l)), isTrue);
    });

    test('content on a NON-first panel survives (the projects-thumbnail bug)', () {
      final t = template([
        panel('p0', const []),
        panel('p1', [text('t', x: 50)]),
      ]);
      final d = migrateToV4(t, const SlotContent()).document;
      expect(d.layers.length, 1);
      expect((d.layers.single as TextLayer).x, 1050);
      expect(d.slideOf(d.layers.single), 1);
    });
  });

  group('field preservation', () {
    test('translate keeps every field, including the optional ones', () {
      final before = image('a', x: 100, assetId: 'photo_9');
      final after = translateLayerX(before, 500) as ImageLayer;

      expect(after.x, 600, reason: 'only x moves');
      expect(after.id, before.id);
      expect(after.slotId, before.slotId);
      expect(after.y, before.y);
      expect(after.width, before.width);
      expect(after.height, before.height);
      expect(after.rotation, before.rotation);
      expect(after.opacity, before.opacity);
      expect(after.borderRadius, before.borderRadius);
      // The two easiest to silently drop in a hand-written copy.
      expect(after.frameAssetId, 'frame_1');
      expect(after.imageAssetId, 'photo_9');
    });

    test('hidden survives the translate', () {
      final hiddenLayer = ImageLayer(
        id: 'h',
        hidden: true,
        slotId: 'slot_h',
        x: 0,
        y: 0,
        width: 10,
        height: 10,
        rotation: 0,
        opacity: 1,
        borderRadius: 0,
      );
      expect(translateLayerX(hiddenLayer, 100).hidden, isTrue);
    });

    test('GUARDRAIL: a grid rides the reflow with its cells intact', () {
      final t = template([
        panel('p0', const []),
        panel('p1', [grid('g', x: 20)]),
      ]);
      final d = migrateToV4(t, const SlotContent()).document;
      final g = d.layers.single as GridLayer;

      expect(g.x, 1020, reason: 'grid reflows like any other layer');
      expect(g.cols, 2);
      expect(g.rows, 2);
      expect(g.colFractions, [1, 2]);
      expect(g.gutter, 8);
      expect(g.cornerRadius, 4);
      expect(g.gutterColor, const Color(0xFFAABBCC));
      expect(g.cells.length, 2);
      expect(g.cells[1].slotId, 'cell_2');
      expect(g.cells[1].rowSpan, 2, reason: 'span survives');
      // Cell slots stay in the document's global slot namespace.
      expect(d.slotIds, contains('cell_1'));
      expect(d.slotIds, contains('cell_2'));
    });
  });

  group('the SlotContent overlay', () {
    test('added panels become extra slides', () {
      final t = template([panel('p0', [image('a', x: 0)])]);
      final content = const SlotContent()
          .withAddedPanel(panel('extra', const [], bg: const Color(0xFF00FF00)));

      final r = migrateToV4(t, content);
      expect(r.document.slideCount, 2);
      expect(r.document.backgroundFor(1), const Color(0xFF00FF00));
    });

    test('added layers fold in above the template layers, reflowed', () {
      final t = template([
        panel('p0', [image('a', x: 0)]),
        panel('p1', [image('b', x: 0)]),
      ]);
      final content = const SlotContent().withAddedLayer('p1', text('added', x: 30));

      final d = migrateToV4(t, content).document;
      expect(d.layers.length, 3);
      final added = d.layers.firstWhere((l) => l.id == 'added') as TextLayer;
      expect(added.x, 1030, reason: 'added layer reflows with its panel');
      expect(d.slideOf(added), 1);
      // Stack order: the template's own layer sits below the user's addition.
      expect([for (final l in d.layers) l.id], ['a', 'b', 'added']);
    });

    test('per-panel backgrounds become slideBackgrounds, in order', () {
      final t = template([
        panel('p0', const [], bg: const Color(0xFF111111)),
        panel('p1', const [], bg: const Color(0xFF222222)),
      ]);
      // The user repainted the second slide red.
      final content = const SlotContent()
          .withPanelBackground('p1', const Color(0xFFFF0000));

      final d = migrateToV4(t, content).document;
      expect(d.slideBackgrounds, [
        const Color(0xFF111111),
        const Color(0xFFFF0000),
      ]);
    });

    test('a reorder override becomes the global list order', () {
      final t = template([
        panel('p0', [image('a', x: 0), image('b', x: 0), image('c', x: 0)]),
      ]);
      // User pulled 'c' to the bottom.
      final content = const SlotContent().withLayerOrder('p0', ['c', 'a', 'b']);

      final d = migrateToV4(t, content).document;
      expect([for (final l in d.layers) l.id], ['c', 'a', 'b']);
    });

    test('slot-scoped overrides pass through; panel-scoped ones are dropped', () {
      final t = template([panel('p0', [text('t', x: 0)])]);
      final content = const SlotContent()
          .withText('slot_t', 'hello')
          .withOffset('slot_t', const Offset(5, 6))
          .withScale('slot_t', 2)
          .withPanelBackground('p0', const Color(0xFF123456))
          .withAddedLayer('p0', image('added', x: 0));

      final r = migrateToV4(t, content);

      // Survive: the user's actual edits.
      expect(r.content.textFor('slot_t'), 'hello');
      expect(r.content.offsetFor('slot_t'), const Offset(5, 6));
      expect(r.content.scaleFor('slot_t'), 2);

      // Dropped: now expressed by the document itself.
      expect(r.content.addedPanels, isEmpty);
      expect(r.content.allAddedLayers, isEmpty);
      expect(r.content.backgroundFor('p0'), isNull);
      // ...but the added layer is not LOST — it moved into the document.
      expect(r.document.layers.map((l) => l.id), contains('added'));
      // ...and the background moved to the slide.
      expect(r.document.backgroundFor(0), const Color(0xFF123456));
    });
  });

  group('against the real designer fixture', () {
    final real = Template.fromJson(
      jsonDecode(File('test/fixtures/fashion_story.json').readAsStringSync())
          as Map<String, dynamic>,
    );

    test('nothing is lost migrating a real published template', () {
      final d = migrateToV4(real, const SlotContent()).document;
      expect(real.layers, isNotEmpty, reason: 'fixture sanity');
      expect(d.layers.length, real.layers.length);
      expect(d.slotIds.toSet(), real.slotIds.toSet());
      expect(d.slideCount, real.panels.length);
      expect(d.slideWidth, real.canvasWidth);
      expect(d.slideHeight, real.canvasHeight);
      expect(d.slideBackgrounds.length, real.panels.length);
    });

    test('every real layer survives the translate byte-for-byte except x', () {
      // A generic guard: whatever the type and whatever fields it carries, the
      // ONLY thing the reflow may change is x. Catches silent field loss for
      // any layer type, present or future.
      const shift = 250.0;
      for (final before in real.layers) {
        final after = translateLayerX(before, shift);
        final a = before.toJson();
        final b = after.toJson();
        expect(
          (b['x'] as num).toDouble(),
          (a['x'] as num).toDouble() + shift,
          reason: 'layer ${before.id} (${a['type']}) should move by $shift',
        );
        a.remove('x');
        b.remove('x');
        expect(
          jsonEncode(b),
          jsonEncode(a),
          reason: 'layer ${before.id} (${a['type']}) lost or changed a field',
        );
      }
    });

    test('a multi-panel document built from real layers reflows correctly', () {
      // Split the real layers across three panels to exercise the reflow with
      // genuine designer data rather than synthetic boxes.
      final ls = real.layers;
      final t = Template(
        id: real.id,
        schemaVersion: 3,
        version: real.version,
        name: real.name,
        aspectRatio: real.aspectRatio,
        canvasWidth: real.canvasWidth,
        canvasHeight: real.canvasHeight,
        panels: [
          panel('p0', ls.sublist(0, 2)),
          panel('p1', ls.sublist(2, 4)),
          panel('p2', ls.sublist(4)),
        ],
      );

      final d = migrateToV4(t, const SlotContent()).document;
      expect(d.layers.length, ls.length);
      expect(d.slideCount, 3);
      // Each layer sits in the slide its panel became.
      final slides = [for (final l in d.layers) d.slideOf(l)];
      expect(slides.sublist(0, 2), everyElement(0));
      expect(slides.sublist(2, 4), everyElement(1));
      expect(slides.sublist(4), everyElement(2));
    });
  });

  test('a corrupt reorder override cannot drop or crash a project', () {
    final t = template([panel('p0', [image('a', x: 0), image('b', x: 0)])]);
    // References a layer that no longer exists.
    final content = const SlotContent().withLayerOrder('p0', ['ghost', 'b', 'a']);

    final d = migrateToV4(t, content).document;
    expect([for (final l in d.layers) l.id], ['b', 'a']);
  });
}
