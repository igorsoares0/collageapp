import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/project_store.dart';
import '../api/template_api.dart';
import '../api/template_store.dart';
import '../model/template.dart';
import 'projects_screen.dart';
import 'template_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final _store = TemplateStore();
  // Handed to every editor session so it auto-saves as a project; the
  // projects themselves are listed on ProjectsScreen, not here.
  final _projects = ProjectStore();
  late Future<IndexResult> _index;

  @override
  void initState() {
    super.initState();
    _index = _store.loadIndex();
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

  Future<void> _openTemplate(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TemplateScreen(id: id, projects: _projects),
      ),
    );
  }

  /// Create-from-scratch entry: pick a canvas size, then open the editor on a
  /// blank draft — everything (text, images, grids, assets, panels) is built
  /// there with the bottom toolbar.
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
  }

  @override
  Widget build(BuildContext context) {
    // Two tabs: published templates and the user's own saved projects — the
    // projects are a first-class destination, not an icon in a corner. The
    // projects tab rebuilds when switched to, so it always lists fresh saves.
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Collage Studio'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Templates'),
              Tab(text: 'My projects'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _createFromScratch,
          icon: const Icon(Icons.add),
          label: const Text('Create'),
        ),
        body: TabBarView(
          children: [
            _buildTemplatesTab(),
            ProjectsList(store: _projects),
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
