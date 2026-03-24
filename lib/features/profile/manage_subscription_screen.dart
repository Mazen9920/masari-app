import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_settings_provider.dart';
import '../shopify/providers/shopify_connection_provider.dart';
import '../../shared/utils/safe_pop.dart';
import '../../l10n/app_localizations.dart';

class ManageSubscriptionScreen extends ConsumerWidget {
  const ManageSubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
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
        title: Text(l10n.subscriptionTitle, style: AppTypography.h3.copyWith(color: AppColors.primaryNavy)),
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
                    currentTier == SubscriptionTier.launch ? l10n.subscriptionFree : currentTier.localizedLabel(l10n),
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
            _buildCurrentPlanCard(currentTier, currency, l10n),
            const SizedBox(height: 32),

            // Available Upgrades Title
            if (currentTier != SubscriptionTier.pro) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    currentTier == SubscriptionTier.launch
                        ? l10n.subscriptionAvailableUpgrades
                        : l10n.subscriptionManagePlan,
                    style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
                  ),
                  if (currentTier == SubscriptionTier.launch)
                    Text(l10n.subscriptionSaveYearly, style: TextStyle(color: AppColors.accentOrange, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Growth Mode Card (includes Shopify)
            _buildGrowthModeCard(context, currency, ref, currentTier, l10n),
            const SizedBox(height: 20),

            // Pro Mode Card
            _buildProModeCard(context, currency, l10n),
            const SizedBox(height: 32),

            // Bottom Accordions
            _buildCompareButton(context, l10n),
            const SizedBox(height: 24),
            Text(l10n.subscriptionFaqTitle, style: AppTypography.h3.copyWith(color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            _buildFAQ(l10n),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ─── Current plan hero card ──────────────────────────────────────────────────
  Widget _buildCurrentPlanCard(SubscriptionTier currentTier, String currency, AppLocalizations l10n) {
    final isGrowthVariant = currentTier.isGrowthOrAbove;

    final String planName;
    final String planDesc;
    final String planPrice;
    final String planSuffix;
    final IconData planIcon;
    final Color bgColor;

    switch (currentTier) {
      case SubscriptionTier.launch:
        planName = l10n.subscriptionLaunchMode;
        planDesc = l10n.subscriptionLaunchDesc;
        planPrice = l10n.subscriptionFree;
        planSuffix = l10n.subscriptionForever;
        planIcon = Icons.rocket_launch_outlined;
        bgColor = AppColors.primaryNavy;
      case SubscriptionTier.growth:
        planName = l10n.subscriptionGrowthMode;
        planDesc = l10n.subscriptionGrowthDesc;
        planPrice = l10n.subscriptionGrowthPrice(currency);
        planSuffix = l10n.subscriptionPerMonth;
        planIcon = Icons.show_chart_rounded;
        bgColor = AppColors.accentOrange;
      case SubscriptionTier.pro:
        planName = l10n.subscriptionProMode;
        planDesc = l10n.subscriptionProDesc;
        planPrice = l10n.subscriptionProPrice(currency);
        planSuffix = l10n.subscriptionPerMonth;
        planIcon = Icons.emoji_events_outlined;
        bgColor = AppColors.primaryNavy;
    }

    final List<String> features;
    if (isGrowthVariant) {
      features = [
        l10n.subscriptionFeatureEverythingLaunch,
        l10n.subscriptionFeatureSalesCogs,
        l10n.subscriptionFeatureGoodsReceiving,
        l10n.subscriptionFeatureIncomeStatement,
        l10n.subscriptionFeatureBalanceSheet,
        l10n.subscriptionFeatureRecurring,
        l10n.subscriptionFeatureUnlimitedProducts,
        l10n.subscriptionFeatureSupplierManagement,
        l10n.subscriptionFeatureFullCashFlowAnalysis,
        l10n.subscriptionFeatureAiInsights,
        l10n.subscriptionFeatureShopify,
        l10n.subscriptionFeature5Team,
      ];
    } else if (currentTier == SubscriptionTier.pro) {
      features = [
        l10n.subscriptionFeatureEverythingGrowth,
        l10n.subscriptionFeatureFinancialModeling,
        l10n.subscriptionFeatureInvestorDash,
        l10n.subscriptionFeatureMultiStore,
        l10n.subscriptionFeatureUnlimitedApi,
      ];
    } else {
      features = [
        l10n.subscriptionFeatureIncomeExpense,
        l10n.subscriptionFeatureSimpleCashOverview,
        l10n.subscriptionFeatureUpTo20Products,
        l10n.subscriptionFeatureCustomCategories,
        l10n.subscriptionFeature1Admin,
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
                    child: Text(l10n.subscriptionActive, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
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
  Widget _buildGrowthModeCard(BuildContext context, String currency, WidgetRef ref, SubscriptionTier currentTier, AppLocalizations l10n) {
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
                      Text(l10n.subscriptionGrowthMode, style: AppTypography.h3.copyWith(color: AppColors.textPrimary)),
                      Text(l10n.subscriptionGrowthDesc, style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(l10n.subscriptionGrowthPrice(currency), style: TextStyle(color: AppColors.textPrimary, fontSize: 32, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(l10n.subscriptionPerMonth, style: TextStyle(color: AppColors.textTertiary, fontSize: 15)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildFeatureItem(l10n.subscriptionEverythingLaunchPlus, isBold: true),
              const SizedBox(height: 12),
              _buildFeatureItem(l10n.subscriptionFeatureSalesCogs),
              const SizedBox(height: 12),
              _buildFeatureItem(l10n.subscriptionFeatureGoodsReceiving),
              const SizedBox(height: 12),
              _buildFeatureItem(l10n.subscriptionFeatureIncomeStatement),
              const SizedBox(height: 12),
              _buildFeatureItem(l10n.subscriptionFeatureBalanceSheet),
              const SizedBox(height: 12),
              _buildFeatureItem(l10n.subscriptionFeatureBudgetLimits),
              const SizedBox(height: 12),
              _buildFeatureItem(l10n.subscriptionFeatureRecurring),
              const SizedBox(height: 12),
              _buildFeatureItem(l10n.subscriptionFeaturePurchaseDash),
              const SizedBox(height: 12),
              _buildFeatureItem(l10n.subscriptionFeatureRawMaterials),
              const SizedBox(height: 12),
              _buildFeatureItem(l10n.subscriptionFeatureReportExport),
              const SizedBox(height: 12),
              _buildFeatureItem(l10n.subscriptionFeatureUnlimitedProducts),
              const SizedBox(height: 12),
              _buildFeatureItem(l10n.subscriptionFeatureSupplierManagement),
              const SizedBox(height: 12),
              _buildFeatureItem(l10n.subscriptionFeatureFullCashFlowAnalysis),
              const SizedBox(height: 12),
              _buildFeatureItem(l10n.subscriptionFeatureAiInsights),
              const SizedBox(height: 12),
              _buildFeatureItem(l10n.subscriptionFeatureShopify),
              const SizedBox(height: 12),
              _buildFeatureItem(l10n.subscriptionFeature5Team),
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
                      Text(l10n.subscriptionCurrentPlan, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.success)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => _showDowngradeDialog(context, ref, SubscriptionTier.launch, l10n),
                  child: Text(l10n.subscriptionSwitchToLaunch, style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
                ),
              ] else if (isAboveGrowth) ...[
                OutlinedButton(
                  onPressed: () => _showDowngradeDialog(context, ref, SubscriptionTier.growth, l10n),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.borderLight, width: 1.5),
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                  ),
                  child: Text(l10n.subscriptionSwitchToGrowth, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ] else ...[
                FilledButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    ref.read(appSettingsProvider.notifier).setTier(SubscriptionTier.growth);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.subscriptionSwitchedToGrowth)),
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
                    children: [
                      Text(l10n.subscriptionUpgradeToGrowth, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
                  children: [
                    const Icon(Icons.star_rounded, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(l10n.subscriptionMostPopular, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── Pro Mode Card ─────────────────────────────────────────────────────────
  Widget _buildProModeCard(BuildContext context, String currency, AppLocalizations l10n) {
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
                  Text(l10n.subscriptionProMode, style: AppTypography.h3.copyWith(color: AppColors.textPrimary)),
                  Text(l10n.subscriptionProDesc, style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(l10n.subscriptionProPrice(currency), style: TextStyle(color: AppColors.textPrimary, fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(l10n.subscriptionPerMonth, style: TextStyle(color: AppColors.textTertiary, fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildFeatureItem(l10n.subscriptionEverythingGrowthPlus, isBold: true, iconOpacity: 0.7),
          const SizedBox(height: 12),
          _buildFeatureItem(l10n.subscriptionFeatureFinancialModeling, iconOpacity: 0.7),
          const SizedBox(height: 12),
          _buildFeatureItem(l10n.subscriptionFeatureInvestorDash, iconOpacity: 0.7),
          const SizedBox(height: 12),
          _buildFeatureItem(l10n.subscriptionFeatureMultiStore, iconOpacity: 0.7),
          const SizedBox(height: 12),
          _buildFeatureItem(l10n.subscriptionFeatureUnlimitedApi, iconOpacity: 0.7),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.subscriptionAddedToWaitlist)),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accentOrange,
              side: const BorderSide(color: AppColors.accentOrange, width: 2),
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
            ),
            child: Text(l10n.subscriptionJoinWaitlist, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ─── Downgrade dialog ──────────────────────────────────────────────────────
  void _showDowngradeDialog(BuildContext context, WidgetRef ref, SubscriptionTier targetTier, AppLocalizations l10n) {
    HapticFeedback.lightImpact();
    final currentTier = ref.read(tierProvider);
    final isShopifyDowngrade = currentTier.hasShopifyAccess && !targetTier.hasShopifyAccess;

    String title;
    String message;
    if (targetTier == SubscriptionTier.launch) {
      title = l10n.subscriptionSwitchLaunchTitle;
      message = l10n.subscriptionSwitchLaunchMessage;
      if (currentTier.hasShopifyAccess) {
        message += l10n.subscriptionShopifyDisconnectWarning;
      }
    } else {
      title = l10n.subscriptionSwitchToTierTitle(targetTier.localizedLabel(l10n));
      message = l10n.subscriptionSwitchGenericMessage;
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
            child: Text(l10n.cancel),
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
                  SnackBar(content: Text(l10n.subscriptionSwitchedToTier(targetTier.localizedLabel(l10n)))),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: isShopifyDowngrade ? AppColors.danger : AppColors.accentOrange,
            ),
            child: Text(l10n.subscriptionSwitchToTierButton(targetTier.localizedLabel(l10n))),
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

  Widget _buildCompareButton(BuildContext context, AppLocalizations l10n) {
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
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.subscriptionComparisonComingSoon)));
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.subscriptionCompareFeatures, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFAQ(AppLocalizations l10n) {
    return Column(
      children: [
        _buildFAQItem(
          l10n.subscriptionFaqShopifyQ,
          l10n.subscriptionFaqShopifyA,
        ),
        const SizedBox(height: 12),
        _buildFAQItem(
          l10n.subscriptionFaqShopifyHowQ,
          l10n.subscriptionFaqShopifyHowA,
        ),
        const SizedBox(height: 12),
        _buildFAQItem(
          l10n.subscriptionFaqDowngradeQ,
          l10n.subscriptionFaqDowngradeA,
        ),
        const SizedBox(height: 12),
        _buildFAQItem(
          l10n.subscriptionFaqEnterpriseQ,
          l10n.subscriptionFaqEnterpriseA,
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
