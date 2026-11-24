import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:material_symbols_icons/symbols.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../api/entitlements.dart';
import '../api/template_api.dart';
import '../theme.dart';
import '../widgets/layer_ui.dart';
import '../widgets/template_meta.dart';

/// What to tell the user about a finished purchase or restore. Null means say
/// nothing: cancelling was the user's own decision, and a snackbar about it
/// reads as an error they caused.
///
/// Shared with Settings, which runs the same restore from a different screen.
String? purchaseOutcomeMessage(PurchaseOutcome outcome) => switch (outcome) {
  PurchaseOutcome.unlocked => 'Pro unlocked — enjoy!',
  PurchaseOutcome.cancelled => null,
  PurchaseOutcome.pending =>
    'Payment pending. Pro unlocks as soon as it clears — no need to buy again.',
  PurchaseOutcome.alreadyOwned =>
    'This store account already has Pro. Tap "Restore purchases".',
  PurchaseOutcome.nothingToRestore => 'No previous purchases found.',
  PurchaseOutcome.offline =>
    'Could not reach the store. Check your connection and try again.',
  PurchaseOutcome.failed => 'Something went wrong. Please try again.',
};

/// Subscription paywall shown when a free user opens a premium template.
/// Pops with `true` after a purchase/restore that unlocked pro.
///
/// "Show the shelf, don't shout": a sharp spread of real Pro covers, the
/// three benefits numbered, the plans as rows. Selecting a plan never
/// charges — the tap that spends money is always the one Continue button.
class PaywallScreen extends StatefulWidget {
  final EntitlementsService entitlements;

  /// The loaded index: its premium covers make the spread at the top.
  /// Optional — without thumbnails the spread is left out.
  final List<TemplateSummary> catalog;

  const PaywallScreen({
    super.key,
    required this.entitlements,
    this.catalog = const [],
  });

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  late final Future<List<Package>> _packages = widget.entitlements.packages();
  bool _busy = false;

  /// Which plan row is selected; null until the user picks (the annual plan
  /// then acts as the default).
  PackageType? _selectedType;

  late final List<(Uint8List, double)> _covers = _decodeCovers();

  /// Up to three covers, premium first (they ARE the pitch), each with its
  /// aspect; decoded once.
  List<(Uint8List, double)> _decodeCovers() {
    final covers = <(Uint8List, double)>[];
    for (final template in [
      ...widget.catalog.where((t) => t.premium),
      ...widget.catalog.where((t) => !t.premium),
    ]) {
      final data = template.thumbnailDataUrl;
      if (data == null || !data.contains(',')) continue;
      try {
        covers.add((
          base64Decode(data.split(',').last),
          aspectRatioOf(template.aspectRatio),
        ));
      } catch (_) {
        // A malformed thumbnail is a gap in the spread, not an error.
      }
      if (covers.length >= 3) break;
    }
    return covers;
  }

