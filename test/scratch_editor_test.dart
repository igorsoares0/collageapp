import 'package:collageapp/src/model/asset_record.dart';
import 'package:collageapp/src/model/slot_content.dart';
import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/rendering/template_canvas.dart';
import 'package:collageapp/src/screens/template_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextStyle testFontResolver(String family, TextStyle base) => base;

// 1×1 transparent PNG — enough for AssetRecord.image to decode.
const _pngB64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQ'
    'DwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

AssetRecord _stickerRecord(String id) => AssetRecord(
  id: id,
  type: 'sticker',
  name: id,
  dataUrl: 'data:image/png;base64,$_pngB64',
  aspect: 1,
  window: null,
);

void main() {
  // The create-from-scratch editor: a blank draft opened directly (no store),
  // built up entirely through the bottom toolbar.
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

  // Taps a bottom-toolbar button by its label (Text, Layout, Photo, Sticker,
  // Panel, ...). The toolbar shows whenever nothing is selected.
  Future<void> addFromToolbar(WidgetTester tester, String item) async {
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  testWidgets('a blank draft opens with an empty canvas', (tester) async {
    await pumpDraft(tester);
    expect(find.byKey(const ValueKey('slide-background-0')), findsOneWidget);
    expect(find.textContaining('Could not load'), findsNothing);
  });

  testWidgets('toolbar inserts a text element and starts inline editing', (
    tester,
  ) async {
    await pumpDraft(tester);
    await addFromToolbar(tester, 'Text');

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();
    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets('grid preset sheet inserts a grid with its first cell selected', (
    tester,
  ) async {
    await pumpDraft(tester);
    await addFromToolbar(tester, 'Layout');

    // The preset sheet is open; pick the classic 2×2.
    await tester.tap(find.text('2 × 2'));
    await tester.pumpAndSettle();

    // Four empty cells, each with a pick icon; the grid styling bar is up
    // (spacing + corners sliders) because the first cell got selected.
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsNWidgets(4));
    expect(find.byType(Slider), findsNWidgets(2));
  });

  testWidgets('toolbar Panel appends an empty second panel', (tester) async {
    await pumpDraft(tester);
    await addFromToolbar(tester, 'Panel');

    expect(find.byKey(const ValueKey('slide-background-1')), findsOneWidget);
  });

  testWidgets('carousel dots appear with a second panel and a tap refocuses', (
    tester,
  ) async {
    await pumpDraft(tester);
    // Single panel: no dots.
    expect(find.byKey(const ValueKey('panel-dot-0')), findsNothing);

    await addFromToolbar(tester, 'Panel');
    expect(find.byKey(const ValueKey('panel-dot-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('panel-dot-1')), findsOneWidget);

    // The added panel took focus; the first dot hands it back to panel 1 —
    // a new text element must land on THAT panel.
    await tester.tap(find.byKey(const ValueKey('panel-dot-0')));
    await tester.pumpAndSettle();
    await addFromToolbar(tester, 'Text');
    final firstCanvas = tester.getRect(
      find.byKey(const ValueKey('slide-background-0')).first,
    );
    expect(
      firstCanvas.contains(tester.getCenter(find.byType(TextField))),
      isTrue,
    );
  });

  testWidgets('asset sheet offers the bundled frames', (tester) async {
    await pumpDraft(tester);
    await addFromToolbar(tester, 'Sticker');

    // No remote catalog in tests, so no stickers — but the seed frames are
    // always available.
    expect(find.text('Frames'), findsOneWidget);
    expect(find.text('Stickers'), findsNothing);
  });

  testWidgets('stickers render their catalog image and select by layer id', (
    tester,
  ) async {
    const sticker = StickerLayer(
      id: 'sticker_1',
      hidden: false,
      assetId: 'st1',
      x: 100,
      y: 100,
      width: 200,
      height: 200,
    );
    String? tapped;
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Center(
          child: PanelCanvas(
            panel: const Panel(
              id: 'p',
              backgroundColor: Color(0xFFFFFFFF),
              layers: [sticker],
            ),
            canvasWidth: 1080,
            canvasHeight: 1920,
            fontResolver: testFontResolver,
            assetCatalog: [_stickerRecord('st1')],
            onSlotTap: (id) => tapped = id,
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.byType(Image));
    expect(tapped, 'sticker_1');
  });

  testWidgets('a sticker missing from the catalog falls back to the '
      'placeholder', (tester) async {
    const sticker = StickerLayer(
      id: 'sticker_1',
      hidden: false,
      assetId: 'st1',
      x: 100,
      y: 100,
      width: 200,
      height: 200,
    );
    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Center(
          child: PanelCanvas(
            panel: Panel(
              id: 'p',
              backgroundColor: Color(0xFFFFFFFF),
              layers: [sticker],
            ),
            canvasWidth: 1080,
            canvasHeight: 1920,
            fontResolver: testFontResolver,
          ),
        ),
      ),
    );

    expect(find.text('st1'), findsOneWidget);
  });

  test('withAddedPanel appends after the template panels', () {
    const content = SlotContent();
    final next = content.withAddedPanel(
      const Panel(
        id: 'panel_2',
        backgroundColor: Color(0xFFFFFFFF),
        layers: [],
      ),
    );
    expect(next.addedPanels.map((p) => p.id), ['panel_2']);
    expect(content.addedPanels, isEmpty);
  });
}
