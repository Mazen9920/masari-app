import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_settings_provider.dart';
import '../shopify/providers/shopify_connection_provider.dart';
import '../../shared/utils/safe_pop.dart';

class ManageSubscriptionScreen extends ConsumerWidget {
  const ManageSubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final currentTier = ref.watch(tierProvider);
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.safePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primaryNavy),
        ),
        title: Text('Your Plan', style: AppTypography.h3.copyWith(color: AppColors.primaryNavy)),
        centerTitle: true,
        actions: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    currentTier == SubscriptionTier.launch ? 'Free' : currentTier.shortLabel,
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Current Plan Card
            _buildCurrentPlanCard(currentTier, currency),
            const SizedBox(height: 32),

            // Available Upgrades Title
            if (currentTier != SubscriptionTier.pro) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    currentTier == SubscriptionTier.launch
                        ? 'Available Upgrades'
                        : 'Manage Plan',
                    style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
                  ),
                  if (currentTier == SubscriptionTier.launch)
                    Text('Save 20% on yearly', style: TextStyle(color: AppColors.accentOrange, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Growth Mode Card (includes Shopify)
            _buildGrowthModeCard(context, currency, ref, currentTier),
            const SizedBox(height: 20),

            // Pro Mode Card
            _buildProModeCard(context, currency),
            const SizedBox(height: 32),

            // Bottom Accordions
            _buildCompareButton(context),
            const SizedBox(height: 24),
            Text('Frequently Asked Questions', style: AppTypography.h3.copyWith(color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            _buildFAQ(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ─── Current plan hero card ──────────────────────────────────────────────────
  Widget _buildCurrentPlanCard(SubscriptionTier currentTier, String currency) {
    final isGrowthVariant = currentTier.isGrowthOrAbove;

    final String planName;
    final String planDesc;
    final String planPrice;
    final String planSuffix;
    final IconData planIcon;
    final Color bgColor;

    switch (currentTier) {
      case SubscriptionTier.launch:
        planName = 'Launch Mode';
        planDesc = 'Perfect for early-stage startups.';
        planPrice = 'Free';
        planSuffix = 'Forever';
        planIcon = Icons.rocket_launch_outlined;
        bgColor = AppColors.primaryNavy;
      case SubscriptionTier.growth:
        planName = 'Growth Mode';
        planDesc = 'For scaling businesses.';
        planPrice = '$currency 249';
        planSuffix = '/mo';
        planIcon = Icons.show_chart_rounded;
        bgColor = AppColors.accentOrange;
      case SubscriptionTier.pro:
        planName = 'Pro Mode';
        planDesc = 'For established enterprises.';
        planPrice = '$currency 749';
        planSuffix = '/mo';
        planIcon = Icons.emoji_events_outlined;
        bgColor = AppColors.primaryNavy;
    }

    final List<String> features;
    if (isGrowthVariant) {
      features = [
        'Everything in Launch Mode',
        'Sales system with COGS tracking',
        'Goods receiving & inventory auto-link',
        'Full Income Statement (P&L)',
        'Balance Sheet',
        'Recurring transactions',
        'AI financial insights',
        'Shopify integration & order sync',
        '5 Team members',
      ];
    } else if (currentTier == SubscriptionTier.pro) {
      features = [
        'Everything in Growth Mode',
        'Advanced financial modeling',
        'Investor reporting dashboard',
        'Multi-store management',
        'Unlimited users & full API access',
      ];
    } else {
      features = [
        'Income & expense tracking',
        'Simple profit/loss report',
        'Cash flow overview',
        'Basic inventory & stock',
        'Supplier ledger & purchases',
        'Custom categories',
        '1 Admin User',
      ];
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: bgColor.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -40,
            right: -40,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(planIcon, color: const Color(0xFF86EFAC), size: 18),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(planName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(planDesc, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: const Text('Active', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(planPrice, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(planSuffix, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 16)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ...features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildFeatureItem(f, isWhite: true),
              )),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Growth Mode Card (includes Shopify) ───────────────────────────────────
  Widget _buildGrowthModeCard(BuildContext context, String currency, WidgetRef ref, SubscriptionTier currentTier) {
    final isOnGrowth = currentTier == SubscriptionTier.growth;
    final isAboveGrowth = currentTier.index > SubscriptionTier.growth.index;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.3), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.accentOrange.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.show_chart_rounded, color: AppColors.accentOrange, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Growth Mode', style: AppTypography.h3.copyWith(color: AppColors.textPrimary)),
                      Text('For scaling businesses', style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$currency 249', style: TextStyle(color: AppColors.textPrimary, fontSize: 32, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('/mo', style: TextStyle(color: AppColors.textTertiary, fontSize: 15)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildFeatureItem('Everything in Launch, plus:', isBold: true),
              const SizedBox(height: 12),
              _buildFeatureItem('Sales system with COGS tracking'),
              const SizedBox(height: 12),
              _buildFeatureItem('Goods receiving & inventory auto-link'),
              const SizedBox(height: 12),
              _buildFeatureItem('Full Income Statement (P&L)'),
              const SizedBox(height: 12),
              _buildFeatureItem('Balance Sheet'),
              const SizedBox(height: 12),
              _buildFeatureItem('Budget limits per category'),
              const SizedBox(height: 12),
              _buildFeatureItem('Recurring transactions'),
              const SizedBox(height: 12),
              _buildFeatureItem('Purchase & payment dashboards'),
              const SizedBox(height: 12),
              _buildFeatureItem('Raw materials tracking'),
              const SizedBox(height: 12),
              _buildFeatureItem('Report export & share'),
              const SizedBox(height: 12),
              _buildFeatureItem('AI financial insights'),
              const SizedBox(height: 12),
              _buildFeatureItem('Shopify integration & order sync'),
              const SizedBox(height: 12),
              _buildFeatureItem('5 Team members'),
              const SizedBox(height: 24),
              if (isOnGrowth) ...[
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                      const SizedBox(width: 8),
                      Text('Current Plan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.success)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => _showDowngradeDialog(context, ref, SubscriptionTier.launch),
                  child: Text('Switch to Launch Mode', style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
                ),
              ] else if (isAboveGrowth) ...[
                OutlinedButton(
                  onPressed: () => _showDowngradeDialog(context, ref, SubscriptionTier.growth),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.borderLight, width: 1.5),
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                  ),
                  child: const Text('Switch to Growth', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ] else ...[
                FilledButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    ref.read(appSettingsProvider.notifier).setTier(SubscriptionTier.growth);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Switched to Growth Mode!')),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentOrange,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                    elevation: 4,
                    shadowColor: AppColors.accentOrange.withValues(alpha: 0.4),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Text('Upgrade to Growth', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (!isAboveGrowth)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.accentOrange,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: AppColors.accentOrange.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.star_rounded, color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text('MOST POPULAR', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── Pro Mode Card ─────────────────────────────────────────────────────────
  Widget _buildProModeCard(BuildContext context, String currency) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.backgroundLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.emoji_events_outlined, color: AppColors.textSecondary, size: 24),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pro Mode', style: AppTypography.h3.copyWith(color: AppColors.textPrimary)),
                  Text('For established enterprises', style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$currency 749', style: TextStyle(color: AppColors.textPrimary, fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('/mo', style: TextStyle(color: AppColors.textTertiary, fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildFeatureItem('Everything in Growth, plus:', isBold: true, iconOpacity: 0.7),
          const SizedBox(height: 12),
          _buildFeatureItem('Advanced financial modeling', iconOpacity: 0.7),
          const SizedBox(height: 12),
          _buildFeatureItem('Investor reporting dashboard', iconOpacity: 0.7),
          const SizedBox(height: 12),
          _buildFeatureItem('Multi-store management', iconOpacity: 0.7),
          const SizedBox(height: 12),
          _buildFeatureItem('Unlimited users & full API access', iconOpacity: 0.7),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Added to Pro Mode waitlist!')),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accentOrange,
              side: const BorderSide(color: AppColors.accentOrange, width: 2),
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
            ),
            child: const Text('Join Waitlist', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ─── Downgrade dialog ──────────────────────────────────────────────────────
  void _showDowngradeDialog(BuildContext context, WidgetRef ref, SubscriptionTier targetTier) {
    HapticFeedback.lightImpact();
    final currentTier = ref.read(tierProvider);
    final isShopifyDowngrade = currentTier.hasShopifyAccess && !targetTier.hasShopifyAccess;

    String title;
    String message;
    if (targetTier == SubscriptionTier.launch) {
      title = 'Switch to Launch Mode?';
      message = 'You will lose access to Growth features like Balance Sheet, Income Statement, AI Insights, and more. Your data will be preserved.';
      if (currentTier.hasShopifyAccess) {
        message += ' Your Shopify integration will also be disconnected.';
      }
    } else {
      title = 'Switch to ${targetTier.label}?';
      message = 'Your data will be preserved. Feature access will change based on the new plan.';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // If downgrading away from Shopify, disconnect integration
              if (isShopifyDowngrade) {
                final conn = ref.read(shopifyConnectionProvider).value;
                if (conn != null && conn.isActive) {
                  await ref.read(shopifyConnectionProvider.notifier).disconnect();
                }
              }
              ref.read(appSettingsProvider.notifier).setTier(targetTier);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Switched to ${targetTier.label} Mode')),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: isShopifyDowngrade ? AppColors.danger : AppColors.accentOrange,
            ),
            child: Text('Switch to ${targetTier.shortLabel}'),
          ),
        ],
      ),
    );
  }

  // ─── Shared helpers ────────────────────────────────────────────────────────
  Widget _buildFeatureItem(String text, {bool isWhite = false, bool isBold = false, double iconOpacity = 1.0, Color? color}) {
    final iconColor = isWhite
        ? const Color(0xFF86EFAC)
        : (color ?? AppColors.accentOrange).withValues(alpha: iconOpacity);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle_rounded, color: iconColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: isWhite ? Colors.white.withValues(alpha: 0.9) : AppColors.textSecondary,
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompareButton(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Full feature comparison coming soon')));
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Compare full feature matrix', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFAQ() {
    return Column(
      children: [
        _buildFAQItem(
          'Does Growth Mode include Shopify integration?',
          'Yes! Growth Mode includes full Shopify e-commerce integration: real-time order sync, inventory management, and product mapping between your Shopify store and Masari.',
        ),
        const SizedBox(height: 12),
        _buildFAQItem(
          'How does Shopify integration work?',
          'After upgrading to Growth Mode, you connect your Shopify store once through a secure OAuth process. After that, your Shopify orders automatically sync as Masari sales in real-time. You can also sync inventory on-demand between Shopify and Masari.',
        ),
        const SizedBox(height: 12),
        _buildFAQItem(
          'Can I downgrade later?',
          'Yes, you can switch between plans at any time. Your data will be preserved, but access to plan-specific features will change. If you downgrade from Growth, your Shopify connection will be paused but existing data is kept.',
        ),
        const SizedBox(height: 12),
        _buildFAQItem(
          'Do you offer custom enterprise plans?',
          'Absolutely. For organizations needing custom integrations or dedicated support, please contact our sales team directly.',
        ),
      ],
    );
  }

  Widget _buildFAQItem(String question, String answer) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: AppColors.textTertiary,
          collapsedIconColor: AppColors.textTertiary,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Text(question, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(answer, style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
          ],
        ),
      ),
    );
  }
}
