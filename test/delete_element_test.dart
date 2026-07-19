import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/screens/template_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextStyle testFontResolver(String family, TextStyle base) => base;

/// Deleting elements from the canvas via the ✕ handle floated above the
/// selected element: user-added layers are removed outright; template layers
/// get a hidden override (the template itself is immutable). Both are one
/// undo step.
void main() {
  Future<void> pumpEditor(WidgetTester tester, Template draft) async {
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: TemplateScreen(draft: draft, fontResolver: testFontResolver),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Taps a bottom-toolbar button by its label (Text, Layout, Panel, ...).
  Future<void> addFromToolbar(WidgetTester tester, String item) async {
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  final deleteHandle = find.byKey(const ValueKey('handle_delete'));

  // The handle visual sits under IgnorePointer by design — the tap lands on
  // the gesture surface beneath it — so the "would not hit test" warning is
  // expected noise.
  Future<void> tapDelete(WidgetTester tester) async {
    await tester.tap(deleteHandle, warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  testWidgets('the ✕ handle removes a user-added element (undoable)', (
    tester,
  ) async {
    await pumpEditor(tester, Template.blank());
    await addFromToolbar(tester, 'Text');
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();

    // Leave inline editing (tap the empty canvas corner), then re-select the
    // text with a single tap — selected but not editing, so the overlay
    // chrome (and its delete handle) mounts.
    final canvas = find.byKey(const ValueKey('slide-background-0'));
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(8, 8));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hello'));
    await tester.pumpAndSettle();
    expect(deleteHandle, findsOneWidget);

    await tapDelete(tester);
    expect(find.text('Hello'), findsNothing);
    expect(deleteHandle, findsNothing);

    // One undo step brings the element (and its text) back.
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets('the ✕ handle on a template element hides it instead', (
    tester,
  ) async {
    final template = Template.fromJson({
      'id': 't_del',
      'version': 1,
      'name': 'delete test',
      'aspectRatio': '9:16',
      'canvas': {'width': 1080, 'height': 1920},
      'layers': [
        {
          'id': 'img1',
          'type': 'image',
          'slotId': 'slot_1',
          'x': 340,
          'y': 660,
          'width': 400,
          'height': 400,
        },
      ],
    });
    await pumpEditor(tester, template);
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsOneWidget);

    // Tap inside the slot but away from its centered pick icon (which would
    // open the gallery): the slot spans template x 340..740, y 660..1060.
    final canvas = tester.getRect(
      find.byKey(const ValueKey('slide-background-0')),
    );
    await tester.tapAt(
      canvas.topLeft +
          Offset(canvas.width * (360 / 1080), canvas.height * (690 / 1920)),
    );
    await tester.pumpAndSettle();
    expect(deleteHandle, findsOneWidget);

    await tapDelete(tester);
    // Hidden, not gone from the template: the canvas no longer renders it.
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsNothing);

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsOneWidget);
  });

  testWidgets('the ✕ handle on a grid cell deletes the whole grid', (
    tester,
  ) async {
    await pumpEditor(tester, Template.blank());
    await addFromToolbar(tester, 'Layout');
    await tester.tap(find.text('2 × 2'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsNWidgets(4));
    expect(deleteHandle, findsOneWidget);

    await tapDelete(tester);
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsNothing);
  });
}
