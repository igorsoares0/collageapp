import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../api/appearance.dart';
import '../api/entitlements.dart';
import '../api/project_store.dart';
import '../api/template_api.dart';
import '../api/template_store.dart';
import '../model/asset_record.dart';
import '../model/migrate_v4.dart';
import '../model/slot_content.dart';
import '../model/template.dart';
import '../rendering/template_canvas.dart';
import '../theme.dart';
import '../widgets/layer_ui.dart';
import '../widgets/template_meta.dart';
import 'projects_screen.dart';
import 'settings_screen.dart';
import 'template_preview_screen.dart';
import 'template_screen.dart';

export '../widgets/template_meta.dart' show aspectRatioOf;

class GalleryScreen extends StatefulWidget {
  /// Both are owned by `main()` in production; tests inject fakes.
  final EntitlementsService? entitlements;
  final TemplateStore? store;

  /// Threaded through preview/editor; tests inject a synchronous fake.
  final FontResolver fontResolver;

  /// The appearance choice (System / Light / Dark), handed to Settings.
  /// Null in tests: Settings then hides its Appearance section.
  final AppearanceController? appearance;

  const GalleryScreen({
    super.key,
    this.entitlements,
    this.store,
    this.fontResolver = googleFontsResolver,
    this.appearance,
  });

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  late final _entitlements = widget.entitlements ?? EntitlementsService();
  late final _store = widget.store ?? TemplateStore();
  // Handed to every editor session so it auto-saves as a project; the
  // projects themselves are listed on the Projects tab.
  final _projects = ProjectStore();
  late Future<IndexResult> _index;

  // Frames/stickers for the folios' live renders.
  List<AssetRecord> _assets = [];

  // Category index selection; null = All. A stale selection (category gone
  // after a refresh) reads as All — see the guard in [_buildDiscover].
  String? _category;

