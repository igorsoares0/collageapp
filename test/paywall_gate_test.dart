import 'dart:io';

import 'package:collageapp/src/api/entitlements.dart';
import 'package:collageapp/src/api/template_api.dart';
import 'package:collageapp/src/api/template_store.dart';
import 'package:collageapp/src/screens/gallery_screen.dart';
import 'package:collageapp/src/screens/paywall_screen.dart';
import 'package:collageapp/src/screens/template_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Never touches the SDK: purchases just flip [isPro], like the Test Store
/// would after a successful (fake) payment.
class FakeEntitlements extends EntitlementsService {
  @override
  Future<void> init() async {}

  @override
  Future<List<Package>> packages() async => [
    _package(r'$rc_annual', PackageType.annual, 29.99, r'$29.99'),
    _package(r'$rc_monthly', PackageType.monthly, 4.99, r'$4.99'),
  ];

  @override
  Future<bool> buy(Package package) async {
    isPro.value = true;
    return true;
  }

  @override
  Future<bool> restore() async => isPro.value;

  static Package _package(
    String id,
    PackageType type,
    double price,
    String priceString,
  ) => Package(
    id,
    type,
    StoreProduct('pro', '', 'Collage Pro', price, priceString, 'USD'),
    const PresentedOfferingContext('default', null, null),
  );
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('paywall_gate_test');
  });

  tearDown(() async {
    for (var attempt = 0; ; attempt++) {
      try {
        await tmp.delete(recursive: true);
        return;
      } on FileSystemException {
        if (attempt >= 4) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  final fixture = File('test/fixtures/fashion_story.json').readAsStringSync();
  const indexBody =
      '[{"id":"tpl_free","name":"Basic","schemaVersion":1,'
      '"aspectRatio":"9:16","category":null,"premium":false,'
      '"thumbnailDataUrl":null},'
      '{"id":"tpl_pro","name":"Fancy","schemaVersion":1,'
      '"aspectRatio":"9:16","category":null,"premium":true,'
      '"thumbnailDataUrl":null}]';

  TemplateStore store() => TemplateStore(
    api: TemplateApi(
      client: MockClient(
        (req) async => switch (req.url.path) {
          '/api/templates' => http.Response(indexBody, 200),
          '/api/assets' => http.Response('[]', 200),
          _ => http.Response('{"template": $fixture}', 200),
        },
      ),
    ),
    cacheDirOverride: tmp,
  );

  /// Same real-IO pattern as projects_screen_test: the store writes its cache
  /// with dart:io, whose completions only fire in the real event loop, so
  /// every test body runs inside runAsync and waits by polling.
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() done, {
    required String reason,
  }) async {
    for (var i = 0; i < 500 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(done(), isTrue, reason: reason);
  }

  Future<FakeEntitlements> pumpGallery(
    WidgetTester tester, {
    bool pro = false,
  }) async {
    // The 2-column grid's cards (aspect 0.62) overflow the default 800x600
    // test surface, putting the name labels off-screen and untappable.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final entitlements = FakeEntitlements()..isPro.value = pro;
    await tester.pumpWidget(
      MaterialApp(
        home: GalleryScreen(entitlements: entitlements, store: store()),
      ),
    );
    await pumpUntil(
      tester,
      () => tester.any(find.text('Basic')),
      reason: 'the template grid never loaded',
    );
    return entitlements;
  }

  testWidgets('free user: premium card is locked and opens the paywall, '
      'buying unlocks and proceeds to the editor', (tester) async {
    await tester.runAsync(() async {
      final entitlements = await pumpGallery(tester);
      // Only the premium card carries the lock badge.
      expect(find.byIcon(Icons.lock), findsOneWidget);

      await tester.tap(find.text('Fancy'));
      await pumpUntil(
        tester,
        () => tester.any(find.byType(PaywallScreen)),
        reason: 'tapping a premium template never opened the paywall',
      );
      expect(find.textContaining(r'$29.99'), findsOneWidget);
      expect(find.textContaining(r'$4.99'), findsOneWidget);
      expect(find.byType(TemplateScreen), findsNothing);

      await tester.tap(find.text('Annual'));
      // Both conditions: mid-transition the popped paywall route is still in
      // the tree while the editor route animates in.
      await pumpUntil(
        tester,
        () =>
            tester.any(find.byType(TemplateScreen)) &&
            !tester.any(find.byType(PaywallScreen)),
        reason: 'a successful purchase never reached the editor',
      );
      expect(entitlements.isPro.value, isTrue);
    });
  });

  testWidgets('pro user: premium template opens directly, no lock badge', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await pumpGallery(tester, pro: true);
      expect(find.byIcon(Icons.lock), findsNothing);

      await tester.tap(find.text('Fancy'));
      await pumpUntil(
        tester,
        () => tester.any(find.byType(TemplateScreen)),
        reason: 'the premium template never opened for the pro user',
      );
      expect(find.byType(PaywallScreen), findsNothing);
    });
  });

  testWidgets('free template never hits the paywall', (tester) async {
    await tester.runAsync(() async {
      await pumpGallery(tester);
      await tester.tap(find.text('Basic'));
      await pumpUntil(
        tester,
        () => tester.any(find.byType(TemplateScreen)),
        reason: 'the free template never opened',
      );
      expect(find.byType(PaywallScreen), findsNothing);
    });
  });

  testWidgets('closing the paywall without buying stays in the gallery', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final entitlements = await pumpGallery(tester);
      await tester.tap(find.text('Fancy'));
      await pumpUntil(
        tester,
        () => tester.any(find.byType(PaywallScreen)),
        reason: 'tapping a premium template never opened the paywall',
      );

      await tester.tap(find.byType(BackButton));
      await pumpUntil(
        tester,
        () => !tester.any(find.byType(PaywallScreen)),
        reason: 'the paywall never closed',
      );
      expect(find.byType(TemplateScreen), findsNothing);
      expect(entitlements.isPro.value, isFalse);
      expect(find.text('Fancy'), findsOneWidget);
    });
  });
}
