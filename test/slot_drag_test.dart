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
    final before = tester.getTopLeft(find.text('title'));

    await pump(
      tester,
      TemplateCanvas(
        template: template,
        content: const SlotContent(scales: {'title': 2.0}),
        fontResolver: testFontResolver,
      ),
    );
    final after = tester.getTopLeft(find.text('title'));

    // Center-anchored 2x scale: the 900-wide slot's top-left moves left by
    // 450 template px → 225 screen px at FittedBox scale 0.5.
    expect(after.dx - before.dx, -225);
    expect(after.dy, lessThan(before.dy));
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

    // The sticker has no tap detector: the tap falls through to the canvas.
    await tester.tap(find.text('sticker_star'));
    expect(canvasTaps, 1);
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
