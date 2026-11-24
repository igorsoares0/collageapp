import 'package:collageapp/src/model/photo_slots.dart';
import 'package:collageapp/src/model/template.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

ImageLayer _image(String slot, double x, double y, {bool hidden = false}) =>
    ImageLayer(
      id: 'l_$slot',
      hidden: hidden,
      slotId: slot,
      x: x,
      y: y,
      width: 200,
      height: 200,
      rotation: 0,
      opacity: 1,
      borderRadius: 0,
    );

TextLayer _text(String slot, double x, double y, Color color) => TextLayer(
  id: 'l_$slot',
  hidden: false,
  slotId: slot,
  x: x,
  y: y,
  width: 100,
  fontFamily: 'Inter',
  fontSize: 40,
  fontWeight: 400,
  color: color,
  alignment: 'left',
);

Document _doc(List<Layer> layers, {int slides = 2}) => Document(
  id: 'd',
  schemaVersion: 4,
  version: 1,
  name: 'd',
  aspectRatio: '4:5',
  slideWidth: 1080,
  slideHeight: 1350,
  slideCount: slides,
  gutter: 0,
  slideBackgrounds: const [],
  layers: layers,
);

void main() {
  test(
    'fill order is slide by slide, then top to bottom, then left to right',
    () {
      final doc = _doc([
        _image('s2_top', 1200, 100), // slide 2
        _image('s1_bottom', 100, 900),
        _image('s1_right', 700, 100),
        _image('s1_left', 100, 105), // same row as s1_right, within tolerance
      ]);
      expect(
        [for (final s in imageSlotsInFillOrder(doc)) s.slotId],
        ['s1_left', 's1_right', 's1_bottom', 's2_top'],
      );
      expect(fillNumbers(doc), {
        's1_left': 1,
        's1_right': 2,
        's1_bottom': 3,
        's2_top': 4,
      });
    },
  );

  test('grid cells count individually, in reading order', () {
    final doc = _doc([
      const GridLayer(
        id: 'g',
        hidden: false,
        x: 0,
        y: 0,
        width: 1000,
        height: 1000,
        rotation: 0,
        cols: 2,
        rows: 2,
        colFractions: [],
        rowFractions: [],
        gutter: 0,
        cornerRadius: 0,
        gutterColor: null,
        cells: [
          GridCell(slotId: 'br', col: 1, row: 1),
          GridCell(slotId: 'tl', col: 0, row: 0),
          GridCell(slotId: 'bl', col: 0, row: 1),
          GridCell(slotId: 'tr', col: 1, row: 0),
        ],
      ),
    ], slides: 1);
    expect(
      [for (final s in imageSlotsInFillOrder(doc)) s.slotId],
      ['tl', 'tr', 'bl', 'br'],
    );
  });

  test('hidden layers and text are not photo slots', () {
    final doc = _doc([
      _image('shown', 0, 0),
      _image('hidden', 300, 0, hidden: true),
      _text('title', 0, 600, const Color(0xFF000000)),
    ]);
    expect([for (final s in imageSlotsInFillOrder(doc)) s.slotId], ['shown']);
  });

  test('light text over a slot marks it for the dark placeholder', () {
    final doc = _doc([
      _image('under_white', 0, 0),
      _image('under_black', 600, 0),
      _image('bare', 0, 800),
      _text('white', 20, 40, const Color(0xFFFFFFFF)),
      _text('black', 620, 40, const Color(0xFF111111)),
    ]);
    expect(slotsUnderLightText(doc), {'under_white'});
  });
}
