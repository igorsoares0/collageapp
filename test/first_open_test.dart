import 'dart:convert';
import 'dart:io';

import 'package:collageapp/src/api/template_api.dart';
import 'package:collageapp/src/api/template_store.dart';
import 'package:collageapp/src/screens/template_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

TextStyle testFontResolver(String family, TextStyle base) => base;

// 1×1 transparent PNG — enough for MemoryImage to decode.
const _pngB64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQ'
    'DwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

/// Gallery picker stub: multi-image picks resolve to [multiResult] and
/// remember the limit they were asked for.
class _FakeImagePicker extends ImagePickerPlatform {
  List<XFile> multiResult = const [];
  int? lastLimit;

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async {
    lastLimit = options.limit;
    return multiResult;
  }
}

String _image(String slot, int x, int y) =>
    '{"id":"l_$slot","type":"image","slotId":"$slot","x":$x,"y":$y,'
    '"width":400,"height":400,"rotation":0,"opacity":1,"borderRadius":0}';

/// Three photo frames, deliberately listed out of reading order: the fill
/// order must come from the geometry, not the layer list.
final _templateBody =
    '{"template":{"id":"tpl","schemaVersion":2,"version":1,'
    '"name":"Three frames","aspectRatio":"story",'
    '"canvas":{"width":1080,"height":1920},'
    '"panels":[{"id":"p","backgroundColor":"#FFFFFF","layers":['
    '${_image('bottom', 100, 1200)},${_image('top_right', 600, 100)},'
    '${_image('top_left', 80, 110)}'
    ']}]}}';

/// The editor's first-open state for a template with photo frames: numbered
/// placeholders, one "Add N photos" that fills them in order, Skip, and an
/// Export that waits for a photo.
void main() {
  late Directory tmp;
  late _FakeImagePicker picker;
  final png = base64Decode(_pngB64);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('first_open_test');
    picker = _FakeImagePicker();
    ImagePickerPlatform.instance = picker;
  });

  tearDown(() async {
    for (var attempt = 0; ; attempt++) {
      try {
        await tmp.delete(recursive: true);
        return;
      } on FileSystemException {
        if (attempt >= 4) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  TemplateStore store() => TemplateStore(
    api: TemplateApi(
      client: MockClient(
        (req) async => switch (req.url.path) {
          '/api/assets' => http.Response('[]', 200),
          _ => http.Response(_templateBody, 200),
        },
      ),
    ),
    cacheDirOverride: tmp,
  );

  /// Real-IO store, so the body runs in runAsync and waits by polling.
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() done, {
    required String reason,
  }) async {
    for (var i = 0; i < 400 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(done(), isTrue, reason: reason);
  }

  Future<void> pumpEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(540, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: TemplateScreen(
          id: 'tpl',
          store: store(),
          fontResolver: testFontResolver,
        ),
      ),
    );
    await pumpUntil(
      tester,
      () => tester.any(find.text('Add 3 photos')),
      reason: 'the editor never opened on its first-open panel',
    );
  }

  Finder exportButton() => find.widgetWithText(FilledButton, 'Export');

  testWidgets('opens on numbered placeholders with Export held back', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await pumpEditor(tester);

      expect(find.text('Start with your photos.'), findsOneWidget);
      // Numbered in READING order, whatever the layer order.
      expect(find.byKey(const ValueKey('pick-top_left')), findsOneWidget);
      final label = tester.widget<Text>(
        find.byKey(const ValueKey('slot-label-top_left')),
      );
      expect(label.data, 'PHOTO 1');
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('slot-label-top_right')))
            .data,
        'PHOTO 2',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('slot-label-bottom')))
            .data,
        'PHOTO 3',
      );
      // No toolbar yet, and nothing to export.
      expect(find.text('Layout'), findsNothing);
      expect(tester.widget<FilledButton>(exportButton()).onPressed, isNull);
    });
  });

  testWidgets('Add N photos fills the frames in order, then the toolbar '
      'returns', (tester) async {
    await tester.runAsync(() async {
      await pumpEditor(tester);
      picker.multiResult = [
        for (var i = 0; i < 2; i++) XFile.fromData(png, name: 'p$i.png'),
      ];

      await tester.tap(find.text('Add 3 photos'));
      await pumpUntil(
        tester,
        // Both: the outgoing panel cross-fades out after the toolbar is in.
        () =>
            tester.any(find.text('Layout')) &&
            !tester.any(find.text('Start with your photos.')),
        reason: 'the toolbar never came back after the photos landed',
      );

      // Asked for exactly as many as there are frames.
      expect(picker.lastLimit, 3);
      // Two photos → frames 1 and 2 filled; frame 3 still waits.
      expect(find.byKey(const ValueKey('slot-label-top_left')), findsNothing);
      expect(find.byKey(const ValueKey('slot-label-top_right')), findsNothing);
      expect(find.byKey(const ValueKey('slot-label-bottom')), findsOneWidget);
      expect(find.text('Start with your photos.'), findsNothing);
      expect(tester.widget<FilledButton>(exportButton()).onPressed, isNotNull);
    });
  });

  testWidgets('Skip shows the toolbar but Export still waits for a photo', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await pumpEditor(tester);

      await tester.tap(find.text('Skip — edit text first'));
      await pumpUntil(
        tester,
        () =>
            tester.any(find.text('Layout')) &&
            !tester.any(find.text('Start with your photos.')),
        reason: 'Skip never showed the toolbar',
      );
      expect(find.text('Start with your photos.'), findsNothing);
      expect(tester.widget<FilledButton>(exportButton()).onPressed, isNull);
    });
  });
}
