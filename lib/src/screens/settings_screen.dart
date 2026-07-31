import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/entitlements.dart';
import '../legal.dart';
import '../theme.dart';
import 'paywall_screen.dart';

/// Settings, pushed from the gear icon in the home header.
class SettingsScreen extends StatelessWidget {
  final EntitlementsService entitlements;

  const SettingsScreen({super.key, required this.entitlements});

  Future<void> _restore(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await entitlements.restore();
    // "Restored" beats the paywall's "unlocked" here — this user is coming
    // back to something they already bought. Every other outcome reads the
    // same on both screens.
    final message = outcome == PurchaseOutcome.unlocked
        ? 'Pro restored — welcome back!'
        : purchaseOutcomeMessage(outcome);
    if (message == null) return;
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Opens a legal page in the browser. A failure here is not worth an error
  /// dialog — the user can still reach the same pages from the store listing.
  Future<void> _open(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the page.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const _SectionLabel('Membership'),
          ValueListenableBuilder<bool>(
            valueListenable: entitlements.isPro,
            builder: (context, isPro, _) => isPro
                ? _SettingsCard(
                    children: [
                      const ListTile(
                        leading: Icon(
                          Symbols.workspace_premium_rounded,
                          color: AppColors.gold,
                        ),
                        title: Text('Collage Pro'),
                        subtitle: Text(
                          'Active — all templates unlocked',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                      // Google Play expects a subscriber to be able to reach
                      // the cancel/change-plan page from inside the app, and
                      // RevenueCat hands over the exact store URL for this
                      // user. It arrives with the customer info, so the row
                      // appears a beat after the screen — hiding it until then
                      // beats showing a link that opens nothing.
                      ValueListenableBuilder<String?>(
                        valueListenable: entitlements.managementUrl,
                        builder: (context, url, _) => url == null
                            ? const SizedBox.shrink()
                            : Column(
                                children: [
                                  const Divider(height: 1, indent: 56),
                                  ListTile(
                                    leading: const Icon(
                                      Symbols.settings_rounded,
                                    ),
                                    title: const Text('Manage subscription'),
                                    subtitle: const Text(
                                      'Change plan or cancel in the store',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    trailing: const Icon(
                                      Symbols.open_in_new_rounded,
                                      size: 18,
                                    ),
                                    onTap: () => _open(context, url),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  )
                : _SettingsCard(
                    children: [
                      ListTile(
                        leading: const Icon(
                          Symbols.workspace_premium_rounded,
                          color: AppColors.gold,
                        ),
                        title: const Text('Get Collage Pro'),
                        subtitle: const Text(
                          'Unlock every premium template',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        trailing: const Icon(Symbols.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PaywallScreen(entitlements: entitlements),
                          ),
                        ),
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: const Icon(Symbols.history_rounded),
                        title: const Text('Restore purchases'),
                        onTap: () => _restore(context),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('Legal'),
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Symbols.shield_rounded),
                title: const Text('Privacy Policy'),
                trailing: const Icon(Symbols.open_in_new_rounded, size: 18),
                onTap: () => _open(context, kPrivacyPolicyUrl),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Symbols.description_rounded),
                title: const Text('Terms of Service'),
                trailing: const Icon(Symbols.open_in_new_rounded, size: 18),
                onTap: () => _open(context, kTermsUrl),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const _SectionLabel('About'),
          const _SettingsCard(
            children: [
              ListTile(
                leading: Icon(Symbols.info_rounded),
                title: Text('Version'),
                trailing: Text(
                  '1.0.0',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// Rounded surface grouping a run of settings rows, matching the app's cards.
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}
