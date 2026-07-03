import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../api/template_store.dart';
import '../model/asset_record.dart';
import '../model/slot_content.dart';
import '../model/template.dart';
import '../rendering/export.dart';
import '../rendering/snap.dart';
import '../rendering/template_canvas.dart';
import '../widgets/grid_style_bar.dart';
import '../widgets/insert_sheets.dart';
import '../widgets/layers_sheet.dart';
import '../widgets/text_style_bar.dart';

/// Renders one template and lets the user fill its slots (spec §12),
/// editing directly on the canvas: tap selects, tap again edits text
/// inline or opens the gallery picker for images. The result exports as
/// a full-resolution PNG through the share sheet.
///
/// Two entry points: a published template by [id] (fetched through the
/// store), or a local [draft] — the create-from-scratch flow hands in
/// [Template.blank] and the user builds everything with the add menu
/// (text, images, grids, assets, panels).
class TemplateScreen extends StatefulWidget {
  final String? id;
  final Template? draft;

  /// Injectable for tests (google_fonts needs network/assets); the app uses
  /// the default runtime-fetching resolver.
  final FontResolver fontResolver;

  const TemplateScreen({
    super.key,
    this.id,
    this.draft,
    this.fontResolver = googleFontsResolver,
  }) : assert(
         (id == null) != (draft == null),
         'Pass exactly one of id or draft',
       );

  @override
  State<TemplateScreen> createState() => _TemplateScreenState();
}

/// Fixed height of the bottom styling-bar strip (content only; the safe-area
/// inset is added at build time). Sized to the TALLEST bar (the text styling
/// bar) and reserved in EVERY state, so the canvas area — and thus the canvas
/// size — never changes when a different bar shows or a slot is selected.
const double _kBottomBarHeight = 164;

class _TemplateScreenState extends State<TemplateScreen> {
  final _store = TemplateStore();
  final _picker = ImagePicker();
  // One RepaintBoundary key per panel, so each carousel slide exports to its
  // own PNG. Reused across rebuilds (keyed by panel id).
  final Map<String, GlobalKey> _panelKeys = {};
  // Pan/zoom of the editing surface. Pinch zooms only when nothing is selected
  // (a selected slot's pinch resizes the slot instead); the zoom persists
  // across selection, and slot gestures keep working because hit testing maps
  // through this transform.
  final TransformationController _zoom = TransformationController();
  // True once zoomed past 1x. At 1x panning is locked to horizontal (browse
  // panels without drifting up/down); when zoomed in, panning goes free so you
  // can reach every corner of the magnified panel.
  bool _isZoomed = false;
  late Future<Template> _template;
  // Remote frame/sticker catalog; empty until loaded (seeds still resolve).
  List<AssetRecord> _catalog = const [];
  SlotContent _content = const SlotContent();
  String? _selectedSlot;
  String? _editingSlot;
  // Panel the styling bars act on (last one the user touched).
  String? _focusedPanelId;
  bool _exporting = false;
  // Screen-space selection overlay (CanvasSelectionOverlay): the leader link
  // the selected element's chrome box publishes inside its PanelCanvas, and
  // that box's measured size keyed by the gesture target id — the size lands
  // one frame after selection (post-layout), and keying it prevents a frame
  // of wrong-sized chrome when the selection jumps between elements.
  final LayerLink _selectionLink = LayerLink();
  (String, Size)? _selectionBox;

  // Undo/redo: snapshots of [_content] — it is immutable copy-on-write, so a
  // snapshot is a cheap shared reference and restoring one can't leak partial
  // state. Selection/zoom are deliberately NOT part of history; only content.
  final List<SlotContent> _undoStack = [];
  final List<SlotContent> _redoStack = [];

  /// Coalescing state: continuous interactions (drag, pinch, twist, sliders,
  /// typing) stream one edit per frame, and all edits sharing a key merge
  /// into ONE undo step while the interaction lasts. A run breaks on any
  /// pointer-up over the canvas area (end of gesture — see the Listener in
  /// [_buildBody]), on an edit with a different key, or after [_kEditRunWindow]
  /// without edits (typing gets checkpoints from its pauses, since the
  /// keyboard produces no canvas pointer events).
  String? _editRunKey;
  DateTime _editRunAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const int _kMaxHistory = 100;
  static const Duration _kEditRunWindow = Duration(seconds: 2);

  // Alignment guides (smart guides): while an element is dragged, its RAW
  // (unsnapped) offset accumulates here and the STORED offset snaps to nearby
  // guides — keeping the raw value outside the stored state is what lets the
  // element escape a guide instead of sticking to it forever. Cleared on
  // pointer-up alongside the undo coalescing run.
  Offset? _dragRaw;
  String? _dragKey;
  List<double> _guideXs = const [];
  List<double> _guideYs = const [];

  /// Snap reach in SCREEN px, converted to template units per gesture so the
  /// magnetic feel is the same at any zoom level.
  static const double _kSnapReachPx = 8.0;

