import 'dart:convert';

import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/screens/template_screen.dart';
import 'package:collageapp/src/widgets/insert_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

TextStyle testFontResolver(String family, TextStyle base) => base;

// 1×1 transparent PNG — enough for MemoryImage to decode.
const _pngB64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQ'
    'DwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

/// Gallery picker stub: multi-image picks resolve to [multiResult] without
/// any platform channel. Extends (not implements) the platform interface so
/// the instance setter's token verification passes.
class _FakeImagePicker extends ImagePickerPlatform {
  List<XFile> multiResult = const [];

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async => multiResult;
}

/// The photos-first flow: the toolbar's Photo action multi-selects from the
/// gallery; several photos suggest layouts for that exact count and land as
/// one pre-filled grid.
void main() {
  final pngBytes = base64Decode(_pngB64);
  late _FakeImagePicker picker;

  setUp(() {
    picker = _FakeImagePicker();
    ImagePickerPlatform.instance = picker;
  });

  final undoButton = find.widgetWithIcon(IconButton, Icons.undo);

  Future<void> pumpDraft(WidgetTester tester) async {
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: TemplateScreen(
          draft: Template.blank(),
          fontResolver: testFontResolver,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('several photos suggest matching layouts and insert a filled '
      'grid in one undo step', (tester) async {
    picker.multiResult = [
      for (var i = 0; i < 3; i++) XFile.fromData(pngBytes, name: 'p$i.png'),
    ];
    await pumpDraft(tester);
    await tester.tap(find.text('Photo'));
    await tester.pumpAndSettle();

    // The layout picker is up, offering only 3-cell presets.
    expect(find.text('Choose a layout'), findsOneWidget);
    expect(find.text('3 photos'), findsOneWidget);
    expect(find.text('1 + 2'), findsOneWidget);
    expect(find.text('2 × 2'), findsNothing);

    await tester.tap(find.text('1 + 2'));
    await tester.pumpAndSettle();

    // The grid landed with every cell already filled (no empty pick icons)
    // and nothing selected (no grid bar) — the toolbar is back.
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsNothing);
    expect(find.byType(Slider), findsNothing);
    expect(find.text('Layout'), findsOneWidget);

    // The collage is really there: a tap inside the left cell selects it.
    // (getRect is in GLOBAL px — getSize would be template units.)
    final canvas = tester.getRect(
      find.byKey(const ValueKey('canvas-background')),
    );
    await tester.tapAt(canvas.center - Offset(canvas.width * 0.2, 0));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNWidgets(2));

    // Layer + all three photos revert as ONE step.
    await tester.tap(undoButton);
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
    expect(tester.widget<IconButton>(undoButton).onPressed, isNull);
  });

  testWidgets('a single photo lands as a plain image element, no layout '
      'sheet', (tester) async {
    picker.multiResult = [XFile.fromData(pngBytes, name: 'solo.png')];
    await pumpDraft(tester);
    await tester.tap(find.text('Photo'));
    await tester.pumpAndSettle();

    expect(find.text('Choose a layout'), findsNothing);
    // The element arrived selected WITH its photo: the photo contextual bar
    // is up. After Done, no pick icon anywhere — a selected slot shows the
    // replace overlay (same glyph), so deselect before asserting.
    expect(find.text('Replace'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('cancelling the gallery pick changes nothing', (tester) async {
    picker.multiResult = const [];
    await pumpDraft(tester);
    await tester.tap(find.text('Photo'));
    await tester.pumpAndSettle();

    expect(find.text('Choose a layout'), findsNothing);
    expect(tester.widget<IconButton>(undoButton).onPressed, isNull);
  });

  test('layoutPresetsFor matches the count exactly, with an auto-grid '
      'fallback', () {
    for (var count = 2; count <= 6; count++) {
      final presets = layoutPresetsFor(count);
      expect(presets, isNotEmpty, reason: '$count photos need suggestions');
      for (final preset in presets) {
        expect(preset.cells.length, count);
      }
    }
    // No curated 7-cell preset: a near-square auto grid steps in.
    final auto = layoutPresetsFor(7).single;
    expect(auto.cells.length, 7);
    expect(auto.cols, 3);
    expect(auto.rows, 3);
  });
}
