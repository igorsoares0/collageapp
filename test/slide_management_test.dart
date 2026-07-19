import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/screens/template_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Slide management from the editor: long-press a carousel dot to reorder or
/// delete that slide (Modelo B, F4 slide-aware layer).
///
/// The behaviour that matters is that a slide moves WITH its content — that is
/// what makes "independent pages" feel native on a continuous canvas.

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

  Future<void> tapToolbar(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> openSlideActions(WidgetTester tester, int index) async {
    await tester.longPress(find.byKey(ValueKey('panel-dot-$index')));
    await tester.pumpAndSettle();
  }

  Finder slide(int i) => find.byKey(ValueKey('slide-background-$i'));

  testWidgets('a single-slide document offers no slide actions', (
    tester,
  ) async {
    await pumpDraft(tester);
    // With one slide there are no dots at all, so nothing to long-press.
    expect(find.byKey(const ValueKey('panel-dot-0')), findsNothing);
  });

  testWidgets('long-pressing a dot offers reorder and delete', (tester) async {
    await pumpDraft(tester);
    await tapToolbar(tester, 'Panel');
    expect(slide(1), findsOneWidget);

    await openSlideActions(tester, 0);
    // First slide: can move right, not left.
    expect(find.byKey(const ValueKey('slide-move-left')), findsNothing);
    expect(find.byKey(const ValueKey('slide-move-right')), findsOneWidget);
    expect(find.byKey(const ValueKey('slide-delete')), findsOneWidget);
  });

  testWidgets('deleting a slide removes it', (tester) async {
    await pumpDraft(tester);
    await tapToolbar(tester, 'Panel');
    expect(slide(1), findsOneWidget);

    await openSlideActions(tester, 1);
    await tester.tap(find.byKey(const ValueKey('slide-delete')));
    await tester.pumpAndSettle();

    expect(slide(1), findsNothing);
    expect(slide(0), findsOneWidget);
  });

  testWidgets('a deleted slide comes back with undo', (tester) async {
    await pumpDraft(tester);
    await tapToolbar(tester, 'Panel');
    await openSlideActions(tester, 1);
    await tester.tap(find.byKey(const ValueKey('slide-delete')));
    await tester.pumpAndSettle();
    expect(slide(1), findsNothing);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.undo));
    await tester.pumpAndSettle();
    expect(
      slide(1),
      findsOneWidget,
      reason: 'undo must restore document STRUCTURE, not just overrides',
    );
  });

  testWidgets('THE POINT: reordering carries the slide\'s content with it', (
    tester,
  ) async {
    await pumpDraft(tester);
    // Second slide first (adding one focuses it), THEN the text — so the text
    // lands on slide 1 and the toolbar is never needed again.
    await tapToolbar(tester, 'Panel');
    await tapToolbar(tester, 'Text');
    await tester.enterText(find.byType(TextField), 'SecondSlide');
    await tester.pumpAndSettle();

    final beforeX = tester.getCenter(find.text('SecondSlide')).dx;

    // Move slide 1 to the left: its text must travel with it.
    await openSlideActions(tester, 1);
    await tester.tap(find.byKey(const ValueKey('slide-move-left')));
    await tester.pumpAndSettle();

    expect(
      find.text('SecondSlide'),
      findsOneWidget,
      reason: 'the element must survive the reorder',
    );
    expect(
      tester.getCenter(find.text('SecondSlide')).dx,
      lessThan(beforeX),
      reason: 'the content moved left along with its slide',
    );
  });
}
