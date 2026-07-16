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
class ProjectsList extends StatefulWidget {
  /// Injectable for tests; the app uses the default documents-dir store.
  final ProjectStore? store;

  /// Used by the row thumbnails' live render; tests inject a synchronous fake.
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

  static String _ago(DateTime time) {
    final d = DateTime.now().difference(time);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
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
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          itemCount: projects.length,
          itemBuilder: (context, i) {
            final summary = projects[i];
            return Padding(
              // Keyed by project id: after a delete the rows shift position,
              // and a positional key would hand row N the thumbnail state
              // (and its cached future) of the row that used to sit there.
              key: ObjectKey(summary.id),
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  leading: _ProjectThumb(
                    store: _store,
                    id: summary.id,
                    fontResolver: widget.fontResolver,
                  ),
                  title: Text(
                    summary.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    'Edited ${_ago(summary.updatedAt)}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete project',
                    onPressed: () => _delete(summary),
                  ),
                  onTap: () => _open(summary),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// A live miniature of the project's first panel: the saved document rendered
/// by the same inert canvas the preview uses — no stale thumbnail files to
/// keep in sync with edits.
class _ProjectThumb extends StatefulWidget {
  final ProjectStore store;
  final String id;
  final FontResolver fontResolver;

  const _ProjectThumb({
    required this.store,
    required this.id,
    required this.fontResolver,
  });

  @override
  State<_ProjectThumb> createState() => _ProjectThumbState();
}

class _ProjectThumbState extends State<_ProjectThumb> {
  // Cached across rebuilds so scrolls/reloads don't re-read the file; the
  // row's ObjectKey retires this state when the id changes.
  late final Future<Project?> _project = widget.store.load(widget.id);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        height: 56,
        child: ColoredBox(
          color: AppColors.surfaceHigh,
          child: FutureBuilder<Project?>(
            future: _project,
            builder: (context, snapshot) {
              final project = snapshot.data;
              if (project == null || project.template.panels.isEmpty) {
                // Loading, corrupt or empty — the neutral glyph covers all
                // three; a broken project still opens the "couldn't open"
                // path from the row itself.
                return const Icon(
                  Symbols.edit_note_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                );
              }
              final template = project.template;
              return Center(
                child: AspectRatio(
                  aspectRatio: template.canvasWidth / template.canvasHeight,
                  child: IgnorePointer(
                    child: PanelCanvas(
                      panel: template.panels.first,
                      canvasWidth: template.canvasWidth,
                      canvasHeight: template.canvasHeight,
                      content: project.content,
                      fontResolver: widget.fontResolver,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