  // Bottom-bar destination: 0 Discover, 1 Projects. The create button in the
  // bar is an action, not a destination — it never lands here.
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _index = _store.loadIndex();
    _loadAssets();
  }

  /// Best-effort, like the preview screen: offline (or on error) the folios
  /// simply render without catalog frames/stickers.
  Future<void> _loadAssets() async {
    try {
      final result = await _store.loadAssets();
      if (mounted) setState(() => _assets = result.assets);
    } catch (_) {
      // Seeds only.
    }
  }

  Future<void> _refresh() async {
    final next = _store.loadIndex();
    // Block body: an arrow closure would RETURN the assigned Future, which
    // setState forbids (and the assertion would abort the rebuild).
    setState(() {
      _index = next;
    });
    try {
      await next;
    } catch (_) {
      // The FutureBuilder renders the error state.
    }
  }

  Future<void> _openTemplate(TemplateSummary summary) async {
    // The loaded index rides along for the paywall's cover spread; a folio
    // is only tappable once _index resolved, so this await is immediate.
    var catalog = <TemplateSummary>[];
    try {
      catalog = (await _index).templates;
    } catch (_) {
      // No index, no spread — the paywall falls back to plain paper.
    }
    if (!mounted) return;
    // Always lands on the read-only preview — looking is free for everyone;
    // the premium gate sits on the preview's "Use this template" button.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TemplatePreviewScreen(
          summary: summary,
          store: _store,
          entitlements: _entitlements,
          projects: _projects,
          fontResolver: widget.fontResolver,
          catalog: catalog,
        ),
      ),
    );
  }

  /// Create-from-scratch entry: pick a format, then open the editor on a
  /// blank draft — everything is built there with the bottom toolbar.
  Future<void> _createFromScratch() async {
    final canvas = await showLayerSheet<(String, double, double)>(
      context: context,
      titleWidget: SerifHeadline(
        roman: 'A blank ',
        italic: 'canvas',
        style: AppType.title(28),
      ),
      builder: (sheetContext) => const _BlankCanvasSheet(),
    );
    if (canvas == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TemplateScreen(
          draft: Template.blank(
            aspectRatio: canvas.$1,
            canvasWidth: canvas.$2,
            canvasHeight: canvas.$3,
          ),
          projects: _projects,
          fontResolver: widget.fontResolver,
          entitlements: _entitlements,
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    var catalog = <TemplateSummary>[];
    try {
      catalog = (await _index).templates;
    } catch (_) {
      // Settings works without the index; only its Pro cover goes plain.
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          entitlements: _entitlements,
          catalog: catalog,
          appearance: widget.appearance,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The switch rebuilds the destination on every visit, so the projects
    // tab always lists fresh saves.
    return Scaffold(
      bottomNavigationBar: _HomeBottomBar(
        current: _tab,
        onSelect: (i) => setState(() => _tab = i),
        onCreate: _createFromScratch,
      ),
      body: SafeArea(
        bottom: false,
        child: _tab == 1
            ? ProjectsList(
                store: _projects,
                fontResolver: widget.fontResolver,
                entitlements: _entitlements,
                onBrowseTemplates: () => setState(() => _tab = 0),
              )
            : _buildDiscover(),
      ),
    );
  }

  Widget _buildDiscover() {
    return FutureBuilder<IndexResult>(
      future: _index,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        final failed = !loading && snapshot.hasError;
        final result = (loading || failed) ? null : snapshot.data!;

        final slivers = <Widget>[
          SliverToBoxAdapter(
            child: _Masthead(
              offline: result?.fromCache ?? false,
              onSettings: _openSettings,
            ),
          ),
        ];

        if (failed) {
          // The exception itself is developer material — a socket error or a
          // status code tells the user nothing and reads as a broken app. It
          // goes to the log; the screen offers the one thing that can help.
          debugPrint('Template index failed: ${snapshot.error}');
          slivers.add(
            SliverFillRemaining(
              hasScrollBody: false,
              child: _OutOfReach(
                onRetry: _refresh,
                onProjects: () => setState(() => _tab = 1),
              ),
            ),
          );
        } else {
          slivers.add(const SliverToBoxAdapter(child: _Headline()));
          if (result == null) {
            // Ghost folios where the real ones will land.
            slivers.add(const SliverToBoxAdapter(child: _SkeletonFolios()));
          } else {
            slivers.addAll(_collectionSlivers(result.templates));
          }
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          color: context.colors.ink,
          backgroundColor: context.colors.paper,
          // Rebuilds when a purchase lands so every "Pro" fades out in place.
          child: ValueListenableBuilder<bool>(
            valueListenable: _entitlements.isPro,
            builder: (context, _, _) => CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: slivers,
            ),
          ),
        );
      },
    );
  }

  List<Widget> _collectionSlivers(List<TemplateSummary> templates) {
    if (templates.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
            child: Text(
              'No templates published yet.',
              style: AppType.bodyS.copyWith(color: context.colors.inkSoft),
            ),
          ),
        ),
      ];
    }
    final counts = <String, int>{};
    for (final t in templates) {
      final c = t.category;
      if (c != null) counts[c] = (counts[c] ?? 0) + 1;
    }
    final categories = counts.keys.toList()..sort();
    final active = categories.contains(_category) ? _category : null;
    final visible = active == null
        ? templates
        : [
            for (final t in templates)
              if (t.category == active) t,
          ];

    final ctx = _FolioContext(
      store: _store,
      fontResolver: widget.fontResolver,
      catalog: _assets,
      isPro: _entitlements.isPro.value,
      onOpen: _openTemplate,
    );
    final rows = _rhythm(visible.skip(1).toList());

    return [
      if (categories.isNotEmpty)
        SliverPersistentHeader(
          pinned: true,
          delegate: _CategoryIndexDelegate(
            total: templates.length,
            categories: categories,
            counts: counts,
            active: active,
            onSelect: (c) => setState(() => _category = c),
          ),
        ),
      SliverToBoxAdapter(
        child: _AppearFromBelow(
          key: ValueKey('featured-${active ?? ''}-${visible.first.id}'),
          order: 0,
          child: _Featured(summary: visible.first, ctx: ctx),
        ),
      ),
      SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (context, i) => _AppearFromBelow(
          // Re-keyed per filter so switching sections replays the entrance.
          key: ValueKey('row-${active ?? ''}-${rows[i].first.$2.id}'),
          order: i + 1,
          child: Padding(
            padding: const EdgeInsets.only(top: 48),
            child: _RhythmRow(row: rows[i], ctx: ctx),
          ),
        ),
      ),
      const SliverToBoxAdapter(child: _EndNote()),
    ];
  }
}

// ── Rhythm ────────────────────────────────────────────────────────────────

/// The collection's row kinds, in the order they cycle: a wide folio with its
/// caption beside it, a staggered pair, a full-bleed sequence, a wide folio
/// with the caption on the left, and a centred folio.
enum _RowKind { wideLeft, pair, sequence, wideRight, centered }

const _kRhythm = _RowKind.values;

/// One row: its kind and its folios as (collection number, template).
typedef _Row = ({_RowKind kind, List<(int, TemplateSummary)> folios});

extension on _Row {
  (int, TemplateSummary) get first => folios.first;
}

/// Lays [rest] (the collection after the featured template) into rows. Numbers
/// continue from the featured N° 01.
List<_Row> _rhythm(List<TemplateSummary> rest) {
  final rows = <_Row>[];
  var i = 0;
  var k = 0;
  while (i < rest.length) {
    final kind = _kRhythm[k % _kRhythm.length];
    final take = kind == _RowKind.pair ? math.min(2, rest.length - i) : 1;
    rows.add((
      kind: take == 1 && kind == _RowKind.pair ? _RowKind.centered : kind,
      folios: [for (var j = 0; j < take; j++) (i + j + 2, rest[i + j])],
    ));
    i += take;
    k++;
  }
  return rows;
}

/// Width of [span] columns of the 6-column grid inside [width].
double _span(double width, int span) {
  const gutter = AppSpace.gutter;
  final col = (width - 5 * gutter) / 6;
  return span * col + (span - 1) * gutter;
}

