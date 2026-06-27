import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/template.dart';

/// Base URL of the Collage Studio backend. Android emulators reach the host
/// machine at 10.0.2.2; override with:
///   flutter run --dart-define=API_BASE=http://10.0.2.2:3000
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
      parseTemplateRecord(await fetchTemplateBody(id));

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

  static List<TemplateSummary> parseIndex(String body) {
    final list = jsonDecode(body) as List<dynamic>;
    return list
        .map((e) => TemplateSummary.fromJson(e as Map<String, dynamic>))
        .where((s) => s.schemaVersion <= kSupportedSchemaVersion)
        .toList();
  }

  static Template parseTemplateRecord(String body) {
    final record = jsonDecode(body) as Map<String, dynamic>;
    return Template.fromJson(record['template'] as Map<String, dynamic>);
  }

  void _ensureOk(http.Response res) {
    if (res.statusCode != 200) {
      throw Exception('API ${res.request?.url.path} -> ${res.statusCode}');
    }
  }
}
