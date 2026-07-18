import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/asset_record.dart';
import '../model/template.dart';

/// Base URL of the Collage Studio backend. Pick an environment with the
/// bundled files instead of retyping the URL:
///   flutter run   --dart-define-from-file=env/dev.json    (localhost)
///   flutter build --dart-define-from-file=env/prod.json   (Vercel)
/// The app only ever GETs, and those routes are public, so no credentials
/// are needed even against the auth-gated production deployment. The default
/// below keeps a bare `flutter run` (no file) pointed at local dev.
const String kApiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://localhost:3000',
);

class TemplateSummary {
  final String id;
  final String name;
  final int schemaVersion;
  final String aspectRatio;
  final String? category;
  final bool premium;
  final String? thumbnailDataUrl;

  const TemplateSummary({
    required this.id,
    required this.name,
    required this.schemaVersion,
    required this.aspectRatio,
    required this.category,
    required this.premium,
    required this.thumbnailDataUrl,
  });

  factory TemplateSummary.fromJson(Map<String, dynamic> json) =>
      TemplateSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
        aspectRatio: json['aspectRatio'] as String,
        category: json['category'] as String?,
        premium: json['premium'] == true,
        thumbnailDataUrl: json['thumbnailDataUrl'] as String?,
      );
}

/// A template plus the assets embedded in its response — today the designer's
/// sample photos, referenced by imageAssetId and shown only in the preview.
class TemplateRecord {
  final Template template;
  final List<AssetRecord> assets;

  const TemplateRecord(this.template, this.assets);
}

class TemplateApi {
  final String baseUrl;
  final http.Client _client;

  TemplateApi({this.baseUrl = kApiBase, http.Client? client})
    : _client = client ?? http.Client();

  /// Template index (spec §26 step 1). Templates whose schema is newer than
  /// this renderer understands are filtered out, never rendered wrong.
  Future<List<TemplateSummary>> fetchIndex() async =>
      parseIndex(await fetchIndexBody());

  Future<Template> fetchTemplate(String id) async =>
      parseTemplateRecord(await fetchTemplateBody(id)).template;

  /// Raw response bodies are exposed so TemplateStore can cache the exact
  /// JSON the server sent (the models have no toJson round-trip).
  Future<String> fetchIndexBody() async {
    final res = await _client.get(Uri.parse('$baseUrl/api/templates'));
    _ensureOk(res);
    return res.body;
  }

  Future<String> fetchTemplateBody(String id) async {
    final res = await _client.get(
      Uri.parse('$baseUrl/api/templates/${Uri.encodeComponent(id)}'),
    );
    _ensureOk(res);
    return res.body;
  }

  /// The uploadable asset catalog. Only frames/stickers — designer photos are
  /// template content and arrive embedded in each template's own response
  /// (see [parseTemplateRecord]), so the app never downloads the photos of
  /// templates the user doesn't open.
  Future<String> fetchAssetsBody() async {
    final res = await _client.get(
      Uri.parse('$baseUrl/api/assets?types=frame,sticker'),
    );
    _ensureOk(res);
    return res.body;
  }

  static List<TemplateSummary> parseIndex(String body) {
    final list = jsonDecode(body) as List<dynamic>;
    return list
        .map((e) => TemplateSummary.fromJson(e as Map<String, dynamic>))
        .where((s) => s.schemaVersion <= kSupportedSchemaVersion)
        .toList();
  }

  static TemplateRecord parseTemplateRecord(String body) {
    final record = jsonDecode(body) as Map<String, dynamic>;
    final assets = record['assets'] as List<dynamic>? ?? const [];
    return TemplateRecord(
      Template.fromJson(record['template'] as Map<String, dynamic>),
      assets
          .map((e) => AssetRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static List<AssetRecord> parseAssets(String body) {
    final list = jsonDecode(body) as List<dynamic>;
    return list
        .map((e) => AssetRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  void _ensureOk(http.Response res) {
    if (res.statusCode != 200) {
      throw Exception('API ${res.request?.url.path} -> ${res.statusCode}');
    }
  }
}
