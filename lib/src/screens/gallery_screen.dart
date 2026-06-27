import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/template_api.dart';
import '../api/template_store.dart';
import 'template_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final _store = TemplateStore();
  late Future<IndexResult> _index;

  @override
  void initState() {
    super.initState();
    _index = _store.loadIndex();
  }

  Future<void> _refresh() async {
    setState(() => _index = _store.loadIndex());
    await _index;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Collage Studio')),
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
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    TemplateScreen(id: templates[i].id),
                              ),
                            ),
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
