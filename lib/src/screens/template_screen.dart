import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../api/project_store.dart';
import '../api/template_store.dart';
import '../model/asset_record.dart';
import '../model/slot_content.dart';
import '../model/template.dart';
import '../rendering/export.dart';
import '../rendering/snap.dart';
import '../rendering/template_canvas.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/grid_style_bar.dart';
import '../widgets/insert_sheets.dart';
import '../widgets/layers_sheet.dart';
import '../widgets/text_style_bar.dart';

/// Renders one template and lets the user fill its slots (spec §12),
/// editing directly on the canvas: tap selects, tap again edits text
/// inline or opens the gallery picker for images. The result exports as
/// a full-resolution PNG through the share sheet.
///
/// Three entry points: a published template by [id] (fetched through the
/// store), a local [draft] — the create-from-scratch flow hands in
/// [Template.blank] and the user builds everything with the bottom toolbar
/// (text, images, grids, assets, panels) — or a saved [project] being
/// resumed (its embedded template snapshot plus the user's edits).
///
/// With a [projects] store, every session persists itself as a project:
/// the first edit creates it, and edits keep flowing to disk (debounced,
/// plus on pointer-up, on app backgrounding and on leaving the screen).
/// Without one (tests), editing is session-only.
class TemplateScreen extends StatefulWidget {
  final String? id;
  final Template? draft;
  final Project? project;
  final ProjectStore? projects;

  /// Injectable for tests (google_fonts needs network/assets); the app uses
  /// the default runtime-fetching resolver.
  final FontResolver fontResolver;

  const TemplateScreen({
    super.key,
    this.id,
    this.draft,
    this.project,
    this.projects,
    this.fontResolver = googleFontsResolver,
  }) : assert(
         (id != null ? 1 : 0) +
                 (draft != null ? 1 : 0) +
                 (project != null ? 1 : 0) ==
             1,
         'Pass exactly one of id, draft or project',
       );

  @override
  State<TemplateScreen> createState() => _TemplateScreenState();
}

/// Fixed height of the bottom styling-bar strip (content only; the safe-area
/// inset is added at build time). Sized to the TALLEST bar (the text styling
/// bar) and reserved in EVERY state, so the canvas area — and thus the canvas
/// size — never changes when a different bar shows or a slot is selected.
const double _kBottomBarHeight = 196;

