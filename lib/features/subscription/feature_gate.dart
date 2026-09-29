import 'package:flutter/material.dart';

import '../profile/upgrade_plans_screen.dart';
import 'subscription_service.dart';

/// Widget + helper for gating features behind a subscription plan.
///
/// Usage:
/// ```dart
/// if (!await FeatureGate.require(context, AppFeatures.offlineDownloads)) return;
/// ```
class FeatureGate {
  FeatureGate._();

  static bool can(String feature) => SubscriptionService.instance.hasFeature(feature);

  /// Returns true when the feature is allowed. Otherwise shows an upgrade
  /// sheet and returns false.
  static Future<bool> require(
    BuildContext context,
    String feature, {
    String? customTitle,
  }) async {
    if (can(feature)) return true;
    if (!context.mounted) return false;
    await _showUpgradeSheet(context, feature, customTitle: customTitle);
    return false;
  }

  static Future<void> _showUpgradeSheet(
    BuildContext context,
    String feature, {
    String? customTitle,
  }) async {
    final theme = Theme.of(context);
    final featureName = customTitle ?? AppFeatures.labels[feature] ?? feature;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                  ),
                ),
                child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                '$featureName is a Premium feature',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Upgrade your plan to unlock $featureName and other premium features.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const UpgradePlansScreen()),
                    );
                  },
                  icon: const Icon(Icons.rocket_launch_rounded),
                  label: const Text('View Plans'),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Maybe later'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Widget that shows [child] when the feature is allowed, otherwise shows
/// [locked] (or a small lock badge) instead.
class FeatureGateWidget extends StatelessWidget {
  final String feature;
  final Widget child;
  final Widget? locked;

  const FeatureGateWidget({
    super.key,
    required this.feature,
    required this.child,
    this.locked,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SubscriptionService.instance,
      builder: (context, _) {
        if (SubscriptionService.instance.hasFeature(feature)) return child;
        return locked ??
            GestureDetector(
              onTap: () => FeatureGate.require(context, feature),
              child: child,
            );
      },
    );
  }
}
