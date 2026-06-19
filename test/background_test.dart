import 'dart:convert';
import 'dart:io';

import 'package:collageapp/src/model/slot_content.dart';
import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/rendering/template_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextStyle testFontResolver(String family, TextStyle base) => base;

void main() {
  Template fixture({String? backgroundColor}) {
    final json = jsonDecode(
      File('test/fixtures/fashion_story.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    if (backgroundColor != null) {
      (json['canvas'] as Map<String, dynamic>)['backgroundColor'] =
          backgroundColor;
    }
    return Template.fromJson(json);
  }

  Color backgroundOf(WidgetTester tester) {
    return tester
        .widget<ColoredBox>(find.byKey(const ValueKey('canvas-background')))
        .color;
  }

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(MaterialApp(home: Center(child: child)));
  }

  testWidgets('canvas paints the template background color', (tester) async {
    await pump(
      tester,
      TemplateCanvas(
        template: fixture(backgroundColor: '#1C1917'),
        fontResolver: testFontResolver,
      ),
    );
    expect(backgroundOf(tester), const Color(0xFF1C1917));
  });

  testWidgets('user background override wins over the template', (tester) async {
    await pump(
      tester,
      TemplateCanvas(
        template: fixture(backgroundColor: '#1C1917'),
        content: const SlotContent(backgroundColor: Color(0xFF2563EB)),
        fontResolver: testFontResolver,
      ),
    );
    expect(backgroundOf(tester), const Color(0xFF2563EB));
  });
}
