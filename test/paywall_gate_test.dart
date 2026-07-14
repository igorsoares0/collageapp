import 'dart:io';

import 'package:collageapp/src/api/entitlements.dart';
import 'package:collageapp/src/api/template_api.dart';
import 'package:collageapp/src/api/template_store.dart';
import 'package:collageapp/src/screens/gallery_screen.dart';
import 'package:collageapp/src/screens/paywall_screen.dart';
import 'package:collageapp/src/screens/template_preview_screen.dart';
import 'package:collageapp/src/screens/template_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

TextStyle testFontResolver(String family, TextStyle base) => base;

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
        home: GalleryScreen(
          entitlements: entitlements,
          store: store(),
          fontResolver: testFontResolver,
        ),
      ),
    );
    await pumpUntil(
      tester,
      () => tester.any(find.text('Basic')),
      reason: 'the template grid never loaded',
    );
    return entitlements;
  }

  /// Taps a gallery card and waits for its read-only preview.
  Future<void> openPreview(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await pumpUntil(
      tester,
      () =>
          tester.any(find.byType(TemplatePreviewScreen)) &&
          !tester.any(find.byType(CircularProgressIndicator)),
      reason: 'the preview of $name never rendered',
    );
  }

  testWidgets('free user: locked card opens the read-only preview, '
      '"Unlock with Pro" paywalls, buying proceeds to the editor', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final entitlements = await pumpGallery(tester);
      // Only the premium card carries the lock badge.
      expect(find.byIcon(Icons.lock), findsOneWidget);

      await openPreview(tester, 'Fancy');
      // Looking is free: the template's real render, no paywall yet, and the
      // button announces the gate.
      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.text('Unlock with Pro'), findsOneWidget);

      await tester.tap(find.text('Unlock with Pro'));
      await pumpUntil(
        tester,
        () => tester.any(find.byType(PaywallScreen)),
        reason: 'the locked button never opened the paywall',
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

  testWidgets('pro user: no lock badge, preview button opens the editor '
      'directly', (tester) async {
    await tester.runAsync(() async {
      await pumpGallery(tester, pro: true);
      expect(find.byIcon(Icons.lock), findsNothing);

      await openPreview(tester, 'Fancy');
      expect(find.text('Use this template'), findsOneWidget);

      await tester.tap(find.text('Use this template'));
      await pumpUntil(
        tester,
        () => tester.any(find.byType(TemplateScreen)),
        reason: 'the premium template never opened for the pro user',
      );
      expect(find.byType(PaywallScreen), findsNothing);
    });
  });

  testWidgets('free template: preview shows "Use this template" and never '
      'hits the paywall', (tester) async {
    await tester.runAsync(() async {
      await pumpGallery(tester);
      await openPreview(tester, 'Basic');
      expect(find.text('Use this template'), findsOneWidget);

      await tester.tap(find.text('Use this template'));
      await pumpUntil(
        tester,
        () => tester.any(find.byType(TemplateScreen)),
        reason: 'the free template never opened',
      );
      expect(find.byType(PaywallScreen), findsNothing);
    });
  });

  testWidgets('closing the paywall without buying returns to the preview', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final entitlements = await pumpGallery(tester);
      await openPreview(tester, 'Fancy');
      await tester.tap(find.text('Unlock with Pro'));
      await pumpUntil(
        tester,
        () => tester.any(find.byType(PaywallScreen)),
        reason: 'the locked button never opened the paywall',
      );

      // The preview's app bar (route below) also has a BackButton — scope to
      // the paywall's.
      await tester.tap(
        find.descendant(
          of: find.byType(PaywallScreen),
          matching: find.byType(BackButton),
        ),
      );
      await pumpUntil(
        tester,
        () => !tester.any(find.byType(PaywallScreen)),
        reason: 'the paywall never closed',
      );
      expect(find.byType(TemplateScreen), findsNothing);
      expect(find.byType(TemplatePreviewScreen), findsOneWidget);
      expect(entitlements.isPro.value, isFalse);
    });
  });

  testWidgets('preview renders the template read-only: real content, '
      'no editor gestures', (tester) async {
    await tester.runAsync(() async {
      await pumpGallery(tester);
      await openPreview(tester, 'Fancy');

      // Fixture content actually rendered (not the gallery thumbnail).
      expect(
        find.descendant(
          of: find.byType(TemplatePreviewScreen),
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
      );
      // Tapping the middle of the canvas selects nothing and changes nothing:
      // still the preview, no editor chrome (delete/rotate handles).
      // The gallery's TabBarView (route below) is a PageView too — scope to
      // the preview's own.
      await tester.tap(
        find.descendant(
          of: find.byType(TemplatePreviewScreen),
          matching: find.byType(PageView),
        ),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(TemplatePreviewScreen), findsOneWidget);
      expect(find.byType(TemplateScreen), findsNothing);
    });
  });
}
