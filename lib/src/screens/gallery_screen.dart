import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/project_store.dart';
import '../api/template_api.dart';
import '../api/template_store.dart';
import '../model/template.dart';
import 'template_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final _store = TemplateStore();
  final _projects = ProjectStore();
  late Future<IndexResult> _index;
  late Future<List<ProjectSummary>> _projectList;

  @override
  void initState() {
    super.initState();
    _index = _store.loadIndex();
    _projectList = _projects.list();
  }

  Future<void> _refresh() async {
    setState(() => _index = _store.loadIndex());
    await _index;
  }

  /// Every editing session auto-saves as a project, so the list is refreshed
  /// whenever the editor pops back to the gallery.
  void _reloadProjects() {
    if (mounted) setState(() => _projectList = _projects.list());
  }

  Future<void> _openTemplate(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TemplateScreen(id: id, projects: _projects),
      ),
    );
    _reloadProjects();
  }

  Future<void> _openProject(ProjectSummary summary) async {
    final project = await _projects.load(summary.id);
    if (!mounted) return;
    if (project == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this project.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TemplateScreen(project: project, projects: _projects),
      ),
    );
    _reloadProjects();
  }

  Future<void> _deleteProject(ProjectSummary summary) async {
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
    await _projects.delete(summary.id);
    _reloadProjects();
  }

  /// Create-from-scratch entry: pick a canvas size, then open the editor on a
  /// blank draft — everything (text, images, grids, assets, panels) is built
  /// there with the add menu.
  Future<void> _createFromScratch() async {
    final canvas = await showModalBottomSheet<(String, double, double)>(
      context: context,
      backgroundColor: const Color(0xFF27272A),
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
                leading: const Icon(Icons.crop_free),
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
        ),
      ),
    );
    _reloadProjects();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Collage Studio')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createFromScratch,
        icon: const Icon(Icons.add),
        label: const Text('Create'),
      ),
      body: FutureBuilder<IndexResult>(
        future: _index,
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
                      'Could not load templates.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _refresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          final result = snapshot.data!;
          final templates = result.templates;
          return Column(
            children: [
              _buildProjectsSection(),
              if (result.fromCache)
                Container(
                  width: double.infinity,
                  color: const Color(0xFF78350F),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: const Text(
                    'Offline — showing downloaded templates',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              Expanded(
                child: templates.isEmpty
                    ? const Center(child: Text('No templates published yet.'))
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        child: GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 0.62,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                          itemCount: templates.length,
                          itemBuilder: (context, i) => _TemplateCard(
                            summary: templates[i],
                            onTap: () => _openTemplate(templates[i].id),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// "Your projects": a horizontal strip of the user's saved editing
  /// sessions, newest first. Hidden while empty. Tap resumes; long-press
  /// deletes (with confirmation).
  Widget _buildProjectsSection() {
    return FutureBuilder<List<ProjectSummary>>(
      future: _projectList,
      builder: (context, snapshot) {
        final projects = snapshot.data ?? const [];
        if (projects.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Text(
                'Your projects',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            SizedBox(
              height: 88,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: projects.length,
                itemBuilder: (context, i) => _ProjectCard(
                  summary: projects[i],
                  onTap: () => _openProject(projects[i]),
                  onLongPress: () => _deleteProject(projects[i]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final ProjectSummary summary;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ProjectCard({
    required this.summary,
    required this.onTap,
    required this.onLongPress,
  });

  static String _ago(DateTime time) {
    final d = DateTime.now().difference(time);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          width: 150,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    const Icon(Icons.edit_note, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        summary.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _ago(summary.updatedAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final TemplateSummary summary;
  final VoidCallback onTap;

  const _TemplateCard({required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final thumb = summary.thumbnailDataUrl;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: thumb != null && thumb.contains(',')
                  ? Image.memory(
                      base64Decode(thumb.split(',').last),
                      fit: BoxFit.contain,
                    )
                  : const ColoredBox(
                      color: Color(0xFF27272A),
                      child: Center(child: Icon(Icons.image_outlined)),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    [
                      summary.aspectRatio,
                      if (summary.category != null) summary.category!,
                      if (summary.premium) 'premium',
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
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
