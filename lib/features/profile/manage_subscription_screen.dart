import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/services/iap_service.dart';
import '../../core/services/remote_config_service.dart';
import '../shopify/providers/shopify_connection_provider.dart';
import '../../shared/utils/safe_pop.dart';
import '../../l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'paymob_checkout_sheet.dart';

/// Billing portal base URL. Users authenticate via Firebase Auth on the web.
const _kBillingPortalUrl = 'https://revvo-app.com/billing';
const _kAppleSubscriptionUrl = 'https://apps.apple.com/account/subscriptions';
const _kGoogleSubscriptionUrl =
    'https://play.google.com/store/account/subscriptions';
const _kTermsUrl = 'https://revvo-app.com/terms';
const _kPrivacyUrl = 'https://revvo-app.com/privacy';

class ManageSubscriptionScreen extends ConsumerStatefulWidget {
  const ManageSubscriptionScreen({super.key});

  @override
  ConsumerState<ManageSubscriptionScreen> createState() =>
      _ManageSubscriptionScreenState();
}

class _ManageSubscriptionScreenState
    extends ConsumerState<ManageSubscriptionScreen> {
  @override
  void initState() {
    super.initState();
    if (isIapAvailable) {
      ref.read(iapProvider.notifier).init();
    }
    // Always refresh subscription data when entering this screen so
    // saved card info, auto-renew state, etc. are up-to-date.
    Future.microtask(() => ref.read(appSettingsProvider.notifier).refreshSubscription());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currency = ref.watch(currencyProvider);
    final currentTier = ref.watch(tierProvider);
    final settings = ref.watch(appSettingsProvider);
    final subStatus = settings.subscriptionStatus;
    final iapState = ref.watch(iapProvider);
    final iapLoading = iapState.loading;
    final iapError = iapState.error;
    final iapProducts = iapState.products;
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
          // Refresh button
          IconButton(
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.subscriptionRefreshing), duration: const Duration(seconds: 1)),
              );
              await ref.read(appSettingsProvider.notifier).refreshSubscription();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.subscriptionRefreshed)),
                );
              }
            },
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primaryNavy),
          ),
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor(subStatus).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _statusColor(subStatus).withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _statusColor(subStatus),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _statusLabel(subStatus, l10n),
                    style: TextStyle(
                      color: _statusColor(subStatus),
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
      body: RefreshIndicator(
        onRefresh: () => ref.read(appSettingsProvider.notifier).refreshSubscription().then((_) {}),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // IAP loading indicator
              if (iapLoading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: LinearProgressIndicator(color: AppColors.accentOrange),
                ),
              // IAP error banner
              if (iapError != null) ...[
                _buildBanner(
                  icon: Icons.error_outline_rounded,
                  color: AppColors.danger,
                  text: iapError,
                  buttonText: l10n.dismiss,
                  onPressed: () =>
                      ref.read(iapProvider.notifier).clearError(),
                ),
                const SizedBox(height: 16),
              ],
              // Grace period / expired banner
              if (subStatus == 'grace_period') ...[
                _buildBanner(
                  icon: Icons.warning_amber_rounded,
                  color: AppColors.accentOrange,
                  text: l10n.subscriptionGraceMessage(3),
                  buttonText: l10n.subscriptionRenew,
                  onPressed: () => _handleRenew(iapProducts),
                ),
                const SizedBox(height: 16),
              ] else if (subStatus == 'expired' && currentTier == SubscriptionTier.launch) ...[
                _buildBanner(
                  icon: Icons.error_outline_rounded,
                  color: AppColors.danger,
                  text: l10n.subscriptionExpiredMessage,
                  buttonText: l10n.subscriptionRenew,
                  onPressed: () => _handleRenew(iapProducts),
                ),
                const SizedBox(height: 16),
              ],

              // Expiry info for active subscribers
              if (settings.subscriptionExpiresAt != null && currentTier.isGrowthOrAbove) ...[
                _buildExpiryRow(settings.subscriptionExpiresAt!, l10n),
                const SizedBox(height: 16),
              ],

              // Payment method & auto-renew section (Paymob users)
              if (currentTier.isGrowthOrAbove && settings.paymentSource == 'paymob') ...[
                _buildPaymentMethodCard(settings, l10n),
                const SizedBox(height: 16),
              ],

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
                _buildSubscribeButton(l10n),
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
    final subStatus = ref.read(appSettingsProvider).subscriptionStatus;

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
              // Handle Shopify disconnect if downgrading from a tier with access
              if (isShopifyDowngrade) {
                final conn = ref.read(shopifyConnectionProvider).value;
                if (conn != null && conn.isActive) {
                  await ref.read(shopifyConnectionProvider.notifier).disconnect();
                }
              }
              // For IAP auto-renewable subscriptions, direct to platform
              // subscription settings. For Paymob one-time payments, expired,
              // and free users, cancel via Cloud Function immediately.
              final isIapActive = (subStatus == 'active' || subStatus == 'grace_period')
                  && !_showPaymob && !kIsWeb;
              if (isIapActive) {
                _openBillingPortal();
              } else {
                await ref.read(appSettingsProvider.notifier).setTier(targetTier);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.subscriptionSwitchedToTier(targetTier.localizedLabel(l10n)))),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: isShopifyDowngrade ? AppColors.danger : AppColors.accentOrange,
            ),
            child: Text(((subStatus == 'active' || subStatus == 'grace_period') && !_showPaymob && !kIsWeb)
                ? _platformManageLabel(l10n)
                : l10n.subscriptionSwitchToTierButton(targetTier.localizedLabel(l10n))),
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

  // ─── Whether to show the Paymob "Pay with Card" option ─────────────────
  bool get _showPaymob {
    if (kIsWeb) return false;
    if (Platform.isAndroid) return true;
    // iOS: controlled by Remote Config kill-switch.
    // Set show_paymob_ios to false in Firebase Console to hide instantly
    // (e.g. if Apple rejects during review).
    return RemoteConfigService.showPaymobIos;
  }

  // ─── Renew handler (IAP on mobile, web portal fallback) ────────────────
  void _handleRenew(List<ProductDetails> iapProducts) {
    if (isIapAvailable && iapProducts.isNotEmpty) {
      // Default to monthly plan for renewal
      final monthly =
          iapProducts.where((p) => p.id == kGrowthMonthlyId).firstOrNull;
      if (monthly != null) {
        ref.read(iapProvider.notifier).buy(monthly);
        return;
      }
    }
    // Fallback: Paymob in-app on mobile, web portal on web
    if (_showPaymob) {
      _openPaymobSheet('growth_monthly');
    } else {
      _openBillingPortal();
    }
  }

  // ─── Paymob in-app checkout ──────────────────────────────────────────────
  Future<void> _openPaymobSheet(String plan) async {
    final prevTier = ref.read(appSettingsProvider).tier;
    final prevCard = ref.read(appSettingsProvider).paymobCardLast4;
    final result = await PaymobCheckoutSheet.show(context, plan: plan);
    if (result == true && mounted) {
      // The redirect fires before the webhook finishes — poll until the
      // backend reflects either a tier upgrade or new card data (max ~10s).
      for (var i = 0; i < 5 && mounted; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        await ref.read(appSettingsProvider.notifier).refreshSubscription();
        final s = ref.read(appSettingsProvider);
        final tierChanged = s.tier != prevTier;
        final cardChanged = s.paymobCardLast4 != prevCard &&
            (s.paymobCardLast4?.isNotEmpty ?? false);
        if (tierChanged || cardChanged) break;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.subscriptionRefreshed),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  // ─── Subscribe button (IAP on mobile, web portal on web) ──────────────
  Widget _buildSubscribeButton(AppLocalizations l10n) {
    final iapState = ref.watch(iapProvider);
    final iapProducts = iapState.products;
    final iapLoading = iapState.loading;
    // On mobile with IAP products loaded → show native subscribe button
    if (isIapAvailable && iapProducts.isNotEmpty) {
      return Column(
        children: [
          // Monthly button
          _buildIapButton(
            l10n,
            iapProducts,
            kGrowthMonthlyId,
            l10n.subscriptionSubscribeMonthly,
            iapLoading,
          ),
          const SizedBox(height: 12),
          // Yearly button with savings badge
          _buildIapButton(
            l10n,
            iapProducts,
            kGrowthYearlyId,
            l10n.subscriptionSubscribeYearly,
            iapLoading,
          ),
          const SizedBox(height: 16),
          // Restore purchases
          TextButton(
            onPressed: iapLoading
                ? null
                : () => ref.read(iapProvider.notifier).restorePurchases(),
            child: Text(
              l10n.subscriptionRestorePurchases,
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 13,
              ),
            ),
          ),
          // ── Auto-renewal disclosure (required by App Store / Google Play) ──
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              l10n.subscriptionAutoRenewDisclosure(
                Platform.isIOS ? 'Apple ID' : 'Google Play',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
              children: [
                TextSpan(
                  text: l10n.termsOfService,
                  style: const TextStyle(
                    color: AppColors.accentOrange,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => launchUrl(
                          Uri.parse(_kTermsUrl),
                          mode: LaunchMode.externalApplication,
                        ),
                ),
                const TextSpan(text: ' · '),
                TextSpan(
                  text: l10n.privacyPolicy,
                  style: const TextStyle(
                    color: AppColors.accentOrange,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => launchUrl(
                          Uri.parse(_kPrivacyUrl),
                          mode: LaunchMode.externalApplication,
                        ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          // Pay with local card (Paymob) — only shown when enabled
          if (_showPaymob) ...[            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            _buildPayWithCardButtons(l10n),
          ],
        ],
      );
    }

    // Fallback: mobile without IAP products → Paymob, web → billing portal
    if (_showPaymob) {
      return _buildPayWithCardButtons(l10n);
    }
    return FilledButton(
      onPressed: () {
        HapticFeedback.lightImpact();
        _openBillingPortal();
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
          Text(l10n.subscriptionSubscribeOnWeb,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          const Icon(Icons.open_in_new_rounded, size: 18),
        ],
      ),
    );
  }

  /// "Pay with Local Card" Paymob buttons (monthly + yearly).
  Widget _buildPayWithCardButtons(AppLocalizations l10n) {
    return Column(
      children: [
        Text(
          l10n.payWithCard,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            _openPaymobSheet('growth_monthly');
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.accentOrange,
            side: const BorderSide(color: AppColors.accentOrange, width: 1.5),
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.credit_card_rounded, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${l10n.subscriptionSubscribeMonthly} — ${RemoteConfigService.paymobMonthlyPrice}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            _openPaymobSheet('growth_yearly');
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryNavy,
            side: const BorderSide(color: AppColors.primaryNavy, width: 1.5),
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.credit_card_rounded, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${l10n.subscriptionSubscribeYearly} — ${RemoteConfigService.paymobYearlyPrice}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIapButton(
    AppLocalizations l10n,
    List<ProductDetails> products,
    String productId,
    String label,
    bool loading,
  ) {
    final product = products.where((p) => p.id == productId).firstOrNull;
    if (product == null) return const SizedBox.shrink();

    final isYearly = productId == kGrowthYearlyId;
    return Semantics(
      button: true,
      label: '$label ${product.price}',
      child: FilledButton(
        onPressed: loading
            ? null
            : () {
                HapticFeedback.lightImpact();
                ref.read(iapProvider.notifier).buy(product);
              },
        style: FilledButton.styleFrom(
          backgroundColor:
              isYearly ? AppColors.primaryNavy : AppColors.accentOrange,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
          elevation: 4,
          shadowColor: (isYearly ? AppColors.primaryNavy : AppColors.accentOrange)
              .withValues(alpha: 0.4),
        ),
        child: Text(
          '$label — ${product.price}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // ─── Platform-aware manage-subscription label ───────────────────────────
  static String _platformManageLabel(AppLocalizations l10n) {
    if (kIsWeb) return l10n.subscriptionManageOnWeb;
    if (Platform.isIOS) return l10n.manageAppleSubscription;
    return l10n.manageGoogleSubscription;
  }

  // ─── Billing portal launcher ─────────────────────────────────────────────
  static void _openBillingPortal() {
    final String url;
    if (kIsWeb) {
      url = _kBillingPortalUrl;
    } else if (Platform.isIOS) {
      url = _kAppleSubscriptionUrl;
    } else {
      url = _kGoogleSubscriptionUrl;
    }
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  // ─── Status helpers ──────────────────────────────────────────────────────
  static Color _statusColor(String status) => switch (status) {
    'active'       => AppColors.success,
    'grace_period' => AppColors.accentOrange,
    'expired'      => AppColors.danger,
    _              => AppColors.success, // 'free' — Launch is always active
  };

  static String _statusLabel(String status, AppLocalizations l10n) => switch (status) {
    'active'       => l10n.subscriptionActive,
    'grace_period' => l10n.subscriptionGracePeriod,
    'expired'      => l10n.subscriptionExpired,
    _              => l10n.subscriptionFree,
  };

  // ─── Grace / expired banner ──────────────────────────────────────────────
  Widget _buildBanner({
    required IconData icon,
    required Color color,
    required String text,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text, style: TextStyle(color: color, fontSize: 13, height: 1.4)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(buttonText),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Expiry date row ─────────────────────────────────────────────────────
  Widget _buildExpiryRow(DateTime expiresAt, AppLocalizations l10n) {
    final formatted = '${expiresAt.day}/${expiresAt.month}/${expiresAt.year}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.textTertiary),
          const SizedBox(width: 8),
          Text(
            l10n.subscriptionExpiresOn(formatted),
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {
              if (_showPaymob) {
                context.pushNamed('BillingManagementScreen');
              } else {
                _openBillingPortal();
              }
            },
            child: Text(
              _showPaymob ? l10n.paymobManageBilling : _platformManageLabel(l10n),
              style: const TextStyle(fontSize: 13, color: AppColors.accentOrange, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Payment method card with auto-renew toggle ─────────────────────────
  Widget _buildPaymentMethodCard(AppSettingsState settings, AppLocalizations l10n) {
    final hasCard = settings.paymobCardLast4 != null && settings.paymobCardLast4!.isNotEmpty;
    final cardBrand = settings.paymobCardBrand ?? '';
    final cardLast4 = settings.paymobCardLast4 ?? '';
    final autoRenew = settings.paymobAutoRenew;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                hasCard ? Icons.credit_card_rounded : Icons.credit_card_off_rounded,
                size: 20,
                color: hasCard ? AppColors.primaryNavy : AppColors.textTertiary,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.paymentMethodSavedCard,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (hasCard) ...[
            // Card info row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.credit_card_rounded, size: 24, color: AppColors.primaryNavy),
                  const SizedBox(width: 10),
                  Text(
                    l10n.paymentMethodCardEnding(cardBrand.toUpperCase(), cardLast4),
                    style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Auto-renew toggle
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.autoRenewLabel,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        autoRenew ? l10n.autoRenewEnabled : l10n.autoRenewDisabled,
                        style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: autoRenew,
                  activeTrackColor: AppColors.accentOrange,
                  onChanged: (value) => _handleToggleAutoRenew(value, l10n),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Remove card button
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: () => _handleRemoveCard(l10n),
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: Text(l10n.removeCard),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  textStyle: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ] else
            Text(
              l10n.noSavedPaymentMethod,
              style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
            ),
        ],
      ),
    );
  }

  void _handleToggleAutoRenew(bool enabled, AppLocalizations l10n) async {
    try {
      await ref.read(appSettingsProvider.notifier).toggleAutoRenew(enabled);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.autoRenewToggleError),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  void _handleRemoveCard(AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.removeCardConfirmTitle),
        content: Text(l10n.removeCardConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(l10n.removeCard),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(appSettingsProvider.notifier).removePaymentMethod();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.removeCardSuccess),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.removeCardError),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }
}
