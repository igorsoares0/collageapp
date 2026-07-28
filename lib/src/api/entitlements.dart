import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// The single seam between the app and RevenueCat. `main()` configures it
/// once at startup; everything else just watches [isPro]. Widget tests
/// subclass it and never touch the SDK (platform channels don't exist there).
class EntitlementsService {
  /// RevenueCat public SDK key, picked at build time like [kApiBase]:
  ///   flutter build --dart-define-from-file=env/prod.json
  ///
  /// This key is *public* by design — it ships inside every APK and is
  /// extractable from one, which is why it lives in a committed env file
  /// rather than a secret. The private half is the service-account JSON that
  /// stays in the RevenueCat dashboard.
  ///
  /// Three states, all deliberate:
  ///   `goog_...` — the Play Store app key (env/prod.json)
  ///   `test_...` — the Test Store key, and the default, so a bare
  ///                `flutter run` behaves exactly as it always has
  ///   empty      — monetization off: the SDK is never configured and every
  ///                user stays free. env/prod.json ships this until the Play
  ///                Console app exists (see docs/play-launch-checklist.md).
  static const _apiKey = String.fromEnvironment(
    'REVENUECAT_KEY',
    defaultValue: 'test_VzAaDRqPYszBSPhvEiphvgZHmkz',
  );
  static const _entitlementId = 'pro';

  /// Whether the user owns the `pro` entitlement. Cached by the SDK, so it
  /// keeps its last known value offline.
  final ValueNotifier<bool> isPro = ValueNotifier(false);

  Future<void> init() async {
    // No key configured: the app runs as a free tier, the paywall shows its
    // "plans unavailable" state and nothing crashes. This is the shape of the
    // first closed-testing build, uploaded before the Play Console app has
    // subscriptions — the 14-day clock starts on a build that opens.
    if (_apiKey.isEmpty) {
      debugPrint('RevenueCat disabled: no REVENUECAT_KEY in this build.');
      return;
    }
    // A Test Store key is rejected by the SDK in any non-debug build, and the
    // rejection comes from the native side — the catch below never sees it, so
    // the app dies at startup instead of degrading to free. That makes it
    // impossible to profile the editor, which is exactly what profile builds
    // are for. Skipping is strictly better than crashing here: the SDK could
    // not have worked in this build either way. RELEASE deliberately keeps
    // crashing — that is RevenueCat's guard against shipping a test key, and
    // it stops being relevant on its own once _apiKey is a real store key.
    if (kProfileMode && _apiKey.startsWith('test_')) {
      debugPrint('RevenueCat skipped: Test Store key in a profile build.');
      return;
    }
    try {
      await Purchases.configure(PurchasesConfiguration(_apiKey));
      Purchases.addCustomerInfoUpdateListener(_apply);
      _apply(await Purchases.getCustomerInfo());
    } catch (e) {
      // First run offline: stay free and keep the app alive; the listener
      // corrects isPro whenever the SDK reaches the backend later.
      debugPrint('RevenueCat init failed: $e');
    }
  }

  void _apply(CustomerInfo info) {
    isPro.value = info.entitlements.active.containsKey(_entitlementId);
  }

  /// Packages of the current offering (monthly/annual), for the paywall.
  Future<List<Package>> packages() async {
    final offerings = await Purchases.getOfferings();
    return offerings.current?.availablePackages ?? const [];
  }

  /// True when the purchase went through and unlocked pro. A cancelled
  /// purchase returns false without throwing.
  Future<bool> buy(Package package) async {
    try {
      await Purchases.purchase(PurchaseParams.package(package));
      _apply(await Purchases.getCustomerInfo());
    } on PlatformException catch (e) {
      debugPrint('Purchase failed: ${e.message}');
    }
    return isPro.value;
  }

  Future<bool> restore() async {
    try {
      _apply(await Purchases.restorePurchases());
    } on PlatformException catch (e) {
      debugPrint('Restore failed: ${e.message}');
    }
    return isPro.value;
  }
}
