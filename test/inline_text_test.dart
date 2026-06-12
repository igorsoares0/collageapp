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

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Center(child: child),
    ));
  }

  testWidgets('no TextField is rendered when nothing is being edited',
      (tester) async {
    await pump(
      tester,
      TemplateCanvas(template: template, fontResolver: testFontResolver),
    );
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('editing slot renders an inline TextField that streams changes',
      (tester) async {
    final changes = <String, String>{};
    await pump(
      tester,
      TemplateCanvas(
        template: template,
        fontResolver: testFontResolver,
        content: const SlotContent(texts: {'title': 'Verão'}),
        editingSlotId: 'title',
        onTextChanged: (slotId, value) => changes[slotId] = value,
      ),
    );

    // The field replaces the Text and is seeded with the current content.
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Verão',
    );

    await tester.enterText(find.byType(TextField), 'Verão 2026');
    expect(changes['title'], 'Verão 2026');
  });
}