  /// Records the current content as an undo step for the edit about to be
  /// applied. [coalesce] marks the edit as part of a continuous interaction;
  /// discrete actions (add/remove/reorder/style taps) pass null and always
  /// get their own step. Any new edit invalidates the redo branch.
  void _record([String? coalesce]) {
    final now = DateTime.now();
    final continuesRun =
        coalesce != null &&
        coalesce == _editRunKey &&
        now.difference(_editRunAt) <= _kEditRunWindow;
    if (!continuesRun) {
      _undoStack.add(_content);
      if (_undoStack.length > _kMaxHistory) _undoStack.removeAt(0);
    }
    _redoStack.clear();
    _editRunKey = coalesce;
    _editRunAt = now;
  }

  /// Applies a content edit with undo recording — for callbacks whose only
  /// state change is [_content]. Sites that also touch selection/focus call
  /// [_record] themselves before their own setState.
  void _edit(SlotContent next, {String? coalesce}) {
    _record(coalesce);
    setState(() => _content = next);
  }

  void _undoEdit(Template template) {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_content);
    _restore(template, _undoStack.removeLast());
  }

  void _redoEdit(Template template) {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_content);
    _restore(template, _redoStack.removeLast());
  }

  void _restore(Template template, SlotContent snapshot) {
    _editRunKey = null;
    _dragRaw = null;
    _dragKey = null;
    setState(() {
      _content = snapshot;
      _guideXs = const [];
      _guideYs = const [];
      // Inline editing can't survive a content swap (the field's controller
      // would show stale text); selection stays unless its element is gone.
      _editingSlot = null;
      if (_selectedSlot != null && _selectionTarget(template) == null) {
        _selectedSlot = null;
      }
    });
  }

  /// End of any touch interaction: breaks the undo coalescing run (the next
  /// same-key edit starts a new step) and drops the drag/guide state.
  void _onPointerEnd() {
    _editRunKey = null;
    if (_dragRaw == null && _guideXs.isEmpty && _guideYs.isEmpty) return;
    setState(() {
      _dragRaw = null;
      _dragKey = null;
      _guideXs = const [];
      _guideYs = const [];
    });
  }

  /// Moves element [slotId] by [delta] (template units) with magnetic
  /// alignment guides: the raw offset accumulates per gesture and the stored
  /// offset snaps to canvas/element guides (see snap.dart). Falls back to a
  /// plain move when the element's painted box can't be derived (template-
  /// rotated elements, unmeasured text).
  void _dragSelected(Template template, String slotId, Offset delta) {
    final raw =
        ((_dragKey == slotId ? _dragRaw : null) ?? _content.offsetFor(slotId)) +
        delta;
    var snapped = raw;
    List<double> xs = const [], ys = const [];
    final box = _dragTargetBox(template, slotId);
    if (box != null) {
      final result = snapDrag(
        box: box,
        scale: _content.scaleFor(slotId),
        raw: raw,
        canvas: Size(template.canvasWidth, template.canvasHeight),
        others: _snapTargets(template, slotId),
        threshold: _kSnapReachPx * _screenToTemplate(template),
        snapEdges: _content.rotationFor(slotId) == 0,
      );
      snapped = result.offset;
      xs = result.guideXs;
      ys = result.guideYs;
    }
    _record('drag:$slotId');
    setState(() {
      _dragKey = slotId;
      _dragRaw = raw;
      _guideXs = xs;
      _guideYs = ys;
      _content = _content.withOffset(slotId, snapped);
    });
  }

  /// The unrotated layout box (template units, before user offset/scale) of
  /// the element gesture key [key] drags, or null when it can't be derived.
  /// A template rotation disqualifies the element: it pivots on the top-left,
  /// so neither the axis-aligned edges NOR the center match the painted
  /// element. (A user rotation is fine — it pivots on the center, which is
  /// exactly what center guides track.) Text height isn't in the model; it
  /// comes from the measured selection box.
  Rect? _dragTargetBox(Template template, String key) {
    for (final layer in _allLayers(template)) {
      switch (layer) {
        case ImageLayer l when l.slotId == key:
          if (l.rotation != 0) return null;
          return Rect.fromLTWH(l.x, l.y, l.width, l.height);
        case TextLayer l when l.slotId == key:
          final box = _selectionBox;
          if (box == null || box.$1 != key) return null;
          final h = box.$2.height - 2 * kChromePad / _content.scaleFor(key);
          if (h <= 0) return null;
          return Rect.fromLTWH(l.x, l.y, l.width, h);
        case StickerLayer l when l.id == key:
          return Rect.fromLTWH(l.x, l.y, l.width, l.height);
        case GridLayer l when l.id == key:
          if (l.rotation != 0) return null;
          return Rect.fromLTWH(l.x, l.y, l.width, l.height);
        default:
      }
    }
    return null;
  }

  /// Painted bounds of the focused panel's other elements — the element snap
  /// targets. Rotated elements and text (unmeasurable height) are skipped;
  /// hidden ones too. Shapes are template decoration with no user overrides,
  /// so their model box IS their painted box.
  List<Rect> _snapTargets(Template template, String movingKey) {
    final panel = _effectivePanel(_focusedPanel(template));
    final targets = <Rect>[];
    for (final layer in panel.layers) {
      if (_content.layerHidden(layer.id, layer.hidden)) continue;
      final (String? key, Rect? box) = switch (layer) {
        ImageLayer l when l.rotation == 0 => (
          l.slotId,
          Rect.fromLTWH(l.x, l.y, l.width, l.height),
        ),
        StickerLayer l => (l.id, Rect.fromLTWH(l.x, l.y, l.width, l.height)),
        GridLayer l when l.rotation == 0 => (
          l.id,
          Rect.fromLTWH(l.x, l.y, l.width, l.height),
        ),
        ShapeLayer l => (null, Rect.fromLTWH(l.x, l.y, l.width, l.height)),
        _ => (null, null),
      };
      if (box == null || key == movingKey) continue;
      if (key == null) {
        targets.add(box);
        continue;
      }
      if (_content.rotationFor(key) != 0) continue;
      final s = _content.scaleFor(key);
      targets.add(
        Rect.fromCenter(
          center: box.center + _content.offsetFor(key),
          width: box.width * s,
          height: box.height * s,
        ),
      );
    }
    return targets;
  }

  GlobalKey _panelKey(String panelId) =>
      _panelKeys.putIfAbsent(panelId, () => GlobalKey());

  /// Every panel on screen: the template's own plus the user's added ones
  /// (empty panels appended at the end). All panel iteration/lookup goes
  /// through here so added panels behave like template panels everywhere.
  List<Panel> _panels(Template template) => [
    ...template.panels,
    ..._content.addedPanels,
  ];

  /// The panel the styling bars and the add menu act on: the last one the
  /// user touched, falling back to the first.
  Panel _focusedPanel(Template template) {
    final panels = _panels(template);
    final id = _focusedPanelId ?? panels.first.id;
    return panels.firstWhere((p) => p.id == id, orElse: () => panels.first);
  }

  /// The panel with the user's added layers stacked on top — what the canvas,
  /// the layer sheet and the export all render. The template itself is never
  /// touched; added layers live in [_content].
  Panel _effectivePanel(Panel panel) {
    final added = _content.addedLayersFor(panel.id);
    if (added.isEmpty) return panel;
    return Panel(
      id: panel.id,
      backgroundColor: panel.backgroundColor,
      layers: [...panel.layers, ...added],
    );
  }

  /// All layers visible to lookups: the template's plus everything the user
  /// added (slot ids are globally unique, so a flat list is fine).
  List<Layer> _allLayers(Template template) => [
    ...template.layers,
    ..._content.allAddedLayers,
  ];

  /// A slot/layer/panel id not used by the template or anything the user
  /// added, so a new element never collides with an existing slot's overrides.
  String _uniqueToken(String base, Template template) {
    final used = {
      for (final l in _allLayers(template)) l.id,
      ...template.slotIds,
      for (final p in _panels(template)) p.id,
    };
    var n = 1;
    while (used.contains('${base}_$n')) {
      n++;
    }
    return '${base}_$n';
  }

  /// Adds a fresh text element to the focused panel, centered, and drops the
  /// user straight into inline editing so they can type immediately.
  void _addTextLayer(Template template) {
    final panel = _focusedPanel(template);
    final token = _uniqueToken('text', template);
    final bg = _content.backgroundFor(panel.id) ?? panel.backgroundColor;
    // Pick a default ink that reads against the current background.
    final color = bg.computeLuminance() > 0.5
        ? const Color(0xFF111111)
        : const Color(0xFFFAFAFA);
    final width = template.canvasWidth * 0.8;
    final layer = TextLayer(
      id: token,
      hidden: false,
      slotId: token,
      x: (template.canvasWidth - width) / 2,
      y: template.canvasHeight * 0.42,
      width: width,
      fontFamily: 'Inter',
      fontSize: 88,
      fontWeight: 400,
      color: color,
      alignment: 'center',
    );
    _record();
    setState(() {
      _content = _content.withAddedLayer(panel.id, layer);
      _focusedPanelId = panel.id;
      _selectedSlot = token;
      _editingSlot = token;
    });
  }

  /// Adds a fresh image element to the focused panel, centered, and opens the
  /// gallery right away (an empty image element is useless on its own).
  /// [frameAssetId]/[aspect] make it a framed photo slot (polaroid etc.) —
  /// the box follows the frame's aspect so the window isn't distorted.
  void _addImageLayer(
    Template template, {
    String? frameAssetId,
    double aspect = 1,
  }) {
    final panel = _focusedPanel(template);
    final token = _uniqueToken('image', template);
    final width = template.canvasWidth * 0.5;
    final height = width / (aspect <= 0 ? 1 : aspect);
    final layer = ImageLayer(
      id: token,
      hidden: false,
      slotId: token,
      x: (template.canvasWidth - width) / 2,
      y: (template.canvasHeight - height) / 2,
      width: width,
      height: height,
      rotation: 0,
      opacity: 1,
      borderRadius: 0,
      frameAssetId: frameAssetId,
    );
    _record();
    setState(() {
      _content = _content.withAddedLayer(panel.id, layer);
      _focusedPanelId = panel.id;
      _selectedSlot = token;
      _editingSlot = null;
    });
    _pickImage(token);
  }

  /// Adds a grid in the chosen layout, inset from the canvas edges, and
  /// selects its first cell so the grid chrome and styling bar appear. Cell
  /// slot ids derive from the grid's unique id, checked as a set so none can
  /// collide with existing slots.
  void _addGridLayer(Template template, GridPreset preset) {
    final panel = _focusedPanel(template);
    final used = {
      for (final l in _allLayers(template)) l.id,
      ...template.slotIds,
      for (final p in _panels(template)) p.id,
    };
    var n = 1;
    String gridId;
    List<String> cellIds;
    do {
      gridId = 'grid_$n';
      cellIds = [
        for (var i = 0; i < preset.cells.length; i++) '${gridId}_c${i + 1}',
      ];
      n++;
    } while (used.contains(gridId) || cellIds.any(used.contains));
    final inset = template.canvasWidth * 0.08;
    final layer = GridLayer(
      id: gridId,
      hidden: false,
      x: inset,
      y: inset,
      width: template.canvasWidth - 2 * inset,
      height: template.canvasHeight - 2 * inset,
      rotation: 0,
      cols: preset.cols,
      rows: preset.rows,
      colFractions: List.filled(preset.cols, 1),
      rowFractions: List.filled(preset.rows, 1),
      gutter: 24,
      cornerRadius: 0,
      gutterColor: null,
      cells: [
        for (final (i, c) in preset.cells.indexed)
          GridCell(
            slotId: cellIds[i],
            col: c.$1,
            row: c.$2,
            colSpan: c.$3,
            rowSpan: c.$4,
          ),
      ],
    );
    _record();
    setState(() {
      _content = _content.withAddedLayer(panel.id, layer);
      _focusedPanelId = panel.id;
      _selectedSlot = cellIds.first;
      _editingSlot = null;
    });
  }

  /// Adds a sticker sized to its own aspect, centered, and selects it (its
  /// layer id doubles as the gesture/selection key — stickers carry no slot).
  void _addStickerLayer(Template template, AssetChoice asset) {
    final panel = _focusedPanel(template);
    final token = _uniqueToken('sticker', template);
    final width = template.canvasWidth * 0.4;
    final height = width / (asset.aspect <= 0 ? 1 : asset.aspect);
    final layer = StickerLayer(
      id: token,
      hidden: false,
      assetId: asset.id,
      x: (template.canvasWidth - width) / 2,
      y: (template.canvasHeight - height) / 2,
      width: width,
      height: height,
    );
    _record();
    setState(() {
      _content = _content.withAddedLayer(panel.id, layer);
      _focusedPanelId = panel.id;
      _selectedSlot = token;
      _editingSlot = null;
    });
  }

  /// Appends an empty panel (a new carousel slide) and focuses it. Its layers
  /// and background ride in SlotContent like any template panel's.
  void _addPanel(Template template) {
    final id = _uniqueToken('panel', template);
    _record();
    setState(() {
      _content = _content.withAddedPanel(
        Panel(
          id: id,
          backgroundColor: const Color(0xFFFFFFFF),
          layers: const [],
        ),
      );
      _focusedPanelId = id;
      _selectedSlot = null;
      _editingSlot = null;
    });
  }

  Future<void> _insertGrid(Template template) async {
    final preset = await showGridPresetSheet(context);
    if (preset == null || !mounted) return;
    _addGridLayer(template, preset);
  }

  Future<void> _insertAsset(Template template) async {
    final asset = await showAssetPickerSheet(context, _catalog);
    if (asset == null || !mounted) return;
    if (asset.isFrame) {
      // A frame is not a layer of its own — it decorates a photo slot, so
      // inserting one creates a framed image slot and opens the gallery.
      _addImageLayer(template, frameAssetId: asset.id, aspect: asset.aspect);
    } else {
      _addStickerLayer(template, asset);
    }
  }

  /// Deletes a user-added layer (template layers can only be hidden, not
  /// removed). Clears the selection if it pointed at the removed element —
  /// including a grid's cells and a sticker's layer-id key.
  void _removeAddedLayer(String panelId, Layer layer) {
    _record();
    setState(() {
      _content = _content.withoutAddedLayer(panelId, layer.id);
      final slotIds = switch (layer) {
        ImageLayer l => {l.slotId},
        TextLayer l => {l.slotId},
        StickerLayer l => {l.id},
        GridLayer l => {for (final c in l.cells) c.slotId},
        _ => const <String>{},
      };
      if (slotIds.contains(_selectedSlot)) {
        _selectedSlot = null;
        _editingSlot = null;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_onZoomChange);
    _template = widget.draft != null
        ? Future.value(widget.draft)
        : _store.loadTemplate(widget.id!).then((r) => r.template);
    _loadCatalog();
  }

  /// Fetches the frame/sticker catalog so uploaded frames resolve. Best-effort:
  /// on a cold offline start it just stays empty and bundled seeds are used.
  Future<void> _loadCatalog() async {
    try {
      final result = await _store.loadAssets();
      if (mounted) setState(() => _catalog = result.assets);
    } catch (_) {
      // Seeds only.
    }
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  // Flip the pan-axis lock only when crossing the 1x threshold (not on every
  // pan/zoom frame), so a sideways drag at 1x can't drift vertically.
  void _onZoomChange() {
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _isZoomed && mounted) {
      setState(() => _isZoomed = zoomed);
    }
  }

  Future<void> _pickImage(String slotId) async {
    // MemoryImage instead of FileImage so the same code works on web;
    // maxWidth caps decode memory (canvas is 1080 wide, 2x for sharpness).
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2160,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    _edit(_content.withImage(slotId, MemoryImage(bytes)));
  }

  /// Tapping a slot selects it (shows the handles for move/resize). A text
  /// slot's second tap starts inline editing. Image slots and grid cells never
  /// edit — their photo icon opens the gallery instead (see [_onPickImage]).
  void _handleSlotTap(Template template, String slotId) {
    final isText = _allLayers(
      template,
    ).any((l) => l is TextLayer && l.slotId == slotId);
    final wasSelected = _selectedSlot == slotId;
    if (!wasSelected) {
      setState(() {
        _selectedSlot = slotId;
        _editingSlot = null;
      });
    }
    if (isText && wasSelected) {
      setState(() => _editingSlot = slotId);
    }
  }

  /// Opens the gallery for an image slot — triggered only by tapping the
  /// slot's photo icon. Also selects the slot so its handles are ready when
  /// the user returns from the picker.
  void _onPickImage(String slotId) {
    setState(() {
      _selectedSlot = slotId;
      _editingSlot = null;
    });
    _pickImage(slotId);
  }

  /// Opens the layer manager for the focused panel: select an element (useful
  /// when slots overlap), reorder its z-position, or hide/show it. All edits
  /// are SlotContent overrides, so the sheet reflects them live and the canvas
  /// updates underneath.
  void _showLayersSheet(Template template) {
    final templatePanel = _focusedPanel(template);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF27272A),
      builder: (sheetContext) {
        // A StatefulBuilder so reorder/hide/remove repaint the sheet rows; the
        // screen keeps the canonical state (_content) and rebuilds the canvas.
        return StatefulBuilder(
          builder: (context, setSheetState) {
            // Recompute each rebuild so an added/removed layer shows up live.
            final panel = _effectivePanel(templatePanel);
            final natural = [for (final l in panel.layers) l.id];
            return LayersSheet(
              panel: panel,
              content: _content,
              // Only the user's own added layers can be deleted; template
              // layers can be hidden but not removed.
              removableLayerIds: {
                for (final l in _content.addedLayersFor(panel.id)) l.id,
              },
              onRemove: (layer) {
                _removeAddedLayer(panel.id, layer);
                setSheetState(() {});
              },
              onSelect: (slotId) {
                Navigator.pop(sheetContext);
                setState(() {
                  _selectedSlot = slotId;
                  _editingSlot = null;
                });
              },
              onToggleHidden: (layer) {
                final nowHidden = !_content.layerHidden(layer.id, layer.hidden);
                _record();
                setState(() {
                  _content = _content.withLayerHidden(layer.id, nowHidden);
                  // A hidden element can't stay selected/edited.
                  if (nowHidden) {
                    final slotIds = switch (layer) {
                      ImageLayer l => {l.slotId},
                      TextLayer l => {l.slotId},
                      StickerLayer l => {l.id},
                      GridLayer l => {for (final c in l.cells) c.slotId},
                      _ => const <String>{},
                    };
                    if (slotIds.contains(_selectedSlot)) {
                      _selectedSlot = null;
                      _editingSlot = null;
                    }
                  }
                });
                setSheetState(() {});
              },
              onReorder: (layer, {required toFront}) {
                _record();
                setState(() {
                  _content = _content.withLayerMoved(
                    panel.id,
                    natural,
                    layer.id,
                    toFront: toFront,
                  );
                });
                setSheetState(() {});
              },
            );
          },
        );
      },
    );
  }

  Future<void> _exportPng(Template template) async {
    // Deselect first: the handles (and the inline editor's cursor) are
    // widgets inside the RepaintBoundary and would end up in the PNG.
    if (_selectedSlot != null || _editingSlot != null) {
      setState(() {
        _selectedSlot = null;
        _editingSlot = null;
      });
      await WidgetsBinding.instance.endOfFrame;
    }
    setState(() => _exporting = true);
    try {
      // One PNG per panel (added panels included), in carousel order — ready
      // to post as a carousel.
      final panels = _panels(template);
      final files = <XFile>[];
      for (var i = 0; i < panels.length; i++) {
        final panel = panels[i];
        final bytes = await capturePng(
          _panelKey(panel.id),
          template.canvasWidth,
        );
        files.add(
          XFile.fromData(
            bytes,
            mimeType: 'image/png',
            name: panels.length == 1
                ? '${template.id}.png'
                : '${template.id}_${i + 1}.png',
          ),
        );
      }
      await Share.shareXFiles(files);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Template>(
      future: _template,
      builder: (context, snapshot) {
        final template = snapshot.data;
        // Read the keyboard/safe-area insets HERE, above the Scaffold: the
        // Scaffold consumes the keyboard inset and hands its body a MediaQuery
        // with viewInsets.bottom == 0, so reading it inside _buildBody would
        // always see zero.
        final media = MediaQuery.of(context);
        final keyboardInset = media.viewInsets.bottom;
        final safeBottom = media.viewPadding.bottom;
        return Scaffold(
          appBar: AppBar(
            title: Text(template?.name ?? '…'),
            actions: [
              if (template != null)
                IconButton(
                  icon: const Icon(Icons.undo),
                  tooltip: 'Undo',
                  onPressed: _undoStack.isEmpty
                      ? null
                      : () => _undoEdit(template),
                ),
              if (template != null)
                IconButton(
                  icon: const Icon(Icons.redo),
                  tooltip: 'Redo',
                  onPressed: _redoStack.isEmpty
                      ? null
                      : () => _redoEdit(template),
                ),
              if (template != null)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add element',
                  onSelected: (value) => switch (value) {
                    'text' => _addTextLayer(template),
                    'image' => _addImageLayer(template),
                    'grid' => _insertGrid(template),
                    'asset' => _insertAsset(template),
                    'panel' => _addPanel(template),
                    _ => null,
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'text',
                      child: ListTile(
                        leading: Icon(Icons.title),
                        title: Text('Text'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'image',
                      child: ListTile(
                        leading: Icon(Icons.image_outlined),
                        title: Text('Image'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'grid',
                      child: ListTile(
                        leading: Icon(Icons.grid_view),
                        title: Text('Grid'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'asset',
                      child: ListTile(
                        leading: Icon(Icons.star_outline),
                        title: Text('Sticker / frame'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'panel',
                      child: ListTile(
                        leading: Icon(Icons.splitscreen_outlined),
                        title: Text('Panel'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              if (template != null)
                IconButton(
                  icon: const Icon(Icons.layers_outlined),
                  tooltip: 'Layers',
                  onPressed: () => _showLayersSheet(template),
                ),
              if (template != null)
                IconButton(
                  icon: _exporting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share),
                  tooltip: 'Export PNG',
                  onPressed: _exporting ? null : () => _exportPng(template),
                ),
            ],
          ),
          body: switch (snapshot.connectionState) {
            ConnectionState.done when snapshot.hasError => Center(
              child: Text(
                'Could not load template.\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
            ConnectionState.done => _buildBody(
              template!,
              keyboardInset,
              safeBottom,
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        );
      },
    );
  }

  /// The TextLayer of the currently selected slot, or null when nothing —
  /// or a non-text slot — is selected. Drives the styling bar.
  TextLayer? _selectedTextLayer(Template template) {
    final slot = _selectedSlot;
    if (slot == null) return null;
    for (final layer in _allLayers(template)) {
      if (layer is TextLayer && layer.slotId == slot) return layer;
    }
    return null;
  }

  /// The GridLayer owning the selected cell (or null). Drives the grid bar and
  /// tells us a grid cell — not a plain image/text slot — is selected.
  GridLayer? _selectedGridLayer(Template template) {
    final slot = _selectedSlot;
    if (slot == null) return null;
    for (final layer in _allLayers(template)) {
      if (layer is GridLayer && layer.cells.any((c) => c.slotId == slot)) {
        return layer;
      }
    }
    return null;
  }

  /// What the selection overlay manipulates for [_selectedSlot]: the gesture
  /// target id (the slot id, or the LAYER id when a grid cell is selected —
  /// moving/resizing acts on the whole grid) and the layer's template
  /// rotation. Null when nothing is selected.
  (String, double)? _selectionTarget(Template template) {
    final slot = _selectedSlot;
    if (slot == null) return null;
    for (final layer in _allLayers(template)) {
      switch (layer) {
        case ImageLayer l when l.slotId == slot:
          return (l.slotId, l.rotation);
        case TextLayer l when l.slotId == slot:
          // Text carries no template rotation (mirrors _LayerWidget).
          return (l.slotId, 0);
        case StickerLayer l when l.id == slot:
          // Stickers select by layer id and carry no template rotation.
          return (l.id, 0);
        case GridLayer l when l.cells.any((c) => c.slotId == slot):
          return (l.id, l.rotation);
        default:
      }
    }
    return null;
  }

  /// Screen px → template px for the canvas-wide gesture surface, which
  /// lives outside the FittedBox/zoom transforms. The export boundary sits in
  /// template units, so its transform-to-global scale IS the composed
  /// FittedBox × zoom factor (both uniform). Evaluated at gesture start
  /// (post-layout, and the zoom is frozen while a slot is selected).
  double _screenToTemplate(Template template) {
    final box = _panelKeys[template.panels.first.id]?.currentContext
        ?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return 1.0;
    final scale = box.getTransformTo(null).getMaxScaleOnAxis();
    return scale > 0 ? 1 / scale : 1.0;
  }

  Widget _buildBody(
    Template template,
    double keyboardInset,
    double safeBottom,
  ) {
    final textLayer = _selectedTextLayer(template);
    final panels = _panels(template);
    final focusedPanel = _focusedPanel(template);

    final gridLayer = _selectedGridLayer(template);
    final bottomBar = _buildBottomBar(textLayer, focusedPanel, gridLayer);
    // Constant height for the bar strip (incl. the home-indicator inset), so
    // the canvas area is a fixed size regardless of which bar shows.
    final barArea = _kBottomBarHeight + safeBottom;

    return Listener(
      // End of any touch on the canvas/bars ends the current coalescing run
      // (the next same-key edit starts a NEW undo step — see [_record]) and
      // drops the drag-snap state and guide lines. Listener doesn't enter the
      // gesture arena, so this can't affect any recognizer.
      behavior: HitTestBehavior.translucent,
      onPointerUp: (_) => _onPointerEnd(),
      onPointerCancel: (_) => _onPointerEnd(),
      child: Column(
        children: [
          Expanded(
            child: ColoredBox(
              color: const Color(0xFF18181B),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // resizeToAvoidBottomInset shrinks this viewport by exactly the
                  // keyboard height, so adding the inset back recovers the
                  // keyboard-free height: the canvas keeps that fixed size and
                  // the extra overflows into the scroll view, which the framework
                  // scrolls to keep the focused text field above the keyboard.
                  // (keyboardInset comes from above the Scaffold — see build().)
                  final canvasHeight = constraints.maxHeight + keyboardInset;
                  // Panels sit side by side; with more than one, each is a bit
                  // narrower than the viewport so the next one peeks in.
                  final panelWidth =
                      constraints.maxWidth * (panels.length == 1 ? 1.0 : 0.82);
                  // With nothing selected the surface is an InteractiveViewer
                  // (pinch zoom + pan). With a slot selected it becomes a STATIC
                  // transform — same matrix and layout, but NO gesture detector:
                  // InteractiveViewer's detector stays opaque even when pan/scale
                  // are off and would otherwise fight the selection handles.
                  final interacting =
                      _selectedSlot != null || _editingSlot != null;
                  // Selection chrome + ring/handle gestures float in an overlay
                  // ABOVE the strip (unclipped by the canvas, so handles work
                  // past its edge). While editing text the legacy in-canvas
                  // chrome is used instead — the overlay would sit on top of
                  // the inline TextField.
                  final target = _editingSlot == null
                      ? _selectionTarget(template)
                      : null;
                  final strip = SizedBox(
                    height: canvasHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final panel in panels.map(_effectivePanel))
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: SizedBox(
                                width: panelWidth,
                                // The export boundary is INSIDE PanelCanvas's
                                // FittedBox (template units): a boundary out
                                // here captures the letterbox bands whenever
                                // this box doesn't match the canvas aspect,
                                // shrinking the artwork in the exported PNG.
                                child: PanelCanvas(
                                  exportKey: _panelKey(panel.id),
                                  panel: panel,
                                  canvasWidth: template.canvasWidth,
                                  canvasHeight: template.canvasHeight,
                                  fontResolver: widget.fontResolver,
                                  guideXs: panel.id == focusedPanel.id
                                      ? _guideXs
                                      : const [],
                                  guideYs: panel.id == focusedPanel.id
                                      ? _guideYs
                                      : const [],
                                  content: _content,
                                  assetCatalog: _catalog,
                                  selectedSlotId: _selectedSlot,
                                  editingSlotId: _editingSlot,
                                  onSlotTap: (slotId) {
                                    _focusedPanelId = panel.id;
                                    _handleSlotTap(template, slotId);
                                  },
                                  onPickImage: (slotId) {
                                    _focusedPanelId = panel.id;
                                    _onPickImage(slotId);
                                  },
                                  onCanvasTap: () => setState(() {
                                    _focusedPanelId = panel.id;
                                    _selectedSlot = null;
                                    _editingSlot = null;
                                  }),
                                  onTextChanged: (slotId, value) => _edit(
                                    _content.withText(slotId, value),
                                    coalesce: 'text:$slotId',
                                  ),
                                  onSlotDrag: (slotId, delta) =>
                                      _dragSelected(template, slotId, delta),
                                  onSlotScale: (slotId, scale) => _edit(
                                    _content.withScale(slotId, scale),
                                    coalesce: 'scale:$slotId',
                                  ),
                                  onSlotRotate: (slotId, degrees) => _edit(
                                    _content.withRotation(slotId, degrees),
                                    coalesce: 'rotate:$slotId',
                                  ),
                                  onGridFractions:
                                      (gridId, columns, fractions) {
                                        _record('fractions:$gridId');
                                        setState(() {
                                          _focusedPanelId = panel.id;
                                          _content = columns
                                              ? _content.withGridColFractions(
                                                  gridId,
                                                  fractions,
                                                )
                                              : _content.withGridRowFractions(
                                                  gridId,
                                                  fractions,
                                                );
                                        });
                                      },
                                  selectionLink: target == null
                                      ? null
                                      : _selectionLink,
                                  onSelectionSize: target == null
                                      ? null
                                      : (s) {
                                          if (_selectionBox == (target.$1, s)) {
                                            return;
                                          }
                                          setState(() {
                                            _selectionBox = (target.$1, s);
                                          });
                                        },
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                  // Same matrix + layout in both branches (constrained:false →
                  // content-sized, top-left aligned, clipped), so toggling on
                  // selection never shifts the canvas.
                  final Widget surface = interacting
                      ? ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.topLeft,
                            minWidth: 0,
                            minHeight: 0,
                            maxWidth: double.infinity,
                            maxHeight: double.infinity,
                            child: Transform(
                              transform: _zoom.value,
                              child: strip,
                            ),
                          ),
                        )
                      : InteractiveViewer(
                          transformationController: _zoom,
                          constrained: false,
                          // Horizontal-only at 1x (browse panels); free once
                          // zoomed in so every corner is reachable.
                          panAxis: _isZoomed
                              ? PanAxis.free
                              : PanAxis.horizontal,
                          minScale: 1,
                          maxScale: 4,
                          boundaryMargin: const EdgeInsets.all(64),
                          child: strip,
                        );
                  final scroll = SingleChildScrollView(
                    // Vertical scroll only while editing — the framework lifts the
                    // focused field above the keyboard then. Frozen otherwise.
                    physics: _editingSlot != null
                        ? const ClampingScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
                    child: SizedBox(height: canvasHeight, child: surface),
                  );
                  // Shared by the chrome overlay (ring/handle gestures) and the
                  // canvas-wide surface (drag/pinch/twist anywhere). Same
                  // coalesce keys as the in-canvas gestures, so a move that
                  // hops between surfaces still lands in one undo step —
                  // and drags route through the snapping path either way.
                  void dragSelected(String slotId, Offset delta) =>
                      _dragSelected(template, slotId, delta);
                  void scaleSelected(String slotId, double scale) => _edit(
                    _content.withScale(slotId, scale),
                    coalesce: 'scale:$slotId',
                  );
                  void rotateSelected(String slotId, double degrees) => _edit(
                    _content.withRotation(slotId, degrees),
                    coalesce: 'rotate:$slotId',
                  );
                  final box = _selectionBox;
                  Widget body = scroll;
                  if (target != null && box != null && box.$1 == target.$1) {
                    body = Stack(
                      clipBehavior: Clip.none,
                      children: [
                        scroll,
                        Positioned.fill(
                          child: CanvasSelectionOverlay(
                            link: _selectionLink,
                            size: box.$2,
                            targetId: target.$1,
                            currentScale: _content.scaleFor(target.$1),
                            currentRotation: _content.rotationFor(target.$1),
                            templateRotation: target.$2,
                            onDrag: dragSelected,
                            onScaleChange: scaleSelected,
                            onRotateChange: rotateSelected,
                          ),
                        ),
                      ],
                    );
                  }
                  if (target != null) {
                    // With a selection active, the whole canvas area drives the
                    // selected element: drag anywhere moves it, pinch anywhere
                    // resizes, two-finger twist rotates. Everything deeper
                    // (taps, dividers, handles) still wins the gesture arena.
                    body = SelectionGestureSurface(
                      targetId: target.$1,
                      currentScale: _content.scaleFor(target.$1),
                      currentRotation: _content.rotationFor(target.$1),
                      screenToTemplate: () => _screenToTemplate(template),
                      onDrag: dragSelected,
                      onScaleChange: scaleSelected,
                      onRotateChange: rotateSelected,
                      child: body,
                    );
                  }
                  return body;
                },
              ),
            ),
          ),
          // The bar strip: fixed height (so the canvas area never changes) and
          // bottom-aligned, sitting just above the keyboard when it's open
          // (resizeToAvoidBottomInset pushes it up).
          ColoredBox(
            color: const Color(0xFF18181B),
            child: SizedBox(
              height: barArea,
              width: double.infinity,
              child: bottomBar == null
                  ? null
                  : Align(alignment: Alignment.bottomCenter, child: bottomBar),
            ),
          ),
        ],
      ),
    );
  }

  /// The bar shown under the canvas: background colors when nothing is
  /// selected, text styling for a text slot, grid spacing/corners for a grid
  /// cell, and nothing for a plain image slot.
  Widget? _buildBottomBar(
    TextLayer? textLayer,
    Panel focusedPanel,
    GridLayer? gridLayer,
  ) {
    if (textLayer == null && _selectedSlot == null) {
      return BackgroundColorBar(
        currentColor:
            _content.backgroundFor(focusedPanel.id) ??
            focusedPanel.backgroundColor,
        onColor: (color) =>
            _edit(_content.withPanelBackground(focusedPanel.id, color)),
      );
    }
    if (textLayer != null) {
      final weight =
          _content.weightFor(textLayer.slotId) ?? textLayer.fontWeight;
      return TextStyleBar(
        currentFont: _content.fontFor(textLayer.slotId) ?? textLayer.fontFamily,
        currentColor: _content.colorFor(textLayer.slotId) ?? textLayer.color,
        currentAlignment:
            _content.alignmentFor(textLayer.slotId) ?? textLayer.alignment,
        isBold: weight >= 700,
        onFont: (font) => _edit(_content.withFont(textLayer.slotId, font)),
        onColor: (color) => _edit(_content.withColor(textLayer.slotId, color)),
        onAlignment: (align) =>
            _edit(_content.withAlignment(textLayer.slotId, align)),
        onBoldToggle: () => _edit(
          _content.withWeight(textLayer.slotId, weight >= 700 ? 400 : 700),
        ),
      );
    }
    if (gridLayer != null) {
      final g = gridLayer;
      final minSide = g.width < g.height ? g.width : g.height;
      return GridStyleBar(
        gutter: _content.gridGutter(g.id, g.gutter),
        cornerRadius: _content.gridCornerRadius(g.id, g.cornerRadius),
        // Caps relative to the grid's own size so the sliders stay sensible.
        maxGutter: minSide * 0.2,
        maxCorner: minSide * 0.25,
        onGutter: (v) =>
            _edit(_content.withGridGutter(g.id, v), coalesce: 'gutter:${g.id}'),
        onCorner: (v) => _edit(
          _content.withGridCornerRadius(g.id, v),
          coalesce: 'corner:${g.id}',
        ),
      );
    }
    return null;
  }
}
