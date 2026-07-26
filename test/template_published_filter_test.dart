import 'package:collageapp/src/api/template_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// The catalog only shows templates the designer chose to publish. The flag is
/// server-side (web editor checkbox); the app filters the index on it, right
/// beside the schemaVersion gate.
void main() {
  String row(String id, {Object? published}) {
    final pub = published == null ? '' : ',"published":$published';
    return '{"id":"$id","name":"$id","schemaVersion":1,'
        '"aspectRatio":"9:16","category":null,"premium":false,'
        '"thumbnailDataUrl":null$pub}';
  }

  test('published:false is hidden, published:true is shown', () {
    final body = '[${row('shown', published: true)},'
        '${row('hidden', published: false)}]';
    final ids = TemplateApi.parseIndex(body).map((s) => s.id).toList();
    expect(ids, ['shown']);
  });

  test('a missing published field defaults to shown (old server back-compat)',
      () {
    final ids = TemplateApi.parseIndex('[${row('legacy')}]')
        .map((s) => s.id)
        .toList();
    expect(ids, ['legacy']);
  });
}
