import 'package:collageapp/src/model/slot_content.dart';
import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/rendering/export.dart';
import 'package:collageapp/src/rendering/template_canvas.dart';
import 'package:collageapp/src/screens/export_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextStyle testFontResolver(String family, TextStyle base) => base;

const _slideW = 300.0;
const _slideH = 400.0;

Document _doc(int slides) => Document(
  id: 'd',
  schemaVersion: 4,
  version: 1,
  name: 'Doc',
  aspectRatio: '3:4',
  slideWidth: _slideW,
  slideHeight: _slideH,
  slideCount: slides,
  gutter: 0,
  slideBackgrounds: const [
    Color(0xFFFF0000),
    Color(0xFF00FF00),
    Color(0xFF0000FF),
  ],
  layers: const [],
);

/// Rasters [d] the way the editor does before it opens the export screen.
Future<DocumentRaster> _raster(WidgetTester tester, Document d) async {
  final key = GlobalKey();
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: _slideW * d.slideCount,
          height: _slideH,
          child: CanvasView(
            document: d,
            content: const SlotContent(),
            fontResolver: testFontResolver,
            exportKey: key,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (await tester.runAsync(() => rasterDocument(key, d)))!;
}

void main() {
  testWidgets('develops every slide, then offers Share and Save to Photos', (
    tester,
  ) async {
    final d = _doc(3);
    final raster = await _raster(tester, d);

    await tester.pumpWidget(
      MaterialApp(
        home: ExportScreen(raster: raster, document: d, projectSaved: true),
      ),
    );
    // The format line, while developing.
    expect(find.text('300 × 400 · PNG'), findsOneWidget);

    // Encoding is real async work: let it run, then settle the fades.
    for (var i = 0; i < 40 && !tester.any(find.text('Share')); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    expect(find.text('Three slides,\nready.'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Save to Photos'), findsOneWidget);
    expect(
      find.text('Your project is saved — find it again in Projects.'),
      findsOneWidget,
    );
    // Every slide is there to check, one PNG each.
    expect(find.byType(Image), findsNWidgets(3));
  });

  testWidgets('a single slide reads in the singular', (tester) async {
    final d = _doc(1);
    final raster = await _raster(tester, d);
    await tester.pumpWidget(
      MaterialApp(
        home: ExportScreen(raster: raster, document: d),
      ),
    );
    for (var i = 0; i < 40 && !tester.any(find.text('Share')); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(find.text('One slide,\nready.'), findsOneWidget);
  });
}