class _FolioContext {
  final TemplateStore store;
  final FontResolver fontResolver;
  final List<AssetRecord> catalog;
  final bool isPro;
  final ValueChanged<TemplateSummary> onOpen;

  const _FolioContext({
    required this.store,
    required this.fontResolver,
    required this.catalog,
    required this.isPro,
    required this.onOpen,
  });
}

class _RhythmRow extends StatelessWidget {
  final _Row row;
  final _FolioContext ctx;

  const _RhythmRow({required this.row, required this.ctx});

  @override
  Widget build(BuildContext context) {
    return switch (row.kind) {
      _RowKind.sequence => _SequenceFolio(
        number: row.first.$1,
        summary: row.first.$2,
        ctx: ctx,
      ),
      _ => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.margin),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            switch (row.kind) {
              case _RowKind.wideLeft:
              case _RowKind.wideRight:
                return _WideFolio(
                  number: row.first.$1,
                  summary: row.first.$2,
                  ctx: ctx,
                  width: w,
                  captionLeft: row.kind == _RowKind.wideRight,
                );
              case _RowKind.pair:
                final (n1, a) = row.folios[0];
                final (n2, b) = row.folios[1];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Staggered: the left folio sits lower.
                    Padding(
                      padding: const EdgeInsets.only(top: 56),
                      child: _StackedFolio(
                        number: n1,
                        summary: a,
                        ctx: ctx,
                        width: _span(w, 3),
                      ),
                    ),
                    const SizedBox(width: AppSpace.gutter),
                    _StackedFolio(
                      number: n2,
                      summary: b,
                      ctx: ctx,
                      width: _span(w, 3),
                    ),
                  ],
                );
              default:
                final cw = _span(w, 4);
                return Padding(
                  padding: EdgeInsets.only(left: (w - cw) / 2),
                  child: _StackedFolio(
                    number: row.first.$1,
                    summary: row.first.$2,
                    ctx: ctx,
                    width: cw,
                    pageable: true,
                    showNumber: false,
                  ),
                );
            }
          },
        ),
      ),
    };
  }
}

// ── Folio plumbing ───────────────────────────────────────────────────────

/// What a folio knows once its template has loaded from the prefetch cache.
class _FolioData {
  final Template template;
  final Document document;
  final List<AssetRecord> catalog;

  const _FolioData(this.template, this.document, this.catalog);

  int get slideCount => document.slideCount;
}

/// Loads a template once (from the prefetch cache — the collection never hits
/// the network per folio) and hands its document to [builder], together with
/// the folio's page index and its press animation.
///
/// Also owns the folio's tap: the image dims 6% and the caption rule draws
/// left to right over 160ms, then the preview opens.
class _FolioShell extends StatefulWidget {
  final TemplateSummary summary;
  final _FolioContext ctx;
  final Widget Function(
    BuildContext context,
    _FolioData? data,
    ValueNotifier<int> page,
    Animation<double> press,
  )
  builder;

  const _FolioShell({
    super.key,
    required this.summary,
    required this.ctx,
    required this.builder,
  });

  @override
  State<_FolioShell> createState() => _FolioShellState();
}

class _FolioShellState extends State<_FolioShell>
    with SingleTickerProviderStateMixin {
  late final Future<TemplateResult> _template = widget.ctx.store
      .loadTemplateCached(widget.summary.id);

  /// Ticks only — a page change repaints the ticks row, never the canvases.
  final _page = ValueNotifier<int>(0);

  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );

  bool _opening = false;

  @override
  void dispose() {
    _page.dispose();
    _press.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (_opening) return;
    _opening = true;
    try {
      if (!MediaQuery.disableAnimationsOf(context)) {
        await _press.forward(from: 0);
      }
      if (!mounted) return;
      widget.ctx.onOpen(widget.summary);
    } finally {
      _opening = false;
      // Undo the press once the preview has covered the folio.
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _press.value = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.summary.name,
      child: GestureDetector(
        // Opaque: the whole folio (cover AND caption) opens the preview. The
        // cover's PageView keeps horizontal drags; taps reach here.
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        child: FutureBuilder<TemplateResult>(
          future: _template,
          builder: (context, snapshot) {
            final result = snapshot.data;
            _FolioData? data;
            if (result != null) {
              // The published template folded into the continuous model, so
              // a panorama really spans slides instead of being echoed.
              final document = migrateToV4(
                result.template,
                const SlotContent(),
              ).document;
              data = _FolioData(result.template, document, [
                ...widget.ctx.catalog,
                ...result.assets,
              ]);
            }
            return widget.builder(context, data, _page, _press);
          },
        ),
      ),
    );
  }
}

/// A folio's cover: slide 1 (or every slide, pageable) at the template's own
/// aspect, with the page edges behind and the press dim on top.
class _Cover extends StatelessWidget {
  final TemplateSummary summary;
  final _FolioContext ctx;
  final _FolioData? data;
  final double width;
  final bool pageable;
  final ValueNotifier<int> page;
  final Animation<double> press;

  const _Cover({
    required this.summary,
    required this.ctx,
    required this.data,
    required this.width,
    required this.pageable,
    required this.page,
    required this.press,
  });

