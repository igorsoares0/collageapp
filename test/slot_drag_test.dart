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
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Center(child: child),
    ));
  }

  testWidgets('SlotContent offsets shift the render by offset * scale',
      (tester) async {
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

  testWidgets('panning a slot reports template-space deltas and moves it',
      (tester) async {
    var content = const SlotContent();
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => TemplateCanvas(
          template: template,
          content: content,
          fontResolver: testFontResolver,
          onSlotDrag: (slotId, delta) => setState(() {
            content = content.withOffset(
                slotId, content.offsetFor(slotId) + delta);
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
}
