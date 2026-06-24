import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../shared/models/bosta_shipment_model.dart';
import '../../../shared/models/sale_model.dart';
import '../../../shared/utils/safe_pop.dart';

/// Detail screen for a single Bosta shipment.
///
/// Shows tracking number, state, fees breakdown, linked sale info,
/// and expense recording status.
class BostaShipmentDetailScreen extends StatelessWidget {
  final BostaShipment shipment;

  const BostaShipmentDetailScreen({super.key, required this.shipment});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context, l10n),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStateCard(l10n)
                        .animate()
                        .fadeIn(duration: 250.ms),
                    const SizedBox(height: 20),
                    _sectionLabel(l10n.bostaShipmentInfo),
                    const SizedBox(height: 10),
                    _buildInfoCard(context, l10n)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 60.ms),
                    if (shipment.totalFees != null &&
                        shipment.totalFees! > 0) ...[
                      const SizedBox(height: 20),
                      _sectionLabel(l10n.bostaFeeBreakdown),
                      const SizedBox(height: 10),
                      _buildFeesCard(l10n)
                          .animate()
                          .fadeIn(duration: 250.ms, delay: 120.ms),
                    ],
                    const SizedBox(height: 20),
                    _sectionLabel(l10n.bostaExpenseInfo),
                    const SizedBox(height: 10),
                    _buildExpenseCard(l10n)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 180.ms),
                    if (shipment.isCashoutPaid ||
                        shipment.cashoutId != null ||
                        shipment.nextCashoutDate != null) ...[
                      const SizedBox(height: 20),
                      _sectionLabel('CASHOUT STATUS'),
                      const SizedBox(height: 10),
                      _buildCashoutCard(l10n)
                          .animate()
                          .fadeIn(duration: 250.ms, delay: 210.ms),
                    ],
                    if (shipment.hasEstimate) ...[
                      const SizedBox(height: 20),
                      _sectionLabel(l10n.bostaAccrualInfo),
                      const SizedBox(height: 10),
                      _buildAccrualCard(l10n)
                          .animate()
                          .fadeIn(duration: 250.ms, delay: 240.ms),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderLight.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.safePop(),
            icon: const Icon(Icons.chevron_left_rounded, size: 28),
            color: AppColors.primaryNavy,
          ),
          const Spacer(),
          Text(
            l10n.bostaShipmentDetail,
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.primaryNavy,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  // ── State hero card ─────────────────────────────────────

  Widget _buildStateCard(AppLocalizations l10n) {
    final stateColor = _stateColor(shipment.state);
    final feeFmt = NumberFormat('#,##0.00');
    final hasFees = shipment.totalFees != null && shipment.totalFees! > 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: stateColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: stateColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: stateColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _stateIcon(shipment.state),
              color: stateColor,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shipment.stateValue,
                  style: AppTypography.labelLarge.copyWith(
                    color: stateColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  shipment.trackingNumber,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (hasFees)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  l10n.bostaTotalFees,
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                  ),
                ),
                Text(
                  'EGP ${feeFmt.format(shipment.totalFees)}',
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── Shipment info card ──────────────────────────────────

  Widget _buildInfoCard(BuildContext context, AppLocalizations l10n) {
    final dateFmt = DateFormat('MMM dd, yyyy');

    return _CardContainer(
      children: [
        _DetailRow(
          label: l10n.bostaTrackingNumber,
          value: shipment.trackingNumber,
          icon: Icons.tag_rounded,
          onTap: () {
            Clipboard.setData(ClipboardData(text: shipment.trackingNumber));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Tracking number copied'),
                duration: Duration(seconds: 1),
              ),
            );
          },
        ),
        _DetailRow(
          label: l10n.bostaState,
          value: shipment.stateValue,
          icon: Icons.local_shipping_rounded,
        ),
        _DetailRow(
          label: l10n.bostaType,
          value: shipment.type,
          icon: Icons.category_rounded,
        ),
        if (shipment.businessReference != null)
          _DetailRow(
            label: l10n.bostaBusinessRef,
            value: shipment.businessReference!,
            icon: Icons.receipt_long_rounded,
          ),
        _DetailRow(
          label: l10n.bostaLinkedSale,
          value: shipment.matched
              ? (shipment.saleId ?? '-')
              : l10n.bostaUnlinked,
          icon: shipment.matched
              ? Icons.link_rounded
              : Icons.link_off_rounded,
          valueColor: shipment.matched ? AppColors.success : AppColors.warning,
          onTap: shipment.matched && shipment.saleId != null
              ? () => _navigateToSale(context, shipment.saleId!)
              : null,
          trailingIcon: shipment.matched ? Icons.chevron_right_rounded : null,
        ),
        if (shipment.cod != null && shipment.cod! > 0)
          _DetailRow(
            label: l10n.bostaCOD,
            value: 'EGP ${NumberFormat('#,##0.00').format(shipment.cod)}',
            icon: Icons.payments_rounded,
          ),
        if (shipment.depositedAt != null)
          _DetailRow(
            label: l10n.bostaDepositedAt,
            value: dateFmt.format(shipment.depositedAt!),
            icon: Icons.account_balance_rounded,
          ),
        if (shipment.syncedAt != null)
          _DetailRow(
            label: l10n.bostaSyncedAt,
            value: dateFmt.format(shipment.syncedAt!),
            icon: Icons.sync_rounded,
          ),
      ],
    );
  }

  // ── Fees breakdown card ─────────────────────────────────

  Widget _buildFeesCard(AppLocalizations l10n) {
    final feeFmt = NumberFormat('#,##0.00');
    final breakdown = shipment.feeBreakdown ?? {};

    final feeLabels = <String, String>{
      'shipping_fees': l10n.bostaShippingFees,
      'fulfillment_fees': l10n.bostaFulfillmentFees,
      'vat': l10n.bostaVat,
      'cod_fees': l10n.bostaCodFees,
      'insurance_fees': l10n.bostaInsuranceFees,
      'expedite_fees': l10n.bostaExpediteFees,
      'opening_package_fees': l10n.bostaOpeningPackageFees,
      'flex_ship_fees': l10n.bostaFlexShipFees,
      'pos_fees': l10n.bostaPosFees,
      'collection_fees': l10n.bostaCollectionFees,
    };

    final nonZero = breakdown.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (nonZero.isEmpty) {
      return _CardContainer(children: [
        _DetailRow(
          label: l10n.bostaTotalFees,
          value: 'EGP ${feeFmt.format(shipment.totalFees ?? 0)}',
          icon: Icons.receipt_rounded,
        ),
      ]);
    }

    final total = shipment.totalFees ?? 1;
    final barColors = [
      const Color(0xFFE2342D),
      const Color(0xFF3B82F6),
      const Color(0xFFF59E0B),
      const Color(0xFF10B981),
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
      const Color(0xFF6366F1),
      const Color(0xFF14B8A6),
      const Color(0xFFF97316),
      const Color(0xFF64748B),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stacked proportion bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: [
                    for (int i = 0; i < nonZero.length; i++)
                      Expanded(
                        flex: (nonZero[i].value / total * 100).round().clamp(1, 100),
                        child: Container(color: barColors[i % barColors.length]),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            // Fee items
            for (int i = 0; i < nonZero.length; i++) ...[
              _FeeRow(
                label: feeLabels[nonZero[i].key] ?? nonZero[i].key,
                value: 'EGP ${feeFmt.format(nonZero[i].value)}',
                pct: '${(nonZero[i].value / total * 100).toStringAsFixed(0)}%',
                color: barColors[i % barColors.length],
              ),
              if (i < nonZero.length - 1) const SizedBox(height: 8),
            ],
            const SizedBox(height: 10),
            Divider(
              height: 1,
              color: AppColors.borderLight.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.bostaTotalFees,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'EGP ${feeFmt.format(shipment.totalFees ?? 0)}',
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Expense status card ─────────────────────────────────

  Widget _buildExpenseCard(AppLocalizations l10n) {
    final recorded = shipment.expenseRecorded;
    final color = recorded ? AppColors.success : AppColors.warning;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              recorded
                  ? Icons.check_circle_rounded
                  : Icons.schedule_rounded,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recorded
                      ? l10n.bostaExpenseRecorded
                      : l10n.bostaExpenseNotRecorded,
                  style: AppTypography.labelMedium.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (shipment.expenseTransactionId != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    shipment.expenseTransactionId!,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (!recorded && shipment.awaitingSettlement) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.bostaPending,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Accrual Timeline Card ─────────────────────────────

  Widget _buildCashoutCard(AppLocalizations l10n) {
    final dateFmt = DateFormat('MMM dd, yyyy');
    final paid = shipment.isCashoutPaid;
    final color = paid ? AppColors.success : const Color(0xFF3B82F6);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              paid
                  ? Icons.account_balance_wallet_rounded
                  : Icons.schedule_send_rounded,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paid ? 'Cashout Received' : 'Cashout Pending',
                  style: AppTypography.labelMedium.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (shipment.nextCashoutDate != null && !paid) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Expected: ${dateFmt.format(shipment.nextCashoutDate!)}',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                if (shipment.cashoutId != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    shipment.cashoutId!,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccrualCard(AppLocalizations l10n) {
    final feeFmt = NumberFormat('#,##0.00');
    final dateFmt = DateFormat('MMM dd, yyyy');

    final estimated = shipment.estimatedFee ?? 0;
    final actual = shipment.totalFees;
    final hasActual = actual != null && actual > 0;
    final adjustment = hasActual ? (actual - estimated) : 0.0;

    // Status
    final String statusLabel;
    final Color statusColor;
    final IconData statusIcon;
    if (shipment.isReconciled) {
      statusLabel = l10n.bostaReconciled;
      statusColor = AppColors.success;
      statusIcon = Icons.check_circle_rounded;
    } else if (shipment.estimateRecorded) {
      statusLabel = l10n.bostaEstRecorded;
      statusColor = const Color(0xFF3B82F6);
      statusIcon = Icons.schedule_rounded;
    } else {
      statusLabel = l10n.bostaPendingSettlement;
      statusColor = AppColors.warning;
      statusIcon = Icons.hourglass_empty_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, size: 14, color: statusColor),
                const SizedBox(width: 6),
                Text(
                  statusLabel,
                  style: AppTypography.captionSmall.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Timeline rows
          _timelineRow(
            icon: Icons.calculate_rounded,
            color: const Color(0xFF3B82F6),
            label: l10n.bostaEstimatedFee,
            value: 'EGP ${feeFmt.format(estimated)}',
            subtitle: shipment.bostaCreatedAt != null
                ? '${l10n.bostaFulfillmentDate}: ${dateFmt.format(shipment.bostaCreatedAt!)}'
                : null,
            isLast: !hasActual,
          ),
          if (hasActual) ...[
            _timelineRow(
              icon: Icons.account_balance_rounded,
              color: AppColors.success,
              label: l10n.bostaActualFee,
              value: 'EGP ${feeFmt.format(actual)}',
              subtitle: shipment.depositedAt != null
                  ? '${l10n.bostaSettlementDate}: ${dateFmt.format(shipment.depositedAt!)}'
                  : null,
              isLast: false,
            ),
            _timelineRow(
              icon: adjustment.abs() < 0.01
                  ? Icons.check_rounded
                  : adjustment > 0
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
              color: adjustment.abs() < 0.01
                  ? AppColors.textTertiary
                  : adjustment > 0
                      ? AppColors.danger
                      : AppColors.success,
              label: l10n.bostaAdjustment,
              value: adjustment.abs() < 0.01
                  ? l10n.bostaNoAdjustment
                  : 'EGP ${adjustment > 0 ? '+' : ''}${feeFmt.format(adjustment)}',
              subtitle: adjustment.abs() < 0.01
                  ? null
                  : adjustment > 0
                      ? l10n.bostaExtraExpense
                      : l10n.bostaCreditBack,
              isLast: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _timelineRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    String? subtitle,
    required bool isLast,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 14, color: color),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 28,
                color: AppColors.borderLight.withValues(alpha: 0.5),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      label,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      value,
                      style: AppTypography.labelSmall.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Sale Navigation ─────────────────────────────────────

  Future<void> _navigateToSale(BuildContext context, String saleId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('sales')
          .doc(saleId)
          .get();
      if (!doc.exists || !context.mounted) return;
      final sale = Sale.fromJson(doc.data()!);
      if (context.mounted) {
        context.push('/sales/detail', extra: {'sale': sale});
      }
    } catch (_) {
      // Silently fail
    }
  }

  // ── Helpers ─────────────────────────────────────────────

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: AppTypography.captionSmall.copyWith(
        color: AppColors.textTertiary,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        fontSize: 11,
      ),
    );
  }

  Color _stateColor(int state) {
    return switch (state) {
      45 => AppColors.success,
      60 => AppColors.danger,
      46 => AppColors.warning,
      _ => AppColors.textSecondary,
    };
  }

  IconData _stateIcon(int state) {
    return switch (state) {
      45 => Icons.check_circle_rounded,
      60 => Icons.undo_rounded,
      46 => Icons.assignment_return_rounded,
      _ => Icons.local_shipping_rounded,
    };
  }
}

// ══════════════════════════════════════════════════════════════
// Private widgets
// ══════════════════════════════════════════════════════════════

class _CardContainer extends StatelessWidget {
  final List<Widget> children;
  const _CardContainer({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: AppColors.borderLight.withValues(alpha: 0.5),
              ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;
  final VoidCallback? onTap;
  final IconData? trailingIcon;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
    this.onTap,
    this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.textTertiary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Flexible(
              child: Text(
                value,
                style: AppTypography.labelSmall.copyWith(
                  color: valueColor ?? AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(trailingIcon ?? Icons.copy_rounded,
                  size: 14, color: AppColors.textTertiary),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  final String label;
  final String value;
  final String pct;
  final Color color;

  const _FeeRow({
    required this.label,
    required this.value,
    required this.pct,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Text(
          pct,
          style: AppTypography.captionSmall.copyWith(
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w600,
            fontSize: 10,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
