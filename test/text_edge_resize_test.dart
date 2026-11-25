import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/screens/template_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextStyle testFontResolver(String family, TextStyle base) => base;

/// Text selection chrome in the real editor (overlay mode). The Ahem test
/// font makes every glyph a fontSize square: "a b" at 220px is 660 wide on
/// one line, "a" / "b" 220 each. (220px: one line must be tall enough for
/// the side pills to show at all — see _edgePillsFit.)
void main() {
  Template textTemplate(String alignment) => Template(
    id: 't',
    schemaVersion: 3,
    version: 1,
    name: 'T',
    aspectRatio: '9:16',
    canvasWidth: 1080,
    canvasHeight: 1920,
    panels: [
      Panel(
        id: 'p',
        backgroundColor: const Color(0xFFFFFFFF),
        layers: [
          TextLayer(
            id: 'txt',
            hidden: false,
            slotId: 'title',
            x: 90,
            y: 800,
            // Much wider than the phrase: the glyphs hug inside it.
            width: 900,
            fontFamily: 'Roboto',
            fontSize: 220,
            fontWeight: 400,
            color: const Color(0xFF111111),
            alignment: alignment,
          ),
        ],
      ),
    ],
  );

  /// Opens the editor, types [text] into the title slot and leaves it
  /// selected (not editing), so the overlay chrome is up.
  Future<Finder> openWithText(
    WidgetTester tester, {
    String alignment = 'center',
    String text = 'a b',
  }) async {
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: TemplateScreen(
          draft: textTemplate(alignment),
          fontResolver: testFontResolver,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Untouched, the slot shows its id. Tap selects, a second tap edits.
    await tester.tap(find.text('title'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('title'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), text);
    await tester.pumpAndSettle();
    // Leave editing: tap empty canvas (deselects), then select again.
    final bg = tester.getRect(find.byKey(const ValueKey('slide-background-0')));
    await tester.tapAt(bg.topLeft + const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const ValueKey('handle_edge_r')), findsOneWidget);
    return find.text(text);
  }

  // The overlay's pill: the leader-side chrome carries no visuals, so the
  // only keyed pill on screen is the overlay's.
  Finder pill(String side) => find.byKey(ValueKey('handle_edge_$side'));

  testWidgets('the right pill sits on the paragraph edge on EVERY frame of '
      'the drag, and narrowing wraps the phrase onto two lines', (tester) async {
    final paragraph = await openWithText(tester);
    final start = tester.getRect(paragraph);
    final oneLine = start.height;

    // At rest the pill hugs the glyphs, not the 900px model box.
    expect(
      (tester.getCenter(pill('r')).dx - start.right).abs(),
      lessThan(1.0),
    );

    final gesture = await tester.startGesture(tester.getCenter(pill('r')));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(-8, 0));
      // ONE pump: the chrome must already match this frame's paragraph.
      await tester.pump();
      final r = tester.getRect(paragraph);
      expect(
        (tester.getCenter(pill('r')).dx - r.right).abs(),
        lessThan(1.0),
        reason: 'pill trails the text on step $i',
      );
      // The anchored (left) edge never moves.
      expect((r.left - start.left).abs(), lessThan(1.0), reason: 'step $i');
    }
    await gesture.up();
    await tester.pumpAndSettle();

    final end = tester.getRect(paragraph);
    // "a" over "b". A wrapped paragraph's box is the wrap width itself,
    // which followed the finger: 12 × 8 screen px narrower.
    expect(end.height, closeTo(oneLine * 2, 0.5));
    expect(end.width, closeTo(start.width - 96, 1.0));
    expect((end.left - start.left).abs(), lessThan(1.0));
  });

  for (final alignment in ['left', 'right']) {
    testWidgets('$alignment-aligned text: the first touch of the pill does not '
        'move the glyphs', (tester) async {
      final paragraph = await openWithText(tester, alignment: alignment);
      final start = tester.getRect(paragraph);
      final gesture = await tester.startGesture(tester.getCenter(pill('l')));
      await gesture.moveBy(const Offset(4, 0));
      await tester.pump();
      final r = tester.getRect(paragraph);
      // Dragging the LEFT pill anchors the right edge.
      expect((r.right - start.right).abs(), lessThan(1.0));
      expect(
        (tester.getCenter(pill('l')).dx - r.left).abs(),
        lessThan(1.0),
      );
      await gesture.up();
    });
  }

  testWidgets('widening stops at the one-line width', (tester) async {
    final paragraph = await openWithText(tester);
    final start = tester.getRect(paragraph);
    final gesture = await tester.startGesture(tester.getCenter(pill('r')));
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(15, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    final r = tester.getRect(paragraph);
    expect(r.width, closeTo(start.width, 0.5));
    expect(r.height, closeTo(start.height, 0.5));
    expect((r.left - start.left).abs(), lessThan(1.0));
    expect(
      (tester.getCenter(pill('r')).dx - r.right).abs(),
      lessThan(1.0),
    );
  });

  testWidgets('corner resize: the handle stays on the text corner every '
      'frame', (tester) async {
    final paragraph = await openWithText(tester);
    final corner = find.byKey(const ValueKey('handle_br'));
    // The corner dot sits out in the chrome pad; track its offset from the
    // paragraph corner, which must stay constant in SCREEN px (the pad is
    // divided by the scale) — any lag shows as a jump in that offset.
    Offset gap() =>
        tester.getCenter(corner) - tester.getRect(paragraph).bottomRight;
    final restGap = gap();
    final gesture = await tester.startGesture(tester.getCenter(corner));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(6, 6));
      await tester.pump();
      expect(
        (gap() - restGap).distance,
        lessThan(1.0),
        reason: 'corner handle trails the text on step $i',
      );
    }
    await gesture.up();
  });
}