class _TemplateScreenState extends State<TemplateScreen>
    with WidgetsBindingObserver {
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
  // Background contextual bar open (entered via the toolbar's Background
  // button; selecting any element leaves it). Stays across canvas taps so the
  // user can hop between panels while recoloring.
  bool _backgroundMode = false;
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

  // Project persistence (only with widget.projects). The project is created
  // lazily on the first edit — browsing a template without touching it never
  // leaves a file behind. [_dirty] marks unsaved content; a debounce timer
  // covers keyboard-only edit streams (typing produces no canvas pointer-up).
  Template? _resolvedTemplate;
  String? _projectId;
  bool _dirty = false;
  bool _saveErrorShown = false;
  Timer? _saveTimer;
  // Disambiguates photo file names picked within the same millisecond.
  int _imageSeq = 0;

  static const Duration _kSaveDebounce = Duration(seconds: 2);

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
    _markDirty();
  }

  /// Flags unsaved content and (re)arms the debounced save. Every content
  /// change funnels through here — [_record] for edits, [_restore] for
  /// undo/redo.
  void _markDirty() {
    if (widget.projects == null) return;
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(_kSaveDebounce, _saveProject);
  }

  /// Writes the project if there is unsaved content. Fire-and-forget: the
  /// store queues writes, so overlapping calls can't interleave on disk. On
  /// failure the content stays dirty (the next trigger retries) and the user
  /// is warned once per session.
  void _saveProject() {
    final store = widget.projects;
    final template = _resolvedTemplate;
    if (!_dirty || store == null || template == null) return;
    _saveTimer?.cancel();
    _dirty = false;
    final project = Project(
      id: _projectId ??= _newProjectId(),
      name: template.name,
      updatedAt: DateTime.now(),
      template: template,
      content: _content,
    );
    store.save(project).catchError((_) {
      _dirty = true;
      if (mounted && !_saveErrorShown) {
        _saveErrorShown = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save your project.')),
        );
      }
    });
  }

  String _newProjectId() => 'p_${DateTime.now().millisecondsSinceEpoch}';

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
    _markDirty();
  }

  /// End of any touch interaction: breaks the undo coalescing run (the next
  /// same-key edit starts a new step), flushes unsaved content to disk (a
  /// finished gesture is a natural checkpoint) and drops the drag/guide state.
  void _onPointerEnd() {
    _editRunKey = null;
    _saveProject();
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
    // A tick the moment the element locks onto a (new) guide — not on every
    // frame it stays snapped.
    if ((xs.isNotEmpty || ys.isNotEmpty) &&
        (!listEquals(xs, _guideXs) || !listEquals(ys, _guideYs))) {
      HapticFeedback.selectionClick();
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
    // Edge stretch grows the LAYOUT box (top-left pinned), so the snapped
    // box is the model box with the stretched dimensions.
    final fx = _content.stretchXFor(key);
    final fy = _content.stretchYFor(key);
    for (final layer in _allLayers(template)) {
      switch (layer) {
        case ImageLayer l when l.slotId == key:
          if (l.rotation != 0) return null;
          return Rect.fromLTWH(l.x, l.y, l.width * fx, l.height * fy);
        case TextLayer l when l.slotId == key:
          final box = _selectionBox;
          if (box == null || box.$1 != key) return null;
          final pad = 2 * kChromePad / _content.scaleFor(key);
          final h = box.$2.height - pad;
          // The text hugs its glyphs inside the model box (see _TextSlot), so
          // the snapped box is the measured one, shifted by the alignment.
          final w = box.$2.width - pad;
          if (h <= 0 || w <= 0) return null;
          final frameW = l.width * fx;
          final dx = switch (_content.alignmentFor(key) ?? l.alignment) {
            'center' => (frameW - w) / 2,
            'right' => frameW - w,
            _ => 0.0,
          };
          return Rect.fromLTWH(l.x + dx, l.y, w, h);
        case StickerLayer l when l.id == key:
          return Rect.fromLTWH(l.x, l.y, l.width * fx, l.height * fy);
        case GridLayer l when l.id == key:
          if (l.rotation != 0) return null;
          return Rect.fromLTWH(l.x, l.y, l.width * fx, l.height * fy);
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
      // Painted bounds: the LAYOUT box stretched from its top-left, then
      // scaled around the stretched box's center, then user-offset.
      final stretched = Rect.fromLTWH(
        box.left,
        box.top,
        box.width * _content.stretchXFor(key),
        box.height * _content.stretchYFor(key),
      );
      targets.add(
        Rect.fromCenter(
          center: stretched.center + _content.offsetFor(key),
          width: stretched.width * s,
          height: stretched.height * s,
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
      _backgroundMode = false;
    });
  }

  /// Adds a fresh image element to the focused panel, centered. With [image]
  /// the photo lands in the same undo step; without one the gallery opens
  /// right away (an empty image element is useless on its own).
  /// [frameAssetId]/[aspect] make it a framed photo slot (polaroid etc.) —
  /// the box follows the frame's aspect so the window isn't distorted.
  void _addImageLayer(
    Template template, {
    String? frameAssetId,
    double aspect = 1,
    ImageProvider? image,
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
      var next = _content.withAddedLayer(panel.id, layer);
      if (image != null) next = next.withImage(token, image);
      _content = next;
      _focusedPanelId = panel.id;
      _selectedSlot = token;
      _editingSlot = null;
      _backgroundMode = false;
    });
    if (image == null) _pickImage(token);
  }

  /// A grid id and its cell slot ids unused by the template or anything the
  /// user added, checked as a set so none can collide with existing slots.
  (String, List<String>) _uniqueGridIds(Template template, int cellCount) {
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
      cellIds = [for (var i = 0; i < cellCount; i++) '${gridId}_c${i + 1}'];
      n++;
    } while (used.contains(gridId) || cellIds.any(used.contains));
    return (gridId, cellIds);
  }

  /// A GridLayer in [preset]'s layout, inset from the canvas edges.
  GridLayer _buildGridLayer(
    Template template,
    GridPreset preset,
    String gridId,
    List<String> cellIds,
  ) {
    final inset = template.canvasWidth * 0.08;
    return GridLayer(
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
  }

  /// Adds an empty grid in the chosen layout and selects its first cell so
  /// the grid chrome and styling bar appear.
  void _addGridLayer(Template template, GridPreset preset) {
    final panel = _focusedPanel(template);
    final (gridId, cellIds) = _uniqueGridIds(template, preset.cells.length);
    final layer = _buildGridLayer(template, preset, gridId, cellIds);
    _record();
    setState(() {
      _content = _content.withAddedLayer(panel.id, layer);
      _focusedPanelId = panel.id;
      _selectedSlot = cellIds.first;
      _editingSlot = null;
      _backgroundMode = false;
    });
  }

  /// Adds [preset] with [images] already in its cells (in pick order) as ONE
  /// undo step — the photos-first flow's landing point. Nothing ends up
  /// selected: the result is the collage itself, ready to fine-tune.
  void _insertFilledGrid(
    Template template,
    GridPreset preset,
    List<ImageProvider> images,
  ) {
    final panel = _focusedPanel(template);
    final (gridId, cellIds) = _uniqueGridIds(template, preset.cells.length);
    final layer = _buildGridLayer(template, preset, gridId, cellIds);
    _record();
    setState(() {
      var next = _content.withAddedLayer(panel.id, layer);
      for (var i = 0; i < cellIds.length && i < images.length; i++) {
        next = next.withImage(cellIds[i], images[i]);
      }
      _content = next;
      _focusedPanelId = panel.id;
      _selectedSlot = null;
      _editingSlot = null;
      _backgroundMode = false;
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
      _backgroundMode = false;
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

  /// The ids under which [layer] can be selected: the slot id for image/text,
  /// the layer id for stickers, every cell's slot id for grids. Used to clear
  /// a selection pointing at an element being removed or hidden.
  static Set<String> _selectionKeys(Layer layer) => switch (layer) {
    ImageLayer l => {l.slotId},
    TextLayer l => {l.slotId},
    StickerLayer l => {l.id},
    GridLayer l => {for (final c in l.cells) c.slotId},
    _ => const <String>{},
  };

  /// Deletes a user-added layer (template layers can only be hidden, not
  /// removed). Clears the selection if it pointed at the removed element —
  /// including a grid's cells and a sticker's layer-id key.
  void _removeAddedLayer(String panelId, Layer layer) {
    _record();
    setState(() {
      _content = _content.withoutAddedLayer(panelId, layer.id);
      if (_selectionKeys(layer).contains(_selectedSlot)) {
        _selectedSlot = null;
        _editingSlot = null;
      }
    });
  }

  /// Deletes the selected element via its ✕ handle. [targetId] is the gesture
  /// target id — the slot id for image/text, the LAYER id for stickers and
  /// grids. A user-added layer is removed outright; a template layer can't
  /// leave the immutable template, so it gets a hidden override instead (it
  /// disappears from canvas and export, and the layers sheet can bring it
  /// back). Both paths are one undo step.
  void _deleteSelected(Template template, String targetId) {
    Layer? target;
    for (final layer in _allLayers(template)) {
      final hit = switch (layer) {
        ImageLayer l => l.slotId == targetId,
        TextLayer l => l.slotId == targetId,
        StickerLayer l => l.id == targetId,
        GridLayer l => l.id == targetId,
        _ => false,
      };
      if (hit) {
        target = layer;
        break;
      }
    }
    if (target == null) return;
    for (final entry in _content.addedLayers.entries) {
      if (entry.value.any((l) => l.id == target!.id)) {
        _removeAddedLayer(entry.key, target);
        return;
      }
    }
    final layer = target;
    _record();
    setState(() {
      _content = _content.withLayerHidden(layer.id, true);
      if (_selectionKeys(layer).contains(_selectedSlot)) {
        _selectedSlot = null;
        _editingSlot = null;
      }
    });
  }

  /// Duplicates the selected element as a user-added layer on the focused
  /// panel, one undo step, and selects the copy. Styling overrides (font,
  /// color, grid spacing, …) are BAKED into the copied layer — the copy then
  /// owns them — while content (text, photos) and transform overrides are
  /// carried over, with the offset nudged so the copy is visibly its own
  /// element. Template layers duplicate into added layers; the template
  /// itself is never touched. [targetId] is the gesture target id, like
  /// [_deleteSelected]'s.
  void _duplicateSelected(Template template, String targetId) {
    Layer? source;
    for (final layer in _allLayers(template)) {
      final hit = switch (layer) {
        ImageLayer l => l.slotId == targetId,
        TextLayer l => l.slotId == targetId,
        StickerLayer l => l.id == targetId,
        GridLayer l => l.id == targetId,
        _ => false,
      };
      if (hit) {
        source = layer;
        break;
      }
    }
    if (source == null) return;
    final panel = _focusedPanel(template);
    final nudge = Offset(
      template.canvasWidth * 0.04,
      template.canvasWidth * 0.04,
    );

    final String selectKey;
    SlotContent next;
    switch (source) {
      case TextLayer l:
        final token = _uniqueToken('text', template);
        selectKey = token;
        next = _content.withAddedLayer(
          panel.id,
          TextLayer(
            id: token,
            hidden: false,
            slotId: token,
            x: l.x,
            y: l.y,
            width: l.width,
            fontFamily: _content.fontFor(l.slotId) ?? l.fontFamily,
            fontSize: l.fontSize,
            fontWeight: _content.weightFor(l.slotId) ?? l.fontWeight,
            color: _content.colorFor(l.slotId) ?? l.color,
            alignment: _content.alignmentFor(l.slotId) ?? l.alignment,
          ),
        );
        final text = _content.textFor(l.slotId);
        if (text != null) next = next.withText(token, text);
        next = _copyTransforms(next, l.slotId, token, nudge);
      case ImageLayer l:
        final token = _uniqueToken('image', template);
        selectKey = token;
        next = _content.withAddedLayer(
          panel.id,
          ImageLayer(
            id: token,
            hidden: false,
            slotId: token,
            x: l.x,
            y: l.y,
            width: l.width,
            height: l.height,
            rotation: l.rotation,
            opacity: l.opacity,
            borderRadius: l.borderRadius,
            frameAssetId: l.frameAssetId,
          ),
        );
        // Both slots reference the same photo file; the cleanup on dispose
        // keeps any file the content still points at.
        final image = _content.imageFor(l.slotId);
        if (image != null) next = next.withImage(token, image);
        next = _copyTransforms(next, l.slotId, token, nudge);
      case StickerLayer l:
        final token = _uniqueToken('sticker', template);
        selectKey = token;
        next = _content.withAddedLayer(
          panel.id,
          StickerLayer(
            id: token,
            hidden: false,
            assetId: l.assetId,
            x: l.x,
            y: l.y,
            width: l.width,
            height: l.height,
          ),
        );
        next = _copyTransforms(next, l.id, token, nudge);
      case GridLayer l:
        final (gridId, cellIds) = _uniqueGridIds(template, l.cells.length);
        selectKey = cellIds.first;
        next = _content.withAddedLayer(
          panel.id,
          GridLayer(
            id: gridId,
            hidden: false,
            x: l.x,
            y: l.y,
            width: l.width,
            height: l.height,
            rotation: l.rotation,
            cols: l.cols,
            rows: l.rows,
            colFractions: _content.gridColFractions(l.id, l.colFractions),
            rowFractions: _content.gridRowFractions(l.id, l.rowFractions),
            gutter: _content.gridGutter(l.id, l.gutter),
            cornerRadius: _content.gridCornerRadius(l.id, l.cornerRadius),
            gutterColor: l.gutterColor,
            cells: [
              for (final (i, c) in l.cells.indexed)
                GridCell(
                  slotId: cellIds[i],
                  col: c.col,
                  row: c.row,
                  colSpan: c.colSpan,
                  rowSpan: c.rowSpan,
                  borderRadius: c.borderRadius,
                ),
            ],
          ),
        );
        for (final (i, c) in l.cells.indexed) {
          final image = _content.imageFor(c.slotId);
          if (image != null) next = next.withImage(cellIds[i], image);
        }
        next = _copyTransforms(next, l.id, gridId, nudge);
      default:
        return;
    }
    _record();
    setState(() {
      _content = next;
      _focusedPanelId = panel.id;
      _selectedSlot = selectKey;
      _editingSlot = null;
      _backgroundMode = false;
    });
  }

  /// Carries the per-slot transform overrides from [from] onto [to], with
  /// the offset nudged by [nudge].
  SlotContent _copyTransforms(
    SlotContent content,
    String from,
    String to,
    Offset nudge,
  ) {
    var next = content.withOffset(to, content.offsetFor(from) + nudge);
    final scale = content.scaleFor(from);
    if (scale != 1) next = next.withScale(to, scale);
    final stretchX = content.stretchXFor(from);
    if (stretchX != 1) next = next.withStretchX(to, stretchX);
    final stretchY = content.stretchYFor(from);
    if (stretchY != 1) next = next.withStretchY(to, stretchY);
    final rotation = content.rotationFor(from);
    if (rotation != 0) next = next.withRotation(to, rotation);
    return next;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _zoom.addListener(_onZoomChange);
    final project = widget.project;
    if (project != null) {
      // Resuming: the saved document carries both the template snapshot and
      // the user's edits.
      _projectId = project.id;
      _content = project.content;
      _template = Future.value(project.template);
    } else if (widget.draft != null) {
      _template = Future.value(widget.draft);
    } else {
      _template = _store.loadTemplate(widget.id!).then((r) => r.template);
    }
    // Saving needs the template outside the FutureBuilder; load errors are
    // already surfaced by build(). Block body: an arrow would type the chain
    // as Future<Template>, which the void-returning onError then violates.
    _template.then((t) {
      _resolvedTemplate = t;
    }, onError: (_) {});
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
    _saveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    // Leaving the editor: flush unsaved content, then drop photo files only
    // the (now dead) undo history still referenced. Both are queued on the
    // store, so the cleanup runs strictly after the final save.
    _saveProject();
    final store = widget.projects;
    final projectId = _projectId;
    if (store != null && projectId != null) {
      unawaited(
        store.cleanupImages(projectId, {
          for (final image in _content.images.values)
            if (imageFileName(image) != null) imageFileName(image)!,
        }),
      );
    }
    _zoom.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The OS may kill a backgrounded app without any further callback; going
    // inactive/paused is the last reliable moment to flush unsaved work.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _saveProject();
    }
  }

  // Flip the pan-axis lock only when crossing the 1x threshold (not on every
  // pan/zoom frame), so a sideways drag at 1x can't drift vertically.
  void _onZoomChange() {
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _isZoomed && mounted) {
      setState(() => _isZoomed = zoomed);
    }
  }

  /// Picks ONE photo from the gallery into [slotId] — the flow behind a
  /// slot's pick icon and the photo bar's Replace.
  Future<void> _pickImage(String slotId) async {
    // maxWidth caps decode memory (canvas is 1080 wide, 2x for sharpness).
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2160,
    );
    if (file == null) return;
    final image = await _persistImage(await file.readAsBytes());
    if (!mounted) return;
    _edit(_content.withImage(slotId, image));
  }

  /// Turns picked photo bytes into the ImageProvider the content stores.
  /// With a project store the photo becomes a project file and rides in the
  /// content as a FileImage (a MemoryImage can't be saved, and its bytes
  /// wouldn't survive a restart anyway). The name is unique per pick:
  /// Flutter's ImageCache keys FileImage by path, and undo snapshots keep
  /// referencing the previous photo's file. Without a store (tests) the
  /// session-only MemoryImage path remains.
  Future<ImageProvider> _persistImage(Uint8List bytes) async {
    final store = widget.projects;
    if (store != null) {
      try {
        return FileImage(
          await store.saveImage(
            _projectId ??= _newProjectId(),
            'img_${DateTime.now().millisecondsSinceEpoch}_${_imageSeq++}.jpg',
            bytes,
          ),
        );
      } catch (_) {
        // Disk full/unwritable: keep the photo usable for this session.
      }
    }
    return MemoryImage(bytes);
  }

  /// The toolbar's Photo action — photos first, layout second. A multi-select
  /// gallery pick: one photo becomes a plain image element; several open the
  /// layout picker (presets for that exact count, previewed with the actual
  /// photos) and land as a pre-filled grid, one undo step, nothing selected.
  Future<void> _insertPhotos(Template template) async {
    final files = await _picker.pickMultiImage(maxWidth: 2160);
    if (files.isEmpty) return;
    final bytesList = <Uint8List>[
      for (final file in files) await file.readAsBytes(),
    ];
    if (!mounted) return;
    if (bytesList.length == 1) {
      final image = await _persistImage(bytesList.single);
      if (!mounted) return;
      _addImageLayer(template, image: image);
      return;
    }
    // Previews stay in memory; the photos are only persisted to project
    // files after the user commits to a layout (cancelling leaves no files).
    final preset = await showLayoutPickerSheet(
      context,
      photos: [for (final bytes in bytesList) MemoryImage(bytes)],
      canvasAspect: template.canvasWidth / template.canvasHeight,
    );
    if (preset == null || !mounted) return;
    final images = <ImageProvider>[
      for (final bytes in bytesList) await _persistImage(bytes),
    ];
    if (!mounted) return;
    _insertFilledGrid(template, preset, images);
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
        _backgroundMode = false;
      });
    }
    if (isText && wasSelected) {
      setState(() => _editingSlot = slotId);
    }
  }

  /// Applies a rotation gesture with angle snapping: the raw angle arrives
  /// every frame, so the snap is stateless — the element locks onto straight
  /// angles (0°/45°/90°…) and escapes as soon as the raw angle leaves the
  /// reach. A tick marks the moment it locks on.
  void _rotateSelected(String slotId, double degrees) {
    final snapped = snapRotation(degrees);
    if (snapped != degrees && _content.rotationFor(slotId) != snapped) {
      HapticFeedback.selectionClick();
    }
    _edit(_content.withRotation(slotId, snapped), coalesce: 'rotate:$slotId');
  }

  /// Applies an edge-pill drag: the new single-axis stretch factor plus the
  /// offset compensation that keeps the opposite edge fixed (Canva-style),
  /// in ONE edit so undo restores both together.
  void _edgeResizeSelected(
    String slotId,
    SlotEdge edge,
    double factor,
    Offset offsetDelta,
  ) {
    final horizontal = edge == SlotEdge.left || edge == SlotEdge.right;
    _edit(
      (horizontal
              ? _content.withStretchX(slotId, factor)
              : _content.withStretchY(slotId, factor))
          .withOffset(slotId, _content.offsetFor(slotId) + offsetDelta),
      coalesce: 'stretch:$slotId',
    );
  }

  /// Opens the gallery for an image slot — triggered only by tapping the
  /// slot's photo icon. Also selects the slot so its handles are ready when
  /// the user returns from the picker.
  void _onPickImage(String slotId) {
    setState(() {
      _selectedSlot = slotId;
      _editingSlot = null;
      _backgroundMode = false;
    });
    _pickImage(slotId);
  }

  /// A carousel dot's tap: focus panel [index] and slide it into view. The
  /// navigation happens at 1x — any pinch zoom resets, which is what you want
  /// when hopping between slides.
  void _focusPanelAt(
    int index,
    List<Panel> panels,
    double panelWidth,
    double viewportWidth,
  ) {
    setState(() {
      _focusedPanelId = panels[index].id;
      _selectedSlot = null;
      _editingSlot = null;
    });
    // Mirror the strip's layout: 16px strip padding + 6px per-panel padding.
    final stripWidth = 32 + panels.length * (panelWidth + 12.0);
    final maxTx = (stripWidth - viewportWidth).clamp(0.0, double.infinity);
    final tx = (index * (panelWidth + 12.0)).clamp(0.0, maxTx);
    _zoom.value = Matrix4.identity()..setTranslationRaw(-tx, 0, 0);
  }

  /// The contextual bar's Done: deselect and return the bottom strip to the
  /// toolbar (also closes the inline text editor and the background mode).
  void _closeContextBar() {
    setState(() {
      _selectedSlot = null;
      _editingSlot = null;
      _backgroundMode = false;
    });
  }

  /// Opens the layer manager for the focused panel: select an element (useful
  /// when slots overlap), drag rows to restack, or hide/show it. All edits
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
            return LayersSheet(
              panel: panel,
              content: _content,
              assetCatalog: _catalog,
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
                  if (nowHidden &&
                      _selectionKeys(layer).contains(_selectedSlot)) {
                    _selectedSlot = null;
                    _editingSlot = null;
                  }
                });
                setSheetState(() {});
              },
              onReorderList: (orderedIds) {
                _record();
                setState(() {
                  _content = _content.withLayerOrder(panel.id, orderedIds);
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
      final names = <String>[];
      for (var i = 0; i < panels.length; i++) {
        final panel = panels[i];
        final bytes = await capturePng(
          _panelKey(panel.id),
          template.canvasWidth,
        );
        files.add(XFile.fromData(bytes, mimeType: 'image/png'));
        names.add(
          panels.length == 1
              ? '${template.id}.png'
              : '${template.id}_${i + 1}.png',
        );
      }
      // fileNameOverrides is REQUIRED with XFile.fromData: cross_file drops
      // the name off-web, share_plus then invents one whose uuid-v1 slice is
      // identical across a burst, and Android flattens the temp files into
      // one cache folder by basename — every panel after the first would
      // overwrite it and the sheet would share the same PNG N times.
      await Share.shareXFiles(files, fileNameOverrides: names);
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
              if (template != null) ...[
                IconButton(
                  icon: const Icon(Icons.undo),
                  tooltip: 'Undo',
                  onPressed: _undoStack.isEmpty
                      ? null
                      : () => _undoEdit(template),
                ),
                IconButton(
                  icon: const Icon(Icons.redo),
                  tooltip: 'Redo',
                  onPressed: _redoStack.isEmpty
                      ? null
                      : () => _redoEdit(template),
                ),
                // Export is the flow's finish line — a labeled button, not
                // one more icon. Inserting/layers live in the bottom toolbar.
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, right: 12),
                    child: FilledButton(
                      onPressed: _exporting ? null : () => _exportPng(template),
                      child: _exporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Export'),
                    ),
                  ),
                ),
              ],
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

  /// The ImageLayer of the currently selected slot (or null). Grid cells are
  /// not ImageLayers, so a selected cell falls through to the grid bar.
  ImageLayer? _selectedImageLayer(Template template) {
    final slot = _selectedSlot;
    if (slot == null) return null;
    for (final layer in _allLayers(template)) {
      if (layer is ImageLayer && layer.slotId == slot) return layer;
    }
    return null;
  }

  /// The StickerLayer selected by its layer id (or null).
  StickerLayer? _selectedStickerLayer(Template template) {
    final slot = _selectedSlot;
    if (slot == null) return null;
    for (final layer in _allLayers(template)) {
      if (layer is StickerLayer && layer.id == slot) return layer;
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
  /// moving/resizing acts on the whole grid), the layer's template rotation,
  /// its model size (pre-stretch, for the edge pills' anchoring math) and
  /// whether it's text (edge pills then stretch the wrap width only). Null
  /// when nothing is selected.
  (String, double, Size, bool)? _selectionTarget(Template template) {
    final slot = _selectedSlot;
    if (slot == null) return null;
    for (final layer in _allLayers(template)) {
      switch (layer) {
        case ImageLayer l when l.slotId == slot:
          return (l.slotId, l.rotation, Size(l.width, l.height), false);
        case TextLayer l when l.slotId == slot:
          // Text carries no template rotation (mirrors _LayerWidget) and no
          // model height (it's automatic).
          return (l.slotId, 0, Size(l.width, 0), true);
        case StickerLayer l when l.id == slot:
          // Stickers select by layer id and carry no template rotation.
          return (l.id, 0, Size(l.width, l.height), false);
        case GridLayer l when l.cells.any((c) => c.slotId == slot):
          return (l.id, l.rotation, Size(l.width, l.height), false);
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
    final panels = _panels(template);
    final focusedPanel = _focusedPanel(template);
    final bottomBar = _buildBottomBar(template);
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
                  // narrower than the viewport so the next one peeks in. A
                  // single panel instead fills the viewport minus the strip's
                  // 16px + per-panel 6px paddings (44px total), so the strip
                  // is exactly viewport-wide and the panel sits centered.
                  final panelWidth = panels.length == 1
                      ? constraints.maxWidth - 44
                      : constraints.maxWidth * 0.82;
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
                                  onSlotDelete: (slotId) =>
                                      _deleteSelected(template, slotId),
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
                                  onSlotRotate: _rotateSelected,
                                  onSlotEdgeResize: _edgeResizeSelected,
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
                          minScale: 0.25,
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
                            currentStretchX: _content.stretchXFor(target.$1),
                            currentStretchY: _content.stretchYFor(target.$1),
                            baseSize: target.$3,
                            verticalEdges: !target.$4,
                            onDrag: dragSelected,
                            onScaleChange: scaleSelected,
                            onRotateChange: _rotateSelected,
                            onEdgeResize: _edgeResizeSelected,
                            onDelete: (id) => _deleteSelected(template, id),
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
                      onRotateChange: _rotateSelected,
                      child: body,
                    );
                  }
                  if (panels.length > 1) {
                    // Carousel dots: which panel is focused, out of how many.
                    // Tapping one focuses that panel and slides it into view.
                    body = Stack(
                      children: [
                        Positioned.fill(child: body),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 6,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (final (i, panel) in panels.indexed)
                                GestureDetector(
                                  key: ValueKey('panel-dot-$i'),
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _focusPanelAt(
                                    i,
                                    panels,
                                    panelWidth,
                                    constraints.maxWidth,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      width: panel.id == focusedPanel.id
                                          ? 18
                                          : 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: panel.id == focusedPanel.id
                                            ? const Color(0xFF3B82F6)
                                            : Colors.white38,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
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
              child: Align(alignment: Alignment.bottomCenter, child: bottomBar),
            ),
          ),
        ],
      ),
    );
  }

  /// The bar strip under the canvas. Home state is the [EditorToolbar]
  /// (insert/layers/background); a selected element swaps in its own
  /// contextual bar with an explicit title and Done, so the strip never
  /// changes silently: text styling, grid spacing/corners, photo actions,
  /// sticker actions — and background colors while [_backgroundMode] is on.
  Widget _buildBottomBar(Template template) {
    final textLayer = _selectedTextLayer(template);
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
        scale: _content.scaleFor(textLayer.slotId),
        onScale: (v) => _edit(
          _content.withScale(textLayer.slotId, v),
          coalesce: 'scale:${textLayer.slotId}',
        ),
        onDuplicate: () => _duplicateSelected(template, textLayer.slotId),
        onDelete: () => _deleteSelected(template, textLayer.slotId),
        onDone: _closeContextBar,
      );
    }
    final gridLayer = _selectedGridLayer(template);
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
        onDuplicate: () => _duplicateSelected(template, g.id),
        onDelete: () => _deleteSelected(template, g.id),
        onDone: _closeContextBar,
      );
    }
    final imageLayer = _selectedImageLayer(template);
    if (imageLayer != null) {
      return ContextBarShell(
        title: 'Photo',
        onDuplicate: () => _duplicateSelected(template, imageLayer.slotId),
        onDelete: () => _deleteSelected(template, imageLayer.slotId),
        onDone: _closeContextBar,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: ToolButton(
              icon: Icons.photo_library_outlined,
              label: 'Replace',
              onTap: () => _pickImage(imageLayer.slotId),
            ),
          ),
        ),
      );
    }
    final stickerLayer = _selectedStickerLayer(template);
    if (stickerLayer != null) {
      return ContextBarShell(
        title: 'Sticker',
        onDuplicate: () => _duplicateSelected(template, stickerLayer.id),
        onDelete: () => _deleteSelected(template, stickerLayer.id),
        onDone: _closeContextBar,
        child: const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Drag to move · pinch to resize · twist to rotate',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
        ),
      );
    }
    if (_backgroundMode) {
      final focusedPanel = _focusedPanel(template);
      return BackgroundColorBar(
        currentColor:
            _content.backgroundFor(focusedPanel.id) ??
            focusedPanel.backgroundColor,
        onColor: (color) =>
            _edit(_content.withPanelBackground(focusedPanel.id, color)),
        onDone: _closeContextBar,
      );
    }
    return EditorToolbar(
      onLayout: () => _insertGrid(template),
      onText: () => _addTextLayer(template),
      onPhoto: () => _insertPhotos(template),
      onSticker: () => _insertAsset(template),
      onBackground: () => setState(() => _backgroundMode = true),
      onPanel: () => _addPanel(template),
      onLayers: () => _showLayersSheet(template),
    );
  }
}
