import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../api/entitlements.dart';
import '../api/project_store.dart';
import '../rendering/template_canvas.dart';
import '../theme.dart';
import '../widgets/layer_ui.dart';
import 'template_screen.dart';

/// Standalone screen wrapper around [ProjectsList] — kept for direct
/// navigation; the home screen embeds the list as its Projects tab.
class ProjectsScreen extends StatelessWidget {
  /// Injectable for tests; the app uses the default documents-dir store.
  final ProjectStore? store;

  const ProjectsScreen({super.key, this.store});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: ProjectsList(store: store)),
    );
  }
}

/// The user's saved editing sessions, newest first — everything auto-saved by
/// the editor (templates they edited and collages created from scratch).
///
/// The archive: the latest project leads at full size as a strip of its
/// pages; the rest file in as catalogue entries with a mini strip. Every
/// strip is the saved document rendered live — no thumbnail files to keep in
/// sync with edits.
class ProjectsList extends StatefulWidget {
  /// Injectable for tests; the app uses the default documents-dir store.
  final ProjectStore? store;

  /// Used by the strips' live render; tests inject a synchronous fake.
  final FontResolver fontResolver;

  /// Threaded into the editor so the asset picker can gate premium assets;
  /// null in tests/standalone (a fresh instance reports free).
  final EntitlementsService? entitlements;

  /// The empty state's "Browse templates" link. Null hides the link.
  final VoidCallback? onBrowseTemplates;

  const ProjectsList({
    super.key,
    this.store,
    this.fontResolver = googleFontsResolver,
    this.entitlements,
    this.onBrowseTemplates,
  });

  @override
  State<ProjectsList> createState() => _ProjectsListState();
}

class _ProjectsListState extends State<ProjectsList> {
  late final ProjectStore _store = widget.store ?? ProjectStore();
  late Future<List<ProjectSummary>> _list;

  @override
  void initState() {
    super.initState();
    _list = _store.list();
  }

  /// The editor auto-saves while open, so the list is refreshed whenever it
  /// pops back here (and after a delete).
  void _reload() {
    if (!mounted) return;
    final next = _store.list();
    // Block body: an arrow closure would RETURN the assigned Future, which
    // setState forbids (and the assertion would abort the rebuild).
    setState(() {
      _list = next;
    });
  }

