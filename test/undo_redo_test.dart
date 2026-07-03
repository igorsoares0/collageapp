import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/screens/template_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextStyle testFontResolver(String family, TextStyle base) => base;

void main() {
  final undoButton = find.widgetWithIcon(IconButton, Icons.undo);
  final redoButton = find.widgetWithIcon(IconButton, Icons.redo);
  final canvas = find.byKey(const ValueKey('canvas-background'));

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

  Future<void> addFromMenu(WidgetTester tester, String item) async {
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<IconButton>(button).onPressed != null;

  testWidgets('undo/redo start disabled and revert/replay an added panel', (
    tester,
  ) async {
    await pumpDraft(tester);
    expect(enabled(tester, undoButton), isFalse);
    expect(enabled(tester, redoButton), isFalse);

    await addFromMenu(tester, 'Panel');
    expect(canvas, findsNWidgets(2));
    expect(enabled(tester, undoButton), isTrue);

    await tester.tap(undoButton);
    await tester.pumpAndSettle();
    expect(canvas, findsOneWidget);
    expect(enabled(tester, undoButton), isFalse);
    expect(enabled(tester, redoButton), isTrue);

    await tester.tap(redoButton);
    await tester.pumpAndSettle();
    expect(canvas, findsNWidgets(2));
    expect(enabled(tester, redoButton), isFalse);
  });

  testWidgets('typing coalesces into one undo step', (tester) async {
    await pumpDraft(tester);
    await addFromMenu(tester, 'Text');
    expect(find.byType(TextField), findsOneWidget);

    // Two keystroke batches within the coalescing window share the
    // 'text:<slot>' key → a single undo step for the whole typed run.
    await tester.enterText(find.byType(TextField), 'Hel');
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();

    await tester.tap(undoButton);
    await tester.pumpAndSettle();

    // One undo removed ALL the typing (and closed the inline editor); the
    // empty text layer renders its slot id.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Hello'), findsNothing);
    expect(find.text('Hel'), findsNothing);
    expect(find.text('text_1'), findsOneWidget);

    // A second undo removes the layer itself.
    await tester.tap(undoButton);
    await tester.pumpAndSettle();
    expect(find.text('text_1'), findsNothing);
    expect(enabled(tester, undoButton), isFalse);
  });

  testWidgets('a new edit clears the redo branch', (tester) async {
    await pumpDraft(tester);
    await addFromMenu(tester, 'Panel');
    await tester.tap(undoButton);
    await tester.pumpAndSettle();
    expect(enabled(tester, redoButton), isTrue);

    await addFromMenu(tester, 'Text');
    expect(enabled(tester, redoButton), isFalse);
  });

  testWidgets('undo clears a selection whose element no longer exists', (
    tester,
  ) async {
    await pumpDraft(tester);
    await addFromMenu(tester, 'Grid');
    await tester.tap(find.text('2 × 2'));
    await tester.pumpAndSettle();
    // First cell selected → grid styling bar (two sliders) is up.
    expect(find.byType(Slider), findsNWidgets(2));

    await tester.tap(undoButton);
    await tester.pumpAndSettle();

    // Grid gone AND selection cleared — the background bar state, not a
    // stale empty bar.
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsNothing);
    expect(find.byType(Slider), findsNothing);
  });
}
