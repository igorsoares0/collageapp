import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/rendering/export.dart';
import 'package:collageapp/src/rendering/template_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextStyle testFontResolver(String family, TextStyle base) => base;

void main() {
  final template = Template.fromJson(
    jsonDecode(File('test/fixtures/fashion_story.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  testWidgets('capturePng exports at full template resolution', (tester) async {
    // Render the canvas small AND letterboxed on screen: the 540x700 box
    // doesn't match the 1080x1920 aspect, so the FittedBox paints the canvas
    // with empty side bands. The export must still be exactly full-resolution
    // artwork — the boundary lives inside the FittedBox in template units,
    // so the bands (and the on-screen scale) never leak into the PNG.
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1;
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Center(
          child: SizedBox(
            width: 540,
            height: 700,
            child: TemplateCanvas(
              template: template,
              fontResolver: testFontResolver,
              exportKey: key,
            ),
          ),
        ),
      ),
    );

    // toImage/instantiateImageCodec are real engine async work and never
    // complete inside testWidgets' fake-async zone — hence runAsync.
    final size = await tester.runAsync(() async {
      final bytes = await capturePng(key, template.canvasWidth);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return Size(frame.image.width.toDouble(), frame.image.height.toDouble());
    });

    expect(size!.width, template.canvasWidth);
    expect(size.height, template.canvasHeight);
  });
}
