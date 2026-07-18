import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/rendering/template_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Carousel bleed: a neighbouring panel's layers paint into this panel as
/// inert ghosts, shifted by one canvas width — see PanelCanvas.panelBefore.
void main() {
  // Panel 1 holds a shape spilling past its right edge (x 1000..1300 on a
  // 1080-wide canvas); panel 2 is empty, so anything it shows is bleed.
  Template twoPanels() => Template.fromJson({
    'id': 'carousel',
    'schemaVersion': 2,
    'version': 1,
    'name': 'Carousel',
    'aspectRatio': 'story',
    'canvas': {'width': 1080, 'height': 1920},
    'panels': [
      {
        'id': 'p1',
        'backgroundColor': '#FFFFFF',
        'layers': [
          {
            'type': 'shape',
            'id': 'spill',
            'x': 1000,
            'y': 100,
            'width': 300,
            'height': 100,
            'fill': '#FF0066',
          },
        ],
      },
      {'id': 'p2', 'backgroundColor': '#FFFFFF', 'layers': <dynamic>[]},
    ],
  });

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 270, height: 480, child: child)),
    ),
  );

  Finder spillShape() => find.byWidgetPredicate(
    (w) => w is Container && w.color == const Color(0xFFFF0066),
  );

  testWidgets('the left neighbour\'s spilling layer renders as a ghost', (
    tester,
  ) async {
    final t = twoPanels();
    await tester.pumpWidget(
      host(
        PanelCanvas(
          panel: t.panels[1],
          panelBefore: t.panels[0],
          canvasWidth: t.canvasWidth,
          canvasHeight: t.canvasHeight,
        ),
      ),
    );
    expect(spillShape(), findsOneWidget);
    // Inert: the bleed lives under an IgnorePointer, so it can never win a
    // gesture over the panel's own content.
    expect(
      find.ancestor(of: spillShape(), matching: find.byType(IgnorePointer)),
      findsWidgets,
    );
  });

  testWidgets('no neighbour wired, no ghost', (tester) async {
    final t = twoPanels();
    await tester.pumpWidget(
      host(
        PanelCanvas(
          panel: t.panels[1],
          canvasWidth: t.canvasWidth,
          canvasHeight: t.canvasHeight,
        ),
      ),
    );
    expect(spillShape(), findsNothing);
  });

  testWidgets('TemplateCanvas bleeds the second panel into the first', (
    tester,
  ) async {
    // Mirror of the web thumbnail: the wrapper renders panel 1 with panel 2's
    // spill. Here the spill layer lives on panel 2, poking LEFT (x < 0).
    final t = Template.fromJson({
      'id': 'carousel',
      'schemaVersion': 2,
      'version': 1,
      'name': 'Carousel',
      'aspectRatio': 'story',
      'canvas': {'width': 1080, 'height': 1920},
      'panels': [
        {'id': 'p1', 'backgroundColor': '#FFFFFF', 'layers': <dynamic>[]},
        {
          'id': 'p2',
          'backgroundColor': '#FFFFFF',
          'layers': [
            {
              'type': 'shape',
              'id': 'spill',
              'x': -200,
              'y': 100,
              'width': 300,
              'height': 100,
              'fill': '#FF0066',
            },
          ],
        },
      ],
    });

    await tester.pumpWidget(host(TemplateCanvas(template: t)));
    expect(spillShape(), findsOneWidget);
  });
}
