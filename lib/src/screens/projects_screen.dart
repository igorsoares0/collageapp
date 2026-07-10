import 'package:flutter/material.dart';

import '../api/project_store.dart';
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

  const ProjectsList({super.key, this.store});

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
                child: Text(
                  'Nothing here yet.\nEdit a template or create a collage '
                  'from scratch — it saves itself.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: projects.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final summary = projects[i];
              return ListTile(
                leading: const Icon(Icons.edit_note),
                title: Text(
                  summary.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(_ago(summary.updatedAt)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete project',
                  onPressed: () => _delete(summary),
                ),
                onTap: () => _open(summary),
              );
            },
          );
        },
    );
  }
}
