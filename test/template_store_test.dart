import 'dart:io';

import 'package:collageapp/src/api/template_api.dart';
import 'package:collageapp/src/api/template_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('template_store_test');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  final fixture = File('test/fixtures/fashion_story.json').readAsStringSync();
  const indexBody =
      '[{"id":"tpl_1","name":"Fashion","schemaVersion":1,'
      '"aspectRatio":"9:16","category":null,"premium":false,'
      '"thumbnailDataUrl":null}]';
  final recordBody = '{"template": $fixture}';

  TemplateStore storeWith(http.Client client) => TemplateStore(
    api: TemplateApi(client: client),
    cacheDirOverride: tmp,
  );

  http.Client onlineClient() => MockClient(
    (req) async => req.url.path == '/api/templates'
        ? http.Response(indexBody, 200)
        : http.Response(recordBody, 200),
  );

  http.Client offlineClient() =>
      MockClient((req) async => throw const SocketException('offline'));

  test('online: serves the network and prefetches templates to disk', () async {
    final store = storeWith(onlineClient());
    final result = await store.loadIndex();

    expect(result.fromCache, isFalse);
    expect(result.templates.single.id, 'tpl_1');

    await store.pendingPrefetch;
    expect(File('${tmp.path}/index.json').existsSync(), isTrue);
    expect(File('${tmp.path}/tpl_tpl_1.json').existsSync(), isTrue);
  });

  test('offline with cache: serves cached index and template', () async {
    final warm = storeWith(onlineClient());
    await warm.loadIndex();
    await warm.pendingPrefetch;

    final offline = storeWith(offlineClient());
    final index = await offline.loadIndex();
    expect(index.fromCache, isTrue);
    expect(index.templates.single.name, 'Fashion');

    final template = await offline.loadTemplate('tpl_1');
    expect(template.fromCache, isTrue);
    expect(template.template.layers, isNotEmpty);
  });

  test('offline without cache: rethrows the network error', () async {
    final store = storeWith(offlineClient());
    await expectLater(store.loadIndex(), throwsA(isA<SocketException>()));
    await expectLater(
      store.loadTemplate('tpl_1'),
      throwsA(isA<SocketException>()),
    );
  });

  test('assets embedded in the template response ride into TemplateResult, '
      'online and from cache', () async {
    const photo =
        '{"id":"photo_1","type":"photo","name":"Sample",'
        '"dataUrl":"data:image/jpeg;base64,AAAA","aspect":1.5,'
        '"window":null,"createdAt":"2026-01-01T00:00:00Z"}';
    final withAssets = MockClient(
      (req) async => req.url.path == '/api/templates'
          ? http.Response(indexBody, 200)
          : http.Response('{"template": $fixture, "assets": [$photo]}', 200),
    );

    final online = storeWith(withAssets);
    final result = await online.loadTemplate('tpl_1');
    expect(result.assets, hasLength(1));
    expect(result.assets.single.type, 'photo');
    expect(result.assets.single.id, 'photo_1');

    // The raw body was cached, so the photos survive offline too.
    final offline = storeWith(offlineClient());
    final cached = await offline.loadTemplate('tpl_1');
    expect(cached.fromCache, isTrue);
    expect(cached.assets.single.id, 'photo_1');
  });
}
