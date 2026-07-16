import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:material_symbols_icons/symbols.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../api/entitlements.dart';
import '../api/template_api.dart';
import '../theme.dart';

/// Subscription paywall shown when a free user opens a premium template.
/// Pops with `true` after a purchase/restore that unlocked pro.
///
/// The plans are selectable cards driving a single Continue button — the tap
/// that spends money is always the same, clearly labeled one.
class PaywallScreen extends StatefulWidget {
  final EntitlementsService entitlements;

  /// Fuels the blurred template mosaic behind the pitch — show the product,
  /// not an abstract splash. Optional: without thumbnails the backdrop is a
  /// quiet gold-tinted gradient.
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

  /// Which plan card is highlighted; null until the user picks (the annual
  /// plan then acts as the default).
  PackageType? _selectedType;

  late final List<Uint8List> _mosaic = _decodeMosaic();

  /// Premium thumbnails first (they ARE the pitch), decoded once; cycled to
  /// fill the grid when there are only a few.
  List<Uint8List> _decodeMosaic() {
    final thumbs = <Uint8List>[];
    for (final template in [
      ...widget.catalog.where((t) => t.premium),
      ...widget.catalog.where((t) => !t.premium),
    ]) {
      final data = template.thumbnailDataUrl;
      if (data == null || !data.contains(',')) continue;
      try {
        thumbs.add(base64Decode(data.split(',').last));
      } catch (_) {
        // A malformed thumbnail is a gap in the backdrop, not an error.
      }
      if (thumbs.length >= 15) break;
    }
    if (thumbs.isEmpty) return const [];
    return [for (var i = 0; i < 15; i++) thumbs[i % thumbs.length]];
  }

  Future<void> _finish(Future<bool> unlock) async {
    setState(() => _busy = true);
    final unlocked = await unlock;
    if (!mounted) return;
    if (unlocked) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _busy = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Purchase not completed.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The mosaic bleeds behind the (transparent) app bar; only the
      // BackButton floats on top.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_mosaic.isNotEmpty) ...[
            _MosaicBackdrop(thumbs: _mosaic),
            // Legibility scrim, fading fully to ink where the plans sit.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xB30D0D0F), Color(0xE60D0D0F), AppColors.ink],
                  stops: [0, 0.35, 0.6],
                ),
              ),
            ),
          ] else
            // No thumbnails to show — a faint warm glow keeps the premium
            // register without faking content.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.7),
                  radius: 1.3,
                  colors: [Color(0xFF2B2216), AppColors.ink],
                ),
              ),
            ),
          SafeArea(
            child: FutureBuilder<List<Package>>(
              future: _packages,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final packages = snapshot.data ?? const <Package>[];
                if (snapshot.hasError || packages.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Plans are unavailable right now.\nCheck your connection and try again.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return _buildPlans(context, packages);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlans(BuildContext context, List<Package> packages) {
    Package? byType(PackageType type) {
      for (final p in packages) {
        if (p.packageType == type) return p;
      }
      return null;
    }

    final annual = byType(PackageType.annual);
    final monthly = byType(PackageType.monthly);
    // "Save 50%" on the annual card, computed from the real store prices so
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

    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, kToolbarHeight, 24, 16),
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Symbols.auto_awesome_rounded,
              size: 36,
              color: AppColors.gold,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Collage '),
              TextSpan(
                text: 'Pro',
                style: TextStyle(color: AppColors.gold),
              ),
            ],
          ),
          textAlign: TextAlign.center,
          style: textTheme.headlineLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Unlock every premium template.',
          textAlign: TextAlign.center,
          style: textTheme.bodyLarge!.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        const _Benefit(
          icon: Symbols.grid_view_rounded,
          text: 'Every premium template, unlocked',
        ),
        const _Benefit(
          icon: Symbols.new_releases_rounded,
          text: 'New premium templates as they arrive',
        ),
        const _Benefit(
          icon: Symbols.devices_rounded,
          text: 'Restore on any device with your store account',
        ),
        const SizedBox(height: 24),
        if (annual != null)
          _PlanCard(
            title: 'Annual',
            price: '${annual.storeProduct.priceString} / year',
            badge: savings,
            selected: selectedType == PackageType.annual,
            enabled: !_busy,
            onTap: () => setState(() => _selectedType = PackageType.annual),
          ),
        if (annual != null) const SizedBox(height: 12),
        if (monthly != null)
          _PlanCard(
            title: 'Monthly',
            price: '${monthly.storeProduct.priceString} / month',
            selected: selectedType == PackageType.monthly,
            enabled: !_busy,
            onTap: () => setState(() => _selectedType = PackageType.monthly),
          ),
        const SizedBox(height: 20),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _busy || selectedPackage == null
              ? null
              : () => _finish(widget.entitlements.buy(selectedPackage)),
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Continue'),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _busy
              ? null
              : () => _finish(widget.entitlements.restore()),
          child: const Text('Restore purchases'),
        ),
        const SizedBox(height: 4),
        const Text(
          'Auto-renews. Cancel anytime in your store settings.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// The blurred wall of template art behind the pitch.
class _MosaicBackdrop extends StatelessWidget {
  final List<Uint8List> thumbs;

  const _MosaicBackdrop({required this.thumbs});

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: GridView.count(
        crossAxisCount: 3,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 0.7,
        children: [
          for (final bytes in thumbs)
            Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
        ],
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Benefit({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.gold),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// A selectable plan: gold ring and radio dot when chosen, quiet otherwise.
/// Selecting never charges — only the Continue button does.
class _PlanCard extends StatelessWidget {
  final String title;
  final String price;
  final String? badge;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _PlanCard({
    required this.title,
    required this.price,
    this.badge,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.gold.withValues(alpha: 0.08)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? AppColors.gold : AppColors.outline,
          width: selected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? AppColors.gold : AppColors.surfaceBright,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? const Center(
                          child: SizedBox(
                            width: 10,
                            height: 10,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.gold,
                              ),
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        price,
                        style: Theme.of(context).textTheme.bodyMedium!
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      // Gold, not the action accent: the savings badge is
                      // premium signaling, not an action.
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onGold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
