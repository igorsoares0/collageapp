import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../api/entitlements.dart';
import '../api/project_store.dart';
import '../api/template_api.dart';
import '../api/template_store.dart';
import '../model/asset_record.dart';
import '../model/migrate_v4.dart';
import '../model/photo_slots.dart';
import '../model/slot_content.dart';
import '../model/template.dart';
import '../rendering/template_canvas.dart';
import '../theme.dart';
import '../widgets/layer_ui.dart';
import '../widgets/slide_strip.dart';
import '../widgets/template_meta.dart';
import 'paywall_screen.dart';
import 'template_screen.dart';

/// Read-only look at a template, between Discover and the editor: every
/// slide rendered with the same canvas the editor uses (fonts, frames and
/// all) but inert, plus the "Use this template" button. The premium gate
/// lives on that button — anyone may look, only pro users proceed to edit.
class TemplatePreviewScreen extends StatefulWidget {
  final TemplateSummary summary;
  final TemplateStore store;
  final EntitlementsService entitlements;
  final ProjectStore projects;
  final FontResolver fontResolver;

  /// The loaded index: numbers this template ("N° 02") and feeds the
  /// paywall's cover spread.
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

class _TemplatePreviewScreenState extends State<TemplatePreviewScreen> {
  late Future<TemplateResult> _template;
  List<AssetRecord> _catalog = const [];

  /// Current page as a notifier: a page change repaints only the numeral,
  /// ticks and strip. A whole-screen setState here would rebuild every
  /// mounted canvas right in the middle of the swipe and hitch it.
  final _page = ValueNotifier<int>(0);

  /// Owned so the sequence strip can jump to a slide, not just reflect it.
  /// Recreated whenever the slide width changes: viewportFraction is final
  /// on PageController, and the pages must be exactly one slide wide so
  /// neighbouring slides sit flush (see [_controllerFor]).
  PageController _pageController = PageController();
  double? _viewportFraction;

  @override
  void initState() {
    super.initState();
    _load();
    _loadCatalog();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _page.dispose();
    super.dispose();
  }

  /// A controller whose viewportFraction makes each page exactly the slide's
  /// rendered width, so the slides touch and the carousel reads as one
  /// continuous image. The old controller is disposed after the frame — the
  /// PageView is still attached to it during this build.
  PageController _controllerFor(double fraction) {
    if (_viewportFraction == fraction) return _pageController;
    final old = _pageController;
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    _viewportFraction = fraction;
    _pageController = PageController(
      viewportFraction: fraction,
      initialPage: _page.value,
    );
    return _pageController;
  }

  void _jumpTo(int i) {
    if (!_pageController.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageController.jumpToPage(i);
    } else {
      _pageController.animateToPage(
        i,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
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
          store: widget.store,
          projects: widget.projects,
          fontResolver: widget.fontResolver,
          entitlements: widget.entitlements,
        ),
      ),
    );
  }