  Future<void> _open(ProjectSummary summary) async {
    // The editor works on the continuous model; a v3 file is migrated on read
    // (nothing is written back until the user actually edits).
    final project = await _store.loadAsDocument(summary.id);
    if (!mounted) return;
    if (project == null) {
      showLayerMessage(context, 'Could not open this project.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TemplateScreen(
          project: project,
          projects: _store,
          entitlements: widget.entitlements,
        ),
      ),
    );
    _reload();
  }

  /// The row's "…": Open or Delete.
  Future<void> _actions(ProjectSummary summary) async {
    final choice = await showLayerSheet<String>(
      context: context,
      title: summary.name,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Hairline(),
          _SheetRow(
            icon: Symbols.north_east,
            label: 'Open',
            onTap: () => Navigator.pop(sheetContext, 'open'),
          ),
          const Hairline(),
          _SheetRow(
            icon: Symbols.delete,
            label: 'Delete',
            onTap: () => Navigator.pop(sheetContext, 'delete'),
          ),
          const Hairline(),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'open':
        await _open(summary);
      case 'delete':
        await _delete(summary);
    }
  }

  Future<void> _delete(ProjectSummary summary) async {
    final confirmed = await showLayerSheet<bool>(
      context: context,
      title: 'Delete project?',
      deep: true,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '"${summary.name}" and its photos will be removed. '
            'This cannot be undone.',
            style: AppType.bodyS.copyWith(color: context.colors.inkSoft),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Cancel',
                  height: 52,
                  onPressed: () => Navigator.pop(sheetContext, false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrimaryButton.destructive(
                  label: 'Delete',
                  height: 52,
                  onPressed: () => Navigator.pop(sheetContext, true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.delete(summary.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ProjectSummary>>(
      future: _list,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        final projects = snapshot.data ?? <ProjectSummary>[];
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _Header(count: loading ? null : projects.length),
            ),
            if (loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: LayerSpinner()),
              )
            else if (projects.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyArchive(onBrowse: widget.onBrowseTemplates),
              )
            else ...[
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 14, 20, 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Eyebrow('Most recent first')),
                      Eyebrow('Saves itself'),
                    ],
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: projects.length,
                itemBuilder: (context, i) {
                  final summary = projects[i];
                  return _ProjectEntry(
                    // Keyed by project id: after a delete the rows shift, and
                    // a positional key would hand row N the strip state (and
                    // its cached future) of the row that used to sit there.
                    key: ValueKey('project-${summary.id}'),
                    index: i,
                    store: _store,
                    summary: summary,
                    fontResolver: widget.fontResolver,
                    onOpen: () => _open(summary),
                    onActions: () => _actions(summary),
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final int? count;

  const _Header({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: Text('Projects', style: AppType.headlineL)),
              if (count != null)
                Text(
                  twoDigits(count!),
                  style: AppType.numeral(30, color: context.colors.stone),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Hairline(color: context.colors.ink),
        ],
      ),
    );
  }
}

class _EmptyArchive extends StatelessWidget {
  final VoidCallback? onBrowse;

  const _EmptyArchive({required this.onBrowse});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // The shape of what will be there: three pages, fading out.
          SizedBox(
            height: 108,
            child: Row(
              children: [
                for (final (i, c) in [
                  context.colors.inkSoft,
                  context.colors.ruleStrong,
                  context.colors.rule,
                ].indexed) ...[
                  if (i > 0) const SizedBox(width: 6),
                  SizedBox(
                    width: i == 2 ? 44 : 86,
                    child: DashedBox(color: c, child: const SizedBox.expand()),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 26),
          SerifHeadline(
            roman: 'Nothing here ',
            italic: 'yet.',
            style: AppType.title(34),
          ),
          const SizedBox(height: 14),
          Text(
            'Edit a template or start from a blank canvas — it saves itself, '
            'page by page.',
            style: AppType.body.copyWith(color: context.colors.inkSoft),
          ),
          if (onBrowse != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                TextLink('Browse templates', onTap: onBrowse, size: 15),
                const SizedBox(width: 20),
                Text(
                  'or tap +',
                  style: AppType.sans(15, color: context.colors.inkSoft),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SheetRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: SizedBox(
      height: 54,
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppType.label)),
          Icon(icon, size: 20, weight: 300),
        ],
      ),
    ),
  );
}

/// One project: the latest (index 0) as a large page strip with name, edit
/// time and an actions button; the rest as catalogue rows.
class _ProjectEntry extends StatefulWidget {
  final int index;
  final ProjectStore store;
  final ProjectSummary summary;
  final FontResolver fontResolver;
  final VoidCallback onOpen;
  final VoidCallback onActions;

  const _ProjectEntry({
    super.key,
    required this.index,
    required this.store,
    required this.summary,
    required this.fontResolver,
    required this.onOpen,
    required this.onActions,
  });

  @override
  State<_ProjectEntry> createState() => _ProjectEntryState();
}

class _ProjectEntryState extends State<_ProjectEntry> {
  // Cached across rebuilds so scrolls/reloads don't re-read the file; the
  // entry's ValueKey retires this state when the id changes.
  // Loaded into the v4 continuous model: a v3 file is migrated on READ (the
  // store writes nothing), so the strip previews the same document the
  // editor will eventually work in.
  late final Future<ContinuousProject?> _project = widget.store.loadAsDocument(
    widget.summary.id,
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ContinuousProject?>(
      future: _project,
      builder: (context, snapshot) {
        final project = snapshot.data;
        final slides = project?.document.slideCount;
        final edited = relativeTime(widget.summary.updatedAt);
        return widget.index == 0
            ? _latest(project, slides, edited)
            : _row(project, slides, edited);
      },
    );
  }

  Widget _moreButton() => IconButton(
    icon: const Icon(Symbols.more_horiz, size: 22),
    tooltip: 'Project actions',
    onPressed: widget.onActions,
  );

  Widget _latest(ContinuousProject? project, int? slides, String edited) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpen,
            child: LayoutBuilder(
              builder: (context, constraints) => _DocumentStrip(
                project: project,
                fontResolver: widget.fontResolver,
                // 176×220 per 4:5 slide at a 390pt screen; scales with width.
                height: math.min(220 * constraints.maxWidth / 350, 320),
                maxWidth: constraints.maxWidth,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onOpen,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.summary.name, style: AppType.title(24)),
                      const SizedBox(height: 6),
                      Text(
                        [
                          'Edited $edited',
                          if (slides != null)
                            slides == 1 ? '1 slide' : '$slides slides',
                        ].join(' · '),
                        style: AppType.sans(14, color: context.colors.inkSoft),
                      ),
                    ],
                  ),
                ),
              ),
              _moreButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(ContinuousProject? project, int? slides, String edited) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.margin),
      child: Column(
        children: [
          const Hairline(),
          InkWell(
            onTap: widget.onOpen,
            onLongPress: widget.onActions,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 14, 0, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 40,
                    child: Text(
                      twoDigits(widget.index + 1),
                      style: AppType.numeral(22),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) =>
                                    _DocumentStrip(
                                      project: project,
                                      fontResolver: widget.fontResolver,
                                      height: 75,
                                      maxWidth: constraints.maxWidth,
                                      scrollable: false,
                                    ),
                              ),
                            ),
                            _moreButton(),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Text(
                                widget.summary.name,
                                style: AppType.title(20),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              [edited, ?slides?.toString()].join(' · '),
                              style: AppType.sans(
                                13,
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
            ),
          ),
        ],
      ),
    );
  }
}

/// The WHOLE saved document in one continuous canvas (Modelo B), [height]
/// tall — slides flush, anything crossing a cut continuous. Wider than
/// [maxWidth] it scrolls sideways (the latest project) or is clipped (rows).
class _DocumentStrip extends StatelessWidget {
  final ContinuousProject? project;
  final FontResolver fontResolver;
  final double height;
  final double maxWidth;
  final bool scrollable;

  const _DocumentStrip({
    required this.project,
    required this.fontResolver,
    required this.height,
    required this.maxWidth,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = project;
    if (p == null || p.document.slideCount == 0) {
      // Loading, corrupt or empty — a quiet page placeholder; a broken
      // project still opens the "couldn't open" path when tapped.
      return Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: height * 0.8,
          height: height,
          child: ColoredBox(color: context.colors.paperDeep),
        ),
      );
    }
    final doc = p.document;
    final scale = height / doc.slideHeight;
    final canvas = RepaintBoundary(
      child: IgnorePointer(
        child: SizedBox(
          width: doc.contentWidth * scale,
          height: height,
          child: CanvasView(
            document: doc,
            content: p.content,
            fontResolver: fontResolver,
          ),
        ),
      ),
    );
    return SizedBox(
      height: height,
      width: maxWidth,
      child: scrollable
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: canvas,
            )
          : ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: double.infinity,
                child: canvas,
              ),
            ),
    );
  }
}
