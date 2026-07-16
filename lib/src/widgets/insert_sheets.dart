import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/asset_record.dart';
import '../model/template.dart';
import '../rendering/frame_assets.dart';
import '../theme.dart';

const Color _cellFill = AppColors.surfaceBright;

/// A grid layout the user can insert from scratch. Mirrors the classic preset
/// catalog of the web editor (lib/template/factory.ts): fraction tracks start
/// uniform; the user reshapes them by dragging dividers afterwards.
class GridPreset {
  final String label;
  final int cols, rows;

  /// (col, row, colSpan, rowSpan) per cell.
  final List<(int, int, int, int)> cells;

  const GridPreset(this.label, this.cols, this.rows, this.cells);
}

const List<GridPreset> kGridPresets = [
  GridPreset('2 columns', 2, 1, [(0, 0, 1, 1), (1, 0, 1, 1)]),
  GridPreset('2 rows', 1, 2, [(0, 0, 1, 1), (0, 1, 1, 1)]),
  GridPreset('3 rows', 1, 3, [(0, 0, 1, 1), (0, 1, 1, 1), (0, 2, 1, 1)]),
  GridPreset('1 + 2', 2, 2, [(0, 0, 1, 2), (1, 0, 1, 1), (1, 1, 1, 1)]),
  GridPreset('2 + 1', 2, 2, [(0, 0, 1, 1), (0, 1, 1, 1), (1, 0, 1, 2)]),
  GridPreset('2 × 2', 2, 2, [
    (0, 0, 1, 1),
    (1, 0, 1, 1),
    (0, 1, 1, 1),
    (1, 1, 1, 1),
  ]),
  GridPreset('1 + 3', 2, 3, [
    (0, 0, 1, 3),
    (1, 0, 1, 1),
    (1, 1, 1, 1),
    (1, 2, 1, 1),
  ]),
  GridPreset('2 + 3', 6, 2, [
    (0, 0, 3, 1),
    (3, 0, 3, 1),
    (0, 1, 2, 1),
    (2, 1, 2, 1),
    (4, 1, 2, 1),
  ]),
  GridPreset('1 + 4', 2, 4, [
    (0, 0, 1, 4),
    (1, 0, 1, 1),
    (1, 1, 1, 1),
    (1, 2, 1, 1),
    (1, 3, 1, 1),
  ]),
  GridPreset('2 × 3', 2, 3, [
    (0, 0, 1, 1),
    (1, 0, 1, 1),
    (0, 1, 1, 1),
    (1, 1, 1, 1),
    (0, 2, 1, 1),
    (1, 2, 1, 1),
  ]),
  GridPreset('3 + 3', 3, 2, [
    (0, 0, 1, 1),
    (1, 0, 1, 1),
    (2, 0, 1, 1),
    (0, 1, 1, 1),
    (1, 1, 1, 1),
    (2, 1, 1, 1),
  ]),
  GridPreset('3 × 3', 3, 3, [
    (0, 0, 1, 1),
    (1, 0, 1, 1),
    (2, 0, 1, 1),
    (0, 1, 1, 1),
    (1, 1, 1, 1),
    (2, 1, 1, 1),
    (0, 2, 1, 1),
    (1, 2, 1, 1),
    (2, 2, 1, 1),
  ]),
];

/// A near-square uniform grid for [count] photos — the fallback when no
/// curated preset matches that count exactly.
GridPreset autoGridPreset(int count) {
  final cols = math.sqrt(count).ceil();
  return GridPreset('Grid', cols, (count + cols - 1) ~/ cols, [
    for (var i = 0; i < count; i++) (i % cols, i ~/ cols, 1, 1),
  ]);
}

/// The layouts suggested for exactly [count] photos: every curated preset
/// with that many cells, or the auto grid when none matches.
List<GridPreset> layoutPresetsFor(int count) {
  final exact = [
    for (final p in kGridPresets)
      if (p.cells.length == count) p,
  ];
  return exact.isEmpty ? [autoGridPreset(count)] : exact;
}

