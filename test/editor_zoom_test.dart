import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/rendering/template_canvas.dart';
import 'package:collageapp/src/screens/template_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// How far out the editor can pinch. On a continuous canvas zooming out is the
/// only way to see a whole carousel at once, so the floor must follow the
/// document — a constant caps a long panorama at a handful of visible slides.

TextStyle testFontResolver(String family, TextStyle base) => base;

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

  double minScale(WidgetTester tester) =>
      tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).minScale;

  testWidgets('a single slide gets the declared 0.25 floor', (tester) async {
    await pumpDraft(tester);
    expect(minScale(tester), 0.25);
  });

  testWidgets('THE POINT: a longer document zooms out further', (tester) async {
    await pumpDraft(tester);
    final one = minScale(tester);

    for (var i = 0; i < 9; i++) {
      await addSlide(tester);
    }
    final ten = minScale(tester);

    expect(
      ten,
      lessThan(one),
      reason: 'a document too long for the default floor must reach further',
    );
    // The whole strip has to actually FIT: at minScale the scaled content is
    // no wider than the viewport, which is the entire point of the floor.
    final width = tester.getSize(find.byType(InteractiveViewer)).width;
    expect(tester.getSize(find.byType(CanvasView)).width * ten, lessThan(width));
  });

  /// The regression that motivated all of this: InteractiveViewer floors the
  /// scale at `viewport / boundaryRect` BEFORE consulting minScale, so a small
  /// finite boundaryMargin silently pinned the editor near 1x however low
  /// minScale was set. Asserting the FIELD passes while the app cannot zoom;
  /// only an actual pinch catches it.
  testWidgets('THE REGRESSION: a real pinch reaches the floor', (tester) async {
    await pumpDraft(tester);
    final floor = minScale(tester);

    final viewer = find.byType(InteractiveViewer);
    final center = tester.getCenter(viewer);
    // Pinch inward, hard and repeatedly, so the gesture is never what limits us.
    for (var i = 0; i < 6; i++) {
      final g1 = await tester.startGesture(center - const Offset(300, 0));
      final g2 = await tester.startGesture(center + const Offset(300, 0));
      for (var step = 0; step < 12; step++) {
        await g1.moveBy(const Offset(24, 0));
        await g2.moveBy(const Offset(-24, 0));
        await tester.pump();
      }
      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();
    }

    final scale = tester
        .widget<Transform>(
          find.descendant(of: viewer, matching: find.byType(Transform)).first,
        )
        .transform
        .getMaxScaleOnAxis();
    expect(
      scale,
      lessThan(0.9),
      reason: 'the canvas must actually shrink — not just report a low minScale',
    );
    expect(scale, closeTo(floor, floor * 0.5));
  });

  testWidgets('the floor never goes absurdly low', (tester) async {
    await pumpDraft(tester);
    for (var i = 0; i < 12; i++) {
      await addSlide(tester);
    }
    expect(minScale(tester), greaterThanOrEqualTo(0.08));
  });
}
