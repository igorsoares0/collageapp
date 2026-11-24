import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/entitlements.dart';
import '../api/template_api.dart';
import '../legal.dart';
import '../theme.dart';
import '../widgets/layer_ui.dart';
import 'paywall_screen.dart';

/// Settings, pushed from the gear in the Discover masthead. Set as a
/// contents page: three sections, each an eyebrow over an ink rule, rows
/// divided by hairlines, a colophon at the foot.
class SettingsScreen extends StatelessWidget {
  final EntitlementsService entitlements;

  /// The loaded index, when there is one: a premium cover for the
  /// membership row, and the paywall's cover spread.
  final List<TemplateSummary> catalog;

  const SettingsScreen({
    super.key,
    required this.entitlements,
    this.catalog = const [],
  });

  Future<void> _restore(BuildContext context) async {
    final outcome = await entitlements.restore();
    if (!context.mounted) return;
    // "Restored" beats the paywall's "unlocked" here — this user is coming
    // back to something they already bought. Every other outcome reads the
    // same on both screens.
    final message = outcome == PurchaseOutcome.unlocked
        ? 'Pro restored — welcome back.'
        : purchaseOutcomeMessage(outcome);
    if (message == null) return;
    showLayerMessage(context, message);
  }

  /// Opens a page in the browser. A failure here is not worth an error
  /// dialog — the user can still reach the same pages from the store listing.
  Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      showLayerMessage(context, 'Could not open the page.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const LayerTopBar(),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              sliver: SliverList.list(
                children: [
                  Text('Settings', style: AppType.headlineL),
                  const SizedBox(height: 32),
                  const _Section('Membership'),
                  ValueListenableBuilder<bool>(
                    valueListenable: entitlements.isPro,
                    builder: (context, isPro, _) =>
                        isPro ? _proActive(context) : _proOffer(context),
                  ),
                  const SizedBox(height: 32),
                  const _Section('Legal'),
                  _Row(
                    label: 'Privacy Policy',
                    icon: Symbols.north_east,
                    onTap: () => _open(context, kPrivacyPolicyUrl),
                  ),
                  _Row(
                    label: 'Terms of Service',
                    icon: Symbols.north_east,
                    onTap: () => _open(context, kTermsUrl),
                  ),
                  const SizedBox(height: 32),
                  const _Section('About'),
                  _Row(
                    label: 'Version',
                    trailing: Text(
                      '1.0.0',
                      style: AppType.sans(14, color: AppColors.inkSoft),
                    ),
                  ),
                ],
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Layer', style: AppType.serif(20, italic: true)),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          'Set in Newsreader & Instrument Sans',
                          textAlign: TextAlign.end,
                          style: AppType.sans(12, color: AppColors.inkSoft),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _proOffer(BuildContext context) {
    void seePlans() => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PaywallScreen(entitlements: entitlements, catalog: catalog),
      ),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: _ProCover(catalog: catalog),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    const _LayerPro(size: 24),
                    const SizedBox(height: 6),
                    Text(
                      'Unlock every premium template.',
                      style: AppType.sans(14, color: AppColors.inkSoft),
                    ),
                    TextLink('See plans', onTap: seePlans),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Hairline(),
        _Row(
          label: 'Restore purchases',
          icon: Symbols.history,
          onTap: () => _restore(context),
        ),
      ],
    );
  }

  Widget _proActive(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _LayerPro(size: 24),
                    const SizedBox(height: 6),
                    Text(
                      'Pro · Active — all templates unlocked',
                      style: AppType.sans(14, color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Hairline(),
        // Google Play expects a subscriber to be able to reach the
        // cancel/change-plan page from inside the app, and RevenueCat hands
        // over the exact store URL for this user. It arrives with the
        // customer info, so the row appears a beat after the screen — hiding
        // it until then beats showing a link that opens nothing.
        ValueListenableBuilder<String?>(
          valueListenable: entitlements.managementUrl,
          builder: (context, url, _) => url == null
              ? const SizedBox.shrink()
              : _Row(
                  label: 'Manage subscription',
                  icon: Symbols.north_east,
                  onTap: () => _open(context, url),
                ),
        ),
      ],
    );
  }
}

/// "Layer *Pro*" — the wordmark with Pro in rouge italic.
class _LayerPro extends StatelessWidget {
  final double size;

  const _LayerPro({required this.size});

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        const TextSpan(text: 'Layer '),
        TextSpan(
          text: 'Pro',
          style: AppType.serif(size, italic: true, color: AppColors.rouge),
        ),
      ],
    ),
    style: AppType.serif(size),
  );
}

/// A premium template's cover from the index (with its page edges); a
/// rouge plate when no cover is at hand.
class _ProCover extends StatelessWidget {
  final List<TemplateSummary> catalog;

  const _ProCover({required this.catalog});

  @override
  Widget build(BuildContext context) {
    String? thumb;
    for (final t in catalog) {
      final url = t.thumbnailDataUrl;
      if (t.premium && url != null && url.contains(',')) {
        thumb = url;
        break;
      }
    }
    return SizedBox(
      width: 72,
      height: 90,
      child: PageEdges(
        slides: 2,
        child: thumb != null
            ? Image.memory(
                base64Decode(thumb.split(',').last),
                fit: BoxFit.cover,
              )
            : ColoredBox(
                color: AppColors.rouge,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'Pro',
                    style: AppType.serif(
                      24,
                      italic: true,
                      color: AppColors.onInk,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String label;

  const _Section(this.label);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Eyebrow(label, color: AppColors.inkSoft),
      const SizedBox(height: 12),
      const Hairline(color: AppColors.ink),
    ],
  );
}

class _Row extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _Row({required this.label, this.icon, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: AppType.sans(16))),
                  ?trailing,
                  if (icon != null) Icon(icon, size: 20, weight: 200),
                ],
              ),
            ),
          ),
        ),
        const Hairline(),
      ],
    );
  }
}
