import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../api/template_store.dart';
import '../model/slot_content.dart';
import '../model/template.dart';
import '../rendering/export.dart';
import '../rendering/template_canvas.dart';
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

class _TemplateScreenState extends State<TemplateScreen> {
  final _store = TemplateStore();
  final _picker = ImagePicker();
  // One RepaintBoundary key per panel, so each carousel slide exports to its
  // own PNG. Reused across rebuilds (keyed by panel id).
  final Map<String, GlobalKey> _panelKeys = {};
  late Future<Template> _template;
  SlotContent _content = const SlotContent();
  String? _selectedSlot;
  String? _editingSlot;
  // Panel the styling bars act on (last one the user touched).
  String? _focusedPanelId;
  bool _exporting = false;

  GlobalKey _panelKey(String panelId) =>
      _panelKeys.putIfAbsent(panelId, () => GlobalKey());

  @override
  void initState() {
    super.initState();
    _template = _store.loadTemplate(widget.id).then((r) => r.template);
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

  /// First tap selects (shows the handles); the second tap acts on the
  /// content — image slots open the picker, text slots start inline
  /// editing. Empty image slots open the picker right away — filling the
  /// slot is what the user almost certainly wants.
  void _handleSlotTap(Template template, String slotId) {
    final isImage = template.layers
        .any((l) => l is ImageLayer && l.slotId == slotId);
    final wasSelected = _selectedSlot == slotId;
    if (!wasSelected) {
      setState(() {
        _selectedSlot = slotId;
        _editingSlot = null;
      });
    }
    if (isImage && (wasSelected || _content.imageFor(slotId) == null)) {
      _pickImage(slotId);
    } else if (!isImage && wasSelected) {
      setState(() => _editingSlot = slotId);
    }
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
        final bytes = await capturePng(_panelKey(panel.id), template.canvasWidth);
        files.add(XFile.fromData(
          bytes,
          mimeType: 'image/png',
          name: template.panels.length == 1
              ? '${template.id}.png'
              : '${template.id}_${i + 1}.png',
        ));
      }
      await Share.shareXFiles(files);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Export failed: $e')));
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
        return Scaffold(
          appBar: AppBar(
            title: Text(template?.name ?? '…'),
            actions: [
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
                  onPressed:
                      _exporting ? null : () => _exportPng(template),
                ),
            ],
          ),
          body: switch (snapshot.connectionState) {
            ConnectionState.done when snapshot.hasError => Center(
                child: Text('Could not load template.\n${snapshot.error}',
                    textAlign: TextAlign.center),
              ),
            ConnectionState.done => _buildBody(template!),
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
    for (final layer in template.layers) {
      if (layer is TextLayer && layer.slotId == slot) return layer;
    }
    return null;
  }

  Widget _buildBody(Template template) {
    final textLayer = _selectedTextLayer(template);
    final focusedId = _focusedPanelId ?? template.panels.first.id;
    final focusedPanel = template.panels.firstWhere(
      (p) => p.id == focusedId,
      orElse: () => template.panels.first,
    );
    return Column(
      children: [
        Expanded(
          child: Container(
            color: const Color(0xFF18181B),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Panels sit side by side; with more than one, each is a bit
                // narrower than the viewport so the next one peeks in.
                final panelWidth = constraints.maxWidth *
                    (template.panels.length == 1 ? 1.0 : 0.82);
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Row(
                    children: [
                      for (final panel in template.panels)
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
                                onCanvasTap: () => setState(() {
                                  _focusedPanelId = panel.id;
                                  _selectedSlot = null;
                                  _editingSlot = null;
                                }),
                                onTextChanged: (slotId, value) => setState(() {
                                  _content = _content.withText(slotId, value);
                                }),
                                onSlotDrag: (slotId, delta) => setState(() {
                                  _content = _content.withOffset(slotId,
                                      _content.offsetFor(slotId) + delta);
                                }),
                                onSlotScale: (slotId, scale) => setState(() {
                                  _content = _content.withScale(slotId, scale);
                                }),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        if (textLayer == null && _selectedSlot == null)
          BackgroundColorBar(
            currentColor: _content.backgroundFor(focusedPanel.id) ??
                focusedPanel.backgroundColor,
            onColor: (color) => setState(() => _content =
                _content.withPanelBackground(focusedPanel.id, color)),
          ),
        if (textLayer != null)
          Builder(builder: (context) {
            final weight =
                _content.weightFor(textLayer.slotId) ?? textLayer.fontWeight;
            return TextStyleBar(
              currentFont:
                  _content.fontFor(textLayer.slotId) ?? textLayer.fontFamily,
              currentColor:
                  _content.colorFor(textLayer.slotId) ?? textLayer.color,
              currentAlignment: _content.alignmentFor(textLayer.slotId) ??
                  textLayer.alignment,
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
                    textLayer.slotId, weight >= 700 ? 400 : 700);
              }),
            );
          }),
      ],
    );
  }
}
