import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import '../model/migrate_v4.dart';
import '../model/slot_content.dart';
import '../model/template.dart';

/// Highest project FILE layout this app understands — independent of the
/// template schema. Files written by a NEWER app are refused instead of being
/// misread.
///
/// Layout 1: `template` (panels) + `content`.
/// Layout 2: `document` (v4 continuous canvas) + `content`.
///
/// Each save writes the layout it actually uses ([kClassicLayoutVersion] or
/// [kDocumentLayoutVersion]), NOT this constant — a classic-shaped file stays
/// openable by older builds, while a continuous one correctly announces that it
/// needs a build that understands v4.
const int kProjectVersion = 2;

/// `template` + `content` — readable by every build.
const int kClassicLayoutVersion = 1;

/// `document` + `content` — the v4 continuous canvas (Modelo B).
const int kDocumentLayoutVersion = 2;

/// A saved editing session: the template snapshot it was built on (embedded,
/// so the project stays openable even if the published template changes or
/// disappears) plus everything the user did to it. Photos live as files next
/// to the JSON and ride in [content] as [FileImage]s.
class Project {
  final String id;
  final String name;
  final DateTime updatedAt;
  final Template template;
  final SlotContent content;

  const Project({
    required this.id,
    required this.name,
    required this.updatedAt,
    required this.template,
    required this.content,
  });
}

/// A saved project loaded into the v4 continuous model (Modelo B), as returned
/// by [ProjectStore.loadAsDocument]. The panel-scoped parts of the overlay have
/// already folded into [document]; [content] keeps the slot-scoped overrides.
class ContinuousProject {
  final String id;
  final String name;
  final DateTime updatedAt;
  final Document document;
  final SlotContent content;

  /// True when this came from a v3 (panels) file migrated on read, false when
  /// the file was already v4. Nothing is written back either way.
  final bool migrated;

  const ContinuousProject({
    required this.id,
    required this.name,
    required this.updatedAt,
    required this.document,
    required this.content,
    required this.migrated,
  });
}

/// What the gallery list needs — read without decoding the whole document.
class ProjectSummary {
  final String id;
  final String name;
  final DateTime updatedAt;

  const ProjectSummary({
    required this.id,
    required this.name,
    required this.updatedAt,
  });
}

/// On-disk store for the user's projects, one directory per project under the
/// app documents dir (backed up by the OS — projects must survive a phone
/// migration, unlike the re-fetchable template cache in app support):
///
///     projects/<id>/project.json   the document (template + SlotContent)
///     projects/<id>/images/…       the user's photos, one file per pick
///
/// Writes are atomic (temp file + rename) and QUEUED — concurrent saves of
/// the same project can't interleave on the temp file — and reads are
/// defensive: one corrupt project is skipped, never the whole list.
class ProjectStore {
  /// Test hook: bypasses path_provider (no plugin in unit tests).
  final Directory? dirOverride;
  Directory? _dir;

  /// All mutations chain on this tail so they hit the disk in call order.
  Future<void> _queue = Future.value();

  ProjectStore({this.dirOverride});

  /// The tail of the write queue — lets tests (and shutdown paths) await
  /// everything scheduled so far.
  @visibleForTesting
  Future<void> get pendingWrites => _queue;

  Future<void> _enqueue(Future<void> Function() job) {
    final next = _queue.then((_) => job());
    // A failed job must not jam the queue for every later write.
    _queue = next.catchError((_) {});
    return next;
  }

  /// Saves [project] atomically: serialize, write to a temp file, rename over
  /// the previous version. A crash mid-write leaves the old file intact.
  Future<void> save(Project project) => _enqueue(() async {
    await _writeProject(project.id, {
      'projectVersion': kClassicLayoutVersion,
      'id': project.id,
      'name': project.name,
      'updatedAt': project.updatedAt.toUtc().toIso8601String(),
      'template': project.template.toJson(),
      'content': _encodeContent(project.content),
    });
  });

  /// Saves a project in the v4 continuous layout (Modelo B).
  ///
  /// This is the point where the app AUTHORS v4: a continuous document cannot
  /// round-trip through the panel model (a panorama crossing slides has no
  /// panel to belong to), so the file announces [kDocumentLayoutVersion] and an
  /// older build refuses it cleanly instead of reading it wrong.
  Future<void> saveDocument(ContinuousProject project) => _enqueue(() async {
    await _writeProject(project.id, {
      'projectVersion': kDocumentLayoutVersion,
      'id': project.id,
      'name': project.name,
      'updatedAt': project.updatedAt.toUtc().toIso8601String(),
      'document': project.document.toJson(),
      'content': _encodeContent(project.content),
    });
  });

  /// Atomic write of a project's JSON body.
  Future<void> _writeProject(String id, Map<String, dynamic> json) async {
    final dir = await _projectDir(id);
    await dir.create(recursive: true);
    final body = jsonEncode(json);
    final tmp = File('${dir.path}/project.json.tmp');
    await tmp.writeAsString(body, flush: true);
    final dest = File('${dir.path}/project.json');
    try {
      await tmp.rename(dest.path);
    } on FileSystemException {
      // Windows (dev machine only) can refuse to rename over an existing
      // file. Delete + rename loses atomicity there; every shipping platform
      // takes the atomic path above.
      if (await dest.exists()) await dest.delete();
      await tmp.rename(dest.path);
    }
  }

