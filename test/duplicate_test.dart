import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/rendering/snap.dart';
import 'package:collageapp/src/screens/template_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextStyle testFontResolver(String family, TextStyle base) => base;

/// The contextual bars' Duplicate action and the phase-3 refinements
/// (text size slider, rotation snapping).
void main() {
  final undoButton = find.widgetWithIcon(IconButton, Icons.undo);
  final duplicateButton = find.byTooltip('Duplicate');

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

  // Taps a bottom-toolbar button by its label.
  Future<void> addFromToolbar(WidgetTester tester, String item) async {
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  testWidgets('duplicating a text element copies its content (undoable)', (
    tester,
  ) async {
    await pumpDraft(tester);
    await addFromToolbar(tester, 'Text');
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pumpAndSettle();

    await tester.tap(duplicateButton);
    await tester.pumpAndSettle();

    // Original (a plain Text again — editing closed) plus the copy.
    expect(find.text('Hello'), findsNWidgets(2));

    // One undo removes only the copy.
    await tester.tap(undoButton);
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets('duplicating a grid copies every cell', (tester) async {
    await pumpDraft(tester);
    await addFromToolbar(tester, 'Layout');
    await tester.tap(find.text('2 × 2'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsNWidgets(4));

    await tester.tap(duplicateButton);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsNWidgets(8));

    await tester.tap(undoButton);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsNWidgets(4));
  });

  testWidgets('the text bar has a size slider driving the slot scale', (
    tester,
  ) async {
    await pumpDraft(tester);
    await addFromToolbar(tester, 'Text');

    final slider = find.byType(Slider);
    expect(slider, findsOneWidget);
    expect(tester.widget<Slider>(slider).value, 1.0);

    // Dragging the slider is a content edit: it lands in the undo history
    // and updates the slider's own position.
    await tester.drag(slider, const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).value, greaterThan(1.0));
  });

  test('snapRotation locks near straight angles and passes the rest through', () {
    expect(snapRotation(44), 45);
    expect(snapRotation(-3), 0);
    expect(snapRotation(92), 90);
    expect(snapRotation(137), 135);
    expect(snapRotation(20), 20);
    expect(snapRotation(67.4), 67.4);
  });
}
