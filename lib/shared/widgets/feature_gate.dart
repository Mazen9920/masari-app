import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/app_settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../shared/utils/safe_pop.dart';

// ─── FeatureGate Widget ──────────────────────────────────────────────────────
/// Wraps a child widget and only renders it if the user's subscription tier
/// meets the [requiredTier]. Otherwise, shows a beautiful upgrade prompt.
///
/// Usage:
/// ```dart
/// FeatureGate(
///   feature: GrowthFeature.balanceSheet,
///   child: BalanceSheetScreen(),
/// )
/// ```
class FeatureGate extends ConsumerWidget {
  const FeatureGate({
    super.key,
    required this.feature,
    required this.child,
    this.requiredTier,
    this.inline = false,
  });

  /// The feature being gated — used for display name and description.
  final GrowthFeature feature;

  /// The widget to render when the feature is unlocked.
  final Widget child;

  /// The minimum tier required. Auto-detected from [feature] if null:
  /// All features → [SubscriptionTier.growth].
  final SubscriptionTier? requiredTier;

  /// If true, renders a compact inline card instead of a full-screen prompt.
  /// Useful for gating a section within a larger screen.
  final bool inline;

  SubscriptionTier get _effectiveTier =>
      requiredTier ?? SubscriptionTier.growth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tier = ref.watch(tierProvider);
    final required = _effectiveTier;
    if (tier.hasAccess(required)) return child;
    return inline
        ? _InlineUpgradeCard(feature: feature, requiredTier: required)
        : _FullUpgradePrompt(feature: feature, requiredTier: required);
  }
}

// ─── Full-screen upgrade prompt ──────────────────────────────────────────────
class _FullUpgradePrompt extends StatelessWidget {
  const _FullUpgradePrompt({required this.feature, required this.requiredTier});
  final GrowthFeature feature;
  final SubscriptionTier requiredTier;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon badge
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.accentOrange.withValues(alpha: 0.15),
                    AppColors.accentOrange.withValues(alpha: 0.05),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.rocket_launch_rounded,
                color: AppColors.accentOrange,
                size: 40,
              ),
            ),
            const SizedBox(height: 28),

            // Feature name
            Text(
              feature.displayName,
              style: AppTypography.h2.copyWith(color: AppColors.primaryNavy),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Description
            Text(
              feature.description,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // Tier badge
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.accentOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${requiredTier.label} Mode Feature',
                style: TextStyle(
                  color: AppColors.accentOrange,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Upgrade button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  context.pushNamed('ManageSubscriptionScreen');
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentOrange,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                  elevation: 4,
                  shadowColor: AppColors.accentOrange.withValues(alpha: 0.4),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.trending_up_rounded, size: 20),
                    const SizedBox(width: 8),
                    Text(
                       'Upgrade to Growth',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Learn more link
            TextButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                context.pushNamed('ManageSubscriptionScreen');
              },
              child: Text(
                 'Compare all plans',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Compact inline upgrade card ─────────────────────────────────────────────
class _InlineUpgradeCard extends StatelessWidget {
  const _InlineUpgradeCard({required this.feature, required this.requiredTier});
  final GrowthFeature feature;
  final SubscriptionTier requiredTier;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accentOrange.withValues(alpha: 0.08),
            AppColors.accentOrange.withValues(alpha: 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.accentOrange.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accentOrange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: AppColors.accentOrange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      feature.displayName,
                      style: TextStyle(
                        color: AppColors.primaryNavy,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${requiredTier.label} Mode',
                      style: TextStyle(
                        color: AppColors.accentOrange,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            feature.description,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                context.pushNamed('ManageSubscriptionScreen');
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentOrange,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              child: Text(
                 'Upgrade to Growth',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Helper: FeatureGateScreen ───────────────────────────────────────────────
/// A convenience wrapper for gating an entire routed screen. Wraps the child
/// in a Scaffold so it looks correct when pushed via GoRouter.
class FeatureGateScreen extends ConsumerWidget {
  const FeatureGateScreen({
    super.key,
    required this.feature,
    required this.child,
    this.requiredTier,
    this.appBarTitle,
  });

  final GrowthFeature feature;
  final Widget child;
  final SubscriptionTier? requiredTier;
  final String? appBarTitle;

  SubscriptionTier get _effectiveTier =>
      requiredTier ?? SubscriptionTier.growth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tier = ref.watch(tierProvider);
    if (tier.hasAccess(_effectiveTier)) return child;

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.safePop(),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.primaryNavy,
          ),
        ),
        title: Text(
          appBarTitle ?? feature.displayName,
          style: AppTypography.h3.copyWith(color: AppColors.primaryNavy),
        ),
        centerTitle: true,
      ),
      body: _FullUpgradePrompt(
        feature: feature,
        requiredTier: _effectiveTier,
      ),
    );
  }
}
