import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

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
import 'projects_screen.dart';
import 'settings_screen.dart';
import 'template_preview_screen.dart';
import 'template_screen.dart';

class GalleryScreen extends StatefulWidget {
  /// Both are owned by `main()` in production; tests inject fakes.
  final EntitlementsService? entitlements;
  final TemplateStore? store;

  /// Threaded through preview/editor; tests inject a synchronous fake.
  final FontResolver fontResolver;

  const GalleryScreen({
    super.key,
    this.entitlements,
    this.store,
    this.fontResolver = googleFontsResolver,
  });

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  late final _entitlements = widget.entitlements ?? EntitlementsService();
  late final _store = widget.store ?? TemplateStore();
  // Handed to every editor session so it auto-saves as a project; the
  // projects themselves are listed on ProjectsScreen, not here.
  final _projects = ProjectStore();
  late Future<IndexResult> _index;

  // Frames/stickers for the cards' live panel renders (multi-panel templates
  // swipe through real canvases, not the static thumbnail).
  List<AssetRecord> _assets = const [];

  // Category filter chip selection; null = All. Cleared implicitly when the
  // selected category disappears from a refreshed index (see the guard in
  // _buildTemplatesTab).
  String? _category;

  // Bottom-bar destination: 0 templates, 1 projects, 2 settings. The create
  // button in the bar is an action, not a destination — it never lands here.
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _index = _store.loadIndex();
    _loadAssets();
  }

  /// Best-effort, like the preview screen: offline (or on error) the cards
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
    await next;
  }

  Future<void> _openTemplate(TemplateSummary summary) async {
    // The loaded index rides along for the paywall's template mosaic; a card
    // is only tappable once _index resolved, so this await is immediate.
    var catalog = const <TemplateSummary>[];
    try {
      catalog = (await _index).templates;
    } catch (_) {
      // No index, no mosaic — the paywall falls back to its gradient.
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

  /// Create-from-scratch entry: pick a canvas size, then open the editor on a
  /// blank draft — everything (text, images, grids, assets, panels) is built
  /// there with the bottom toolbar.
  Future<void> _createFromScratch() async {
    final canvas = await showModalBottomSheet<(String, double, double)>(
      context: context,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Canvas size',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            for (final (label, aspect, w, h) in const [
              ('Story', '9:16', 1080.0, 1920.0),
              ('Portrait', '4:5', 1080.0, 1350.0),
              ('Square', '1:1', 1080.0, 1080.0),
            ])
              ListTile(
                leading: const Icon(Symbols.crop_free_rounded),
                title: Text(label),
                subtitle: Text('$aspect · ${w.toInt()}×${h.toInt()}'),
                onTap: () => Navigator.pop(sheetContext, (aspect, w, h)),
              ),
          ],
        ),
      ),
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Two bottom-bar destinations around the center create button; settings
    // lives behind the gear in the header. The switch rebuilds the destination
    // on every visit, so the projects tab always lists fresh saves.
    final (title, body) = switch (_tab) {
      1 => (
        'My projects',
        ProjectsList(store: _projects, fontResolver: widget.fontResolver)
            as Widget,
      ),
      _ => ('Collage Studio', _buildTemplatesTab()),
    };
    return Scaffold(
      bottomNavigationBar: _HomeBottomBar(
        current: _tab,
        onSelect: (i) => setState(() => _tab = i),
        onCreate: _createFromScratch,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Symbols.settings_rounded,
                      color: AppColors.textSecondary,
                    ),
                    tooltip: 'Settings',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            SettingsScreen(entitlements: _entitlements),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplatesTab() {
    return FutureBuilder<IndexResult>(
      future: _index,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // Ghost cards where the real ones will land — the layout doesn't
          // jump when the index arrives.
          return const _SkeletonGrid();
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Could not load templates.\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _refresh, child: const Text('Retry')),
                ],
              ),
            ),
          );
        }
        final result = snapshot.data!;
        final templates = result.templates;
        final categories = <String>{
          for (final t in templates)
            if (t.category != null) t.category!,
        }.toList()..sort();
        // A stale selection (category gone after a refresh) reads as All.
        final active = categories.contains(_category) ? _category : null;
        final visible = active == null
            ? templates
            : [
                for (final t in templates)
                  if (t.category == active) t,
              ];
        return Column(
          children: [
            if (result.fromCache)
              // A quiet status pill, not an alarm strip: offline is a state,
              // not an error.
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.outline),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Symbols.cloud_off_rounded,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Offline — showing downloaded templates',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (categories.isNotEmpty)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  children: [
                    _FilterChip(
                      label: 'All',
                      selected: active == null,
                      onTap: () => setState(() => _category = null),
                    ),
                    for (final category in categories)
                      _FilterChip(
                        label: category,
                        selected: active == category,
                        onTap: () => setState(() => _category = category),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: templates.isEmpty
                  ? const _EmptyTab(
                      icon: Symbols.grid_view_rounded,
                      message: 'No templates published yet.',
                    )
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      // Rebuilds when a purchase lands so the locks vanish.
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _entitlements.isPro,
                        builder: (context, isPro, _) => GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate: _kGridDelegate,
                          itemCount: visible.length,
                          itemBuilder: (context, i) => _AppearFromBelow(
                            // Re-keyed per template so switching category
                            // filters replays the entrance on the new set.
                            key: ValueKey(visible[i].id),
                            order: i,
                            child: _TemplateCard(
                              summary: visible[i],
                              locked: visible[i].premium && !isPro,
                              store: _store,
                              fontResolver: widget.fontResolver,
                              catalog: _assets,
                              onTap: () => _openTemplate(visible[i]),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// The home's bottom bar: templates and projects flanking the create button,
/// which sits dead-center, accent-filled because creating is THE action of
/// the app — the destinations stay quiet.
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
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              Expanded(
                child: _NavItem(
                  icon: Symbols.grid_view_rounded,
                  label: 'Templates',
                  selected: current == 0,
                  onTap: () => onSelect(0),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _CreateButton(onTap: onCreate),
              ),
              Expanded(
                child: _NavItem(
                  icon: Symbols.space_dashboard_rounded,
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
    final color = selected ? AppColors.textPrimary : AppColors.textSecondary;
    return InkResponse(
      onTap: onTap,
      radius: 40,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24, fill: selected ? 1 : 0, color: color),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Create-from-scratch: an action styled like the FAB it replaces.
class _CreateButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CreateButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: const SizedBox(
          width: 52,
          height: 44,
          child: Icon(
            Symbols.add_rounded,
            size: 26,
            color: AppColors.onAccent,
            semanticLabel: 'Create from scratch',
          ),
        ),
      ),
    );
  }
}

/// Shared by the real grid and its skeleton so the loading layout is exact.
const SliverGridDelegate _kGridDelegate =
    SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      childAspectRatio: 0.62,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
    );

/// Pulsing ghost cards shown while the template index loads.
class _SkeletonGrid extends StatefulWidget {
  const _SkeletonGrid();

  @override
  State<_SkeletonGrid> createState() => _SkeletonGridState();
}

class _SkeletonGridState extends State<_SkeletonGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Repeat only under an active ticker; a static ghost respects the
    // system's reduced-motion setting.
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
      _pulse.value = 1;
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
    return FadeTransition(
      opacity: Tween(
        begin: 0.45,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        gridDelegate: _kGridDelegate,
        itemCount: 6,
        itemBuilder: (context, i) => Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(child: ColoredBox(color: AppColors.surfaceHigh)),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bar(widthFactor: 0.6, height: 12),
                    const SizedBox(height: 6),
                    _bar(widthFactor: 0.4, height: 10),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _bar({required double widthFactor, required double height}) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppColors.surfaceBright,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

/// One-shot entrance for grid items: fade in while sliding up 12px, staggered
/// by [order] (capped so deep items don't wait). Runs once per element — a
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

/// A category pill: accent-filled when active (selection is an action),
/// quiet otherwise.
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.onAccent : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty state: an icon above the message, quiet and centered.
class _EmptyTab extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyTab({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final TemplateSummary summary;
  final bool locked;
  final TemplateStore store;
  final FontResolver fontResolver;
  final List<AssetRecord> catalog;
  final VoidCallback onTap;

  const _TemplateCard({
    required this.summary,
    required this.locked,
    required this.store,
    required this.fontResolver,
    required this.catalog,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      // Stable per-template handle (the visible name was removed): lets tests
      // and Heroes target a specific card without a text label.
      key: ValueKey('template-card-${summary.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Shared with the preview screen's canvas: the thumbnail
                  // flies into place instead of vanishing and reappearing.
                  Hero(
                    tag: 'template-${summary.id}',
                    child: _CardCarousel(
                      summary: summary,
                      store: store,
                      fontResolver: fontResolver,
                      catalog: catalog,
                    ),
                  ),
                  // Always mounted so the badge can animate out the moment a
                  // purchase lands (isPro rebuilds flip [locked] live).
                  Positioned(
                    top: 8,
                    right: 8,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      switchInCurve: Curves.easeOutBack,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: locked
                          ? Container(
                              key: const ValueKey('locked'),
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.lock,
                                size: 16,
                                color: AppColors.gold,
                              ),
                            )
                          : const SizedBox.shrink(key: ValueKey('unlocked')),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // The gold badge already says premium; repeating it in
                    // text would be noise.
                    [
                      summary.aspectRatio,
                      if (summary.category != null) summary.category!,
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The card's thumbnail area. Single-panel templates keep the static index
/// thumbnail; multi-panel ones become a mini carousel of live panel renders,
/// so every slide of a carousel template can be seen right from the home.
/// The template comes from the prefetch cache ([TemplateStore
/// .loadTemplateCached]) — the grid itself never hits the network per card.
class _CardCarousel extends StatefulWidget {
  final TemplateSummary summary;
  final TemplateStore store;
  final FontResolver fontResolver;
  final List<AssetRecord> catalog;

  const _CardCarousel({
    required this.summary,
    required this.store,
    required this.fontResolver,
    required this.catalog,
  });

  @override
  State<_CardCarousel> createState() => _CardCarouselState();
}

class _CardCarouselState extends State<_CardCarousel> {
  late final Future<TemplateResult> _template = widget.store.loadTemplateCached(
    widget.summary.id,
  );

  /// Dots only — same trick as the preview screen: a page change repaints
  /// the dots row, never the mounted canvases.
  final _page = ValueNotifier<int>(0);

  /// Recreated when the slide width changes (viewportFraction is final): each
  /// page is sized to the canvas' rendered width so adjacent panels sit flush
  /// and the carousel bleed reads as one image — the preview screen's fix,
  /// applied to the card. See _controllerFor.
  PageController _pageController = PageController();
  double? _viewportFraction;

  @override
  void dispose() {
    _pageController.dispose();
    _page.dispose();
    super.dispose();
  }

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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TemplateResult>(
      future: _template,
      builder: (context, snapshot) {
        final template = snapshot.data?.template;
        // Loading, failed, or nothing to swipe: the static thumbnail is
        // exactly what this card always showed.
        if (template == null || template.panels.length < 2) {
          return _staticThumb();
        }
        // The published template folded into the continuous model, so a
        // panorama really spans slides instead of being echoed by a bleed.
        final document = migrateToV4(template, const SlotContent()).document;
        final catalog = [...widget.catalog, ...snapshot.data!.assets];
        return Stack(
          fit: StackFit.expand,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                // Each page is exactly the canvas' rendered width, so the
                // slides touch instead of each floating letterboxed in a
                // full-width page (which read as a gap between panels).
                final aspect = template.canvasWidth / template.canvasHeight;
                final slideWidth = math.min(
                  constraints.maxWidth,
                  constraints.maxHeight * aspect,
                );
                final fraction = (slideWidth / constraints.maxWidth)
                    .clamp(0.05, 1.0)
                    .toDouble();
                return PageView.builder(
                  controller: _controllerFor(fraction),
                  itemCount: document.slideCount,
                  onPageChanged: (i) => _page.value = i,
                  itemBuilder: (context, i) => Center(
                    child: AspectRatio(
                      aspectRatio: template.canvasWidth / template.canvasHeight,
                      // Inert, like the preview: the card's InkWell keeps the
                      // tap, the PageView keeps the horizontal drag.
                      child: IgnorePointer(
                        child: SlideView(
                          document: document,
                          slideIndex: i,
                          fontResolver: widget.fontResolver,
                          assetCatalog: catalog,
                          // Cards show the "with sample photos" look, matching
                          // the static thumbnail they replace.
                          showTemplatePhotos: true,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            // Tiny page dots so the swipe is discoverable; inert so they
            // never steal the card's tap.
            Positioned(
              left: 0,
              right: 0,
              bottom: 6,
              child: IgnorePointer(
                child: ValueListenableBuilder<int>(
                  valueListenable: _page,
                  builder: (context, page, _) => Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < document.slideCount; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: i == page ? 12 : 5,
                          height: 5,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: i == page
                                ? AppColors.accent
                                : Colors.black26,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _staticThumb() {
    final thumb = widget.summary.thumbnailDataUrl;
    return thumb != null && thumb.contains(',')
        ? Image.memory(base64Decode(thumb.split(',').last), fit: BoxFit.contain)
        : const ColoredBox(
            color: AppColors.surfaceHigh,
            child: Center(
              child: Icon(
                Symbols.image_rounded,
                color: AppColors.textSecondary,
              ),
            ),
          );
  }
}
