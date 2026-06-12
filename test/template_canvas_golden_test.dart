import 'dart:convert';
import 'dart:io';

import 'package:collageapp/src/model/slot_content.dart';
import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/rendering/template_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A plain font resolver is injected: the test environment has no network for
// google_fonts, and layout/position/color are what these goldens lock down.
// Font fidelity is verified against the editor with the running app.
TextStyle testFontResolver(String family, TextStyle base) => base;

void main() {

  final template = Template.fromJson(
    jsonDecode(File('test/fixtures/fashion_story.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  Widget host(Widget child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Center(child: child),
      );

  testWidgets('renders the fixture template (empty slots)', (tester) async {
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(host(
      TemplateCanvas(template: template, fontResolver: testFontResolver),
    ));

    await expectLater(
      find.byType(TemplateCanvas),
      matchesGoldenFile('goldens/fashion_story_empty.png'),
    );
  });

  testWidgets('renders user content injected into slots', (tester) async {
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1;
    const content = SlotContent(texts: {
      'title': 'Verão 2026',
      'subtitle': 'nova coleção · em breve',
    });
    await tester.pumpWidget(host(
      TemplateCanvas(
        template: template,
        content: content,
        fontResolver: testFontResolver,
      ),
    ));

    await expectLater(
      find.byType(TemplateCanvas),
      matchesGoldenFile('goldens/fashion_story_filled.png'),
    );
  });
}
