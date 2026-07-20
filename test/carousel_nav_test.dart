import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/screens/template_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tapping a carousel dot must bring THAT slide into view. The translation is
/// computed by hand in `_focusPanelAt`, mirroring the strip's layout — so it
/// silently rots whenever the strip changes, which is exactly what happened
/// when the Row of PanelCanvas became one continuous CanvasView.

TextStyle testFontResolver(String family, TextStyle base) => base;

/// The strip's own horizontal padding: a focused slide sits flush against it.
const _stripPadding = 16.0;

void main() {
  Future<void> pumpDraft(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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

  Future<void> addSlide(WidgetTester tester) async {
    await tester.tap(find.text('Panel'));
    await tester.pumpAndSettle();
  }

  Future<void> tapDot(WidgetTester tester, int i) async {
    await tester.tap(find.byKey(ValueKey('panel-dot-$i')));
    await tester.pumpAndSettle();
  }

  double slideLeft(WidgetTester tester, int i) =>
      tester.getTopLeft(find.byKey(ValueKey('slide-background-$i'))).dx;

  testWidgets('THE POINT: each dot lands its own slide, with no drift', (
    tester,
  ) async {
    await pumpDraft(tester);
    for (var i = 0; i < 3; i++) {
      await addSlide(tester);
    }

    // The last dot deliberately clamps at the document's end, so it is not
    // expected to sit flush — the drift shows up well before it anyway.
    for (final dot in [0, 1, 2]) {
      await tapDot(tester, dot);
      expect(
        slideLeft(tester, dot),
        closeTo(_stripPadding, 1.0),
        reason:
            'dot $dot must place slide $dot flush against the strip padding; '
            'a per-index error compounds and is only obvious on later dots',
      );
    }
  });

  testWidgets('the last dot stops at the document end, never past it', (
    tester,
  ) async {
    await pumpDraft(tester);
    for (var i = 0; i < 3; i++) {
      await addSlide(tester);
    }
    await tapDot(tester, 3);

    final viewportWidth = tester.getSize(find.byType(InteractiveViewer)).width;
    final right =
        tester.getTopRight(find.byKey(const ValueKey('slide-background-3'))).dx;
    expect(
      right,
      greaterThanOrEqualTo(viewportWidth - _stripPadding - 1.0),
      reason: 'scrolling past the end would leave dead space after the canvas',
    );
  });
}
