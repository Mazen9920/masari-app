import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers/app_settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/models/payment_history_entry.dart';
import '../../shared/utils/safe_pop.dart';
import 'paymob_checkout_sheet.dart';

class BillingManagementScreen extends ConsumerStatefulWidget {
  const BillingManagementScreen({super.key});

  @override
  ConsumerState<BillingManagementScreen> createState() =>
      _BillingManagementScreenState();
}

class _BillingManagementScreenState
    extends ConsumerState<BillingManagementScreen> {
  List<PaymentHistoryEntry>? _payments;
  bool _loadingHistory = true;
  bool _removingCard = false;
  bool _updatingCard = false;

  @override
  void initState() {
    super.initState();
    _loadPaymentHistory();
  }

  Future<void> _loadPaymentHistory() async {
    final result =
        await ref.read(appSettingsProvider.notifier).getPaymentHistory();
    if (mounted) {
      setState(() {
        _payments = result;
        _loadingHistory = false;
      });
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        title: Text(l10n.billingTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.safePop(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.read(appSettingsProvider.notifier).refreshSubscription(),
            _loadPaymentHistory(),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            _buildSubscriptionSummary(settings, l10n),
            const SizedBox(height: 20),
            _buildPaymentMethodSection(settings, l10n),
            const SizedBox(height: 20),
            _buildPlanManagementSection(settings, l10n),
            const SizedBox(height: 20),
            _buildPaymentHistorySection(l10n),
            const SizedBox(height: 20),
            _buildCancelSection(settings, l10n),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. Subscription Summary
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildSubscriptionSummary(
      AppSettingsState settings, AppLocalizations l10n) {
    final tier = settings.tier;
    final status = settings.subscriptionStatus;
    final expiresAt = settings.subscriptionExpiresAt;

    final tierLabel = tier.localizedLabel(l10n);
    final statusColor = _statusColor(status);
    final statusText = _statusLabel(status, l10n);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryNavy,
            AppColors.primaryNavy.withValues(alpha: 0.85),
            AppColors.secondaryBlue,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryNavy.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded,
                  color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tierLabel,
                  style: AppTypography.h2.copyWith(color: Colors.white),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (expiresAt != null) ...[
            const SizedBox(height: 12),
            Text(
              l10n.subscriptionExpiresOn(
                  DateFormat.yMMMd().format(expiresAt)),
              style: const TextStyle(
                  color: Colors.white70, fontSize: 13),
            ),
          ],
          if (settings.paymentSource != null) ...[
            const SizedBox(height: 6),
            Text(
              settings.paymentSource == 'paymob'
                  ? l10n.paymentSourcePaymob
                  : l10n.paymentSourceIap,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. Payment Method
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildPaymentMethodSection(
      AppSettingsState settings, AppLocalizations l10n) {
    final hasCard = settings.paymobCardLast4 != null &&
        settings.paymobCardLast4!.isNotEmpty;
    final cardBrand = settings.paymobCardBrand ?? '';
    final cardLast4 = settings.paymobCardLast4 ?? '';
    final autoRenew = settings.paymobAutoRenew;
    final isPaymob = settings.paymentSource == 'paymob';

    return _buildSection(
      title: l10n.billingPaymentMethod,
      children: [
        if (hasCard) ...[
          _buildCardRow(cardBrand, cardLast4, l10n),
          const Divider(height: 1, color: AppColors.borderLight),
          _buildAutoRenewRow(autoRenew, l10n),
          const Divider(height: 1, color: AppColors.borderLight),
          _buildActionRow(
            icon: Icons.refresh_rounded,
            label: l10n.billingUpdateCard,
            color: AppColors.secondaryBlue,
            loading: _updatingCard,
            onTap: _handleUpdateCard,
          ),
          const Divider(height: 1, color: AppColors.borderLight),
          _buildActionRow(
            icon: Icons.delete_outline_rounded,
            label: l10n.removeCard,
            color: AppColors.danger,
            loading: _removingCard,
            onTap: () => _handleRemoveCard(l10n),
          ),
        ] else if (isPaymob) ...[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Icon(Icons.credit_card_off_rounded,
                    size: 40, color: AppColors.textTertiary),
                const SizedBox(height: 8),
                Text(l10n.noSavedPaymentMethod,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 14)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _handleUpdateCard,
                  icon: const Icon(Icons.add_card_rounded, size: 18),
                  label: Text(l10n.billingAddCard),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentOrange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.paymentSourceIap,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCardRow(
      String brand, String last4, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.secondaryBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.credit_card_rounded,
                size: 20, color: AppColors.secondaryBlue),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.paymentMethodSavedCard,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  l10n.paymentMethodCardEnding(brand, last4),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoRenewRow(bool autoRenew, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.autoRenewLabel,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  autoRenew
                      ? l10n.autoRenewEnabled
                      : l10n.autoRenewDisabled,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: autoRenew,
            activeTrackColor: AppColors.success,
            onChanged: (val) async {
              try {
                await ref
                    .read(appSettingsProvider.notifier)
                    .toggleAutoRenew(val);
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.autoRenewToggleError)),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. Plan Management
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildPlanManagementSection(
      AppSettingsState settings, AppLocalizations l10n) {
    final tier = settings.tier;
    final currentPlan = settings.subscriptionPlan ?? '';
    final isMonthly = currentPlan.contains('monthly');
    final isYearly = currentPlan.contains('yearly');

    return _buildSection(
      title: l10n.billingPlanManagement,
      children: [
        if (tier == SubscriptionTier.launch) ...[
          _buildActionRow(
            icon: Icons.rocket_launch_rounded,
            label: l10n.subscriptionUpgradeToGrowth,
            color: AppColors.accentOrange,
            onTap: () => _openPaymobSheet('growth_monthly'),
          ),
        ] else ...[
          if (!isMonthly)
            _buildActionRow(
              icon: Icons.calendar_month_rounded,
              label: l10n.billingChangeToMonthly,
              color: AppColors.secondaryBlue,
              onTap: () => _openPaymobSheet('growth_monthly'),
            ),
          if (!isMonthly && !isYearly)
            const Divider(height: 1, color: AppColors.borderLight),
          if (!isYearly)
            _buildActionRow(
              icon: Icons.calendar_today_rounded,
              label: l10n.billingChangeToYearly,
              subtitle: l10n.subscriptionSaveYearly,
              color: AppColors.success,
              onTap: () => _openPaymobSheet('growth_yearly'),
            ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. Payment History
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildPaymentHistorySection(AppLocalizations l10n) {
    return _buildSection(
      title: l10n.billingPaymentHistory,
      children: [
        if (_loadingHistory)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_payments == null || _payments!.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                l10n.billingNoPayments,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 14),
              ),
            ),
          )
        else
          ...List.generate(_payments!.length, (i) {
            final entry = _payments![i];
            return Column(
              children: [
                if (i > 0)
                  const Divider(
                      height: 1, color: AppColors.borderLight),
                _buildPaymentRow(entry, l10n),
              ],
            );
          }),
      ],
    );
  }

  Widget _buildPaymentRow(PaymentHistoryEntry entry, AppLocalizations l10n) {
    final dateStr = entry.createdAt != null
        ? DateFormat.yMMMd().add_jm().format(entry.createdAt!)
        : '—';
    final planLabel = _planLabel(entry.plan);
    final amountStr =
        '${(entry.amountCents / 100).toStringAsFixed(2)} ${entry.currency}';

    return InkWell(
      onTap: () => _showReceiptSheet(entry, l10n),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: entry.success
                    ? AppColors.success.withValues(alpha: 0.1)
                    : AppColors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                entry.success
                    ? Icons.check_circle_outline_rounded
                    : Icons.error_outline_rounded,
                size: 20,
                color: entry.success ? AppColors.success : AppColors.danger,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(planLabel,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      if (entry.isRenewal) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.secondaryBlue
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            l10n.billingRenewal,
                            style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.secondaryBlue,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(dateStr,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Text(
              amountStr,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: entry.success
                    ? AppColors.textPrimary
                    : AppColors.danger,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. Cancel Subscription
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildCancelSection(
      AppSettingsState settings, AppLocalizations l10n) {
    // Only show cancel for paid tiers
    if (settings.tier == SubscriptionTier.launch) {
      return const SizedBox.shrink();
    }

    return _buildSection(
      title: l10n.billingDangerZone,
      borderColor: AppColors.danger.withValues(alpha: 0.3),
      children: [
        _buildActionRow(
          icon: Icons.cancel_outlined,
          label: l10n.billingCancelSubscription,
          color: AppColors.danger,
          onTap: () => _handleCancel(l10n),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Shared Builders
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildSection({
    required String title,
    required List<Widget> children,
    Color? borderColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: AppTypography.captionSmall
                .copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: borderColor ?? AppColors.borderLight),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }

  Widget _buildActionRow({
    required IconData icon,
    required String label,
    required Color color,
    String? subtitle,
    bool loading = false,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: loading ? null : onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: loading
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: color),
                      )
                    : Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: color)),
                    if (subtitle != null)
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: color.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Actions
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _openPaymobSheet(String plan) async {
    final result = await PaymobCheckoutSheet.show(context, plan: plan);
    if (result == true && mounted) {
      // Poll for backend update
      for (var i = 0; i < 5 && mounted; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        await ref.read(appSettingsProvider.notifier).refreshSubscription();
      }
      await _loadPaymentHistory();
    }
  }

  Future<void> _handleUpdateCard() async {
    setState(() => _updatingCard = true);
    try {
      // Remove existing card first, then open checkout for re-tokenization
      await ref.read(appSettingsProvider.notifier).removePaymentMethod();
      if (!mounted) return;
      final result =
          await PaymobCheckoutSheet.show(context, plan: 'growth_monthly');
      if (result == true && mounted) {
        for (var i = 0; i < 5 && mounted; i++) {
          await Future<void>.delayed(const Duration(seconds: 2));
          await ref.read(appSettingsProvider.notifier).refreshSubscription();
          final s = ref.read(appSettingsProvider);
          if (s.paymobCardLast4 != null &&
              s.paymobCardLast4!.isNotEmpty) {
            break;
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() => _updatingCard = false);
      }
    }
  }

  Future<void> _handleRemoveCard(AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.removeCardConfirmTitle),
        content: Text(l10n.removeCardConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger),
            child: Text(l10n.removeCard),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _removingCard = true);
    try {
      final removed =
          await ref.read(appSettingsProvider.notifier).removePaymentMethod();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(removed
                ? l10n.removeCardSuccess
                : l10n.removeCardError),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.removeCardError)),
        );
      }
    } finally {
      if (mounted) setState(() => _removingCard = false);
    }
  }

  Future<void> _handleCancel(AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.billingCancelConfirmTitle),
        content: Text(l10n.billingCancelConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger),
            child: Text(l10n.billingCancelSubscription),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref
        .read(appSettingsProvider.notifier)
        .setTier(SubscriptionTier.launch);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.billingCancelledSuccess)),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Receipt Sheet
  // ═══════════════════════════════════════════════════════════════════════════
  void _showReceiptSheet(PaymentHistoryEntry entry, AppLocalizations l10n) {
    final dateStr = entry.createdAt != null
        ? DateFormat.yMMMd().add_jm().format(entry.createdAt!)
        : '—';
    final amountStr =
        '${(entry.amountCents / 100).toStringAsFixed(2)} ${entry.currency}';
    final planLabel = _planLabel(entry.plan);

    final lines = <String>[
      l10n.billingReceipt,
      '─' * 30,
      '${l10n.billingReceiptPlan}: $planLabel',
      '${l10n.billingReceiptAmount}: $amountStr',
      '${l10n.billingReceiptDate}: $dateStr',
      '${l10n.billingReceiptStatus}: ${entry.success ? l10n.billingReceiptSuccess : l10n.billingReceiptFailed}',
      if (entry.isRenewal)
        '${l10n.billingReceiptType}: ${l10n.billingRenewal}',
      if (entry.paymobTransactionId != null)
        '${l10n.billingReceiptTxId}: ${entry.paymobTransactionId}',
      '─' * 30,
      'Revvo — revvo-app.com',
    ];
    final receiptText = lines.join('\n');

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_rounded,
                    color: AppColors.primaryNavy),
                const SizedBox(width: 12),
                Text(l10n.billingReceipt,
                    style: AppTypography.h3),
              ],
            ),
            const SizedBox(height: 20),
            _receiptRow(l10n.billingReceiptPlan, planLabel),
            _receiptRow(l10n.billingReceiptAmount, amountStr),
            _receiptRow(l10n.billingReceiptDate, dateStr),
            _receiptRow(
              l10n.billingReceiptStatus,
              entry.success
                  ? l10n.billingReceiptSuccess
                  : l10n.billingReceiptFailed,
            ),
            if (entry.paymobTransactionId != null)
              _receiptRow(
                  l10n.billingReceiptTxId, entry.paymobTransactionId!),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Share.share(receiptText.trim());
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.share_rounded, size: 18),
                label: Text(l10n.billingShareReceipt),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryNavy,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _receiptRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════════════════
  static String _planLabel(String? plan) => switch (plan) {
        'growth_monthly' => 'Growth Monthly',
        'growth_yearly' => 'Growth Yearly',
        'pro_monthly' => 'Pro Monthly',
        'pro_yearly' => 'Pro Yearly',
        _ => plan ?? '—',
      };

  static Color _statusColor(String status) => switch (status) {
        'active' => AppColors.success,
        'grace_period' => AppColors.accentOrange,
        'expired' => AppColors.danger,
        _ => AppColors.success,
      };

  static String _statusLabel(String status, AppLocalizations l10n) =>
      switch (status) {
        'active' => l10n.subscriptionActive,
        'grace_period' => l10n.subscriptionGracePeriod,
        'expired' => l10n.subscriptionExpired,
        _ => l10n.subscriptionFree,
      };
}