  /// Raw project JSON, or null when it's missing, corrupt, or written by a
  /// newer app version. Shared by [load] and [loadAsDocument] so both inherit
  /// the same refuse-don't-crash behaviour.
  Future<({Map<String, dynamic> json, Directory dir})?> _readProjectJson(
    String id,
  ) async {
    try {
      final dir = await _projectDir(id);
      final json =
          jsonDecode(await File('${dir.path}/project.json').readAsString())
              as Map<String, dynamic>;
      if (((json['projectVersion'] as num?)?.toInt() ?? 0) > kProjectVersion) {
        return null;
      }
      return (json: json, dir: dir);
    } catch (_) {
      return null;
    }
  }

  /// Loads one project, or null when it's missing, corrupt, or written by a
  /// newer app version — the caller shows "couldn't open", not a crash.
  Future<Project?> load(String id) async {
    final read = await _readProjectJson(id);
    if (read == null) return null;
    try {
      final json = read.json;
      return Project(
        id: id,
        name: json['name'] as String,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        template: Template.fromJson(json['template'] as Map<String, dynamic>),
        content: _decodeContent(
          json['content'] as Map<String, dynamic>,
          Directory('${read.dir.path}/images'),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Loads one project into the v4 continuous model (Modelo B).
  ///
  /// Dual read: a file holding a `document` is already v4 and is parsed
  /// straight through; the classic `template` + panels shape is migrated on
  /// READ by [migrateToV4].
  ///
  /// Deliberately writes NOTHING. The migration is deterministic and lossless,
  /// so re-running it on every load costs microseconds and keeps the file
  /// readable by the current renderer. Persisting v4 only becomes necessary
  /// once the app AUTHORS it — until then, rewriting the file would strand the
  /// user's project in a format nothing can draw yet.
  Future<ContinuousProject?> loadAsDocument(String id) async {
    final read = await _readProjectJson(id);
    if (read == null) return null;
    try {
      final json = read.json;
      final images = Directory('${read.dir.path}/images');
      final content = _decodeContent(
        json['content'] as Map<String, dynamic>,
        images,
      );
      final name = json['name'] as String;
      final updatedAt = DateTime.parse(json['updatedAt'] as String);

      final documentJson = json['document'];
      if (documentJson is Map<String, dynamic>) {
        // Natively v4 — no migration needed.
        return ContinuousProject(
          id: id,
          name: name,
          updatedAt: updatedAt,
          document: Document.fromJson(documentJson),
          content: content,
          migrated: false,
        );
      }

      final result = migrateToV4(
        Template.fromJson(json['template'] as Map<String, dynamic>),
        content,
      );
      return ContinuousProject(
        id: id,
        name: name,
        updatedAt: updatedAt,
        document: result.document,
        content: result.content,
        migrated: true,
      );
    } catch (_) {
      return null;
    }
  }

  /// All projects, newest first. Unreadable entries are skipped one by one.
  Future<List<ProjectSummary>> list() async {
    final root = await _rootDir();
    if (!await root.exists()) return const [];
    final summaries = <ProjectSummary>[];
    await for (final entry in root.list()) {
      if (entry is! Directory) continue;
      try {
        final json =
            jsonDecode(await File('${entry.path}/project.json').readAsString())
                as Map<String, dynamic>;
        if (((json['projectVersion'] as num?)?.toInt() ?? 0) >
            kProjectVersion) {
          continue;
        }
        summaries.add(
          ProjectSummary(
            id: entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
            name: json['name'] as String,
            updatedAt: DateTime.parse(json['updatedAt'] as String),
          ),
        );
      } catch (_) {
        // Corrupt/foreign entry — skip it, keep the rest of the list.
      }
    }
    summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return summaries;
  }

  /// Persists one picked photo under the project and returns its file. The
  /// caller passes a name unique per pick: Flutter's ImageCache keys FileImage
  /// by path, and undo snapshots keep referencing the previous photo's file,
  /// so overwriting an existing name would corrupt both.
  Future<File> saveImage(String projectId, String name, Uint8List bytes) async {
    final dir = await _imagesDir(projectId);
    await dir.create(recursive: true);
    final file = File('${dir.path}/$name');
    await _enqueue(() => file.writeAsBytes(bytes, flush: true));
    return file;
  }

  /// Removes the whole project — document and photos.
  Future<void> delete(String id) => _enqueue(() async {
    final dir = await _projectDir(id);
    for (var attempt = 0; ; attempt++) {
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
        return;
      } on FileSystemException {
        // Windows (dev machine only) can hold a transient lock on a file a
        // read just released (the projects list renders live thumbnails from
        // project.json) or one an AV scan is touching; every shipping
        // platform deletes open files without complaint.
        if (attempt >= 4) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  /// Deletes photo files no longer referenced by the saved document (undone
  /// picks). Queued, so it runs after any save already scheduled — [keep] must
  /// be the file names the FINAL document references. Call it only when no
  /// undo history can resurrect a reference (i.e. when the editor closes).
  Future<void> cleanupImages(String projectId, Set<String> keep) =>
      _enqueue(() async {
        final dir = await _imagesDir(projectId);
        if (!await dir.exists()) return;
        await for (final entry in dir.list()) {
          if (entry is! File) continue;
          final name = entry.uri.pathSegments.last;
          if (!keep.contains(name)) {
            try {
              await entry.delete();
            } catch (_) {
              // A locked file just stays until the next cleanup.
            }
          }
        }
      });

  Future<Directory> _rootDir() async {
    if (_dir == null) {
      final base = dirOverride != null
          ? dirOverride!.path
          : (await getApplicationDocumentsDirectory()).path;
      _dir = Directory('$base/projects');
    }
    return _dir!;
  }

  Future<Directory> _projectDir(String id) async {
    // Defense in depth: ids are app-generated, but never let one escape the
    // projects root through separators.
    final safe = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return Directory('${(await _rootDir()).path}/$safe');
  }

  Future<Directory> _imagesDir(String id) async =>
      Directory('${(await _projectDir(id)).path}/images');
}

/// File name a photo is stored under inside the project's images dir. Only
/// [FileImage]s are persistable; anything else (a MemoryImage from a failed
/// disk write) is session-only and dropped from the saved document.
String? imageFileName(ImageProvider image) =>
    image is FileImage ? image.file.uri.pathSegments.last : null;

Map<String, dynamic> _encodeContent(SlotContent c) => {
  'texts': c.texts,
  'images': {
    for (final e in c.images.entries)
      if (imageFileName(e.value) != null) e.key: imageFileName(e.value),
  },
  'offsets': {
    for (final e in c.offsets.entries) e.key: [e.value.dx, e.value.dy],
  },
  'scales': c.scales,
  'stretchX': c.stretchX,
  'stretchY': c.stretchY,
  'rotations': c.rotations,
  'colors': {for (final e in c.colors.entries) e.key: colorToHex(e.value)},
  'fonts': c.fonts,
  'alignments': c.alignments,
  'weights': c.weights,
  'panelBackgrounds': {
    for (final e in c.panelBackgrounds.entries) e.key: colorToHex(e.value),
  },
  'layerOrders': c.layerOrders,
  'hiddenLayers': c.hiddenLayers,
  'gridOverrides': {
    for (final e in c.gridOverrides.entries) e.key: e.value.toJson(),
  },
  'addedLayers': {
    for (final e in c.addedLayers.entries)
      e.key: [for (final l in e.value) l.toJson()],
  },
  'addedPanels': [for (final p in c.addedPanels) p.toJson()],
};

SlotContent _decodeContent(Map<String, dynamic> json, Directory imagesDir) {
  Map<String, dynamic> section(String key) =>
      json[key] as Map<String, dynamic>? ?? const {};
  return SlotContent(
    texts: section('texts').cast<String, String>(),
    images: {
      // A photo whose file vanished degrades to an empty slot (with its pick
      // icon) instead of a decode error blowing up the canvas.
      for (final e in section('images').entries)
        if (File('${imagesDir.path}/${e.value}').existsSync())
          e.key: FileImage(File('${imagesDir.path}/${e.value}')),
    },
    offsets: {
      for (final e in section('offsets').entries)
        e.key: Offset(
          ((e.value as List<dynamic>)[0] as num).toDouble(),
          ((e.value as List<dynamic>)[1] as num).toDouble(),
        ),
    },
    scales: _doubles(section('scales')),
    stretchX: _doubles(section('stretchX')),
    stretchY: _doubles(section('stretchY')),
    rotations: _doubles(section('rotations')),
    colors: _colors(section('colors')),
    fonts: section('fonts').cast<String, String>(),
    alignments: section('alignments').cast<String, String>(),
    weights: {
      for (final e in section('weights').entries)
        e.key: (e.value as num).toInt(),
    },
    panelBackgrounds: _colors(section('panelBackgrounds')),
    layerOrders: {
      for (final e in section('layerOrders').entries)
        e.key: (e.value as List<dynamic>).cast<String>(),
    },
    hiddenLayers: section('hiddenLayers').cast<String, bool>(),
    gridOverrides: {
      for (final e in section('gridOverrides').entries)
        e.key: GridOverride.fromJson(e.value as Map<String, dynamic>),
    },
    addedLayers: {
      for (final e in section('addedLayers').entries)
        e.key: [
          for (final l in e.value as List<dynamic>)
            Layer.fromJson(l as Map<String, dynamic>),
        ].whereType<Layer>().toList(),
    },
    addedPanels: [
      for (final p in json['addedPanels'] as List<dynamic>? ?? const [])
        Panel.fromJson(p as Map<String, dynamic>),
    ],
  );
}

Map<String, double> _doubles(Map<String, dynamic> json) => {
  for (final e in json.entries) e.key: (e.value as num).toDouble(),
};

Map<String, Color> _colors(Map<String, dynamic> json) => {
  for (final e in json.entries) e.key: parseHexColor(e.value as String),
};
