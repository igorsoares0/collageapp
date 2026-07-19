import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../api/project_store.dart';
import '../rendering/template_canvas.dart';
import '../theme.dart';
import 'template_screen.dart';

/// Standalone screen wrapper around [ProjectsList] — kept for direct
/// navigation; the home screen embeds the list as its "My projects" tab.
class ProjectsScreen extends StatelessWidget {
  /// Injectable for tests; the app uses the default documents-dir store.
  final ProjectStore? store;

  const ProjectsScreen({super.key, this.store});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your projects')),
      body: ProjectsList(store: store),
    );
  }
}

/// The user's saved editing sessions, newest first — everything auto-saved by
/// the editor (templates they edited and collages created from scratch).
/// A grid of live thumbnails only: the collage speaks for itself, so the rows
/// carry no name or timestamp — just the artwork and a delete affordance.
class ProjectsList extends StatefulWidget {
  /// Injectable for tests; the app uses the default documents-dir store.
  final ProjectStore? store;

  /// Used by the card thumbnails' live render; tests inject a synchronous
  /// fake.
  final FontResolver fontResolver;

  const ProjectsList({
    super.key,
    this.store,
    this.fontResolver = googleFontsResolver,
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
    final project = await _store.load(summary.id);
    if (!mounted) return;
    if (project == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this project.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TemplateScreen(project: project, projects: _store),
      ),
    );
    _reload();
  }

  Future<void> _delete(ProjectSummary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text(
          '"${summary.name}" and its photos will be removed. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
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
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final projects = snapshot.data ?? const [];
        if (projects.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Symbols.space_dashboard_rounded,
                    size: 40,
                    color: AppColors.textSecondary,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Nothing here yet.\nEdit a template or create a collage '
                    'from scratch — it saves itself.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.72,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: projects.length,
          itemBuilder: (context, i) {
            final summary = projects[i];
            return _ProjectCard(
              // Keyed by project id: after a delete the cards shift position,
              // and a positional key would hand slot N the thumbnail state
              // (and its cached future) of the card that used to sit there.
              key: ValueKey('project-${summary.id}'),
              store: _store,
              summary: summary,
              fontResolver: widget.fontResolver,
              onOpen: () => _open(summary),
              onDelete: () => _delete(summary),
            );
          },
        );
      },
    );
  }
}

/// A live miniature of the project's first panel: the saved document rendered
/// by the same inert canvas the preview uses — no stale thumbnail files to
/// keep in sync with edits. The whole card opens the project; the corner
/// button deletes it.
class _ProjectCard extends StatefulWidget {
  final ProjectStore store;
  final ProjectSummary summary;
  final FontResolver fontResolver;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _ProjectCard({
    super.key,
    required this.store,
    required this.summary,
    required this.fontResolver,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  State<_ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<_ProjectCard> {
  // Cached across rebuilds so scrolls/reloads don't re-read the file; the
  // card's ValueKey retires this state when the id changes.
  late final Future<Project?> _project = widget.store.load(widget.summary.id);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onOpen,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: FutureBuilder<Project?>(
                future: _project,
                builder: (context, snapshot) {
                  final project = snapshot.data;
                  if (project == null || project.template.panels.isEmpty) {
                    // Loading, corrupt or empty — the neutral glyph covers
                    // all three; a broken project still opens the "couldn't
                    // open" path from the card itself.
                    return const Center(
                      child: Icon(
                        Symbols.edit_note_rounded,
                        size: 32,
                        color: AppColors.textSecondary,
                      ),
                    );
                  }
                  final template = project.template;
                  // Every slide of the document — the template's own panels plus
                  // the ones the user added while editing (added panels live in
                  // the content, not the template). Effective panels so
                  // user-added layers show too.
                  final panels = [
                    for (final p in [
                      ...template.panels,
                      ...project.content.addedPanels,
                    ])
                      project.content.effectivePanel(p),
                  ];
                  // Preview the WHOLE carousel — all slides side by side, each
                  // with its neighbour bleed — not a single panel. A seamless
                  // panorama lives on one panel and only reaches the others
                  // through the bleed, so any single-panel crop shows just a
                  // slice (a blank cover, or "only the right half"). The strip
                  // fits into the card, so it reads as the full carousel.
                  final aspect = template.canvasWidth / template.canvasHeight;
                  return Center(
                    child: IgnorePointer(
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final (i, panel) in panels.indexed)
                              SizedBox(
                                width: template.canvasWidth,
                                height: template.canvasHeight,
                                child: AspectRatio(
                                  aspectRatio: aspect,
                                  child: PanelCanvas(
                                    panel: panel,
                                    panelBefore: i > 0 ? panels[i - 1] : null,
                                    panelAfter: i + 1 < panels.length
                                        ? panels[i + 1]
                                        : null,
                                    canvasWidth: template.canvasWidth,
                                    canvasHeight: template.canvasHeight,
                                    content: project.content,
                                    fontResolver: widget.fontResolver,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Same corner-badge treatment as the gallery's lock: a quiet dark
            // circle that stays legible over any collage.
            Positioned(
              top: 8,
              right: 8,
              child: Tooltip(
                message: 'Delete project',
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: widget.onDelete,
                    child: const Padding(
                      padding: EdgeInsets.all(7),
                      child: Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