/// Bottom sheet of grid layouts; resolves to the chosen preset or null.
Future<GridPreset?> showGridPresetSheet(BuildContext context) {
  return showModalBottomSheet<GridPreset>(
    context: context,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Grid layout',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final preset in kGridPresets)
                  InkWell(
                    onTap: () => Navigator.pop(sheetContext, preset),
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CustomPaint(
                          size: const Size(64, 64),
                          painter: _GridThumbPainter(preset),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          preset.label,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Bottom sheet of layout suggestions for the photos the user just picked:
/// every preset matching that photo count, drawn as a miniature of the real
/// collage — the photos cover-fitted into the cells with the same [cellRect]
/// math the canvas uses. Resolves to the chosen preset or null.
Future<GridPreset?> showLayoutPickerSheet(
  BuildContext context, {
  required List<ImageProvider> photos,
  required double canvasAspect,
}) {
  final presets = layoutPresetsFor(photos.length);
  return showModalBottomSheet<GridPreset>(
    context: context,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose a layout',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${photos.length} photos',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 176,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final preset in presets)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: InkWell(
                        onTap: () => Navigator.pop(sheetContext, preset),
                        borderRadius: BorderRadius.circular(8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 150,
                              child: AspectRatio(
                                aspectRatio: canvasAspect,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: _FilledLayoutThumb(
                                    preset: preset,
                                    photos: photos,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              preset.label,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A preset miniature with the picked photos inside its cells (cover-fitted,
/// in pick order — exactly how the inserted grid will look).
class _FilledLayoutThumb extends StatelessWidget {
  final GridPreset preset;
  final List<ImageProvider> photos;

  const _FilledLayoutThumb({required this.preset, required this.photos});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final grid = GridLayer(
          id: 'preview',
          hidden: false,
          x: 0,
          y: 0,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          rotation: 0,
          cols: preset.cols,
          rows: preset.rows,
          colFractions: List.filled(preset.cols, 1),
          rowFractions: List.filled(preset.rows, 1),
          gutter: 3,
          cornerRadius: 0,
          gutterColor: null,
          cells: [
            for (final (i, c) in preset.cells.indexed)
              GridCell(
                slotId: 'c$i',
                col: c.$1,
                row: c.$2,
                colSpan: c.$3,
                rowSpan: c.$4,
              ),
          ],
        );
        return Stack(
          children: [
            for (final (i, cell) in grid.cells.indexed)
              Positioned.fromRect(
                rect: cellRect(grid, cell),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Image(
                    image: photos[i % photos.length],
                    fit: BoxFit.cover,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Paints a preset's cells with the same [cellRect] math the canvas uses, so
/// the thumbnail is a faithful miniature of what gets inserted.
class _GridThumbPainter extends CustomPainter {
  final GridPreset preset;

  const _GridThumbPainter(this.preset);

  @override
  void paint(Canvas canvas, Size size) {
    final grid = GridLayer(
      id: 'preview',
      hidden: false,
      x: 0,
      y: 0,
      width: size.width,
      height: size.height,
      rotation: 0,
      cols: preset.cols,
      rows: preset.rows,
      colFractions: List.filled(preset.cols, 1),
      rowFractions: List.filled(preset.rows, 1),
      gutter: 4,
      cornerRadius: 0,
      gutterColor: null,
      cells: [
        for (final (i, c) in preset.cells.indexed)
          GridCell(
            slotId: 'c$i',
            col: c.$1,
            row: c.$2,
            colSpan: c.$3,
            rowSpan: c.$4,
          ),
      ],
    );
    final paint = Paint()..color = _cellFill;
    for (final cell in grid.cells) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(cellRect(grid, cell), const Radius.circular(3)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GridThumbPainter oldDelegate) =>
      oldDelegate.preset != preset;
}

/// What the asset picker resolved to: a sticker (placed as its own layer) or a
/// frame (placed as an empty framed photo slot that opens the gallery).
class AssetChoice {
  final String id;
  final String name;
  final double aspect;
  final bool isFrame;
  final ImageProvider image;

  const AssetChoice({
    required this.id,
    required this.name,
    required this.aspect,
    required this.isFrame,
    required this.image,
  });
}

/// Bottom sheet of insertable assets: the catalog's stickers plus every frame
/// (bundled seeds and uploaded catalog frames). Resolves to the chosen asset
/// or null.
Future<AssetChoice?> showAssetPickerSheet(
  BuildContext context,
  List<AssetRecord> catalog,
) {
  final stickers = [
    for (final a in catalog)
      if (a.type == 'sticker')
        AssetChoice(
          id: a.id,
          name: a.name,
          aspect: a.aspect,
          isFrame: false,
          image: a.image,
        ),
  ];
  final frames = [
    for (final f in kFrameAssets)
      AssetChoice(
        id: f.id,
        name: f.id.replaceFirst('frame_', '').replaceAll('_', ' '),
        aspect: f.aspect,
        isFrame: true,
        image: AssetImage(f.asset),
      ),
    for (final a in catalog)
      if (a.type == 'frame' && a.window != null)
        AssetChoice(
          id: a.id,
          name: a.name,
          aspect: a.aspect,
          isFrame: true,
          image: a.image,
        ),
  ];
  return showModalBottomSheet<AssetChoice>(
    context: context,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: stickers.isEmpty && frames.isEmpty
            ? const SizedBox(
                height: 120,
                child: Center(
                  child: Text(
                    'No assets available yet.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (stickers.isNotEmpty)
                      _AssetSection(
                        title: 'Stickers',
                        assets: stickers,
                        onPick: (a) => Navigator.pop(sheetContext, a),
                      ),
                    if (frames.isNotEmpty)
                      _AssetSection(
                        title: 'Frames',
                        assets: frames,
                        onPick: (a) => Navigator.pop(sheetContext, a),
                      ),
                  ],
                ),
              ),
      ),
    ),
  );
}

class _AssetSection extends StatelessWidget {
  final String title;
  final List<AssetChoice> assets;
  final void Function(AssetChoice) onPick;

  const _AssetSection({
    required this.title,
    required this.assets,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final asset in assets)
              InkWell(
                onTap: () => onPick(asset),
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: Image(image: asset.image, fit: BoxFit.contain),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 72,
                      child: Text(
                        asset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
