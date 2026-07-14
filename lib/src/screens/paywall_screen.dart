import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../api/entitlements.dart';

/// Subscription paywall shown when a free user opens a premium template.
/// Pops with `true` after a purchase/restore that unlocked pro.
class PaywallScreen extends StatefulWidget {
  final EntitlementsService entitlements;

  const PaywallScreen({super.key, required this.entitlements});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  late final Future<List<Package>> _packages = widget.entitlements.packages();
  bool _busy = false;

  Future<void> _finish(Future<bool> unlock) async {
    setState(() => _busy = true);
    final unlocked = await unlock;
    if (!mounted) return;
    if (unlocked) {
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
      appBar: AppBar(),
      body: SafeArea(
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

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      children: [
        const Icon(Icons.auto_awesome, size: 48),
        const SizedBox(height: 12),
        Text(
          'Collage Pro',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Unlock every premium template.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        if (annual != null)
          _PlanCard(
            title: 'Annual',
            price: '${annual.storeProduct.priceString} / year',
            badge: savings,
            highlighted: true,
            enabled: !_busy,
            onTap: () => _finish(widget.entitlements.buy(annual)),
          ),
        if (annual != null) const SizedBox(height: 12),
        if (monthly != null)
          _PlanCard(
            title: 'Monthly',
            price: '${monthly.storeProduct.priceString} / month',
            enabled: !_busy,
            onTap: () => _finish(widget.entitlements.buy(monthly)),
          ),
        const SizedBox(height: 16),
        if (_busy)
          const Center(child: CircularProgressIndicator())
        else
          TextButton(
            onPressed: () => _finish(widget.entitlements.restore()),
            child: const Text('Restore purchases'),
          ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String title;
  final String price;
  final String? badge;
  final bool highlighted;
  final bool enabled;
  final VoidCallback onTap;

  const _PlanCard({
    required this.title,
    required this.price,
    this.badge,
    this.highlighted = false,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: highlighted ? scheme.primaryContainer : null,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(price, style: Theme.of(context).textTheme.bodyMedium),
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
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
