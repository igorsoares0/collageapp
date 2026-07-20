import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/rendering/template_canvas.dart';
import 'package:collageapp/src/screens/template_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fresh document must open CENTERED in the editor.
///
/// The strip is laid out `constrained: false`, which aligns the child TOP-LEFT
/// — so centering is not something the viewer does, it has to come out of the
/// strip's own padding. Whenever the canvas is narrower than the viewport it
/// hugs the left edge, and that only happens when the canvas is limited by
/// HEIGHT rather than width: a 9:16 story on a tall phone. Portrait and square
/// fill the width and hide the bug, which is why it kept coming back.

TextStyle testFontResolver(String family, TextStyle base) => base;

void main() {
  /// [size] is the whole screen; the editor viewport is whatever is left after
  /// the app bar and the bottom toolbar.
  Future<void> pumpBlank(
    WidgetTester tester, {
    required double width,
    required double height,
    required Size screen,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: TemplateScreen(
          draft: Template.blank(canvasWidth: width, canvasHeight: height),
          fontResolver: testFontResolver,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// How far the canvas's centre sits from the viewport's, horizontally.
  double offCentre(WidgetTester tester) {
    final viewport = tester.getRect(find.byType(InteractiveViewer));
    final canvas = tester.getRect(find.byType(CanvasView));
    return canvas.center.dx - viewport.center.dx;
  }

  testWidgets('THE BUG: a fresh 9:16 story opens centred, not hugging the left',
      (tester) async {
    // Tall and narrow: the canvas is height-limited here, so the strip does
    // NOT fill the viewport and top-left alignment becomes visible.
    await pumpBlank(
      tester,
      width: 1080,
      height: 1920,
      screen: const Size(1200, 2000),
    );
    expect(
      offCentre(tester),
      closeTo(0, 1.0),
      reason: 'a story canvas narrower than the viewport must be centred; '
          'a positive gap here means it is pinned to the left padding',
    );
  });

  testWidgets('the other canvas sizes stay centred too', (tester) async {
    for (final (w, h) in const [(1080.0, 1350.0), (1080.0, 1080.0)]) {
      await pumpBlank(
        tester,
        width: w,
        height: h,
        screen: const Size(1200, 2000),
      );
      expect(offCentre(tester), closeTo(0, 1.0), reason: '${w}x$h');
    }
  });

  testWidgets('a carousel too wide to fit still starts at the left', (
    tester,
  ) async {
    await pumpBlank(
      tester,
      width: 1080,
      height: 1920,
      screen: const Size(1200, 2000),
    );
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Panel'));
      await tester.pumpAndSettle();
    }

    // Centring is for documents that FIT. Once the strip overflows, slide 0
    // must sit at the strip padding so the carousel reads left-to-right and
    // `_focusPanelAt`'s translations stay meaningful.
    final viewport = tester.getRect(find.byType(InteractiveViewer));
    final first =
        tester.getTopLeft(find.byKey(const ValueKey('slide-background-0'))).dx;
    expect(first - viewport.left, closeTo(16.0, 1.0));
  });
}
