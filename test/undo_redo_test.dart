import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/screens/template_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextStyle testFontResolver(String family, TextStyle base) => base;

void main() {
  final undoButton = find.widgetWithIcon(IconButton, Icons.undo);
  final redoButton = find.widgetWithIcon(IconButton, Icons.redo);
  // Slides each carry their own background key now, so the presence of the
  // SECOND one is what 'the document has two slides' looks like.
  final secondSlide = find.byKey(const ValueKey('slide-background-1'));

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

  // Taps a bottom-toolbar button by its label (Text, Layout, Panel, ...).
  Future<void> addFromToolbar(WidgetTester tester, String item) async {
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

    await addFromToolbar(tester, 'Panel');
    expect(secondSlide, findsOneWidget);
    expect(enabled(tester, undoButton), isTrue);

    await tester.tap(undoButton);
    await tester.pumpAndSettle();
    expect(secondSlide, findsNothing);
    expect(enabled(tester, undoButton), isFalse);
    expect(enabled(tester, redoButton), isTrue);

    await tester.tap(redoButton);
    await tester.pumpAndSettle();
    expect(secondSlide, findsOneWidget);
    expect(enabled(tester, redoButton), isFalse);
  });

  testWidgets('typing coalesces into one undo step', (tester) async {
    await pumpDraft(tester);
    await addFromToolbar(tester, 'Text');
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

  testWidgets('a whole drag is one undo step', (tester) async {
    // A single 300×300 element, so the sweep below has nothing to snap to but
    // the canvas itself and the drag stays a plain move.
    final template = Template(
      id: 't',
      schemaVersion: 3,
      version: 1,
      name: 'T',
      aspectRatio: '9:16',
      canvasWidth: 1080,
      canvasHeight: 1920,
      panels: const [
        Panel(
          id: 'p',
          backgroundColor: Color(0xFFFFFFFF),
          layers: [
            ImageLayer(
              id: 'img',
              hidden: false,
              slotId: 'img',
              x: 270,
              y: 690,
              width: 300,
              height: 300,
              rotation: 0,
              opacity: 1,
              borderRadius: 0,
            ),
          ],
        ),
      ],
    );
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: TemplateScreen(draft: template, fontResolver: testFontResolver),
      ),
    );
    await tester.pumpAndSettle();

    final slot = find.byWidgetPredicate(
      (w) => w is Container && w.color == const Color(0xFFE4E4E7),
    );
    // Select it (tapping the placeholder below the pick icon). Selecting is
    // not an edit, so there is still nothing to undo.
    await tester.tapAt(tester.getCenter(slot) + const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(enabled(tester, undoButton), isFalse);

    // Sweep from empty canvas space — the canvas-wide surface moves the
    // selected element. Every one of these moves is its own _dragSelected
    // call; the whole run must collapse into ONE undo step, not twelve.
    final before = tester.getCenter(slot);
    final canvasRect = tester.getRect(
      find.byKey(const ValueKey('slide-background-0')),
    );
    final gesture = await tester.startGesture(
      canvasRect.topLeft + const Offset(60, 60),
    );
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(4, 4));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getCenter(slot), isNot(before));

    await tester.tap(undoButton);
    await tester.pumpAndSettle();
    expect(tester.getCenter(slot), before);
    // Nothing left: one undo took back the entire gesture.
    expect(enabled(tester, undoButton), isFalse);
  });

  testWidgets('a new edit clears the redo branch', (tester) async {
    await pumpDraft(tester);
    await addFromToolbar(tester, 'Panel');
    await tester.tap(undoButton);
    await tester.pumpAndSettle();
    expect(enabled(tester, redoButton), isTrue);

    await addFromToolbar(tester, 'Text');
    expect(enabled(tester, redoButton), isFalse);
  });

  testWidgets('undo clears a selection whose element no longer exists', (
    tester,
  ) async {
    await pumpDraft(tester);
    await addFromToolbar(tester, 'Layout');
    await tester.tap(find.text('2 × 2'));
    await tester.pumpAndSettle();
    // First cell selected → grid styling bar (two sliders) is up.
    expect(find.byType(Slider), findsNWidgets(2));

    await tester.tap(undoButton);
    await tester.pumpAndSettle();

    // Grid gone AND selection cleared — the bottom strip is back to the
    // toolbar, not a stale grid bar.
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsNothing);
    expect(find.byType(Slider), findsNothing);
  });
}
