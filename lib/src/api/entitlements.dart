import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// The single seam between the app and RevenueCat. `main()` configures it
/// once at startup; everything else just watches [isPro]. Widget tests
/// subclass it and never touch the SDK (platform channels don't exist there).
class EntitlementsService {
  /// RevenueCat Test Store key (project "Collage Studio"). Swap for the Play
  /// Store app key once the app exists in the Play Console.
  static const _apiKey = 'test_VzAaDRqPYszBSPhvEiphvgZHmkz';
  static const _entitlementId = 'pro';

  /// Whether the user owns the `pro` entitlement. Cached by the SDK, so it
  /// keeps its last known value offline.
  final ValueNotifier<bool> isPro = ValueNotifier(false);

  Future<void> init() async {
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
