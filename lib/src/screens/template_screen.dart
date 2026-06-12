import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../api/template_store.dart';
import '../model/slot_content.dart';
import '../model/template.dart';
import '../rendering/export.dart';
import '../rendering/template_canvas.dart';

/// Renders one template and lets the user fill its slots (spec §12):
/// text slots are editable below the preview; image slots open the
/// system gallery picker. The result exports as a full-resolution PNG
/// through the share sheet.
class TemplateScreen extends StatefulWidget {
  final String id;

  const TemplateScreen({super.key, required this.id});

  @override
  State<TemplateScreen> createState() => _TemplateScreenState();
}

class _TemplateScreenState extends State<TemplateScreen> {
  final _store = TemplateStore();
  final _picker = ImagePicker();
  final _canvasKey = GlobalKey();
  late Future<Template> _template;
  SlotContent _content = const SlotContent();
  String? _selectedSlot;
  bool _exporting = false;

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

  /// First tap selects (shows the handles); tapping the selected image slot
  /// again opens the picker. Empty image slots open the picker right away —
  /// filling the slot is what the user almost certainly wants.
  void _handleSlotTap(Template template, String slotId) {
    final isImage = template.layers
        .any((l) => l is ImageLayer && l.slotId == slotId);
    final wasSelected = _selectedSlot == slotId;
    if (!wasSelected) setState(() => _selectedSlot = slotId);
    if (isImage && (wasSelected || _content.imageFor(slotId) == null)) {
      _pickImage(slotId);
    }
  }

  Future<void> _exportPng(Template template) async {
    // Deselect first: the handles are widgets inside the RepaintBoundary
    // and would end up in the PNG.
    if (_selectedSlot != null) {
      setState(() => _selectedSlot = null);
      await WidgetsBinding.instance.endOfFrame;
    }
    setState(() => _exporting = true);
    try {
      final bytes = await capturePng(_canvasKey, template.canvasWidth);
      await Share.shareXFiles([
        XFile.fromData(bytes, mimeType: 'image/png', name: '${template.id}.png'),
      ]);
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

  Widget _buildBody(Template template) {
    final textSlots = [
      for (final layer in template.layers)
        if (layer is TextLayer && !layer.hidden) layer.slotId,
    ];
    return Column(
      children: [
        Expanded(
          child: Container(
            color: const Color(0xFF18181B),
            padding: const EdgeInsets.all(16),
            alignment: Alignment.center,
            child: RepaintBoundary(
              key: _canvasKey,
              child: TemplateCanvas(
                template: template,
                content: _content,
                selectedSlotId: _selectedSlot,
                onSlotTap: (slotId) => _handleSlotTap(template, slotId),
                onCanvasTap: () => setState(() => _selectedSlot = null),
                onSlotDrag: (slotId, delta) => setState(() {
                  _content = _content.withOffset(
                      slotId, _content.offsetFor(slotId) + delta);
                }),
                onSlotScale: (slotId, scale) => setState(() {
                  _content = _content.withScale(slotId, scale);
                }),
              ),
            ),
          ),
        ),
        if (textSlots.isNotEmpty)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final slotId in textSlots)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        decoration: InputDecoration(
                          labelText: slotId,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (value) => setState(() {
                          _content = _content.withText(slotId, value);
                        }),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
