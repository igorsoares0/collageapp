import 'package:flutter/material.dart';

import '../api/entitlements.dart';
import '../api/project_store.dart';
import '../api/template_api.dart';
import '../api/template_store.dart';
import '../model/asset_record.dart';
import '../model/template.dart';
import '../rendering/template_canvas.dart';
import 'paywall_screen.dart';
import 'template_screen.dart';

/// Read-only look at a template, between the gallery and the editor: every
/// panel rendered with the same canvas the editor uses (fonts, frames and all)
/// but inert, plus the "Use this template" button. The premium gate lives on
/// that button — anyone may look, only pro users proceed to edit.
class TemplatePreviewScreen extends StatefulWidget {
  final TemplateSummary summary;
  final TemplateStore store;
  final EntitlementsService entitlements;
  final ProjectStore projects;
  final FontResolver fontResolver;

  const TemplatePreviewScreen({
    super.key,
    required this.summary,
    required this.store,
    required this.entitlements,
    required this.projects,
    this.fontResolver = googleFontsResolver,
  });

  @override
  State<TemplatePreviewScreen> createState() => _TemplatePreviewScreenState();
}

class _TemplatePreviewScreenState extends State<TemplatePreviewScreen> {
  late Future<Template> _template;
  List<AssetRecord> _catalog = const [];
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadCatalog();
  }

  void _load() {
    _template = widget.store
        .loadTemplate(widget.summary.id)
        .then((r) => r.template);
  }

  /// Best-effort, like the editor: offline the bundled seeds still resolve.
  Future<void> _loadCatalog() async {
    try {
      final result = await widget.store.loadAssets();
      if (mounted) setState(() => _catalog = result.assets);
    } catch (_) {
      // Seeds only.
    }
  }

  Future<void> _useTemplate() async {
    if (widget.summary.premium && !widget.entitlements.isPro.value) {
      final unlocked = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => PaywallScreen(entitlements: widget.entitlements),
        ),
      );
      if (unlocked != true || !mounted) return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TemplateScreen(
          id: widget.summary.id,
          projects: widget.projects,
          fontResolver: widget.fontResolver,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.summary.name)),
      body: FutureBuilder<Template>(
        future: _template,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Could not load this template.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => setState(_load),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          return _buildPreview(snapshot.data!);
        },
      ),
    );
  }

  Widget _buildPreview(Template template) {
    final panels = template.panels;
    return Column(
      children: [
        Expanded(
          child: ColoredBox(
            color: const Color(0xFF18181B),
            child: PageView.builder(
              itemCount: panels.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: template.canvasWidth / template.canvasHeight,
                    // Inert render: no callbacks wired, and IgnorePointer on
                    // top so nothing in the canvas can enter the gesture
                    // arena — the PageView keeps every swipe.
                    child: IgnorePointer(
                      child: PanelCanvas(
                        panel: panels[i],
                        canvasWidth: template.canvasWidth,
                        canvasHeight: template.canvasHeight,
                        fontResolver: widget.fontResolver,
                        assetCatalog: _catalog,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  [
                    widget.summary.aspectRatio,
                    if (widget.summary.category != null)
                      widget.summary.category!,
                    if (panels.length > 1) '${_page + 1}/${panels.length}',
                    if (widget.summary.premium) 'premium',
                  ].join(' · '),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<bool>(
                  valueListenable: widget.entitlements.isPro,
                  builder: (context, isPro, _) {
                    final locked = widget.summary.premium && !isPro;
                    return FilledButton.icon(
                      onPressed: _useTemplate,
                      icon: Icon(locked ? Icons.lock : Icons.edit_outlined),
                      label: Text(
                        locked ? 'Unlock with Pro' : 'Use this template',
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