  /// "PHOTOGRAPHY — N° 02": the section, then the template's place in the
  /// collection.
  String get _eyebrow {
    final index = widget.catalog.indexWhere((t) => t.id == widget.summary.id);
    final section = widget.summary.category ?? 'Template';
    return index < 0 ? section : '$section — N° ${twoDigits(index + 1)}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.entitlements.isPro,
      builder: (context, isPro, _) {
        final locked = widget.summary.premium && !isPro;
        return Scaffold(
          appBar: LayerTopBar(
            eyebrow: _eyebrow,
            trailing: SizedBox(
              width: 48,
              child: Center(child: ProMark(visible: locked)),
            ),
          ),
          body: FutureBuilder<TemplateResult>(
            future: _template,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: LayerSpinner());
              }
              if (snapshot.hasError) {
                debugPrint('Template load failed: ${snapshot.error}');
                return Padding(
                  padding: const EdgeInsets.all(AppSpace.margin),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SerifHeadline(
                        roman: 'This template',
                        italic: 'is out of reach.',
                        breakLine: true,
                        style: AppType.headline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Couldn't load it. Check your connection and try "
                        'again.',
                        style: AppType.body.copyWith(color: AppColors.inkSoft),
                      ),
                      const SizedBox(height: 24),
                      SecondaryButton(
                        label: 'Try again',
                        icon: Symbols.refresh,
                        onPressed: () => setState(_load),
                      ),
                    ],
                  ),
                );
              }
              return _buildPreview(
                snapshot.data!.template,
                snapshot.data!.assets,
                locked,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildPreview(
    Template template,
    List<AssetRecord> embedded,
    bool locked,
  ) {
    // The published template folded into the continuous model, so a
    // panorama really spans slides instead of being echoed by a bleed.
    final document = migrateToV4(template, const SlotContent()).document;
    // Frames/stickers from the global catalog + this template's own photos.
    final catalog = [..._catalog, ...embedded];
    final photos = imageSlotsInFillOrder(document).length;
    final slides = document.slideCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RiseIn(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: _TwoLineTitle(widget.summary.name)),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${formatNameOf(widget.summary.aspectRatio)} '
                      '${ratioLabelOf(widget.summary.aspectRatio)} · '
                      '${slidesLabel(slides)}',
                      textAlign: TextAlign.end,
                      style: AppType.sans(14, color: AppColors.inkSoft),
                    ),
                    if (photos > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        photos == 1 ? 'Needs 1 photo' : 'Needs $photos photos',
                        style: AppType.sans(14, weight: FontWeight.w500),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // One slide = the screen minus margins minus the next slide's
              // peek, unless the height is the tighter bound.
              final aspect = template.canvasWidth / template.canvasHeight;
              final viewport = constraints.maxWidth - AppSpace.margin;
              final peek = slides > 1 ? constraints.maxWidth * 0.2 : 0.0;
              // Whole device pixels, so each seam lands on a pixel boundary
              // and no background hairline shows between flush slides.
              final dpr = MediaQuery.devicePixelRatioOf(context);
              final slideWidth =
                  (math.max(
                            40.0,
                            math.min(
                              constraints.maxWidth - 2 * AppSpace.margin - peek,
                              constraints.maxHeight * aspect,
                            ),
                          ) *
                          dpr)
                      .floorToDouble() /
                  dpr;
              final fraction = (slideWidth / viewport)
                  .clamp(0.05, 1.0)
                  .toDouble();
              return Padding(
                padding: const EdgeInsets.only(left: AppSpace.margin),
                child: PageView.builder(
                  controller: _controllerFor(fraction),
                  padEnds: false,
                  itemCount: slides,
                  onPageChanged: (i) => _page.value = i,
                  itemBuilder: (context, i) {
                    Widget canvas = AspectRatio(
                      aspectRatio: aspect,
                      // Inert render: no callbacks wired, and IgnorePointer
                      // on top so nothing in the canvas can enter the gesture
                      // arena — the PageView keeps every swipe.
                      child: IgnorePointer(
                        child: SlideView(
                          document: document,
                          slideIndex: i,
                          fontResolver: widget.fontResolver,
                          assetCatalog: catalog,
                          // The preview is the "with sample photos" look;
                          // the editor starts from placeholders.
                          showTemplatePhotos: true,
                        ),
                      ),
                    );
                    // Only the first slide pairs with the Discover cover —
                    // one Hero per tag per route.
                    if (i == 0) {
                      canvas = Hero(
                        tag: 'template-${widget.summary.id}',
                        child: canvas,
                      );
                    }
                    return Align(alignment: Alignment.topLeft, child: canvas);
                  },
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: ValueListenableBuilder<int>(
            valueListenable: _page,
            builder: (context, page, _) => Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: twoDigits(page + 1),
                        style: AppType.numeral(34),
                      ),
                      TextSpan(
                        text: '/${twoDigits(slides)}',
                        style: AppType.numeral(18, color: AppColors.inkMuted),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (slides > 1)
                  Ticks(count: slides, active: page, width: 18, gap: 6),
              ],
            ),
          ),
        ),
        if (slides > 1) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Column(
              children: [
                Hairline(),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: Eyebrow('The sequence', size: 11)),
                    Eyebrow('Tap to jump', size: 11),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            height: 64,
            child: ValueListenableBuilder<int>(
              valueListenable: _page,
              builder: (context, page, _) => SlideStrip(
                document: document,
                fontResolver: widget.fontResolver,
                assetCatalog: catalog,
                showTemplatePhotos: true,
                slideHeight: 54,
                active: page,
                onSelect: _jumpTo,
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
        ],
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (locked) ...[
                  Text(
                    'Looking is free. Editing is part of Pro.',
                    style: AppType.bodyS,
                  ),
                  const SizedBox(height: 10),
                ],
                PrimaryButton(
                  label: locked ? 'Unlock with Pro' : 'Use this template',
                  labelWidget: locked
                      ? const Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: 'Unlock with '),
                              TextSpan(
                                text: 'Pro',
                                style: TextStyle(fontStyle: FontStyle.italic),
                              ),
                            ],
                          ),
                        )
                      : null,
                  onPressed: _useTemplate,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A template name set as a two-line headline: the first word roman, the
/// rest italic ("Lisbon, / *in June*").
class _TwoLineTitle extends StatelessWidget {
  final String name;

  const _TwoLineTitle(this.name);

  @override
  Widget build(BuildContext context) {
    final cut = name.indexOf(' ');
    if (cut < 0) return Text(name, style: AppType.headline);
    return SerifHeadline(
      roman: name.substring(0, cut),
      italic: name.substring(cut + 1),
      breakLine: true,
      style: AppType.headline,
    );
  }
}

/// The title's entrance: rises 8px and fades in over 320ms (instant under
/// reduced motion).
class _RiseIn extends StatelessWidget {
  final Widget child;

  const _RiseIn({required this.child});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
