import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../model/asset_record.dart';
import '../model/template.dart';
import 'template_api.dart';

class IndexResult {
  final List<TemplateSummary> templates;
  final bool fromCache;

  const IndexResult(this.templates, {required this.fromCache});
}

class TemplateResult {
  final Template template;
  final bool fromCache;

  const TemplateResult(this.template, {required this.fromCache});
}

class AssetsResult {
  final List<AssetRecord> assets;
  final bool fromCache;

  const AssetsResult(this.assets, {required this.fromCache});
}

/// Network-first cache (spec §26/§27): every successful response is written
/// to disk as the raw JSON the server sent; when the network fails, the
/// cached copy is served instead, so downloaded templates keep working
/// offline. Uses dart:io files — mobile/desktop only, not Flutter web.
class TemplateStore {
  final TemplateApi api;
  final Directory? cacheDirOverride;
  Directory? _dir;

  /// Handle to the last opportunistic prefetch, so tests can await it.
  @visibleForTesting
  Future<void>? pendingPrefetch;

  TemplateStore({TemplateApi? api, this.cacheDirOverride})
    : api = api ?? TemplateApi();

  Future<IndexResult> loadIndex() async {
    String body;
    try {
      body = await api.fetchIndexBody();
    } catch (_) {
      final cached = await _readCache(_indexFile);
      if (cached == null) rethrow;
      return IndexResult(TemplateApi.parseIndex(cached), fromCache: true);
    }
    await _writeCache(_indexFile, body);
    final summaries = TemplateApi.parseIndex(body);
    pendingPrefetch = _prefetch(summaries);
    return IndexResult(summaries, fromCache: false);
  }

  Future<TemplateResult> loadTemplate(String id) async {
    final name = _templateFile(id);
    String body;
    try {
      body = await api.fetchTemplateBody(id);
    } catch (_) {
      final cached = await _readCache(name);
      if (cached == null) rethrow;
      return TemplateResult(
        TemplateApi.parseTemplateRecord(cached),
        fromCache: true,
      );
    }
    await _writeCache(name, body);
    return TemplateResult(
      TemplateApi.parseTemplateRecord(body),
      fromCache: false,
    );
  }

  /// The asset catalog (frames/stickers), network-first with the same on-disk
  /// cache as templates, so uploaded frames render offline once fetched. On a
  /// cold offline start it throws (like loadIndex) and the caller falls back to
  /// the bundled seeds.
  Future<AssetsResult> loadAssets() async {
    String body;
    try {
      body = await api.fetchAssetsBody();
    } catch (_) {
      final cached = await _readCache(_assetsFile);
      if (cached == null) rethrow;
      return AssetsResult(TemplateApi.parseAssets(cached), fromCache: true);
    }
    await _writeCache(_assetsFile, body);
    return AssetsResult(TemplateApi.parseAssets(body), fromCache: false);
  }

  /// Spec §26 step 3: after a fresh index, download templates not cached yet
  /// so they open offline later. Opportunistic — failures are ignored, and
  /// already-cached templates are refreshed only when actually opened.
  Future<void> _prefetch(List<TemplateSummary> summaries) async {
    for (final summary in summaries) {
      final name = _templateFile(summary.id);
      if (await _exists(name)) continue;
      try {
        await _writeCache(name, await api.fetchTemplateBody(summary.id));
      } catch (_) {
        // Offline mid-sync; the next loadIndex tries again.
      }
    }
  }

  static const _indexFile = 'index.json';
  static const _assetsFile = 'assets.json';

  String _templateFile(String id) =>
      'tpl_${id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.json';

  Future<File> _file(String name) async {
    if (_dir == null) {
      final base =
          cacheDirOverride ??
          Directory(
            '${(await getApplicationSupportDirectory()).path}/template_cache',
          );
      _dir = await base.create(recursive: true);
    }
    return File('${_dir!.path}/$name');
  }

  Future<bool> _exists(String name) async => (await _file(name)).exists();

  Future<String?> _readCache(String name) async {
    try {
      final file = await _file(name);
      return await file.exists() ? await file.readAsString() : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String name, String body) async {
    try {
      await (await _file(name)).writeAsString(body);
    } catch (_) {
      // A failed cache write must never break the online path.
    }
  }
}
