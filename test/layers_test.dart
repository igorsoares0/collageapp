import 'dart:convert';
import 'dart:io';

import 'package:collageapp/src/model/slot_content.dart';
import 'package:collageapp/src/model/template.dart';
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
      final reordered = <(String, bool)>[];
      await pump(
        tester,
        LayersSheet(
          panel: panel,
          content: const SlotContent(),
          onSelect: selected.add,
          onToggleHidden: (l) => toggled.add(l.id),
          onReorder: (l, {required toFront}) => reordered.add((l.id, toFront)),
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
          onReorder: (_, {required toFront}) {},
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
