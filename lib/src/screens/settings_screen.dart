import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../api/entitlements.dart';
import '../theme.dart';
import 'paywall_screen.dart';

/// Settings, pushed from the gear icon in the home header.
class SettingsScreen extends StatelessWidget {
  final EntitlementsService entitlements;

  const SettingsScreen({super.key, required this.entitlements});

  Future<void> _restore(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final restored = await entitlements.restore();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          restored
              ? 'Pro restored — welcome back!'
              : 'No previous purchases found.',
        ),
      ),
    );
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
                ? const _SettingsCard(
                    children: [
                      ListTile(
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