  Future<void> _finish(Future<PurchaseOutcome> attempt) async {
    setState(() => _busy = true);
    final outcome = await attempt;
    if (!mounted) return;
    if (outcome == PurchaseOutcome.unlocked) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _busy = false);
    // Everything else keeps the user on the paywall, because everything else
    // leaves something to do here — retry, restore, or just wait.
    final message = purchaseOutcomeMessage(outcome);
    if (message == null) return;
    showLayerMessage(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<Package>>(
          future: _packages,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState != ConnectionState.done;
            final packages = snapshot.data ?? const <Package>[];
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(Symbols.close, size: 24),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
                if (_covers.isNotEmpty) ...[
                  _CoverSpread(covers: _covers),
                  const SizedBox(height: 36),
                ] else
                  const SizedBox(height: 12),
                const Eyebrow('Layer Pro', color: AppColors.rouge),
                const SizedBox(height: 8),
                SerifHeadline(
                  roman: 'The whole ',
                  italic: 'collection.',
                  style: AppType.headline,
                ),
                const SizedBox(height: 22),
                const _Benefit(n: 1, text: 'Every premium template, unlocked'),
                const _Benefit(
                  n: 2,
                  text: 'New premium templates as they arrive',
                ),
                const _Benefit(
                  n: 3,
                  text: 'Restore on any device with your store account',
                ),
                const Hairline(),
                const SizedBox(height: 22),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: LayerSpinner()),
                  )
                else if (snapshot.hasError || packages.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Plans are unavailable right now. Check your '
                      'connection and try again.',
                      style: AppType.body.copyWith(color: AppColors.inkSoft),
                    ),
                  )
                else
                  ..._buildPlans(packages),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildPlans(List<Package> packages) {
    Package? byType(PackageType type) {
      for (final p in packages) {
        if (p.packageType == type) return p;
      }
      return null;
    }

    final annual = byType(PackageType.annual);
    final monthly = byType(PackageType.monthly);
    // "Save 50%" on the annual row, computed from the real store prices so
    // it stays honest when prices change in the dashboard.
    String? savings;
    if (annual != null && monthly != null && monthly.storeProduct.price > 0) {
      final ratio =
          1 - annual.storeProduct.price / (monthly.storeProduct.price * 12);
      if (ratio > 0.05) savings = 'Save ${(ratio * 100).round()}%';
    }

    final selectedType =
        _selectedType ??
        (annual != null
            ? PackageType.annual
            : monthly != null
            ? PackageType.monthly
            : null);
    final selectedPackage = selectedType == PackageType.annual
        ? annual
        : selectedType == PackageType.monthly
        ? monthly
        : null;

    return [
      if (annual != null)
        _PlanRow(
          title: 'Annual',
          price: '${annual.storeProduct.priceString} / year',
          savings: savings,
          selected: selectedType == PackageType.annual,
          enabled: !_busy,
          onTap: () => setState(() => _selectedType = PackageType.annual),
        ),
      if (annual != null) const SizedBox(height: 12),
      if (monthly != null)
        _PlanRow(
          title: 'Monthly',
          price: '${monthly.storeProduct.priceString} / month',
          selected: selectedType == PackageType.monthly,
          enabled: !_busy,
          onTap: () => setState(() => _selectedType = PackageType.monthly),
        ),
      const SizedBox(height: 20),
      PrimaryButton(
        label: 'Continue',
        labelWidget: _busy
            ? const Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppColors.inkSoft,
                  ),
                ),
              )
            : null,
        icon: _busy ? null : Symbols.arrow_forward,
        onPressed: _busy || selectedPackage == null
            ? null
            : () => _finish(widget.entitlements.buy(selectedPackage)),
      ),
      const SizedBox(height: 8),
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TextLink(
            'Restore purchases',
            onTap: _busy ? null : () => _finish(widget.entitlements.restore()),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Text(
              'Auto-renews. Cancel anytime.',
              textAlign: TextAlign.end,
              style: AppType.sans(13, color: AppColors.inkSoft),
            ),
          ),
        ],
      ),
    ];
  }
}

/// Three real covers, sharp, at their own aspects: a large one on the left,
/// two smaller ones and a "From the Pro shelf" caption on the right.
class _CoverSpread extends StatelessWidget {
  final List<(Uint8List, double)> covers;

  const _CoverSpread({required this.covers});

  @override
  Widget build(BuildContext context) {
    Widget cover((Uint8List, double) c, double width) => SizedBox(
      width: width,
      height: width / c.$2,
      child: Image.memory(c.$1, fit: BoxFit.cover, gaplessPlayback: true),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final big = w * 0.43;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cover(covers[0], big),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (covers.length > 1)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          cover(covers[1], w * 0.31),
                          if (covers.length > 2) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: LayoutBuilder(
                                  builder: (context, c) =>
                                      cover(covers[2], c.maxWidth),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    const SizedBox(height: 12),
                    const Eyebrow('From the Pro shelf', size: 11),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Benefit extends StatelessWidget {
  final int n;
  final String text;

  const _Benefit({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Hairline(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 30,
                child: Text(twoDigits(n), style: AppType.numeral(16)),
              ),
              Expanded(child: Text(text, style: AppType.sans(15))),
            ],
          ),
        ),
      ],
    );
  }
}

/// A selectable plan row: square radio (filled ink square when chosen),
/// paperDeep fill and an ink border when selected, a rule border otherwise.
/// Selecting never charges — only the Continue button does.
class _PlanRow extends StatelessWidget {
  final String title;
  final String price;
  final String? savings;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _PlanRow({
    required this.title,
    required this.price,
    this.savings,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: selected ? AppColors.paperDeep : Colors.transparent,
            border: Border.all(
              color: selected ? AppColors.ink : AppColors.rule,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: selected ? AppColors.ink : AppColors.inkSoft,
                  ),
                ),
                child: selected
                    ? Container(width: 8, height: 8, color: AppColors.ink)
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppType.sans(15, weight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      price,
                      style: AppType.sans(12.5, color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
              if (savings != null)
                Text(
                  savings!,
                  style: AppType.serif(
                    18,
                    italic: true,
                    color: AppColors.rouge,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
