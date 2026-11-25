import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../api/entitlements.dart';
import '../api/project_store.dart';
import '../api/template_store.dart';
import '../model/asset_record.dart';
import '../model/migrate_v4.dart';
import '../model/photo_slots.dart';
import '../model/slide_aware.dart';
import '../model/slide_ops.dart';
import '../model/slot_content.dart';
import '../model/template.dart';
import '../rendering/export.dart';
import '../rendering/snap.dart';
import '../rendering/template_canvas.dart';
import '../theme.dart';
import 'export_screen.dart';
import 'paywall_screen.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/grid_style_bar.dart';
import '../widgets/insert_sheets.dart';
import '../widgets/layer_ui.dart';
import '../widgets/layers_sheet.dart';
import '../widgets/slide_strip.dart';
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

  /// A saved project, already loaded into the v4 continuous model
  /// (ProjectStore.loadAsDocument — a v3 file is migrated on read).
  final ContinuousProject? project;
  final ProjectStore? projects;

  /// Injectable for tests (google_fonts needs network/assets); the app uses
  /// the default runtime-fetching resolver.
  final FontResolver fontResolver;

  /// The app's single entitlement seam (owned by `main()`), threaded through so
  /// the asset picker can gate premium frames/stickers. Null in tests and the
  /// draft/blank flow, where a fresh instance reports free — which is the safe
  /// default (a real pro user always arrives with the initialized instance).
  final EntitlementsService? entitlements;

  /// Where [id] loads from; the preview hands over its own (shared cache).
  /// Null = a fresh default store.
  final TemplateStore? store;

  const TemplateScreen({
    super.key,
    this.id,
    this.draft,
    this.project,
    this.projects,
    this.fontResolver = googleFontsResolver,
    this.entitlements,
    this.store,
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
const double _kBottomBarHeight = 224;

/// The bar strip's height while the first-open "Make it yours" panel shows —
/// taller than the toolbar; it eases back to [_kBottomBarHeight] once photos
/// land (or the panel is skipped).
const double _kFirstOpenBarHeight = 292;

/// One point in edit history. Both halves of the document travel together:
/// the continuous [Document] (structure) and the [SlotContent] overlay
/// (per-slot overrides). Snapshotting only the overlay would make structural
/// edits — adding, deleting or reordering a slide — silently un-undoable.
typedef _Snapshot = ({Document doc, SlotContent content});

class _TemplateScreenState extends State<TemplateScreen>
    with WidgetsBindingObserver {
  late final TemplateStore _store = widget.store ?? TemplateStore();
  final _picker = ImagePicker();
  // Gates premium frames/stickers in the asset picker. A fresh fallback reports
  // free (locked), which is safe: the real pro user always arrives with main()'s
  // initialized instance threaded in from the gallery/preview/projects flows.
  late final EntitlementsService _entitlements =
      widget.entitlements ?? EntitlementsService();
  // ONE RepaintBoundary over the whole continuous canvas. The export rasters it
  // once and slices per slide (capturePngSlices), so the seams line up by
  // construction — this replaced a key per panel, where each slide was an
  // independent raster aligned only by eye through the bleed.
  final GlobalKey _canvasKey = GlobalKey();
  // Pan/zoom of the editing surface. Pinch zooms only when nothing is selected
  // (a selected slot's pinch resizes the slot instead); the zoom persists
  // across selection, and slot gestures keep working because hit testing maps
  // through this transform.
  final TransformationController _zoom = TransformationController();
  // True once zoomed past 1x. At 1x panning is locked to horizontal (browse
  // panels without drifting up/down); when zoomed in, panning goes free so you
  // can reach every corner of the magnified panel.
  bool _isZoomed = false;

  /// Resolves the document to edit: a saved project arrives already continuous,
  /// a template (draft or fetched) is migrated to v4 on the way in.
  late Future<Document> _documentLoad;

  /// The resolved document — the editor's source of truth for STRUCTURE
  /// (layers in one coordinate space, slide count, per-slide backgrounds).
  /// Per-slot overrides stay in [_content]. Null only before the load settles,
  /// which is before any editing callback can exist.
  Document? _document;
  Document get _doc => _document!;
  // Remote frame/sticker catalog; empty until loaded (seeds still resolve).
  List<AssetRecord> _catalog = [];
  SlotContent _content = const SlotContent();
  String? _selectedSlot;
  String? _editingSlot;
  // Slide the styling bars and the add menu act on. Unlike the old
  // _focusedPanelId this is not bookkeeping the callbacks have to maintain: on
  // a continuous canvas the focused slide is DERIVED from the selection (see
  // [_focusedSlide]), so there is no per-callback assignment to forget.
  int _lastTouchedSlide = 0;
  // Background contextual bar open (entered via the toolbar's Background
  // button; selecting any element leaves it). Stays across canvas taps so the
  // user can hop between slides while recoloring.
  bool _backgroundMode = false;
  bool _exporting = false;

  // The first-open panel was skipped ("Skip — edit text first").
  bool _firstOpenSkipped = false;

  // Canvas geometry from the last layout, for the slide strip's navigation
  // (the strip lives outside the canvas's LayoutBuilder).
  double _panelWidth = 0;
  double _viewportWidth = 0;

  // Screen-space selection overlay (CanvasSelectionOverlay): the leader link
  // the selected element's chrome box publishes inside its PanelCanvas, and
  // that box's measured size keyed by the gesture target id — the size lands
  // one frame after selection (post-layout), and keying it prevents a frame
  // of wrong-sized chrome when the selection jumps between elements.
  final LayerLink _selectionLink = LayerLink();
  (String, Size)? _selectionBox;

  // The text chrome box the last build DERIVED (see [_chromeBoxFor]). The
  // post-layout measurement is compared against it: a mismatch means the
  // paragraph changed outside a rebuild (a web font finished loading), and
  // only then does the measurement trigger one.
  (String, Size)? _derivedTextBox;

  // Undo/redo: snapshots of BOTH halves of the document — the continuous
  // [Document] (structure: layers, slides, backgrounds) and [_content] (the
  // user's per-slot overrides). Both are immutable copy-on-write, so a snapshot
  // is a pair of cheap shared references and restoring one can't leak partial
  // state. Snapshotting only the content would silently drop structure: adding
  // or reordering a slide would become un-undoable.
  // Selection/zoom are deliberately NOT part of history.
  final List<_Snapshot> _undoStack = [];
  final List<_Snapshot> _redoStack = [];

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
  // Everything the snap needs that CANNOT change while one element is dragged,
  // captured when the gesture starts and dropped with the rest of the drag
  // state on pointer-up. The dragged element's own box is fixed (a drag moves
  // it, it does not resize or restretch it); the other elements are not the one
  // moving; and the screen→template factor is frozen because selecting an
  // element swaps the InteractiveViewer for a static Transform (see
  // [_buildBody]). Recomputing all of it per pointer event meant walking every
  // layer of the document and the render tree on every frame of every drag.
  Rect? _dragBox;
  SnapTargets? _dragTargets;
  double _dragOriginX = 0;
  double _dragThreshold = 0;
  List<double> _guideXs = [];
  List<double> _guideYs = [];

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
      _undoStack.add((doc: _doc, content: _content));
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
    final document = _document;
    if (!_dirty || store == null || document == null) return;
    _saveTimer?.cancel();
    _dirty = false;
    final project = ContinuousProject(
      id: _projectId ??= _newProjectId(),
      name: document.name,
      updatedAt: DateTime.now(),
      document: document,
      content: _content,
      migrated: false,
    );
    store.saveDocument(project).catchError((_) {
      _dirty = true;
      if (mounted && !_saveErrorShown) {
        _saveErrorShown = true;
        showLayerMessage(context, 'Could not save your project.');
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

  /// Applies a STRUCTURAL edit (layers, slides, backgrounds) with undo
  /// recording. Most structural changes are discrete — there is no continuous
  /// gesture that adds a slide — so they omit [coalesce]; the exception is a
  /// live drag like background color, which passes a key so the whole gesture
  /// collapses into one undo step.
  void _editDoc(Document next, {String? coalesce}) {
    _record(coalesce);
    setState(() => _document = next);
  }

  void _undoEdit() {
    if (_undoStack.isEmpty) return;
    _redoStack.add((doc: _doc, content: _content));
    _restore(_undoStack.removeLast());
  }

  void _redoEdit() {
    if (_redoStack.isEmpty) return;
    _undoStack.add((doc: _doc, content: _content));
    _restore(_redoStack.removeLast());
  }

  void _restore(_Snapshot snapshot) {
    _editRunKey = null;
    _dragRaw = null;
    _dragKey = null;
    _dragBox = null;
    _dragTargets = null;
    setState(() {
      _document = snapshot.doc;
      _content = snapshot.content;
      _guideXs = [];
      _guideYs = [];
      // Inline editing can't survive a content swap (the field's controller
      // would show stale text); selection stays unless its element is gone.
      _editingSlot = null;
      if (_selectedSlot != null && _selectionTarget() == null) {
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
    _dragBox = null;
    _dragTargets = null;
    if (_dragRaw == null && _guideXs.isEmpty && _guideYs.isEmpty) return;
    setState(() {
      _dragRaw = null;
      _dragKey = null;
      _guideXs = [];
      _guideYs = [];
    });
  }

  /// Moves element [slotId] by [delta] (template units) with magnetic
  /// alignment guides: the raw offset accumulates per gesture and the stored
  /// offset snaps to canvas/element guides (see snap.dart). Falls back to a
  /// plain move when the element's painted box can't be derived (template-
  /// rotated elements, unmeasured text).
  void _dragSelected(String slotId, Offset delta) {
    final previous = _dragKey == slotId ? _dragRaw : null;
    if (previous == null) _startDrag(slotId);
    final raw = (previous ?? _content.offsetFor(slotId)) + delta;
    var snapped = raw;
    List<double> xs = [], ys = [];
    final box = _dragBox;
    final targets = _dragTargets;
    if (box != null && targets != null) {
      // Scale and rotation are read LIVE, not captured with the rest: two
      // fingers on the element fire onDrag and onScaleChange within the same
      // gesture, so both can move while this runs.
      final result = snapDrag(
        box: box,
        scale: _content.scaleFor(slotId),
        raw: raw,
        targets: targets,
        threshold: _dragThreshold,
        snapEdges: _content.rotationFor(slotId) == 0,
      );
      snapped = result.offset;
      xs = [for (final x in result.guideXs) x + _dragOriginX];
      ys = result.guideYs;
    }
    // A tick the moment the element locks onto a (new) guide — not on every
    // frame it stays snapped.
    if ((xs.isNotEmpty || ys.isNotEmpty) &&
        (!listEquals(xs, _guideXs) || !listEquals(ys, _guideYs))) {
      HapticFeedback.selectionClick();
    }
    setState(() {
      _dragKey = slotId;
      _dragRaw = raw;
      _guideXs = xs;
      _guideYs = ys;
      _content = _content.withOffset(slotId, snapped);
    });
  }

  /// Opens a drag gesture on [slotId]: takes the drag's ONE undo step and
  /// captures the snap inputs that stay fixed for its whole run (see the
  /// [_dragBox] field). The undo step is recorded here rather than coalesced
  /// frame by frame — a drag is one user action, and [_onPointerEnd] already
  /// closes the run, so nothing downstream needs the per-edit bookkeeping.
  void _startDrag(String slotId) {
    _record();
    // Snapping is SLIDE-scoped: the element snaps to the edges and centre of
    // the slide it is in, and to that slide's other elements — not to the
    // whole document (which would put every canvas guide on slide 0) and not
    // to elements two slides away. Everything below is stored in slide-local
    // space; only the guides are shifted back for painting.
    final box = _dragTargetBox(slotId);
    if (box == null) {
      // No derivable box (template-rotated element, unmeasured text): this
      // drag simply moves without snapping. Deciding once per gesture also
      // keeps snapping from appearing halfway through one.
      _dragBox = null;
      _dragTargets = null;
      return;
    }
    final slide = _doc.slideIndexAtX(box.center.dx);
    _dragOriginX = _doc.slideRect(slide).left;
    final toLocal = Offset(-_dragOriginX, 0);
    _dragBox = box.shift(toLocal);
    _dragTargets = SnapTargets.around(Size(_doc.slideWidth, _doc.slideHeight), [
      for (final r in _snapTargets(slotId, slide)) r.shift(toLocal),
    ]);
    _dragThreshold = _kSnapReachPx * _screenToTemplate();
  }

  /// The unrotated layout box (template units, before user offset/scale) of
  /// the element gesture key [key] drags, or null when it can't be derived.
  /// A template rotation disqualifies the element: it pivots on the top-left,
  /// so neither the axis-aligned edges NOR the center match the painted
  /// element. (A user rotation is fine — it pivots on the center, which is
  /// exactly what center guides track.) Text height isn't in the model; it
  /// comes from the measured selection box.
  Rect? _dragTargetBox(String key) {
    // Edge stretch grows the LAYOUT box (top-left pinned), so the snapped
    // box is the model box with the stretched dimensions.
    final fx = _content.stretchXFor(key);
    final fy = _content.stretchYFor(key);
    for (final layer in _allLayers) {
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
  List<Rect> _snapTargets(String movingKey, int slide) {
    final targets = <Rect>[];
    for (final layer in _doc.layersInSlide(slide)) {
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

  /// The slide the styling bars and the add menu act on.
  ///
  /// Derived, not tracked: whatever holds the selected element wins, falling
  /// back to the last slide the user touched. In the panel model this was
  /// _focusedPanelId, which every callback had to remember to assign — a class
  /// of bug that simply doesn't exist once the answer comes from geometry.
  int get _focusedSlide {
    final layer = _selectionLayer();
    if (layer != null) return _doc.slideOf(layer);
    return _lastTouchedSlide.clamp(0, _doc.slideCount - 1);
  }

  /// The layer behind the current selection, if any.
  Layer? _selectionLayer() {
    final id = _selectedSlot;
    if (id == null) return null;
    for (final layer in _doc.layers) {
      final match = switch (layer) {
        ImageLayer l => l.slotId == id,
        TextLayer l => l.slotId == id,
        GridLayer l => l.id == id || l.cells.any((c) => c.slotId == id),
        _ => layer.id == id,
      };
      if (match) return layer;
    }
    return null;
  }

  /// All layers visible to lookups. On a continuous canvas this is simply the
  /// document's layer list — there is no template/overlay split to merge.
  List<Layer> get _allLayers => _doc.layers;

  /// A slot/layer id not already in the document, so a new element never
  /// collides with an existing slot's overrides.
  String _uniqueToken(String base) {
    final used = {for (final l in _allLayers) l.id, ..._doc.slotIds};
    var n = 1;
    while (used.contains('${base}_$n')) {
      n++;
    }
    return '${base}_$n';
  }

  /// Adds a fresh text element to the focused panel, centered, and drops the
  /// user straight into inline editing so they can type immediately.
  void _addTextLayer() {
    final slide = _focusedSlide;
    final token = _uniqueToken('text');
    final bg = _doc.backgroundFor(slide);
    // Pick a default ink that reads against the current background.
    final color = bg.computeLuminance() > 0.5
        ? const Color(0xFF111111)
        : const Color(0xFFFAFAFA);
    final width = _doc.slideWidth * 0.8;
    final layer = TextLayer(
      id: token,
      hidden: false,
      slotId: token,
      x: (_doc.slideWidth - width) / 2,
      y: _doc.slideHeight * 0.42,
      width: width,
      fontFamily: 'Inter',
      fontSize: 88,
      fontWeight: 400,
      color: color,
      alignment: 'center',
    );
    _record();
    setState(() {
      _document = addLayerToSlide(_doc, slide, layer);
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
  void _addImageLayer({
    String? frameAssetId,
    double aspect = 1,
    ImageProvider? image,
  }) {
    final slide = _focusedSlide;
    final token = _uniqueToken('image');
    final width = _doc.slideWidth * 0.5;
    final height = width / (aspect <= 0 ? 1 : aspect);
    final layer = ImageLayer(
      id: token,
      hidden: false,
      slotId: token,
      x: (_doc.slideWidth - width) / 2,
      y: (_doc.slideHeight - height) / 2,
      width: width,
      height: height,
      rotation: 0,
      opacity: 1,
      borderRadius: 0,
      frameAssetId: frameAssetId,
    );
    _record();
    setState(() {
      _document = addLayerToSlide(_doc, slide, layer);
      if (image != null) _content = _content.withImage(token, image);
      _selectedSlot = token;
      _editingSlot = null;
      _backgroundMode = false;
    });
    if (image == null) _pickImage(token);
  }

  /// A grid id and its cell slot ids unused by the template or anything the
  /// user added, checked as a set so none can collide with existing slots.
  (String, List<String>) _uniqueGridIds(int cellCount) {
    final used = {for (final l in _allLayers) l.id, ..._doc.slotIds};
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
    GridPreset preset,
    String gridId,
    List<String> cellIds,
  ) {
    final inset = _doc.slideWidth * 0.08;
    return GridLayer(
      id: gridId,
      hidden: false,
      x: inset,
      y: inset,
      width: _doc.slideWidth - 2 * inset,
      height: _doc.slideHeight - 2 * inset,
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
  void _addGridLayer(GridPreset preset) {
    final slide = _focusedSlide;
    final (gridId, cellIds) = _uniqueGridIds(preset.cells.length);
    final layer = _buildGridLayer(preset, gridId, cellIds);
    _record();
    setState(() {
      _document = addLayerToSlide(_doc, slide, layer);
      _selectedSlot = cellIds.first;
      _editingSlot = null;
      _backgroundMode = false;
    });
  }

  /// Adds [preset] with [images] already in its cells (in pick order) as ONE
  /// undo step — the photos-first flow's landing point. Nothing ends up
  /// selected: the result is the collage itself, ready to fine-tune.
  void _insertFilledGrid(GridPreset preset, List<ImageProvider> images) {
    final slide = _focusedSlide;
    final (gridId, cellIds) = _uniqueGridIds(preset.cells.length);
    final layer = _buildGridLayer(preset, gridId, cellIds);
    _record();
    setState(() {
      _document = addLayerToSlide(_doc, slide, layer);
      var next = _content;
      for (var i = 0; i < cellIds.length && i < images.length; i++) {
        next = next.withImage(cellIds[i], images[i]);
      }
      _content = next;
      _selectedSlot = null;
      _editingSlot = null;
      _backgroundMode = false;
    });
  }

  /// Adds a sticker sized to its own aspect, centered, and selects it (its
  /// layer id doubles as the gesture/selection key — stickers carry no slot).
  void _addStickerLayer(AssetChoice asset) {
    final slide = _focusedSlide;
    final token = _uniqueToken('sticker');
    final width = _doc.slideWidth * 0.4;
    final height = width / (asset.aspect <= 0 ? 1 : asset.aspect);
    final layer = StickerLayer(
      id: token,
      hidden: false,
      assetId: asset.id,
      x: (_doc.slideWidth - width) / 2,
      y: (_doc.slideHeight - height) / 2,
      width: width,
      height: height,
    );
    _record();
    setState(() {
      _document = addLayerToSlide(_doc, slide, layer);
      _selectedSlot = token;
      _editingSlot = null;
      _backgroundMode = false;
    });
  }

  /// Appends an empty slide and focuses it. On a continuous canvas this is
  /// just a wider document — appending reflows nothing (see addSlide).
  void _addPanel() {
    _record();
    setState(() {
      _document = addSlide(_doc);
      _lastTouchedSlide = _doc.slideCount - 1;
      _selectedSlot = null;
      _editingSlot = null;
    });
  }

  /// Slide management for slide [index] — reorder or delete. Reached by
  /// long-pressing its carousel dot; adding is the toolbar's Panel button.
  Future<void> _showSlideActions(int index) async {
    final count = _doc.slideCount;
    if (count <= 1) return;
    Widget row(
      Key key,
      String label,
      IconData icon,
      String value,
      BuildContext sheetContext, {
      Color? color,
    }) => InkWell(
      key: key,
      onTap: () => Navigator.pop(sheetContext, value),
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.colors.rule)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: AppType.label.copyWith(color: color)),
            ),
            Icon(icon, size: 20, weight: 300, color: color),
          ],
        ),
      ),
    );
    final action = await showLayerSheet<String>(
      context: context,
      titleWidget: Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'Slide '),
            TextSpan(
              text: twoDigits(index + 1),
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
            TextSpan(
              text: ' of ${twoDigits(count)}',
              style: TextStyle(color: context.colors.inkMuted),
            ),
          ],
        ),
        style: AppType.title(26),
      ),
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Hairline(),
          if (index > 0)
            row(
              const ValueKey('slide-move-left'),
              'Move left',
              Symbols.arrow_back,
              'left',
              sheetContext,
            ),
          if (index < count - 1)
            row(
              const ValueKey('slide-move-right'),
              'Move right',
              Symbols.arrow_forward,
              'right',
              sheetContext,
            ),
          row(
            const ValueKey('slide-delete'),
            'Delete slide',
            Symbols.delete,
            'delete',
            sheetContext,
            color: context.colors.rouge,
          ),
          const SizedBox(height: 10),
          Text(
            'Its elements are deleted with it.',
            style: AppType.caption.copyWith(color: context.colors.inkSoft),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'left':
        _moveSlide(index, index - 1);
      case 'right':
        _moveSlide(index, index + 1);
      case 'delete':
        _deleteSlide(index);
    }
  }

  /// Moves a slide, carrying its content as a group (see reorderSlide) — what
  /// makes independent pages feel native on a continuous canvas.
  void _moveSlide(int from, int to) {
    _record();
    setState(() {
      _document = reorderSlide(_doc, from, to);
      _lastTouchedSlide = to;
      _selectedSlot = null;
      _editingSlot = null;
    });
  }

  void _deleteSlide(int index) {
    // An element CROSSING a cut belongs to no single slide, so removeSlide
    // leaves it where it is instead of tearing a panorama in half. Say so, or
    // the leftover reads as a bug.
    final crossing = spanningLayers(_doc).isNotEmpty;
    _record();
    setState(() {
      _document = removeSlide(_doc, index);
      _lastTouchedSlide = index.clamp(0, _doc.slideCount - 1);
      _selectedSlot = null;
      _editingSlot = null;
    });
    if (crossing && mounted) {
      showLayerMessage(context, 'Elements crossing slides were kept.');
    }
  }

  Future<void> _insertGrid() async {
    final preset = await showGridPresetSheet(context);
    if (preset == null || !mounted) return;
    _addGridLayer(preset);
  }

  Future<void> _insertAsset() async {
    final isPro = _entitlements.isPro.value;
    final asset = await showAssetPickerSheet(context, _catalog, isPro: isPro);
    if (asset == null || !mounted) return;
    // A free user who picks a paid-only asset lands on the paywall instead of
    // inserting it; the badge already told them it was locked.
    if (asset.premium && !_entitlements.isPro.value) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PaywallScreen(entitlements: _entitlements),
        ),
      );
      return;
    }
    if (asset.isFrame) {
      // A frame is not a layer of its own — it decorates a photo slot, so
      // inserting one creates a framed image slot and opens the gallery.
      _addImageLayer(frameAssetId: asset.id, aspect: asset.aspect);
    } else {
      _addStickerLayer(asset);
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
    _ => <String>{},
  };

  /// Deletes a user-added layer (template layers can only be hidden, not
  /// removed). Clears the selection if it pointed at the removed element —
  /// including a grid's cells and a sticker's layer-id key.
  void _removeLayer(Layer layer) {
    _record();
    setState(() {
      _document = removeLayer(_doc, layer.id);
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
  void _deleteSelected(String targetId) {
    Layer? target;
    for (final layer in _allLayers) {
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
    // Delete now REMOVES any element. The panel model had to distinguish
    // "user-added" (removable) from "template" (hide-only) layers, because the
    // template was immutable and lived outside the user's overlay. The document
    // owns every layer, so that split is gone — and undo covers a mistake.
    // Hiding is still available from the layers sheet.
    _removeLayer(target);
  }

  /// Duplicates the selected element as a user-added layer on the focused
  /// panel, one undo step, and selects the copy. Styling overrides (font,
  /// color, grid spacing, …) are BAKED into the copied layer — the copy then
  /// owns them — while content (text, photos) and transform overrides are
  /// carried over, with the offset nudged so the copy is visibly its own
  /// element. Template layers duplicate into added layers; the template
  /// itself is never touched. [targetId] is the gesture target id, like
  /// [_deleteSelected]'s.
  void _duplicateSelected(String targetId) {
    Layer? source;
    for (final layer in _allLayers) {
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
    final nudge = Offset(_doc.slideWidth * 0.04, _doc.slideWidth * 0.04);

    final String selectKey;
    // Snapshot BEFORE the switch: it already writes _document, so recording
    // afterwards would capture the MUTATED document and undo would do nothing.
    _record();
    SlotContent next;
    switch (source) {
      case TextLayer l:
        final token = _uniqueToken('text');
        selectKey = token;
        next = _content;
        _document = appendLayer(
          _doc,
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
        final token = _uniqueToken('image');
        selectKey = token;
        next = _content;
        _document = appendLayer(
          _doc,
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
        final token = _uniqueToken('sticker');
        selectKey = token;
        next = _content;
        _document = appendLayer(
          _doc,
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
        final (gridId, cellIds) = _uniqueGridIds(l.cells.length);
        selectKey = cellIds.first;
        next = _content;
        _document = appendLayer(
          _doc,
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
    setState(() {
      _content = next;
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
      // Resuming: already continuous (migrated on read if the file was v3).
      _projectId = project.id;
      _content = project.content;
      _documentLoad = Future.value(project.document);
    } else if (widget.draft != null) {
      _documentLoad = Future.value(_documentFrom(widget.draft!));
    } else {
      _documentLoad = _store
          .loadTemplate(widget.id!)
          .then((r) => _documentFrom(r.template));
    }
    // Saving needs the document outside the FutureBuilder; load errors are
    // already surfaced by build(). Block body: an arrow would type the chain
    // as Future<Document>, which the void-returning onError then violates.
    _documentLoad.then((d) {
      _document = d;
    }, onError: (_) {});
    _loadCatalog();
  }

  /// A published template (or a blank draft) folded into the continuous model.
  /// Templates are authored as panels; this is the same reflow the project
  /// store does on read, with no user overlay yet.
  Document _documentFrom(Template template) =>
      migrateToV4(template, const SlotContent()).document;

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
  Future<void> _insertPhotos() async {
    final files = await _picker.pickMultiImage(maxWidth: 2160);
    if (files.isEmpty) return;
    final bytesList = <Uint8List>[
      for (final file in files) await file.readAsBytes(),
    ];
    if (!mounted) return;
    if (bytesList.length == 1) {
      final image = await _persistImage(bytesList.single);
      if (!mounted) return;
      _addImageLayer(image: image);
      return;
    }
    // Previews stay in memory; the photos are only persisted to project
    // files after the user commits to a layout (cancelling leaves no files).
    final preset = await showLayoutPickerSheet(
      context,
      photos: [for (final bytes in bytesList) MemoryImage(bytes)],
      canvasAspect: _doc.slideWidth / _doc.slideHeight,
    );
    if (preset == null || !mounted) return;
    final images = <ImageProvider>[
      for (final bytes in bytesList) await _persistImage(bytes),
    ];
    if (!mounted) return;
    _insertFilledGrid(preset, images);
  }

  /// Tapping a slot selects it (shows the handles for move/resize). A text
  /// slot's second tap starts inline editing. Image slots and grid cells never
  /// edit — their photo icon opens the gallery instead (see [_onPickImage]).
  void _handleSlotTap(String slotId) {
    final isText = _allLayers.any((l) => l is TextLayer && l.slotId == slotId);
    final wasSelected = _selectedSlot == slotId;
    if (!wasSelected) {
      // Same tick the snap/rotation locks use — selection is a physical event.
      HapticFeedback.selectionClick();
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
    int slideCount,
    double panelWidth,
    double viewportWidth,
  ) {
    setState(() {
      _lastTouchedSlide = index;
      _selectedSlot = null;
      _editingSlot = null;
    });
    // Mirror the strip's layout: 16px of padding around ONE continuous canvas
    // whose slides tile edge to edge. There is no per-panel padding to account
    // for — that belonged to the Row of PanelCanvas this replaced, and leaving
    // it here shifted every hop by 12px MORE than the last (dot 6 landed most
    // of a slide off), while also letting maxTx scroll past the document end.
    final stripWidth = 32 + panelWidth * slideCount;
    final maxTx = (stripWidth - viewportWidth).clamp(0.0, double.infinity);
    final tx = (index * panelWidth).clamp(0.0, maxTx);
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
  void _showLayersSheet() {
    final slide = _focusedSlide;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        // A StatefulBuilder so reorder/hide/remove repaint the sheet rows; the
        // screen keeps the canonical state (_content) and rebuilds the canvas.
        return StatefulBuilder(
          builder: (context, setSheetState) {
            // Recompute each rebuild so an added/removed layer shows up live.
            // LayersSheet still speaks Panel; on a continuous canvas the
            // focused slide IS that view, built fresh each rebuild so an
            // added/removed layer shows up live.
            final panel = Panel(
              id: 'slide_$slide',
              backgroundColor: _doc.backgroundFor(slide),
              layers: _doc.layersInSlide(slide),
            );
            return LayersSheet(
              panel: panel,
              content: _content,
              assetCatalog: _catalog,
              // Only the user's own added layers can be deleted; template
              // layers can be hidden but not removed.
              // Every layer is removable now: the document owns them all, so
              // there is no immutable-template subset to protect.
              removableLayerIds: {for (final l in panel.layers) l.id},
              onRemove: (layer) {
                _removeLayer(layer);
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
              // The stack lives in the document's layer list, not in a
              // SlotContent override — see [reorderLayersInSlide]. Writing the
              // override instead was a silent no-op: the sheet read its own
              // list back through it and looked reordered while the canvas,
              // which paints doc.layers directly, never moved.
              onReorderList: (orderedIds) {
                _editDoc(reorderLayersInSlide(_doc, slide, orderedIds));
                setSheetState(() {});
              },
            );
          },
        );
      },
    );
  }

  /// Export: raster the whole document NOW (the canvas must be painted, and
  /// a route under another one isn't), then hand the raster to the export
  /// screen, which cuts and encodes the slides with progress and offers
  /// Share / Save to Photos. Deselects first: the handles (and the inline
  /// editor's cursor) live inside the boundary and would end up in the PNG.
  Future<void> _openExport() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    DocumentRaster? raster;
    try {
      if (_selectedSlot != null || _editingSlot != null) {
        setState(() {
          _selectedSlot = null;
          _editingSlot = null;
        });
      }
      await WidgetsBinding.instance.endOfFrame;
      // ONE raster of the continuous canvas, sliced per slide later: the
      // seams line up by construction.
      raster = await rasterDocument(
        _canvasKey,
        _doc,
        targetSlideWidth: _doc.slideWidth,
      );
    } catch (e) {
      if (mounted) showLayerMessage(context, 'Export failed: $e');
      return;
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
    if (!mounted) {
      raster.dispose();
      return;
    }
    // Whatever is on screen is what gets saved: the footnote promises it.
    _saveProject();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExportScreen(
          raster: raster!,
          document: _doc,
          projectSaved: widget.projects != null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Document>(
      future: _documentLoad,
      builder: (context, snapshot) {
        final document = snapshot.data;
        // Read the keyboard/safe-area insets HERE, above the Scaffold: the
        // Scaffold consumes the keyboard inset and hands its body a MediaQuery
        // with viewInsets.bottom == 0, so reading it inside _buildBody would
        // always see zero.
        final media = MediaQuery.of(context);
        final keyboardInset = media.viewInsets.bottom;
        final safeBottom = media.viewPadding.bottom;
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 60,
            titleSpacing: 0,
            centerTitle: false,
            leading: const BackButton(),
            shape: Border(bottom: BorderSide(color: context.colors.rule)),
            title: document == null
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _doc.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.serif(17, height: 1.15),
                      ),
                      const SizedBox(height: 2),
                      Eyebrow(
                        _statusLine(),
                        size: 11,
                        color: context.colors.inkSoft,
                      ),
                    ],
                  ),
            actions: [
              if (document != null) ...[
                IconButton(
                  icon: const Icon(Symbols.undo),
                  tooltip: 'Undo',
                  onPressed: _undoStack.isEmpty ? null : () => _undoEdit(),
                ),
                IconButton(
                  icon: const Icon(Symbols.redo),
                  tooltip: 'Redo',
                  onPressed: _redoStack.isEmpty ? null : () => _redoEdit(),
                ),
                // Export is the flow's finish line — a labeled button, not
                // one more icon.
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 12),
                  child: Center(
                    child: CompactButton(
                      label: 'Export',
                      onPressed: (_exporting || _awaitingPhotos)
                          ? null
                          : () => _openExport(),
                      child: _exporting
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: context.colors.inkSoft,
                              ),
                            )
                          : null,
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
            // Empty photo slots show their fill number (and read dark under
            // light text) — editor-only hints, see PhotoSlotHints.
            ConnectionState.done => PhotoSlotHints(
              numbers: fillNumbers(_doc),
              dark: slotsUnderLightText(_doc),
              child: _buildBody(keyboardInset, safeBottom),
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        );
      },
    );
  }

  /// The TextLayer of the currently selected slot, or null when nothing —
  /// or a non-text slot — is selected. Drives the styling bar.
  TextLayer? _selectedTextLayer() {
    final slot = _selectedSlot;
    if (slot == null) return null;
    for (final layer in _allLayers) {
      if (layer is TextLayer && layer.slotId == slot) return layer;
    }
    return null;
  }

  /// The ImageLayer of the currently selected slot (or null). Grid cells are
  /// not ImageLayers, so a selected cell falls through to the grid bar.
  ImageLayer? _selectedImageLayer() {
    final slot = _selectedSlot;
    if (slot == null) return null;
    for (final layer in _allLayers) {
      if (layer is ImageLayer && layer.slotId == slot) return layer;
    }
    return null;
  }

  /// The StickerLayer selected by its layer id (or null).
  StickerLayer? _selectedStickerLayer() {
    final slot = _selectedSlot;
    if (slot == null) return null;
    for (final layer in _allLayers) {
      if (layer is StickerLayer && layer.id == slot) return layer;
    }
    return null;
  }

  /// The GridLayer owning the selected cell (or null). Drives the grid bar and
  /// tells us a grid cell — not a plain image/text slot — is selected.
  GridLayer? _selectedGridLayer() {
    final slot = _selectedSlot;
    if (slot == null) return null;
    for (final layer in _allLayers) {
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
  (String, double, Size, bool)? _selectionTarget() {
    final slot = _selectedSlot;
    if (slot == null) return null;
    for (final layer in _allLayers) {
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

  /// The padded chrome box the overlay draws for [target] — the same box
  /// _leaderChromed lays out around the element, in leader-local units.
  ///
  /// Images, stickers and grids lay out to exactly base × stretch, so the box
  /// is DERIVED here, in the very build that applies the resize: the white
  /// ring and its handles then move on the same frame as the content. Reading
  /// it back from the measured leader instead (as text must) costs a frame —
  /// the measurement is post-layout and setStates — and that lag was visible
  /// as the photo/grid shrinking out from under a ring still on its old size.
  ///
  /// Text hugs its glyphs, so its box comes from laying the paragraph out
  /// here ([measureTextLayer], the same layout its Text does) — reading it
  /// back from the leader made the handles trail every resize and re-wrap by
  /// a frame. [textGlyphs] is that measurement for a text [target].
  Size? _chromeBoxFor(
    (String, double, Size, bool) target,
    double viewScale,
    Size? textGlyphs,
  ) {
    final (id, _, base, isText) = target;
    // Must match _leaderChromed's padding exactly (kChromePad over the chrome
    // scale, which folds in the canvas zoom), or the ring misses the edges.
    final pad = kChromePad / (_content.scaleFor(id) * viewScale);
    if (isText) {
      final glyphs = textGlyphs;
      if (glyphs == null) return null;
      final box = Size(glyphs.width + 2 * pad, glyphs.height + 2 * pad);
      _derivedTextBox = (id, box);
      return box;
    }
    return Size(
      base.width * _content.stretchXFor(id) + 2 * pad,
      base.height * _content.stretchYFor(id) + 2 * pad,
    );
  }

  /// Screen px → template px for the canvas-wide gesture surface, which
  /// lives outside the FittedBox/zoom transforms. The export boundary sits in
  /// template units, so its transform-to-global scale IS the composed
  /// FittedBox × zoom factor (both uniform). Evaluated at gesture start
  /// (post-layout, and the zoom is frozen while a slot is selected).
  double _screenToTemplate() {
    final box = _canvasKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return 1.0;
    final scale = _planarScale(box.getTransformTo(null));
    return scale > 0 ? 1 / scale : 1.0;
  }

  /// The 2D scale of a paint transform — NOT Matrix4.getMaxScaleOnAxis, which
  /// takes the max over X, Y **and Z**. The composed transform above includes
  /// the FittedBox's, and RenderFittedBox scales X and Y while leaving Z at 1
  /// — so getMaxScaleOnAxis returned that 1 for every canvas drawn smaller
  /// than life size, which is the normal editor view. The canvas-wide drag
  /// surface then skipped its screen→template conversion entirely: the element
  /// crawled at the fitted scale (~35% of the finger) instead of tracking it,
  /// and the snap threshold shrank by the same factor.
  ///
  /// The zoom matrix alone is NOT affected — InteractiveViewer scales all
  /// three axes — which is why `viewScale` reads it with getMaxScaleOnAxis and
  /// is correct. Only the composed transform needs this.
  static double _planarScale(Matrix4 m) {
    final s = m.storage;
    return math.sqrt(
      math.max(s[0] * s[0] + s[1] * s[1], s[4] * s[4] + s[5] * s[5]),
    );
  }

  Widget _buildBody(double keyboardInset, double safeBottom) {
    final slideCount = _doc.slideCount;
    final bottomBar = _buildBottomBar();
    // Constant height for the bar strip (incl. the home-indicator inset), so
    // the canvas area is a fixed size regardless of which bar shows.
    final barArea =
        (_showFirstOpen ? _kFirstOpenBarHeight : _kBottomBarHeight) +
        safeBottom;

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
              color: context.colors.table,
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
                  // own 16px on each side. Either way, never wider than the
                  // canvas actually paints at the strip's height (32px vertical
                  // padding): a tall canvas is height-limited, and reserving
                  // more width would only letterbox the FittedBox — bands that
                  // read as a huge gap between panels.
                  final aspect = _doc.slideWidth / _doc.slideHeight;
                  final panelWidth = math.min(
                    slideCount == 1
                        ? constraints.maxWidth - 32
                        : constraints.maxWidth * 0.82,
                    (canvasHeight - 32) * aspect,
                  );
                  // Centring is the strip's job, not the viewer's: the surface
                  // below lays the strip out `constrained: false`, which aligns
                  // it TOP-LEFT. So whenever the content is narrower than the
                  // viewport the padding has to absorb the slack, or the canvas
                  // hugs the left edge. That only happens when the canvas is
                  // limited by HEIGHT instead of width — a 9:16 story on a tall
                  // phone. Portrait and square fill the width and look fine
                  // either way, which is exactly why this kept regressing.
                  final contentWidth = panelWidth * slideCount;
                  // The slide strip (outside this builder) navigates with the
                  // same geometry; remember it for its taps.
                  _panelWidth = panelWidth;
                  _viewportWidth = constraints.maxWidth;
                  final hPad = math.max(
                    16.0,
                    (constraints.maxWidth - contentWidth) / 2,
                  );
                  // How far out you can pinch. The old 0.25 was a leftover from
                  // the panel era, where zooming out did little; on a continuous
                  // canvas it is how you step BACK from the work — to judge a
                  // composition, or to see a whole carousel at once. 0.25 is
                  // the value this screen always declared; it simply never
                  // worked (see boundaryMargin below), and it turns out to be
                  // the right feel once it does. Below that the canvas reads as
                  // a stamp, so the deeper zoom is reserved for the case that
                  // needs it: a carousel too long to fit any other way (a fixed
                  // floor caps a panorama at a few slides however long it is).
                  final stripWidth = contentWidth + hPad * 2;
                  final minZoom = math
                      .min(0.25, (constraints.maxWidth / stripWidth) * 0.9)
                      .clamp(0.08, 0.25);
                  // minScale ALONE does nothing here. InteractiveViewer floors
                  // the scale at `viewport / boundaryRect` BEFORE it clamps to
                  // minScale (see _matrixScale), so a finite boundaryMargin is
                  // what actually decides how far out you can pinch: with the
                  // old EdgeInsets.all(64) the strip is viewport-tall, giving a
                  // real floor near 0.94 — the editor barely zoomed out at all.
                  // So the margin is derived FROM minZoom: pad by exactly what
                  // the child needs to still cover the viewport at that scale.
                  // (Infinite margins would also work, but they unbound panning
                  // and the canvas can be dragged off into nowhere.)
                  final margin = math.max(
                    (constraints.maxWidth / minZoom - stripWidth) / 2,
                    (constraints.maxHeight / minZoom - canvasHeight) / 2,
                  );
                  // With nothing selected the surface is an InteractiveViewer
                  // (pinch zoom + pan). With a slot selected it becomes a STATIC
                  // transform — same matrix and layout, but NO gesture detector:
                  // InteractiveViewer's detector stays opaque even when pan/scale
                  // are off and would otherwise fight the selection handles.
                  final interacting =
                      _selectedSlot != null || _editingSlot != null;
                  // The chrome sizes itself against this so the handles stay
                  // grabbable when the canvas is pinched out — see
                  // [PanelCanvas.viewScale]. Reading `_zoom.value` in build is
                  // enough precisely BECAUSE of `interacting` above: selecting
                  // an element swaps the InteractiveViewer for a static
                  // Transform, so the zoom is frozen for as long as there is
                  // any chrome on screen. No per-frame listener needed.
                  final viewScale = _zoom.value.getMaxScaleOnAxis();
                  // Selection chrome + ring/handle gestures float in an overlay
                  // ABOVE the strip (unclipped by the canvas, so handles work
                  // past its edge). While editing text the legacy in-canvas
                  // chrome is used instead — the overlay would sit on top of
                  // the inline TextField.
                  final target = _editingSlot == null
                      ? _selectionTarget()
                      : null;
                  // ONE continuous canvas for the whole document. This
                  // replaced a Row of PanelCanvas — one per slide, each echoing
                  // its neighbours through the bleed. With every layer in a
                  // single coordinate space a panorama simply spans the slides,
                  // so there is nothing to echo and no seam to align by eye.
                  final strip = SizedBox(
                    height: canvasHeight,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: hPad,
                        vertical: 16,
                      ),
                      child: SizedBox(
                        width: contentWidth,
                        child: CanvasView(
                          exportKey: _canvasKey,
                          document: _doc,
                          content: _content,
                          fontResolver: widget.fontResolver,
                          assetCatalog: _catalog,
                          // The editor is the only place the cut lines show.
                          showCutGuides: true,
                          viewScale: viewScale,
                          guideXs: _guideXs,
                          guideYs: _guideYs,
                          selectedSlotId: _selectedSlot,
                          editingSlotId: _editingSlot,
                          onSlotTap: (slotId) => _handleSlotTap(slotId),
                          onPickImage: (slotId) => _onPickImage(slotId),
                          onSlotDelete: (slotId) => _deleteSelected(slotId),
                          onCanvasTap: () => setState(() {
                            _selectedSlot = null;
                            _editingSlot = null;
                          }),
                          onTextChanged: (slotId, value) => _edit(
                            _content.withText(slotId, value),
                            coalesce: 'text:$slotId',
                          ),
                          onSlotDrag: (slotId, delta) =>
                              _dragSelected(slotId, delta),
                          onSlotScale: (slotId, scale) => _edit(
                            _content.withScale(slotId, scale),
                            coalesce: 'scale:$slotId',
                          ),
                          onSlotRotate: _rotateSelected,
                          onSlotEdgeResize: _edgeResizeSelected,
                          onGridFractions: (gridId, columns, fractions) {
                            _record('fractions:$gridId');
                            setState(() {
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
                          selectionLink: target == null ? null : _selectionLink,
                          // Only TEXT needs measuring — see _chromeBoxFor. For
                          // every other layer the measurement is both redundant
                          // and harmful: its post-frame setState made the chrome
                          // trail the content by a frame on every resize.
                          // The chrome itself is derived in build; the
                          // measurement only feeds the drag snap's text box
                          // and resyncs the chrome when the paragraph changed
                          // without a rebuild (a font finished loading).
                          onSelectionSize: (target == null || !target.$4)
                              ? null
                              : (sz) {
                                  final measured = (target.$1, sz);
                                  _selectionBox = measured;
                                  if (mounted && _derivedTextBox != measured) {
                                    setState(() {});
                                  }
                                },
                        ),
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
                          minScale: minZoom,
                          maxScale: 4,
                          boundaryMargin: EdgeInsets.all(math.max(64, margin)),
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
                      _dragSelected(slotId, delta);
                  void scaleSelected(String slotId, double scale) => _edit(
                    _content.withScale(slotId, scale),
                    coalesce: 'scale:$slotId',
                  );
                  // Text geometry, laid out HERE (this context sits where the
                  // canvas' slots do: same DefaultTextStyle and MediaQuery) so
                  // the chrome and the edge-drag limits track the paragraph on
                  // the very frame it changes.
                  final textLayer = target != null && target.$4
                      ? _selectedTextLayer()
                      : null;
                  final textMeasure = textLayer == null
                      ? null
                      : measureTextLayer(
                          context,
                          textLayer,
                          _content,
                          widget.fontResolver,
                        );
                  final chromeBox = target == null
                      ? null
                      : _chromeBoxFor(target, viewScale, textMeasure?.size);
                  Widget body = scroll;
                  if (target != null && chromeBox != null) {
                    body = Stack(
                      clipBehavior: Clip.none,
                      children: [
                        scroll,
                        Positioned.fill(
                          child: CanvasSelectionOverlay(
                            link: _selectionLink,
                            size: chromeBox,
                            targetId: target.$1,
                            currentScale: _content.scaleFor(target.$1),
                            currentRotation: _content.rotationFor(target.$1),
                            templateRotation: target.$2,
                            currentStretchX: _content.stretchXFor(target.$1),
                            currentStretchY: _content.stretchYFor(target.$1),
                            baseSize: target.$3,
                            verticalEdges: !target.$4,
                            hugAlignment: textLayer == null
                                ? null
                                : textHugAlignment(textLayer, _content),
                            minEdgeFactor: textLayer == null
                                ? null
                                : textMinEdgeFactor(textLayer),
                            maxEdgeFactor: textLayer == null
                                ? null
                                : textMaxEdgeFactor(textLayer, textMeasure!),
                            viewScale: viewScale,
                            onDrag: dragSelected,
                            onScaleChange: scaleSelected,
                            onRotateChange: _rotateSelected,
                            onEdgeResize: _edgeResizeSelected,
                            onDelete: (id) => _deleteSelected(id),
                            // Taps on the element's body that the overlay's
                            // widened corner/edge zones claim (small text:
                            // most of it) — same select/edit path as a tap
                            // that reaches the canvas.
                            onTap: _handleSlotTap,
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
                      screenToTemplate: () => _screenToTemplate(),
                      onDrag: dragSelected,
                      onScaleChange: scaleSelected,
                      onRotateChange: _rotateSelected,
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
          // (resizeToAvoidBottomInset pushes it up). Shorter bars leave the
          // table showing above them.
          ColoredBox(
            color: context.colors.table,
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              height: barArea,
              width: double.infinity,
              child: Column(
                children: [
                  Expanded(
                    // Keyed per bar (see _buildBottomBar), so swapping
                    // selection cross-fades bars while slider drags inside one
                    // bar never re-animate.
                    child: AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, 0.06),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.bottomCenter,
                        children: [...previous, ?current],
                      ),
                      child: bottomBar,
                    ),
                  ),
                  Container(height: safeBottom, color: context.colors.paper),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Photo slots still waiting for a photo, in fill order.
  List<PhotoSlot> _emptyPhotoSlots() => [
    for (final slot in imageSlotsInFillOrder(_doc))
      if (_content.imageFor(slot.slotId) == null) slot,
  ];

  /// A template session that has photo frames and not one photo yet: the
  /// editor opens on its numbered placeholders, Export waits for a photo.
  /// (Blank canvases and resumed projects are never held back.)
  bool get _awaitingPhotos {
    if (widget.id == null) return false;
    final slots = imageSlotsInFillOrder(_doc);
    return slots.isNotEmpty &&
        slots.every((s) => _content.imageFor(s.slotId) == null);
  }

  /// The "Make it yours" panel replaces the strip + toolbar on first open.
  bool get _showFirstOpen =>
      _awaitingPhotos &&
      !_firstOpenSkipped &&
      _selectedSlot == null &&
      _editingSlot == null &&
      !_backgroundMode;

  /// "Add N photos": one multi-pick that fills the empty frames in fill order
  /// (the numbers on the placeholders) — one undo step for all of them.
  Future<void> _fillPhotosInOrder() async {
    final empty = _emptyPhotoSlots();
    if (empty.isEmpty) return;
    final List<XFile> files;
    if (empty.length == 1) {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2160,
      );
      files = file == null ? [] : [file];
    } else {
      files = await _picker.pickMultiImage(maxWidth: 2160, limit: empty.length);
    }
    if (files.isEmpty || !mounted) return;
    var next = _content;
    for (var i = 0; i < files.length && i < empty.length; i++) {
      final image = await _persistImage(await files[i].readAsBytes());
      next = next.withImage(empty[i].slotId, image);
    }
    if (!mounted) return;
    HapticFeedback.selectionClick();
    _edit(next);
  }

  /// The top bar's eyebrow: where you are and that the work is safe.
  String _statusLine() {
    if (_awaitingPhotos) {
      final total = imageSlotsInFillOrder(_doc).length;
      return '0 of $total ${total == 1 ? 'photo' : 'photos'}';
    }
    final count = _doc.slideCount;
    final where =
        'Slide ${twoDigits(_focusedSlide + 1)} of ${twoDigits(count)}';
    return widget.projects != null && _projectId != null
        ? '$where · Saved'
        : where;
  }

  /// A slot id as a label: "hero_image" → "hero image". Auto-generated ids
  /// (text_1712…) read as plain "text".
  static String _humanize(String slotId) {
    final words = slotId.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    final generated = RegExp(r'^(text|image|grid|sticker) ?\d{6,}');
    if (generated.hasMatch(words)) return words.split(' ').first;
    return words;
  }

  /// The bar strip under the canvas. Home state is the [EditorToolbar]
  /// (insert/layers/background); a selected element swaps in its own
  /// contextual bar with an explicit title and Done, so the strip never
  /// changes silently: text styling, grid spacing/corners, photo actions,
  /// sticker actions — and background colors while [_backgroundMode] is on.
  Widget _buildBottomBar() {
    if (_showFirstOpen) {
      return _MakeItYours(
        key: const ValueKey('bar-first-open'),
        count: imageSlotsInFillOrder(_doc).length,
        onAdd: _fillPhotosInOrder,
        onSkip: () => setState(() => _firstOpenSkipped = true),
      );
    }
    final textLayer = _selectedTextLayer();
    if (textLayer != null) {
      final weight =
          _content.weightFor(textLayer.slotId) ?? textLayer.fontWeight;
      return TextStyleBar(
        key: ValueKey('bar-text-${textLayer.slotId}'),
        currentFont: _content.fontFor(textLayer.slotId) ?? textLayer.fontFamily,
        currentColor: _content.colorFor(textLayer.slotId) ?? textLayer.color,
        currentAlignment:
            _content.alignmentFor(textLayer.slotId) ?? textLayer.alignment,
        isBold: weight >= 700,
        isPro: _entitlements.isPro.value,
        onFont: (font) {
          // A free user picking a paid font lands on the paywall instead of
          // applying it; the "PRO" badge already flagged it. Fonts already in
          // the template render for everyone — only picking a new one is gated.
          if (kPremiumFonts.contains(font) && !_entitlements.isPro.value) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PaywallScreen(entitlements: _entitlements),
              ),
            );
            return;
          }
          _edit(_content.withFont(textLayer.slotId, font));
        },
        onColor: (color) => _edit(
          _content.withColor(textLayer.slotId, color),
          coalesce: 'color:${textLayer.slotId}',
        ),
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
        onDuplicate: () => _duplicateSelected(textLayer.slotId),
        onDelete: () => _deleteSelected(textLayer.slotId),
        onDone: _closeContextBar,
        slotLabel: _humanize(textLayer.slotId),
      );
    }
    final gridLayer = _selectedGridLayer();
    if (gridLayer != null) {
      final g = gridLayer;
      final minSide = g.width < g.height ? g.width : g.height;
      return GridStyleBar(
        key: ValueKey('bar-grid-${g.id}'),
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
        onDuplicate: () => _duplicateSelected(g.id),
        onDelete: () => _deleteSelected(g.id),
        onDone: _closeContextBar,
      );
    }
    final imageLayer = _selectedImageLayer();
    if (imageLayer != null) {
      final number = fillNumbers(_doc)[imageLayer.slotId];
      final photo = _content.imageFor(imageLayer.slotId);
      return ContextBarShell(
        key: ValueKey('bar-photo-${imageLayer.slotId}'),
        title: number == null ? 'Photo' : 'Photo · Slot $number',
        onDuplicate: () => _duplicateSelected(imageLayer.slotId),
        onDelete: () => _deleteSelected(imageLayer.slotId),
        onDone: _closeContextBar,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // What will change: the photo in the slot now.
              Container(
                width: 64,
                height: 80,
                color: context.colors.paperDeep,
                child: photo == null
                    ? null
                    : Image(image: photo, fit: BoxFit.cover),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SecondaryButton(
                      label: 'Replace photo',
                      icon: Symbols.photo_library,
                      height: 48,
                      onPressed: () => _pickImage(imageLayer.slotId),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Drag to move · pinch to resize · twist to rotate',
                      style: AppType.sans(12.5, color: context.colors.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    final stickerLayer = _selectedStickerLayer();
    if (stickerLayer != null) {
      return ContextBarShell(
        key: ValueKey('bar-sticker-${stickerLayer.id}'),
        title: 'Sticker',
        onDuplicate: () => _duplicateSelected(stickerLayer.id),
        onDelete: () => _deleteSelected(stickerLayer.id),
        onDone: _closeContextBar,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Text(
            'Drag to move · pinch to resize · twist to rotate',
            style: AppType.sans(12.5, color: context.colors.inkSoft),
          ),
        ),
      );
    }
    if (_backgroundMode) {
      final slide = _focusedSlide;
      return BackgroundColorBar(
        key: const ValueKey('bar-background'),
        slideLabel: 'Slide ${twoDigits(slide + 1)}',
        currentColor: _doc.backgroundFor(slide),
        // Per-slide backgrounds are the one naturally per-slide datum, so this
        // is a structural edit on the document rather than an overlay override.
        onColor: (color) => _editDoc(
          setSlideBackground(_doc, slide, color),
          coalesce: 'bg:$slide',
        ),
        onDone: _closeContextBar,
      );
    }
    final slideCount = _doc.slideCount;
    return Material(
      key: const ValueKey('bar-toolbar'),
      color: context.colors.paper,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The whole document in miniature: tap a slide to focus it, long-
          // press for its actions, "+ Slide" at the end. Keys stay
          // `panel-dot-$i` — the handle the carousel dots this replaced had.
          SizedBox(
            height: 96,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: SlideStrip(
                document: _doc,
                content: _content,
                fontResolver: widget.fontResolver,
                assetCatalog: _catalog,
                slideHeight: 55,
                active: _focusedSlide,
                numerals: true,
                keyPrefix: 'panel-dot-',
                onSelect: (i) =>
                    _focusPanelAt(i, slideCount, _panelWidth, _viewportWidth),
                // One slide has nothing to reorder and can't be deleted.
                onLongPress: slideCount > 1 ? _showSlideActions : null,
                onAdd: _addPanel,
              ),
            ),
          ),
          const Hairline(),
          EditorToolbar(
            onLayout: () => _insertGrid(),
            onText: () => _addTextLayer(),
            onPhoto: () => _insertPhotos(),
            onSticker: () => _insertAsset(),
            onBackground: () => setState(() => _backgroundMode = true),
            onLayers: () => _showLayersSheet(),
          ),
        ],
      ),
    );
  }
}

/// The editor's first-open state for a template with photo frames: the
/// placeholders are numbered in fill order, and one action — the gallery
/// multi-pick — fills them 1→N. Skip goes straight to the toolbar.
class _MakeItYours extends StatelessWidget {
  final int count;
  final VoidCallback onAdd;
  final VoidCallback onSkip;

  const _MakeItYours({
    super.key,
    required this.count,
    required this.onAdd,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final one = count == 1;
    // Clipped, not squeezed: while the bar eases down to the toolbar's
    // height this panel is on its way out, and must not overflow meanwhile.
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.bottomCenter,
        minHeight: 0,
        maxHeight: double.infinity,
        child: _panel(context, one),
      ),
    );
  }

  Widget _panel(BuildContext context, bool one) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.paper,
        border: Border(top: BorderSide(color: context.colors.ink)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Eyebrow('Make it yours', color: context.colors.rouge),
          const SizedBox(height: 8),
          SerifHeadline(
            roman: 'Start with ',
            italic: 'your photos.',
            style: AppType.title(30),
          ),
          const SizedBox(height: 10),
          Text(
            one
                ? 'Pick 1 from your library — it fills the numbered frame. '
                      'You can swap or move it after.'
                : 'Pick $count from your library — they fill the numbered '
                      'frames in order. You can swap or move any of them '
                      'after.',
            style: AppType.bodyS.copyWith(color: context.colors.inkSoft),
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            label: one ? 'Add 1 photo' : 'Add $count photos',
            icon: Symbols.photo_library,
            onPressed: onAdd,
          ),
          Center(child: TextLink('Skip — edit text first', onTap: onSkip)),
        ],
      ),
    );
  }
}
