import 'dart:convert';
import 'dart:io';

import 'package:collageapp/src/model/slot_content.dart';
import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/rendering/template_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextStyle testFontResolver(String family, TextStyle base) => base;

void main() {
  final template = Template.fromJson(
    jsonDecode(File('test/fixtures/fashion_story.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  // 540x960 view for a 1080x1920 canvas → FittedBox scale 0.5.
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Center(child: child),
      ),
    );
  }

  testWidgets('SlotContent offsets shift the render by offset * scale', (
    tester,
  ) async {
    await pump(
      tester,
      TemplateCanvas(template: template, fontResolver: testFontResolver),
    );
    final before = tester.getTopLeft(find.text('title'));

    await pump(
      tester,
      TemplateCanvas(
        template: template,
        content: const SlotContent(offsets: {'title': Offset(100, 60)}),
        fontResolver: testFontResolver,
      ),
    );
    final after = tester.getTopLeft(find.text('title'));

    expect(after - before, const Offset(50, 30));
  });

  testWidgets('panning a selected slot reports template-space deltas and '
      'moves it', (tester) async {
    var content = const SlotContent();
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => TemplateCanvas(
          template: template,
          content: content,
          fontResolver: testFontResolver,
          // Move/resize gestures are only wired on the selected slot.
          selectedSlotId: 'hero_image',
          onSlotDrag: (slotId, delta) => setState(() {
            content = content.withOffset(
              slotId,
              content.offsetFor(slotId) + delta,
            );
          }),
        ),
      ),
    );

    // The hero image slot is rotated 4° — dragging must still follow the
    // finger because translation is applied before rotation.
    final start = tester.getCenter(find.text('hero_image'));
    final gesture = await tester.startGesture(start);
    // First move eats the touch slop; the second is delivered in full.
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    final mid = tester.getTopLeft(find.text('hero_image'));
    await gesture.moveBy(const Offset(50, 30));
    await tester.pump();
    await gesture.up();
    final end = tester.getTopLeft(find.text('hero_image'));

    // 50 screen px → 100 template px → re-rendered at scale 0.5 → 50 px.
    expect(end - mid, const Offset(50, 30));
    expect(content.offsetFor('hero_image').dx, greaterThan(0));
  });

  testWidgets('an unselected slot is not draggable', (tester) async {
    var content = const SlotContent();
    var dragged = false;
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => TemplateCanvas(
          template: template,
          content: content,
          fontResolver: testFontResolver,
          // No selectedSlotId: the slot only taps to select; a drag must fall
          // through (to the canvas pan) instead of moving the element.
          onSlotDrag: (slotId, delta) {
            dragged = true;
            setState(
              () => content = content.withOffset(
                slotId,
                content.offsetFor(slotId) + delta,
              ),
            );
          },
        ),
      ),
    );

    final start = tester.getCenter(find.text('hero_image'));
    final g = await tester.startGesture(start);
    await g.moveBy(const Offset(40, 0));
    await tester.pump();
    await g.moveBy(const Offset(50, 30));
    await tester.pump();
    await g.up();

    expect(dragged, isFalse);
    expect(content.offsetFor('hero_image'), Offset.zero);
  });

  testWidgets('image gallery opens from the photo icon, not the element', (
    tester,
  ) async {
    final taps = <String>[];
    final picks = <String>[];
    await pump(
      tester,
      PanelCanvas(
        panel: template.panels.first,
        canvasWidth: template.canvasWidth,
        canvasHeight: template.canvasHeight,
        fontResolver: testFontResolver,
        onSlotTap: taps.add,
        onPickImage: picks.add,
      ),
    );

    // Tapping the slot body (its label) selects it — it must NOT open gallery.
    await tester.tap(find.text('hero_image'));
    expect(picks, isEmpty);
    expect(taps, contains('hero_image'));

    // Tapping the photo icon is the only thing that opens the gallery.
    await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
    expect(picks, ['hero_image']);
  });

  testWidgets('SlotContent scales resize the slot around its center', (
    tester,
  ) async {
    await pump(
      tester,
      TemplateCanvas(template: template, fontResolver: testFontResolver),
    );
    final before = tester.getRect(find.text('title'));

    await pump(
      tester,
      TemplateCanvas(
        template: template,
        content: const SlotContent(scales: {'title': 2.0}),
        fontResolver: testFontResolver,
      ),
    );
    final after = tester.getRect(find.text('title'));

    // Center-anchored 2x scale: the text box (which hugs its glyphs) doubles
    // in place — same center, twice the extent.
    expect(after.center.dx, closeTo(before.center.dx, 0.001));
    expect(after.center.dy, closeTo(before.center.dy, 0.001));
    expect(after.width, closeTo(before.width * 2, 0.001));
    expect(after.height, closeTo(before.height * 2, 0.001));
  });

  testWidgets('pinching a selected slot updates its scale', (tester) async {
    var content = const SlotContent();
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => TemplateCanvas(
          template: template,
          content: content,
          fontResolver: testFontResolver,
          // Pinch-resize is only wired on the selected slot.
          selectedSlotId: 'title',
          onSlotScale: (slotId, scale) =>
              setState(() => content = content.withScale(slotId, scale)),
        ),
      ),
    );

    final center = tester.getCenter(find.text('title'));
    final finger1 = await tester.startGesture(center - const Offset(20, 0));
    final finger2 = await tester.startGesture(center + const Offset(20, 0));
    await finger1.moveBy(const Offset(-20, 0));
    await finger2.moveBy(const Offset(20, 0));
    await tester.pump();
    await finger1.up();
    await finger2.up();

    // Finger spread doubled (40 → 80 px).
    expect(content.scaleFor('title'), closeTo(2.0, 0.25));
  });

  testWidgets('tap selects a slot; canvas tap clears the selection', (
    tester,
  ) async {
    final taps = <String>[];
    var canvasTaps = 0;
    await pump(
      tester,
      TemplateCanvas(
        template: template,
        fontResolver: testFontResolver,
        onSlotTap: taps.add,
        onCanvasTap: () => canvasTaps++,
      ),
    );

    await tester.tap(find.text('title'));
    expect(taps, ['title']);

    // Stickers are slot citizens too, selecting by their LAYER id.
    await tester.tap(find.text('sticker_star'));
    expect(taps, ['title', 'sticker_deco']);
    expect(canvasTaps, 0);
  });

  testWidgets('selected slot shows handles and corner drag resizes it', (
    tester,
  ) async {
    var content = const SlotContent();
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => TemplateCanvas(
          template: template,
          content: content,
          fontResolver: testFontResolver,
          selectedSlotId: 'title',
          onSlotScale: (slotId, scale) =>
              setState(() => content = content.withScale(slotId, scale)),
        ),
      ),
    );

    // Four round corner handles, no side handles.
    for (final key in ['tl', 'tr', 'bl', 'br']) {
      expect(find.byKey(ValueKey('handle_$key')), findsOneWidget);
    }
    for (final key in ['l', 'r', 't', 'b']) {
      expect(find.byKey(ValueKey('handle_$key')), findsNothing);
    }

    // Grab the bottom-right corner and pull outward: the slot grows.
    // (Multi-step gesture: the first move clears the recognizer's slop.
    // Kept small so the wide fixture title's corner stays on-canvas.)
    final corner = tester.getCenter(find.byKey(const ValueKey('handle_br')));
    final grow = await tester.startGesture(corner);
    await grow.moveBy(const Offset(8, 4));
    await tester.pump();
    await grow.moveBy(const Offset(8, 4));
    await tester.pump();
    await grow.up();
    final grown = content.scaleFor('title');
    expect(grown, greaterThan(1.0));

    // And back inward shrinks.
    final cornerNow = tester.getCenter(find.byKey(const ValueKey('handle_br')));
    final shrink = await tester.startGesture(cornerNow);
    await shrink.moveBy(const Offset(-8, -4));
    await tester.pump();
    await shrink.moveBy(const Offset(-12, -6));
    await tester.pump();
    await shrink.up();
    expect(content.scaleFor('title'), lessThan(grown));
  });

  testWidgets('corner drag resizes a slot with a template rotation', (
    tester,
  ) async {
    // Regression: the element paints through its template rotation, so the
    // visible corner handles orbit with it. The touch zones must too — before
    // the fix they were computed unrotated, so grabbing the visible handle of a
    // designer-rotated element did nothing.
    final rotated = Template.fromJson({
      'id': 'rot',
      'schemaVersion': 1,
      'version': 0,
      'name': 'rot',
      'aspectRatio': 'story',
      'canvas': {'width': 1080, 'height': 1920, 'backgroundColor': '#FFFFFF'},
      'layers': [
        {
          'type': 'image',
          'id': 'img',
          'slotId': 'rot_img',
          'x': 340,
          'y': 760,
          'width': 400,
          'height': 400,
          'rotation': 45,
          'opacity': 1,
          'borderRadius': 0,
        },
      ],
    });

    var content = const SlotContent();
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => TemplateCanvas(
          template: rotated,
          content: content,
          fontResolver: testFontResolver,
          selectedSlotId: 'rot_img',
          onSlotScale: (slotId, scale) =>
              setState(() => content = content.withScale(slotId, scale)),
          // Wired so a mis-detected grab would move (not resize) — proving the
          // grab really is recognized as a corner resize.
          onSlotDrag: (slotId, delta) => setState(
            () => content = content.withOffset(
              slotId,
              content.offsetFor(slotId) + delta,
            ),
          ),
        ),
      ),
    );

    // Pull the (rotated) bottom-right handle straight outward from the center.
    final tl = tester.getCenter(find.byKey(const ValueKey('handle_tl')));
    final br = tester.getCenter(find.byKey(const ValueKey('handle_br')));
    final center = (tl + br) / 2;
    final dir = (br - center) / (br - center).distance;

    final grow = await tester.startGesture(br);
    await grow.moveBy(dir * 8);
    await tester.pump();
    await grow.moveBy(dir * 12);
    await tester.pump();
    await grow.up();

    // Resize fired (scale grew) and it was NOT treated as a move.
    expect(content.scaleFor('rot_img'), greaterThan(1.0));
    expect(content.offsetFor('rot_img'), Offset.zero);
  });

  // A 1x1 transparent PNG so MemoryImage decodes in the filled-cell test.
  final onePixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA'
    '60e6kgAAAABJRU5ErkJggg==',
  );

  Template gridTemplate({required bool single}) => Template.fromJson({
    'id': 'grid_t',
    'schemaVersion': 3,
    'version': 0,
    'name': 'Grid',
    'aspectRatio': 'story',
    'canvas': {'width': 1080, 'height': 1920, 'backgroundColor': '#FFFFFF'},
    'layers': [
      single
          ? {
              'type': 'grid',
              'id': 'g',
              'x': 40,
              'y': 40,
              'width': 1000,
              'height': 1000,
              'rotation': 0,
              'cols': 1,
              'rows': 1,
              'colFractions': [1],
              'rowFractions': [1],
              'gutter': 0,
              'cornerRadius': 0,
              'cells': [
                {'slotId': 'cell_1', 'col': 0, 'row': 0},
              ],
            }
          : {
              'type': 'grid',
              'id': 'g',
              'x': 40,
              'y': 400,
              'width': 1000,
              'height': 1000,
              'rotation': 0,
              'cols': 2,
              'rows': 2,
              'colFractions': [1, 1],
              'rowFractions': [1, 1],
              'gutter': 20,
              'cornerRadius': 0,
              'cells': [
                {'slotId': 'cell_1', 'col': 0, 'row': 0},
                {'slotId': 'cell_2', 'col': 1, 'row': 0},
                {'slotId': 'cell_3', 'col': 0, 'row': 1},
                {'slotId': 'cell_4', 'col': 1, 'row': 1},
              ],
            },
    ],
  });

  testWidgets('an empty grid cell opens the picker from its icon', (
    tester,
  ) async {
    final picks = <String>[];
    final template = gridTemplate(single: false);
    await pump(
      tester,
      PanelCanvas(
        panel: template.panels.first,
        canvasWidth: template.canvasWidth,
        canvasHeight: template.canvasHeight,
        fontResolver: testFontResolver,
        onSlotTap: (_) {},
        onPickImage: picks.add,
      ),
    );

    // Empty cells advertise the add-photo icon; tapping it opens the gallery
    // for that cell's slot.
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsWidgets);
    await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined).first);
    expect(picks, isNotEmpty);
    expect(picks.first, startsWith('cell_'));
  });

  testWidgets('dragging inside a selected grid cell moves the whole grid', (
    tester,
  ) async {
    final template = gridTemplate(single: true); // grid layer id 'g'
    var content = SlotContent(images: {'cell_1': MemoryImage(onePixelPng)});
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => PanelCanvas(
          panel: template.panels.first,
          canvasWidth: template.canvasWidth,
          canvasHeight: template.canvasHeight,
          fontResolver: testFontResolver,
          content: content,
          selectedSlotId: 'cell_1',
          onSlotTap: (_) {},
          onSlotScale: (id, s) =>
              setState(() => content = content.withScale(id, s)),
          onSlotDrag: (id, d) => setState(
            () => content = content.withOffset(id, content.offsetFor(id) + d),
          ),
        ),
      ),
    );

    // Drag from inside the (only) cell: the cell is translucent, so the touch
    // falls through to the whole-grid surface and MOVES the grid — no crop.
    // First move eats the recognizer's slop.
    final start = tester.getCenter(find.byType(Image));
    final g = await tester.startGesture(start);
    await g.moveBy(const Offset(30, 0));
    await tester.pump();
    await g.moveBy(const Offset(40, 0));
    await tester.pump();
    await g.up();
    expect(content.offsetFor('g'), isNot(Offset.zero));
    expect(content.offsetFor('cell_1'), Offset.zero);
  });

  testWidgets('dragging a grid divider re-splits the column fractions', (
    tester,
  ) async {
    final template = gridTemplate(single: false); // 2x2, one column divider
    final calls = <List<double>>[];
    bool? sawColumns;
    await pump(
      tester,
      PanelCanvas(
        panel: template.panels.first,
        canvasWidth: template.canvasWidth,
        canvasHeight: template.canvasHeight,
        fontResolver: testFontResolver,
        // A selected cell puts the grid in "active" mode → dividers appear.
        selectedSlotId: 'cell_1',
        onSlotTap: (_) {},
        onGridFractions: (id, columns, fractions) {
          sawColumns = columns;
          calls.add(fractions);
        },
      ),
    );

    final handle = find.byKey(const ValueKey('grid_div_col_0'));
    expect(handle, findsOneWidget);
    // Grab near the top of the column divider, away from where the row divider
    // crosses it at the grid centre.
    final rect = tester.getRect(handle);
    final g = await tester.startGesture(
      Offset(rect.center.dx, rect.top + rect.height * 0.2),
    );
    await g.moveBy(const Offset(30, 0));
    await tester.pump();
    await g.moveBy(const Offset(40, 0));
    await tester.pump();
    await g.up();

    // ONE commit on release with the whole drag accumulated — the in-flight
    // frames repaint the grid locally instead of updating the content.
    expect(calls, hasLength(1));
    expect(sawColumns, isTrue);
    // The boundary moved right → the left track grew past its original half.
    expect(calls.last[0], greaterThan(1.0));
    // Sum is preserved (fraction is transferred between the pair).
    expect(calls.last[0] + calls.last[1], closeTo(2.0, 0.0001));
  });

  testWidgets('a spanning cell trims the crossing divider to its real '
      'segment', (tester) async {
    // The user's collage layout: the left cell spans both rows, so the row
    // boundary only exists in the RIGHT column. Its handle strip (and pill)
    // must sit there — not run across the whole grid and stack a "+" onto
    // the column divider at the grid centre.
    final template = Template.fromJson({
      'id': 'grid_t',
      'schemaVersion': 3,
      'version': 0,
      'name': 'Grid',
      'aspectRatio': 'story',
      'canvas': {'width': 1080, 'height': 1920, 'backgroundColor': '#FFFFFF'},
      'layers': [
        {
          'type': 'grid',
          'id': 'g',
          'x': 40,
          'y': 400,
          'width': 1000,
          'height': 1000,
          'rotation': 0,
          'cols': 2,
          'rows': 2,
          'colFractions': [1, 1],
          'rowFractions': [1, 1],
          'gutter': 20,
          'cornerRadius': 0,
          'cells': [
            {'slotId': 'cell_1', 'col': 0, 'row': 0, 'rowSpan': 2},
            {'slotId': 'cell_2', 'col': 1, 'row': 0},
            {'slotId': 'cell_3', 'col': 1, 'row': 1},
          ],
        },
      ],
    });
    await pump(
      tester,
      PanelCanvas(
        panel: template.panels.first,
        canvasWidth: template.canvasWidth,
        canvasHeight: template.canvasHeight,
        fontResolver: testFontResolver,
        selectedSlotId: 'cell_1',
        onSlotTap: (_) {},
        onGridFractions: (_, _, _) {},
      ),
    );

    final colStrip = tester.getRect(find.byKey(const ValueKey('grid_div_col_0')));
    final rowStrip = tester.getRect(find.byKey(const ValueKey('grid_div_row_0')));
    // The row strip lives entirely in the right column, past the column
    // boundary — the spanning left cell erased its left half.
    expect(rowStrip.left, greaterThanOrEqualTo(colStrip.center.dx));
    // The column boundary splits the full-height left cell, so its strip
    // still spans well past the row strip's band on both sides.
    expect(colStrip.top, lessThan(rowStrip.top - 50));
    expect(colStrip.bottom, greaterThan(rowStrip.bottom + 50));
  });

  testWidgets('selecting a grid cell reveals the whole-grid handles', (
    tester,
  ) async {
    final template = gridTemplate(single: true);
    await pump(
      tester,
      PanelCanvas(
        panel: template.panels.first,
        canvasWidth: template.canvasWidth,
        canvasHeight: template.canvasHeight,
        fontResolver: testFontResolver,
        selectedSlotId: 'cell_1',
        onSlotTap: (_) {},
      ),
    );
    // The whole-grid chrome (corner + rotate handles) appears around the grid.
    expect(find.byKey(const ValueKey('handle_tl')), findsOneWidget);
    expect(find.byKey(const ValueKey('handle_rotate')), findsOneWidget);
  });

  testWidgets('dragging the grid chrome ring moves the whole grid', (
    tester,
  ) async {
    final template = gridTemplate(single: true); // grid layer id 'g'
    var content = const SlotContent();
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => PanelCanvas(
          panel: template.panels.first,
          canvasWidth: template.canvasWidth,
          canvasHeight: template.canvasHeight,
          fontResolver: testFontResolver,
          content: content,
          selectedSlotId: 'cell_1',
          onSlotTap: (_) {},
          onSlotScale: (id, s) =>
              setState(() => content = content.withScale(id, s)),
          onSlotDrag: (id, d) => setState(
            () => content = content.withOffset(id, content.offsetFor(id) + d),
          ),
        ),
      ),
    );

    // A point just left of the grid box (canvas x≈20 → in the chrome ring, not
    // over a cell) drags the whole grid, not a cell's crop.
    final g = await tester.startGesture(const Offset(10, 260));
    await g.moveBy(const Offset(0, 24));
    await tester.pump();
    await g.moveBy(const Offset(0, 30));
    await tester.pump();
    await g.up();

    // The grid layer ('g') gained a move offset; no cell was cropped.
    expect(content.offsetFor('g'), isNot(Offset.zero));
    expect(content.offsetFor('cell_1'), Offset.zero);
  });

  testWidgets('dragging the interior moves the selected slot, not resize', (
    tester,
  ) async {
    var content = const SlotContent();
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => TemplateCanvas(
          template: template,
          content: content,
          fontResolver: testFontResolver,
          selectedSlotId: 'title',
          onSlotScale: (slotId, scale) =>
              setState(() => content = content.withScale(slotId, scale)),
          onSlotDrag: (slotId, delta) => setState(
            () => content = content.withOffset(
              slotId,
              content.offsetFor(slotId) + delta,
            ),
          ),
        ),
      ),
    );

    // Centre of the title slot is interior → move, scale untouched.
    final center = tester.getCenter(find.text('title'));
    final g = await tester.startGesture(center);
    await g.moveBy(const Offset(15, 20));
    await tester.pump();
    await g.moveBy(const Offset(15, 20));
    await tester.pump();
    await g.up();
    expect(content.scaleFor('title'), 1.0);
    expect(content.offsetFor('title'), isNot(Offset.zero));
  });
}
