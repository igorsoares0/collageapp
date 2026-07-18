import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../api/entitlements.dart';
import '../api/project_store.dart';
import '../api/template_api.dart';
import '../api/template_store.dart';
import '../model/asset_record.dart';
import '../model/template.dart';
import '../rendering/template_canvas.dart';
import '../theme.dart';
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

  /// Passed through to the paywall for its template-mosaic backdrop.
  final List<TemplateSummary> catalog;

  const TemplatePreviewScreen({
    super.key,
    required this.summary,
    required this.store,
    required this.entitlements,
    required this.projects,
    this.fontResolver = googleFontsResolver,
    this.catalog = const [],
  });

  @override
  State<TemplatePreviewScreen> createState() => _TemplatePreviewScreenState();
}

/// A small metadata pill; the `.pro` variant is the gold premium mark.
class _MetaChip extends StatelessWidget {
  final String label;
  final bool pro;

  const _MetaChip({required this.label}) : pro = false;

  const _MetaChip.pro() : label = 'PRO', pro = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: pro ? AppColors.gold : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: _TemplatePreviewScreenState._kChipText.copyWith(
          color: pro ? AppColors.onGold : AppColors.textSecondary,
          letterSpacing: pro ? 0.6 : 0,
        ),
      ),
    );
  }
}

class _TemplatePreviewScreenState extends State<TemplatePreviewScreen> {
  late Future<TemplateResult> _template;
  List<AssetRecord> _catalog = const [];
  int _page = 0;

  /// Owned so the page dots can jump to a panel, not just reflect it.
  final _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _load();
    _loadCatalog();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _load() {
    // The whole result: the template AND the sample photos embedded in its
    // response, which the preview (and only the preview) renders.
    _template = widget.store.loadTemplate(widget.summary.id);
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
          builder: (_) => PaywallScreen(
            entitlements: widget.entitlements,
            catalog: widget.catalog,
          ),
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
      body: FutureBuilder<TemplateResult>(
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
          return _buildPreview(snapshot.data!.template, snapshot.data!.assets);
        },
      ),
    );
  }

  static const _kChipText = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
  );

  Widget _buildPreview(Template template, List<AssetRecord> embedded) {
    final panels = template.panels;
    // Frames/stickers from the global catalog + this template's own photos.
    final catalog = [..._catalog, ...embedded];
    return Column(
      children: [
        Expanded(
          child: ColoredBox(
            color: AppColors.ink,
            child: PageView.builder(
              controller: _pageController,
              itemCount: panels.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) {
                Widget canvas = AspectRatio(
                  aspectRatio: template.canvasWidth / template.canvasHeight,
                  // Inert render: no callbacks wired, and IgnorePointer on
                  // top so nothing in the canvas can enter the gesture
                  // arena — the PageView keeps every swipe.
                  child: IgnorePointer(
                    child: PanelCanvas(
                      panel: panels[i],
                      // Carousel bleed from the neighbouring slides.
                      panelBefore: i > 0 ? panels[i - 1] : null,
                      panelAfter: i + 1 < panels.length ? panels[i + 1] : null,
                      canvasWidth: template.canvasWidth,
                      canvasHeight: template.canvasHeight,
                      fontResolver: widget.fontResolver,
                      assetCatalog: catalog,
                      // The preview is the "with sample photos" look; the
                      // editor starts from placeholders.
                      showTemplatePhotos: true,
                    ),
                  ),
                );
                // Only the first panel pairs with the gallery thumbnail —
                // one Hero per tag per route.
                if (i == 0) {
                  canvas = Hero(
                    tag: 'template-${widget.summary.id}',
                    child: canvas,
                  );
                }
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(child: canvas),
                );
              },
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
                if (panels.length > 1) ...[
                  // Same dot language as the editor's panel carousel; tapping
                  // one slides that panel into view.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < panels.length; i++)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _pageController.animateToPage(
                            i,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutCubic,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: i == _page ? 18 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: i == _page
                                    ? AppColors.accent
                                    : AppColors.surfaceBright,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetaChip(label: widget.summary.aspectRatio),
                    if (widget.summary.category != null)
                      _MetaChip(label: widget.summary.category!),
                    if (widget.summary.premium) const _MetaChip.pro(),
                  ],
                ),
                const SizedBox(height: 14),
                ValueListenableBuilder<bool>(
                  valueListenable: widget.entitlements.isPro,
                  builder: (context, isPro, _) {
                    final locked = widget.summary.premium && !isPro;
                    return FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: _useTemplate,
                      icon: Icon(locked ? Icons.lock : Symbols.edit_rounded),
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
