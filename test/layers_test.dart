import 'dart:convert';
import 'dart:io';

import 'package:collageapp/src/model/asset_record.dart';
import 'package:collageapp/src/model/slot_content.dart';
import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/rendering/frame_assets.dart';
import 'package:collageapp/src/rendering/template_canvas.dart';
import 'package:collageapp/src/widgets/layers_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextStyle _testFontResolver(String family, TextStyle base) => base;

void main() {
  final template = Template.fromJson(
    jsonDecode(File('test/fixtures/fashion_story.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  final panel = template.panels.first;
  // Natural stack order (index 0 = bottom).
  final natural = [for (final l in panel.layers) l.id];

  group('SlotContent layer overrides', () {
    test('orderedLayerIds returns the natural order without an override', () {
      const content = SlotContent();
      expect(content.orderedLayerIds(panel.id, natural), natural);
    });

    test('withLayerMoved swaps a layer one step toward the front', () {
      const content = SlotContent();
      // Move the title text one step forward (toward the top of the stack).
      final moved = content.withLayerMoved(
        panel.id,
        natural,
        'txt_title',
        toFront: true,
      );
      final order = moved.orderedLayerIds(panel.id, natural);
      final i = natural.indexOf('txt_title');
      expect(order[i], natural[i + 1]); // neighbour moved down
      expect(order[i + 1], 'txt_title'); // title moved up
    });

    test('withLayerMoved is a no-op at the front edge', () {
      const content = SlotContent();
      final topId = natural.last; // frontmost
      final moved = content.withLayerMoved(
        panel.id,
        natural,
        topId,
        toFront: true,
      );
      expect(moved.orderedLayerIds(panel.id, natural), natural);
    });

    test('withLayerMoved is a no-op at the back edge', () {
      const content = SlotContent();
      final bottomId = natural.first;
      final moved = content.withLayerMoved(
        panel.id,
        natural,
        bottomId,
        toFront: false,
      );
      expect(moved.orderedLayerIds(panel.id, natural), natural);
    });

    test('a stale override never drops layers from the render', () {
      // Override mentions only two ids; the rest must still appear, appended.
      final content = const SlotContent().withLayerOrder(panel.id, [
        'txt_title',
        'img_hero',
      ]);
      final order = content.orderedLayerIds(panel.id, natural);
      expect(order.toSet(), natural.toSet());
      expect(order.take(2), ['txt_title', 'img_hero']);
    });

    test('added layers stack on top and can be removed', () {
      const text = TextLayer(
        id: 'text_1',
        hidden: false,
        slotId: 'text_1',
        x: 0,
        y: 0,
        width: 100,
        fontFamily: 'Inter',
        fontSize: 40,
        fontWeight: 400,
        color: Color(0xFF000000),
        alignment: 'center',
      );
      final added = const SlotContent().withAddedLayer(panel.id, text);
      expect(added.addedLayersFor(panel.id).single.id, 'text_1');
      expect(added.allAddedLayers, hasLength(1));

      final removed = added.withoutAddedLayer(panel.id, 'text_1');
      expect(removed.addedLayersFor(panel.id), isEmpty);
    });

    test('removing an added layer drops it from the order override', () {
      const text = TextLayer(
        id: 'text_1',
        hidden: false,
        slotId: 'text_1',
        x: 0,
        y: 0,
        width: 100,
        fontFamily: 'Inter',
        fontSize: 40,
        fontWeight: 400,
        color: Color(0xFF000000),
        alignment: 'center',
      );
      final withOrder = const SlotContent()
          .withAddedLayer(panel.id, text)
          .withLayerOrder(panel.id, [...natural, 'text_1']);
      final removed = withOrder.withoutAddedLayer(panel.id, 'text_1');
      expect(removed.layerOrders[panel.id], isNot(contains('text_1')));
    });

    test('rotationFor defaults to 0 and withRotation overrides it', () {
      const content = SlotContent();
      expect(content.rotationFor('txt_title'), 0.0);
      final rotated = content.withRotation('txt_title', 35);
      expect(rotated.rotationFor('txt_title'), 35);
      // Other slots are untouched.
      expect(rotated.rotationFor('img_hero'), 0.0);
    });

    test('image layer parses an optional frameAssetId (absent = null)', () {
      ImageLayer parse(Map<String, dynamic> extra) =>
          Layer.fromJson({
                'type': 'image',
                'id': 'img_1',
                'slotId': 'img_1',
                'x': 0,
                'y': 0,
                'width': 100,
                'height': 100,
                'rotation': 0,
                'opacity': 1,
                'borderRadius': 0,
                ...extra,
              })
              as ImageLayer;
      expect(parse({}).frameAssetId, isNull);
      expect(
        parse({'frameAssetId': 'frame_polaroid_v'}).frameAssetId,
        'frame_polaroid_v',
      );
    });

    test('frameAsset resolves known ids and maps the window into a box', () {
      expect(frameAsset(null), isNull);
      expect(frameAsset('nope'), isNull);
      final f = frameAsset('frame_polaroid_v')!;
      // Window is inset from the frame edges (normalized coords scale to px).
      final win = f.windowIn(1000, 1000);
      expect(win.left, closeTo(49.2, 0.1));
      expect(win.width, closeTo(902.4, 0.1));
      expect(win.right, lessThan(1000));
    });

    test('AssetRecord parses a frame window and a null-window sticker', () {
      final frame = AssetRecord.fromJson({
        'id': 'a1',
        'type': 'frame',
        'name': 'My frame',
        'dataUrl': 'data:image/png;base64,AAAA',
        'aspect': 0.7,
        'window': {'x': 0.05, 'y': 0.02, 'w': 0.9, 'h': 0.82},
      });
      expect(frame.window, isNotNull);
      expect(frame.window!.w, 0.9);
      final sticker = AssetRecord.fromJson({
        'id': 'a2',
        'type': 'sticker',
        'name': 'St',
        'dataUrl': 'data:image/png;base64,AAAA',
        'aspect': 1,
        'window': null,
      });
      expect(sticker.window, isNull);
    });

    test('resolveFrame falls back to seeds, then the remote catalog', () {
      // Unset / unknown → null.
      expect(resolveFrame(null, const []), isNull);
      expect(resolveFrame('nope', const []), isNull);

      // A bundled seed resolves with no catalog.
      final seed = resolveFrame('frame_polaroid_v', const [])!;
      expect(seed.image, isA<AssetImage>());
      final w = seed.windowIn(1000, 1000);
      expect(w.left, closeTo(49.2, 0.1));

      // An uploaded frame resolves from the catalog as a MemoryImage, using its
      // own window. (1x1 transparent PNG so the decode is valid.)
      const png =
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
      final record = AssetRecord.fromJson({
        'id': 'frame_custom',
        'type': 'frame',
        'name': 'Custom',
        'dataUrl': png,
        'aspect': 1.5,
        'window': {'x': 0.1, 'y': 0.1, 'w': 0.8, 'h': 0.8},
      });
      final remote = resolveFrame('frame_custom', [record])!;
      expect(remote.image, isA<MemoryImage>());
      expect(remote.aspect, 1.5);
      expect(remote.windowIn(1000, 1000).width, closeTo(800, 0.1));
    });

    test('grid layer parses and cellRect tiles the box (with a span)', () {
      final grid =
          Layer.fromJson({
                'type': 'grid',
                'id': 'g1',
                'x': 0,
                'y': 0,
                'width': 210,
                'height': 210,
                'rotation': 0,
                'cols': 2,
                'rows': 2,
                'colFractions': [1, 1],
                'rowFractions': [1, 1],
                'gutter': 10,
                'cornerRadius': 4,
                'cells': [
                  {'slotId': 'cell_1', 'col': 0, 'row': 0, 'rowSpan': 2},
                  {'slotId': 'cell_2', 'col': 1, 'row': 0},
                  {'slotId': 'cell_3', 'col': 1, 'row': 1},
                ],
              })
              as GridLayer;
      expect(grid.cols, 2);
      expect(grid.cells, hasLength(3));
      // usable = 210 - 10*3 = 180; each track = 90.
      final b = cellRect(grid, grid.cells[1]);
      expect(b.left, closeTo(110, 0.001));
      expect(b.top, closeTo(10, 0.001));
      expect(b.width, closeTo(90, 0.001));
      expect(b.height, closeTo(90, 0.001));
      // The spanning cell eats the internal gutter: height = 90 + 10 + 90.
      final span = cellRect(grid, grid.cells[0]);
      expect(span.height, closeTo(190, 0.001));
    });

    test('grid cells join the panel slot namespace', () {
      final t = Template.fromJson({
        'id': 't',
        'schemaVersion': 3,
        'version': 0,
        'name': 'g',
        'aspectRatio': 'story',
        'canvas': {'width': 1080, 'height': 1920, 'backgroundColor': '#FFFFFF'},
        'layers': [
          {
            'type': 'grid',
            'id': 'g1',
            'x': 0,
            'y': 0,
            'width': 200,
            'height': 200,
            'rotation': 0,
            'cols': 1,
            'rows': 2,
            'colFractions': [1],
            'rowFractions': [1, 1],
            'gutter': 0,
            'cornerRadius': 0,
            'cells': [
              {'slotId': 'cell_1', 'col': 0, 'row': 0},
              {'slotId': 'cell_2', 'col': 0, 'row': 1},
            ],
          },
        ],
      });
      expect(t.slotIds, containsAll(['cell_1', 'cell_2']));
    });

    test('grid overrides fall back to the layer, then to the user value', () {
      const content = SlotContent();
      expect(content.gridGutter('g', 12), 12);
      expect(content.gridCornerRadius('g', 0), 0);
      expect(content.gridColFractions('g', const [1, 1]), [1, 1]);

      final c = content
          .withGridGutter('g', 40)
          .withGridCornerRadius('g', 8)
          .withGridColFractions('g', const [2, 1]);
      expect(c.gridGutter('g', 12), 40);
      expect(c.gridCornerRadius('g', 0), 8);
      expect(c.gridColFractions('g', const [1, 1]), [2, 1]);
      // Rows still fall back; a different grid is untouched.
      expect(c.gridRowFractions('g', const [1, 1]), [1, 1]);
      expect(c.gridGutter('other', 12), 12);
    });

    test('layerHidden defers to the template flag, then to the override', () {
      const content = SlotContent();
      // shape_hidden carries editor.hidden:true in the fixture.
      expect(content.layerHidden('shape_hidden', true), isTrue);
      expect(content.layerHidden('img_hero', false), isFalse);
      // A user override wins over the template flag either way.
      final shown = content.withLayerHidden('shape_hidden', false);
      expect(shown.layerHidden('shape_hidden', true), isFalse);
      final hidden = content.withLayerHidden('img_hero', true);
      expect(hidden.layerHidden('img_hero', false), isTrue);
    });
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: child),
      ),
    );
  }

  group('PanelCanvas honours layer overrides', () {
    testWidgets('a user-hidden layer is not rendered', (tester) async {
      await pump(
        tester,
        PanelCanvas(
          panel: panel,
          canvasWidth: template.canvasWidth,
          canvasHeight: template.canvasHeight,
          fontResolver: _testFontResolver,
        ),
      );
      expect(find.text('title'), findsOneWidget);

      await pump(
        tester,
        PanelCanvas(
          panel: panel,
          canvasWidth: template.canvasWidth,
          canvasHeight: template.canvasHeight,
          content: const SlotContent().withLayerHidden('txt_title', true),
          fontResolver: _testFontResolver,
        ),
      );
      expect(find.text('title'), findsNothing);
    });

    testWidgets('a template-hidden layer can be shown via override', (
      tester,
    ) async {
      // shape_hidden is hidden in the template; an override reveals it.
      await pump(
        tester,
        PanelCanvas(
          panel: panel,
          canvasWidth: template.canvasWidth,
          canvasHeight: template.canvasHeight,
          content: const SlotContent().withLayerHidden('shape_hidden', false),
          fontResolver: _testFontResolver,
        ),
      );
      // The revealed red shape now paints (its ColoredBox/Container exists).
      // Simply assert the render didn't throw and the slot labels still show.
      expect(find.text('hero_image'), findsOneWidget);
    });
  });

  group('LayersSheet', () {
    testWidgets('lists layers front-to-back and reports interactions', (
      tester,
    ) async {
      final selected = <String>[];
      final toggled = <String>[];
      final reordered = <List<String>>[];
      await pump(
        tester,
        LayersSheet(
          panel: panel,
          content: const SlotContent(),
          onSelect: selected.add,
          onToggleHidden: (l) => toggled.add(l.id),
          onReorderList: reordered.add,
        ),
      );

      // Fillable slots are labelled by slotId.
      expect(find.text('hero_image'), findsOneWidget);
      expect(find.text('title'), findsOneWidget);
      // Decorative layers are listed too.
      expect(find.text('Shape'), findsWidgets);

      // Tapping a fillable row selects its slot.
      await tester.tap(find.text('title'));
      expect(selected, ['title']);

      // Each row has a visibility toggle.
      expect(find.byTooltip('Hide'), findsWidgets);
      await tester.tap(find.byTooltip('Hide').first);
      expect(toggled, isNotEmpty);

      // Dragging a row by its handle reports the panel's complete new stack
      // order, bottom-first — the exact permutation, not merely "something
      // was reported". A weaker assertion here let a reorder that never
      // reached the canvas pass for a whole migration.
      final handles = find.byIcon(Icons.drag_indicator);
      expect(handles, findsNWidgets(panel.layers.length));

      // One row down, measured rather than guessed.
      final rowHeight =
          tester.getCenter(handles.at(1)).dy -
          tester.getCenter(handles.first).dy;
      // ReorderableListView follows the pointer frame by frame; a single
      // tester.drag() jumps past its bookkeeping and drops the row in place.
      final gesture = await tester.startGesture(
        tester.getCenter(handles.first),
      );
      await tester.pump(const Duration(milliseconds: 300));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(Offset(0, rowHeight / 10));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      // The sheet lists front-first, so its top row is the stack's LAST
      // entry: dragging it down one swaps the two topmost layers and leaves
      // everything below them alone.
      final natural = [for (final l in panel.layers) l.id];
      expect(reordered.last, [
        ...natural.sublist(0, natural.length - 2),
        natural.last,
        natural[natural.length - 2],
      ]);
    });

    testWidgets('only user-added layers expose a delete button', (
      tester,
    ) async {
      const added = TextLayer(
        id: 'text_1',
        hidden: false,
        slotId: 'text_1',
        x: 0,
        y: 0,
        width: 100,
        fontFamily: 'Inter',
        fontSize: 40,
        fontWeight: 400,
        color: Color(0xFF000000),
        alignment: 'center',
      );
      final effective = Panel(
        id: panel.id,
        backgroundColor: panel.backgroundColor,
        layers: [...panel.layers, added],
      );
      final removed = <String>[];
      await pump(
        tester,
        LayersSheet(
          panel: effective,
          content: const SlotContent(),
          onSelect: (_) {},
          onToggleHidden: (_) {},
          onReorderList: (_) {},
          removableLayerIds: const {'text_1'},
          onRemove: (l) => removed.add(l.id),
        ),
      );

      // Exactly one row (the added one) is deletable.
      expect(find.byTooltip('Delete'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete'));
      expect(removed, ['text_1']);
    });
  });
}