  @override
  Widget build(BuildContext context) {
    final height = width / aspectRatioOf(summary.aspectRatio);
    return SizedBox(
      key: ValueKey('template-cover-${summary.id}'),
      width: width,
      height: height,
      child: PageEdges(
        slides: data?.slideCount ?? 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Shared with the preview's canvas: the cover flies into place.
            Hero(
              tag: 'template-${summary.id}',
              child: ColoredBox(
                color: context.colors.paperDeep,
                child: _artwork(),
              ),
            ),
            IgnorePointer(
              child: AnimatedBuilder(
                animation: press,
                builder: (context, _) => ColoredBox(
                  color: context.colors.ink.withValues(
                    alpha: 0.06 * press.value,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _artwork() {
    final d = data;
    if (d == null) return _staticThumb(summary);
    if (!pageable || d.slideCount < 2) {
      // The boundary is not decoration: a cover is expensive to paint and
      // never changes once built, so without it every folio repaints on
      // every frame of a scroll.
      return RepaintBoundary(
        child: Center(
          child: IgnorePointer(
            child: SlideView(
              document: d.document,
              slideIndex: 0,
              fontResolver: ctx.fontResolver,
              assetCatalog: d.catalog,
              showTemplatePhotos: true,
            ),
          ),
        ),
      );
    }
    return PageView.builder(
      itemCount: d.slideCount,
      onPageChanged: (i) => page.value = i,
      itemBuilder: (context, i) => Center(
        // Inert: the folio's GestureDetector keeps the tap, the PageView
        // keeps the horizontal drag.
        child: IgnorePointer(
          child: SlideView(
            document: d.document,
            slideIndex: i,
            fontResolver: ctx.fontResolver,
            assetCatalog: d.catalog,
            showTemplatePhotos: true,
          ),
        ),
      ),
    );
  }
}

Widget _staticThumb(TemplateSummary summary) {
  final thumb = summary.thumbnailDataUrl;
  return thumb != null && thumb.contains(',')
      ? Image.memory(base64Decode(thumb.split(',').last), fit: BoxFit.cover)
      : const SizedBox.expand();
}

/// The caption's top rule: 1px ink, with a heavier stroke drawing left to
/// right while the folio is pressed.
class _CaptionRule extends StatelessWidget {
  final Animation<double> press;

  const _CaptionRule({required this.press});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2,
      child: AnimatedBuilder(
        animation: press,
        builder: (context, _) => Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Hairline(color: context.colors.ink),
            ),
            FractionallySizedBox(
              widthFactor: press.value,
              child: Container(height: 2, color: context.colors.ink),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _ticksFor(_FolioData? data, ValueNotifier<int> page) {
  final n = data?.slideCount ?? 0;
  if (n < 2) return const SizedBox(height: 3);
  return ValueListenableBuilder<int>(
    valueListenable: page,
    builder: (context, p, _) => Ticks(count: n, active: p),
  );
}

// ── Folio layouts ────────────────────────────────────────────────────────

/// The featured strip: eyebrow, the template's slides at 4:5-ish size paging
/// sideways (bleeding off the right edge), ticks, name and meta.
class _Featured extends StatelessWidget {
  final TemplateSummary summary;
  final _FolioContext ctx;

  const _Featured({required this.summary, required this.ctx});

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context).width;
    final content = screen - 2 * AppSpace.margin;
    final aspect = aspectRatioOf(summary.aspectRatio);
    var slideW = content * 0.71;
    var slideH = slideW / aspect;
    // Tall formats would fill the screen; cap the height instead.
    final maxH = content * 1.12;
    if (slideH > maxH) {
      slideH = maxH;
      slideW = slideH * aspect;
    }
    // Whole device pixels: with a fractional width every seam lands mid-
    // pixel, both neighbours antialias it, and the background shows through
    // as a hairline between slides that should read as one image.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    slideW = (slideW * dpr).floorToDouble() / dpr;
    slideH = slideW / aspect;
    // Flush: a carousel is one continuous image, so neighbouring slides
    // touch and anything crossing a cut continues across it.
    const gap = 0.0;
    final viewport = screen - AppSpace.margin;

    return _FolioShell(
      key: ValueKey('template-card-${summary.id}'),
      summary: summary,
      ctx: ctx,
      builder: (context, data, page, press) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
            child: Row(
              children: [
                const Expanded(child: Eyebrow('N° 01 — Featured')),
                ProMark(visible: summary.premium && !ctx.isPro),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: AppSpace.margin),
            child: SizedBox(
              height: slideH,
              child: Hero(
                tag: 'template-${summary.id}',
                child: data == null
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          key: ValueKey('template-cover-${summary.id}'),
                          width: slideW,
                          child: _staticThumb(summary),
                        ),
                      )
                    : _FeaturedPages(
                        coverKey: ValueKey('template-cover-${summary.id}'),
                        data: data,
                        ctx: ctx,
                        page: page,
                        press: press,
                        fraction: ((slideW + gap) / viewport).clamp(0.1, 1.0),
                        slideWidth: slideW,
                        gap: gap,
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: _ticksFor(data, page),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: Text(summary.name, style: AppType.title(30))),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (summary.category != null)
                      Text(
                        summary.category!,
                        style: AppType.caption.copyWith(
                          color: context.colors.inkSoft,
                        ),
                      ),
                    Text(
                      metaLabel(summary.aspectRatio, data?.slideCount),
                      style: AppType.caption.copyWith(
                        color: context.colors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedPages extends StatelessWidget {
  final Key coverKey;
  final _FolioData data;
  final _FolioContext ctx;
  final ValueNotifier<int> page;
  final Animation<double> press;
  final double fraction;
  final double slideWidth;
  final double gap;

  const _FeaturedPages({
    required this.coverKey,
    required this.data,
    required this.ctx,
    required this.page,
    required this.press,
    required this.fraction,
    required this.slideWidth,
    required this.gap,
  });

  @override
  Widget build(BuildContext context) {
    Widget slide(int i) => Padding(
      padding: EdgeInsets.only(right: gap),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          // The first slide stands for the cover (tests measure its aspect).
          key: i == 0 ? coverKey : null,
          width: slideWidth,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: context.colors.paperDeep,
                child: IgnorePointer(
                  child: Center(
                    child: SlideView(
                      document: data.document,
                      slideIndex: i,
                      fontResolver: ctx.fontResolver,
                      assetCatalog: data.catalog,
                      showTemplatePhotos: true,
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: AnimatedBuilder(
                  animation: press,
                  builder: (context, _) => ColoredBox(
                    color: context.colors.ink.withValues(
                      alpha: .06 * press.value,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (data.slideCount < 2) return slide(0);
    return _FractionPageView(
      fraction: fraction,
      count: data.slideCount,
      onPage: (i) => page.value = i,
      builder: slide,
    );
  }
}

/// A PageView whose pages are [fraction] of the viewport, left-aligned, so
/// the next slide peeks in from the right edge.
class _FractionPageView extends StatefulWidget {
  final double fraction;
  final int count;
  final ValueChanged<int> onPage;
  final Widget Function(int) builder;

  const _FractionPageView({
    required this.fraction,
    required this.count,
    required this.onPage,
    required this.builder,
  });

  @override
  State<_FractionPageView> createState() => _FractionPageViewState();
}

class _FractionPageViewState extends State<_FractionPageView> {
  late PageController _controller = PageController(
    viewportFraction: widget.fraction,
  );

  @override
  void didUpdateWidget(_FractionPageView old) {
    super.didUpdateWidget(old);
    if ((old.fraction - widget.fraction).abs() > 0.001) {
      final page = _controller.hasClients ? _controller.page?.round() ?? 0 : 0;
      _controller.dispose();
      _controller = PageController(
        viewportFraction: widget.fraction,
        initialPage: page,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageView.builder(
    controller: _controller,
    padEnds: false,
    itemCount: widget.count,
    onPageChanged: widget.onPage,
    itemBuilder: (context, i) => widget.builder(i),
  );
}

/// A wide (4-column) folio with its caption in the remaining 2 columns,
/// bottom-aligned: ticks, a big italic number, rule, category, name, meta.
class _WideFolio extends StatelessWidget {
  final int number;
  final TemplateSummary summary;
  final _FolioContext ctx;
  final double width;
  final bool captionLeft;

  const _WideFolio({
    required this.number,
    required this.summary,
    required this.ctx,
    required this.width,
    required this.captionLeft,
  });

  @override
  Widget build(BuildContext context) {
    final coverW = _span(width, 4);
    final captionW = _span(width, 2);
    return _FolioShell(
      key: ValueKey('template-card-${summary.id}'),
      summary: summary,
      ctx: ctx,
      builder: (context, data, page, press) {
        final cover = _Cover(
          summary: summary,
          ctx: ctx,
          data: data,
          width: coverW,
          pageable: true,
          page: page,
          press: press,
        );
        final caption = SizedBox(
          width: captionW,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!captionLeft) ...[
                _ticksFor(data, page),
                const SizedBox(height: 18),
              ],
              Text(twoDigits(number), style: AppType.numeral(40)),
              const SizedBox(height: 10),
              _CaptionRule(press: press),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (summary.category != null)
                    Expanded(child: Eyebrow(summary.category!, size: 11))
                  else
                    const Spacer(),
                  ProMark(visible: summary.premium && !ctx.isPro, size: 11),
                ],
              ),
              const SizedBox(height: 4),
              Text(summary.name, style: AppType.captionTitle),
              const SizedBox(height: 6),
              Text(
                metaLabel(summary.aspectRatio, data?.slideCount),
                style: AppType.caption.copyWith(color: context.colors.inkSoft),
              ),
              if (captionLeft) ...[
                const SizedBox(height: 14),
                _ticksFor(data, page),
              ],
            ],
          ),
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: captionLeft
              ? [caption, const SizedBox(width: AppSpace.gutter), cover]
              : [cover, const SizedBox(width: AppSpace.gutter), caption],
        );
      },
    );
  }
}

/// A folio with its caption underneath: rule, category + number/Pro, name,
/// meta. Narrow (3-column) folios are static and open on tap; the centred
/// 4-column one pages.
class _StackedFolio extends StatelessWidget {
  final int number;
  final TemplateSummary summary;
  final _FolioContext ctx;
  final double width;
  final bool pageable;
  final bool showNumber;

  const _StackedFolio({
    required this.number,
    required this.summary,
    required this.ctx,
    required this.width,
    this.pageable = false,
    this.showNumber = true,
  });

  @override
  Widget build(BuildContext context) {
    return _FolioShell(
      key: ValueKey('template-card-${summary.id}'),
      summary: summary,
      ctx: ctx,
      builder: (context, data, page, press) => SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Cover(
              summary: summary,
              ctx: ctx,
              data: data,
              width: width,
              pageable: pageable,
              page: page,
              press: press,
            ),
            if (pageable) ...[
              const SizedBox(height: 12),
              _ticksFor(data, page),
            ],
            const SizedBox(height: 12),
            _CaptionRule(press: press),
            const SizedBox(height: 10),
            if (showNumber) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: summary.category == null
                        ? const SizedBox.shrink()
                        : Eyebrow(summary.category!, size: 11),
                  ),
                  ProMark(visible: summary.premium && !ctx.isPro, size: 11),
                  const SizedBox(width: 8),
                  Text(twoDigits(number), style: AppType.numeral(18)),
                ],
              ),
              const SizedBox(height: 4),
              Text(summary.name, style: AppType.captionTitle),
              const SizedBox(height: 6),
              Text(
                [
                  formatNameOf(summary.aspectRatio),
                  metaLabel(summary.aspectRatio, data?.slideCount),
                ].join(' '),
                style: AppType.caption.copyWith(color: context.colors.inkSoft),
              ),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(summary.name, style: AppType.title(22))),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        ProMark(
                          visible: summary.premium && !ctx.isPro,
                          size: 11,
                        ),
                        Text(
                          [
                            ?summary.category,
                            if (data != null) slidesLabel(data.slideCount),
                          ].join(' · '),
                          textAlign: TextAlign.end,
                          style: AppType.caption.copyWith(
                            color: context.colors.inkSoft,
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
    );
  }
}

/// The full-bleed sequence: the template's whole continuous document as one
/// strip running off the right edge — "read as a sequence".
class _SequenceFolio extends StatelessWidget {
  final int number;
  final TemplateSummary summary;
  final _FolioContext ctx;

  const _SequenceFolio({
    required this.number,
    required this.summary,
    required this.ctx,
  });

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context).width;
    final content = screen - 2 * AppSpace.margin;
    final aspect = aspectRatioOf(summary.aspectRatio);
    final height = math.min(content * 0.47, 240.0);
    final slideW = height * aspect;
    return _FolioShell(
      key: ValueKey('template-card-${summary.id}'),
      summary: summary,
      ctx: ctx,
      builder: (context, data, page, press) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Row(
              children: [
                Expanded(
                  child: Eyebrow(
                    'N° ${twoDigits(number)} — Read as a sequence',
                  ),
                ),
                ProMark(visible: summary.premium && !ctx.isPro),
                if (data != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    slidesLabel(data.slideCount),
                    style: AppType.caption.copyWith(
                      color: context.colors.inkSoft,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            key: ValueKey('template-cover-${summary.id}'),
            height: height,
            child: Stack(
              children: [
                data == null
                    ? Padding(
                        padding: const EdgeInsets.only(left: AppSpace.margin),
                        child: SizedBox(
                          width: slideW,
                          height: height,
                          child: _staticThumb(summary),
                        ),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.margin,
                        ),
                        child: Hero(
                          tag: 'template-${summary.id}',
                          child: _DocumentStrip(
                            data: data,
                            ctx: ctx,
                            height: height,
                          ),
                        ),
                      ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: press,
                      builder: (context, _) => ColoredBox(
                        color: context.colors.ink.withValues(
                          alpha: 0.06 * press.value,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: Text(summary.name, style: AppType.title(26))),
                const SizedBox(width: 12),
                Text(
                  [
                    ?summary.category,
                    ratioLabelOf(summary.aspectRatio),
                  ].join(' · '),
                  style: AppType.caption.copyWith(
                    color: context.colors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A template's whole continuous document at [height] — one canvas, so the
/// slides sit flush and anything crossing a cut continues unbroken.
class _DocumentStrip extends StatelessWidget {
  final _FolioData data;
  final _FolioContext ctx;
  final double height;

  const _DocumentStrip({
    required this.data,
    required this.ctx,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final doc = data.document;
    final scale = height / doc.slideHeight;
    return RepaintBoundary(
      child: IgnorePointer(
        child: SizedBox(
          width: doc.contentWidth * scale,
          height: height,
          child: CanvasView(
            document: doc,
            content: const SlotContent(),
            fontResolver: ctx.fontResolver,
            assetCatalog: data.catalog,
            showTemplatePhotos: true,
          ),
        ),
      ),
    );
  }
}

// ── Discover chrome ──────────────────────────────────────────────────────

class _Masthead extends StatelessWidget {
  final bool offline;
  final VoidCallback onSettings;

  const _Masthead({required this.offline, required this.onSettings});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Layer',
                  style: AppType.serif(26, italic: true, tracking: -.02),
                ),
              ),
              IconButton(
                icon: const Icon(Symbols.settings, size: 24),
                tooltip: 'Settings',
                onPressed: onSettings,
              ),
            ],
          ),
          if (offline)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 12),
              child: Row(
                children: [
                  Icon(
                    Symbols.cloud_off,
                    size: 15,
                    color: context.colors.rouge,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Eyebrow(
                      'Offline — saved copies',
                      size: 11,
                      color: context.colors.rouge,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
    child: SerifHeadline(
      roman: 'Make something',
      italic: 'worth keeping.',
      breakLine: true,
      style: AppType.display,
    ),
  );
}

class _EndNote extends StatelessWidget {
  const _EndNote();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 64, 20, 40),
    child: Column(
      children: [
        Text(
          "That's the collection.",
          textAlign: TextAlign.center,
          style: AppType.serif(22, italic: true),
        ),
        const SizedBox(height: 8),
        Text(
          'Pull down to check for new templates.',
          textAlign: TextAlign.center,
          style: AppType.bodyS.copyWith(color: context.colors.inkSoft),
        ),
      ],
    ),
  );
}

class _OutOfReach extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onProjects;

  const _OutOfReach({required this.onRetry, required this.onProjects});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SerifHeadline(
            roman: 'The collection',
            italic: 'is out of reach.',
            breakLine: true,
            style: AppType.headline,
          ),
          const SizedBox(height: 18),
          Text(
            "Couldn't load templates. Check your connection and try again "
            '— your projects are still here.',
            style: AppType.body.copyWith(color: context.colors.inkSoft),
          ),
          const SizedBox(height: 28),
          SecondaryButton(
            label: 'Try again',
            icon: Symbols.refresh,
            onPressed: onRetry,
          ),
          const SizedBox(height: 8),
          Center(child: TextLink('Open Projects', onTap: onProjects)),
        ],
      ),
    );
  }
}

/// The category index: Newsreader words with a superscript count, sticky
/// under the headline. Bordered 1px ink on top, 1px rule beneath.
class _CategoryIndexDelegate extends SliverPersistentHeaderDelegate {
  final int total;
  final List<String> categories;
  final Map<String, int> counts;
  final String? active;
  final ValueChanged<String?> onSelect;

  _CategoryIndexDelegate({
    required this.total,
    required this.categories,
    required this.counts,
    required this.active,
    required this.onSelect,
  });

  static const double _height = 54;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  bool shouldRebuild(_CategoryIndexDelegate old) => true;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.paper,
        border: Border(
          top: BorderSide(color: context.colors.ink),
          bottom: BorderSide(color: context.colors.rule),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.margin),
        children: [
          _CategoryWord(
            label: 'All',
            count: total,
            selected: active == null,
            onTap: () => onSelect(null),
          ),
          for (final c in categories)
            _CategoryWord(
              label: c,
              count: counts[c] ?? 0,
              selected: active == c,
              onTap: () => onSelect(c),
            ),
        ],
      ),
    );
  }
}

class _CategoryWord extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryWord({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? context.colors.ink : context.colors.stone;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(right: 24),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Container(
              padding: const EdgeInsets.only(bottom: 9),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected ? context.colors.ink : Colors.transparent,
                  ),
                ),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: label),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.top,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 3),
                        child: Text(
                          '$count',
                          style: AppType.sans(
                            11,
                            color: selected
                                ? context.colors.rouge
                                : context.colors.stone,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                style: AppType.category.copyWith(color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Breathing ghost folios in the collection's ragged silhouette, shown while
/// the index loads: paperDeep ↔ table at 900ms, static under reduced motion.
class _SkeletonFolios extends StatefulWidget {
  const _SkeletonFolios();

  @override
  State<_SkeletonFolios> createState() => _SkeletonFoliosState();
}

class _SkeletonFoliosState extends State<_SkeletonFolios>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
      _pulse.value = 0;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          return AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final tone = Color.lerp(
                context.colors.paperDeep,
                context.colors.table,
                Curves.easeInOut.transform(_pulse.value),
              )!;
              Widget block(double bw, double bh) =>
                  Container(width: bw, height: bh, color: tone);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  block(w * .45, 12),
                  const SizedBox(height: 16),
                  block(w * .71, w * .71 * 1.25),
                  const SizedBox(height: 48),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      block(_span(w, 4), _span(w, 4) / (9 / 16)),
                      const SizedBox(width: AppSpace.gutter),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          block(_span(w, 1), 30),
                          const SizedBox(height: 12),
                          block(_span(w, 2), 14),
                          const SizedBox(height: 8),
                          block(_span(w, 2) * .7, 10),
                        ],
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// One-shot entrance for collection rows: fade in while sliding up, staggered
/// by [order] (capped so deep rows don't wait). Runs once per element — a
/// rebuild (e.g. the unlock flip) never replays it.
class _AppearFromBelow extends StatefulWidget {
  final int order;
  final Widget child;

  const _AppearFromBelow({super.key, required this.order, required this.child});

  @override
  State<_AppearFromBelow> createState() => _AppearFromBelowState();
}

class _AppearFromBelowState extends State<_AppearFromBelow>
    with SingleTickerProviderStateMixin {
  // The stagger is an Interval inside one controller run — no timers, so
  // widget tests never end with one pending.
  static const int _kStepMs = 40;
  static const int _kFadeMs = 240;

  late final int _delayMs = _kStepMs * widget.order.clamp(0, 8);
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _delayMs + _kFadeMs),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _in.value = 1;
    } else {
      _in.forward();
    }
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(
      parent: _in,
      curve: Interval(
        _delayMs / (_delayMs + _kFadeMs),
        1,
        curve: Curves.easeOutCubic,
      ),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curve),
        child: widget.child,
      ),
    );
  }
}

// ── Navigation ───────────────────────────────────────────────────────────

/// The home's bottom bar: Discover and Projects flanking the create square.
/// Grid `1fr 72 1fr`; the active destination is ink with a short rouge rule
/// at the bar's top edge — the one rouge mark.
class _HomeBottomBar extends StatelessWidget {
  final int current;
  final ValueChanged<int> onSelect;
  final VoidCallback onCreate;

  const _HomeBottomBar({
    required this.current,
    required this.onSelect,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.paper,
        border: Border(top: BorderSide(color: context.colors.rule)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              Expanded(
                child: _NavItem(
                  icon: Symbols.auto_stories,
                  label: 'Discover',
                  selected: current == 0,
                  onTap: () => onSelect(0),
                ),
              ),
              SizedBox(
                width: 72,
                child: Center(child: _CreateButton(onTap: onCreate)),
              ),
              Expanded(
                child: _NavItem(
                  icon: Symbols.photo_library,
                  label: 'Projects',
                  selected: current == 1,
                  onTap: () => onSelect(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? context.colors.ink : context.colors.inkSoft;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 24,
                  weight: selected ? 300 : 200,
                  color: color,
                ),
                const SizedBox(height: 4),
                Text(label, style: AppType.navLabel(color: color)),
              ],
            ),
            if (selected)
              Positioned(
                top: 0,
                child: Container(
                  width: 18,
                  height: 2,
                  color: context.colors.rouge,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Create-from-scratch: the ink square in the middle of the bar.
class _CreateButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CreateButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.ink,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 52,
          height: 44,
          child: Icon(
            Symbols.add,
            size: 24,
            weight: 250,
            color: context.colors.onInk,
            semanticLabel: 'Create from scratch',
          ),
        ),
      ),
    );
  }
}

// ── Blank canvas sheet ───────────────────────────────────────────────────

class _BlankCanvasSheet extends StatefulWidget {
  const _BlankCanvasSheet();

  @override
  State<_BlankCanvasSheet> createState() => _BlankCanvasSheetState();
}

class _BlankCanvasSheetState extends State<_BlankCanvasSheet> {
  // (name, ratio, width, height, drawn frame size)
  static const _formats = [
    ('Story', '9:16', 1080.0, 1920.0, Size(72, 128)),
    ('Portrait', '4:5', 1080.0, 1350.0, Size(96, 120)),
    ('Square', '1:1', 1080.0, 1080.0, Size(100, 100)),
  ];

  int _selected = 1;

  @override
  Widget build(BuildContext context) {
    final chosen = _formats[_selected];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "Choose a format. You can add slides once you're in.",
          style: AppType.bodyS.copyWith(color: context.colors.inkSoft),
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < _formats.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: _formatOption(i)),
            ],
          ],
        ),
        const SizedBox(height: 28),
        PrimaryButton(
          label: 'Start with ${chosen.$1}',
          onPressed: () =>
              Navigator.of(context).pop((chosen.$2, chosen.$3, chosen.$4)),
        ),
      ],
    );
  }

  Widget _formatOption(int i) {
    final (name, ratio, w, h, frame) = _formats[i];
    final selected = i == _selected;
    final box = Container(
      width: frame.width,
      height: frame.height,
      decoration: BoxDecoration(
        color: selected ? Colors.transparent : context.colors.paperDeep,
        border: Border.all(color: context.colors.ink),
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: '$name $ratio',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selected = i),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 140,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: selected
                      ? Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            border: Border.all(color: context.colors.ink),
                          ),
                          child: box,
                        )
                      : Padding(padding: const EdgeInsets.all(5), child: box),
                ),
              ),
            ),
            Hairline(color: context.colors.ink),
            const SizedBox(height: 10),
            Text(name, style: AppType.title(20)),
            const SizedBox(height: 4),
            Text(
              '$ratio · ${w.toInt()}×${h.toInt()}',
              style: AppType.caption.copyWith(color: context.colors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}
