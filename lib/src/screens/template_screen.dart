import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../api/template_store.dart';
import '../model/slot_content.dart';
import '../model/template.dart';
import '../rendering/export.dart';
import '../rendering/template_canvas.dart';
import '../widgets/layers_sheet.dart';
import '../widgets/text_style_bar.dart';

/// Renders one template and lets the user fill its slots (spec §12),
/// editing directly on the canvas: tap selects, tap again edits text
/// inline or opens the gallery picker for images. The result exports as
/// a full-resolution PNG through the share sheet.
class TemplateScreen extends StatefulWidget {
  final String id;

  const TemplateScreen({super.key, required this.id});

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
  SlotContent _content = const SlotContent();
  String? _selectedSlot;
  String? _editingSlot;
  // Panel the styling bars act on (last one the user touched).
  String? _focusedPanelId;
  bool _exporting = false;

  GlobalKey _panelKey(String panelId) =>
      _panelKeys.putIfAbsent(panelId, () => GlobalKey());

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

  /// A slot/layer id not used by the template or any added layer, so a new
  /// element never collides with an existing slot's overrides.
  String _uniqueToken(String base, Template template) {
    final used = {
      for (final l in _allLayers(template)) l.id,
      ...template.slotIds,
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
    final panelId = _focusedPanelId ?? template.panels.first.id;
    final panel = template.panels.firstWhere(
      (p) => p.id == panelId,
      orElse: () => template.panels.first,
    );
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
    setState(() {
      _content = _content.withAddedLayer(panel.id, layer);
      _focusedPanelId = panel.id;
      _selectedSlot = token;
      _editingSlot = token;
    });
  }

  /// Adds a fresh image element to the focused panel, centered, and opens the
  /// gallery right away (an empty image element is useless on its own).
  void _addImageLayer(Template template) {
    final panelId = _focusedPanelId ?? template.panels.first.id;
    final panel = template.panels.firstWhere(
      (p) => p.id == panelId,
      orElse: () => template.panels.first,
    );
    final token = _uniqueToken('image', template);
    final side = template.canvasWidth * 0.5;
    final layer = ImageLayer(
      id: token,
      hidden: false,
      slotId: token,
      x: (template.canvasWidth - side) / 2,
      y: (template.canvasHeight - side) / 2,
      width: side,
      height: side,
      rotation: 0,
      opacity: 1,
      borderRadius: 0,
    );
    setState(() {
      _content = _content.withAddedLayer(panel.id, layer);
      _focusedPanelId = panel.id;
      _selectedSlot = token;
      _editingSlot = null;
    });
    _pickImage(token);
  }

  /// Deletes a user-added layer (template layers can only be hidden, not
  /// removed). Clears the selection if it pointed at the removed element.
  void _removeAddedLayer(String panelId, Layer layer) {
    setState(() {
      _content = _content.withoutAddedLayer(panelId, layer.id);
      final slotId = switch (layer) {
        ImageLayer l => l.slotId,
        TextLayer l => l.slotId,
        _ => null,
      };
      if (slotId != null && _selectedSlot == slotId) {
        _selectedSlot = null;
        _editingSlot = null;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_onZoomChange);
    _template = _store.loadTemplate(widget.id).then((r) => r.template);
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
    setState(() => _content = _content.withImage(slotId, MemoryImage(bytes)));
  }

  /// Tapping a slot selects it (shows the handles for move/resize). A text
  /// slot's second tap starts inline editing. An image slot's gallery is NOT
  /// opened here — only its photo icon opens it (see [_onPickImage]).
  void _handleSlotTap(Template template, String slotId) {
    final isImage = _allLayers(
      template,
    ).any((l) => l is ImageLayer && l.slotId == slotId);
    final wasSelected = _selectedSlot == slotId;
    if (!wasSelected) {
      setState(() {
        _selectedSlot = slotId;
        _editingSlot = null;
      });
    }
    if (!isImage && wasSelected) {
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
    final panelId = _focusedPanelId ?? template.panels.first.id;
    final templatePanel = template.panels.firstWhere(
      (p) => p.id == panelId,
      orElse: () => template.panels.first,
    );
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
                setState(() {
                  _content = _content.withLayerHidden(layer.id, nowHidden);
                  // A hidden element can't stay selected/edited.
                  if (nowHidden) {
                    final slotId = switch (layer) {
                      ImageLayer l => l.slotId,
                      TextLayer l => l.slotId,
                      _ => null,
                    };
                    if (slotId != null && _selectedSlot == slotId) {
                      _selectedSlot = null;
                      _editingSlot = null;
                    }
                  }
                });
                setSheetState(() {});
              },
              onReorder: (layer, {required toFront}) {
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
      // One PNG per panel, in carousel order — ready to post as a carousel.
      final files = <XFile>[];
      for (var i = 0; i < template.panels.length; i++) {
        final panel = template.panels[i];
        final bytes = await capturePng(
          _panelKey(panel.id),
          template.canvasWidth,
        );
        files.add(
          XFile.fromData(
            bytes,
            mimeType: 'image/png',
            name: template.panels.length == 1
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
                PopupMenuButton<String>(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add element',
                  onSelected: (value) {
                    if (value == 'text') _addTextLayer(template);
                    if (value == 'image') _addImageLayer(template);
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

  Widget _buildBody(
    Template template,
    double keyboardInset,
    double safeBottom,
  ) {
    final textLayer = _selectedTextLayer(template);
    final focusedId = _focusedPanelId ?? template.panels.first.id;
    final focusedPanel = template.panels.firstWhere(
      (p) => p.id == focusedId,
      orElse: () => template.panels.first,
    );

    final bottomBar = _buildBottomBar(textLayer, focusedPanel);
    // Constant height for the bar strip (incl. the home-indicator inset), so
    // the canvas area is a fixed size regardless of which bar shows.
    final barArea = _kBottomBarHeight + safeBottom;

    return Column(
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
                    constraints.maxWidth *
                    (template.panels.length == 1 ? 1.0 : 0.82);
                // With nothing selected the surface is an InteractiveViewer
                // (pinch zoom + pan). With a slot selected it becomes a STATIC
                // transform — same matrix and layout, but NO gesture detector:
                // InteractiveViewer's detector stays opaque even when pan/scale
                // are off and would otherwise fight the selection handles.
                final interacting =
                    _selectedSlot != null || _editingSlot != null;
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
                        for (final panel in template.panels.map(
                          _effectivePanel,
                        ))
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: SizedBox(
                              width: panelWidth,
                              child: RepaintBoundary(
                                key: _panelKey(panel.id),
                                child: PanelCanvas(
                                  panel: panel,
                                  canvasWidth: template.canvasWidth,
                                  canvasHeight: template.canvasHeight,
                                  content: _content,
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
                                  onTextChanged: (slotId, value) =>
                                      setState(() {
                                        _content = _content.withText(
                                          slotId,
                                          value,
                                        );
                                      }),
                                  onSlotDrag: (slotId, delta) => setState(() {
                                    _content = _content.withOffset(
                                      slotId,
                                      _content.offsetFor(slotId) + delta,
                                    );
                                  }),
                                  onSlotScale: (slotId, scale) => setState(() {
                                    _content = _content.withScale(
                                      slotId,
                                      scale,
                                    );
                                  }),
                                  onSlotRotate: (slotId, degrees) =>
                                      setState(() {
                                        _content = _content.withRotation(
                                          slotId,
                                          degrees,
                                        );
                                      }),
                                ),
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
                        panAxis: _isZoomed ? PanAxis.free : PanAxis.horizontal,
                        minScale: 1,
                        maxScale: 4,
                        boundaryMargin: const EdgeInsets.all(64),
                        child: strip,
                      );
                return SingleChildScrollView(
                  // Vertical scroll only while editing — the framework lifts the
                  // focused field above the keyboard then. Frozen otherwise.
                  physics: _editingSlot != null
                      ? const ClampingScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  child: SizedBox(height: canvasHeight, child: surface),
                );
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
    );
  }

  /// The bar shown under the canvas: background colors when nothing is
  /// selected, text styling when a text slot is, and nothing for image slots.
  Widget? _buildBottomBar(TextLayer? textLayer, Panel focusedPanel) {
    if (textLayer == null && _selectedSlot == null) {
      return BackgroundColorBar(
        currentColor:
            _content.backgroundFor(focusedPanel.id) ??
            focusedPanel.backgroundColor,
        onColor: (color) => setState(
          () => _content = _content.withPanelBackground(focusedPanel.id, color),
        ),
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
        onFont: (font) => setState(() {
          _content = _content.withFont(textLayer.slotId, font);
        }),
        onColor: (color) => setState(() {
          _content = _content.withColor(textLayer.slotId, color);
        }),
        onAlignment: (align) => setState(() {
          _content = _content.withAlignment(textLayer.slotId, align);
        }),
        onBoldToggle: () => setState(() {
          _content = _content.withWeight(
            textLayer.slotId,
            weight >= 700 ? 400 : 700,
          );
        }),
      );
    }
    return null;
  }
}
