import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// How a purchase or a restore ended. The UI turns these into what the user
/// reads, and the distinctions are the point: a cancelled purchase is the user
/// closing the store sheet, and a pending one is money already committed.
/// Collapsing either into "purchase failed" is the mistake RevenueCat's docs
/// single out — it shows an error to someone who did nothing wrong, and tells
/// someone whose payment is clearing that they need to try again.
enum PurchaseOutcome {
  /// Pro is active right now.
  unlocked,

  /// The user dismissed the store sheet. Say nothing.
  cancelled,

  /// The store accepted the purchase but the payment clears later — cash,
  /// bank transfer, parental approval. The entitlement arrives on its own,
  /// through the customer-info listener, with no further action from anyone.
  pending,

  /// The store account already owns the subscription. Restoring is the fix,
  /// buying again is not.
  alreadyOwned,

  /// A restore ran and turned up nothing to restore.
  nothingToRestore,

  /// No usable connection to the store or to RevenueCat.
  offline,

  /// Anything else.
  failed,
}

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
  ///   `test_...` — the Test Store key (env/dev.json)
  ///   empty      — the default, and therefore what a build with no
  ///                `--dart-define-from-file` gets: monetization off, the SDK
  ///                is never configured, every user stays free.
  ///
  /// That default used to be the `test_` key, so a forgotten flag produced an
  /// AAB that uploaded fine and then died on launch on every device — the
  /// native SDK rejects a Test Store key outside debug, and the rejection
  /// never reaches the `catch` below. An empty default cannot do that: the
  /// worst a forgotten flag can now cause is an app that runs free.
  static const _apiKey = String.fromEnvironment('REVENUECAT_KEY');
  static const _entitlementId = 'pro';

  /// Whether the user owns the `pro` entitlement. Cached by the SDK, so it
  /// keeps its last known value offline.
  final ValueNotifier<bool> isPro = ValueNotifier(false);

  /// The store page where the user changes plan or cancels, handed over by
  /// RevenueCat. Null until customer info arrives, and for anyone who never
  /// subscribed — Settings only offers the row once there is a real URL.
  final ValueNotifier<String?> managementUrl = ValueNotifier(null);

  /// Whether [Purchases] is live in this build. False for a key-less build, a
  /// profile build on a test key, or a failed configure — in all three the
  /// SDK would throw on every call, so the paywall asks nothing and says its
  /// plans are unavailable instead.
  bool _configured = false;

  /// Settles when [init] has finished. Everything that talks to the SDK
  /// awaits it first: `main()` fires init without awaiting so the gallery
  /// paints immediately, which leaves a window on a cold start where a quick
  /// user reaches the paywall before `configure()` has returned. A call made
  /// in that window throws, and the paywall would blame the user's connection
  /// for a perfectly healthy account — the same dead end as an offering with
  /// no products, and indistinguishable from it on the device.
  Future<void> _ready = Future.value();

  Future<void> init() => _ready = _init();

  Future<void> _init() async {
    // No key configured: the app runs as a free tier, the paywall shows its
    // "plans unavailable" state and nothing crashes.
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
      _configured = true;
    } catch (e) {
      // configure() is local setup, so this is close to impossible — but if it
      // does fail, every later call would throw too. Staying unconfigured lets
      // packages()/buy() answer honestly instead of throwing into the UI.
      debugPrint('RevenueCat configure failed: $e');
      return;
    }
    // Registered before the first fetch, and outside the try: a listener that
    // exists can still correct isPro later, so a first run offline recovers on
    // its own instead of staying free until the app is killed.
    Purchases.addCustomerInfoUpdateListener(_apply);
    try {
      _apply(await Purchases.getCustomerInfo());
    } catch (e) {
      // First run offline: stay free and keep the app alive; the listener
      // corrects isPro whenever the SDK reaches the backend later.
      debugPrint('RevenueCat customer info unavailable: $e');
    }
  }

  void _apply(CustomerInfo info) {
    isPro.value = info.entitlements.active.containsKey(_entitlementId);
    managementUrl.value = info.managementURL;
  }

  /// Packages of the current offering (monthly/annual), for the paywall.
  Future<List<Package>> packages() async {
    await _ready;
    if (!_configured) return const [];
    final offerings = await Purchases.getOfferings();
    return offerings.current?.availablePackages ?? const [];
  }

  Future<PurchaseOutcome> buy(Package package) async {
    await _ready;
    if (!_configured) return PurchaseOutcome.failed;
    try {
      // The result already carries the post-purchase customer info, so there
      // is no second round-trip — and no window where a cached getCustomerInfo
      // could answer with the state from before the purchase.
      final result = await Purchases.purchase(PurchaseParams.package(package));
      _apply(result.customerInfo);
      if (isPro.value) return PurchaseOutcome.unlocked;
      // The store took the money and `pro` still is not active: the product is
      // not attached to the entitlement in the dashboard. Silent by nature —
      // see the "nomes que precisam bater" table in
      // docs/play-launch-checklist.md.
      debugPrint(
        'Purchase completed but "$_entitlementId" is not active — check that '
        'the product is attached to the entitlement in RevenueCat.',
      );
      return PurchaseOutcome.failed;
    } on PlatformException catch (e) {
      return _outcomeFor(e, 'Purchase');
    }
  }

  Future<PurchaseOutcome> restore() async {
    await _ready;
    if (!_configured) return PurchaseOutcome.failed;
    try {
      _apply(await Purchases.restorePurchases());
      // Nothing to restore is not an error: it is the answer for every user
      // who never subscribed, which on this screen is most of them.
      return isPro.value
          ? PurchaseOutcome.unlocked
          : PurchaseOutcome.nothingToRestore;
    } on PlatformException catch (e) {
      return _outcomeFor(e, 'Restore');
    }
  }

  /// Maps the SDK's error code onto something the user can act on. Anything
  /// unmapped stays [PurchaseOutcome.failed].
  PurchaseOutcome _outcomeFor(PlatformException e, String what) {
    PurchasesErrorCode code;
    try {
      code = PurchasesErrorHelper.getErrorCode(e);
    } on FormatException {
      // getErrorCode parses e.code as a number. A PlatformException from
      // anywhere but the RevenueCat plugin would throw here, and an exception
      // escaping this method would take the paywall down with it.
      code = PurchasesErrorCode.unknownError;
    }
    debugPrint('$what failed: $code — ${e.message}');
    return switch (code) {
      PurchasesErrorCode.purchaseCancelledError => PurchaseOutcome.cancelled,
      PurchasesErrorCode.paymentPendingError => PurchaseOutcome.pending,
      PurchasesErrorCode.productAlreadyPurchasedError ||
      PurchasesErrorCode.receiptAlreadyInUseError =>
        PurchaseOutcome.alreadyOwned,
      PurchasesErrorCode.networkError ||
      PurchasesErrorCode.offlineConnectionError => PurchaseOutcome.offline,
      _ => PurchaseOutcome.failed,
    };
  }
}
