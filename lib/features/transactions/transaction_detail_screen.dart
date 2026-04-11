import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import '../../l10n/app_localizations.dart';
import '../../core/navigation/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../shared/models/transaction_model.dart';
import '../../shared/models/category_data.dart';
import '../../shared/models/bosta_shipment_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../sales/sale_detail_screen.dart';

/// Transaction detail screen showing full info for one transaction.
/// Reached by tapping a transaction from the dashboard or transaction list.
class TransactionDetailScreen extends ConsumerWidget {
  final Transaction transaction;

  const TransactionDetailScreen({super.key, required this.transaction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // If this transaction is linked to a sale/order, show order detail instead
    final latestTransactions = ref.watch(transactionsProvider).value ?? [];
    final liveTx = latestTransactions.firstWhere(
      (t) => t.id == transaction.id,
      orElse: () => transaction,
    );

    final salesAsync = ref.watch(salesProvider);
    final sales = salesAsync.value ?? [];

    // 1) Direct saleId link
    final effectiveSaleId = liveTx.saleId ?? transaction.saleId;
    if (effectiveSaleId != null) {
      for (final s in sales) {
        if (s.id == effectiveSaleId) {
          return SaleDetailScreen(sale: s);
        }
      }
    }

    // 2) Sale-category transactions → always try to find the matching order
    if (liveTx.categoryId == 'cat_sales_revenue' ||
        liveTx.categoryId == 'cat_cogs' ||
        liveTx.categoryId == 'cat_shipping') {

      // 2a) Try extracting saleId from transaction ID pattern
      String? extractedSaleId;
      if (liveTx.id.startsWith('sale_rev_')) {
        extractedSaleId = liveTx.id.substring('sale_rev_'.length);
      } else if (liveTx.id.startsWith('sale_cogs_')) {
        extractedSaleId = liveTx.id.substring('sale_cogs_'.length);
      } else if (liveTx.id.startsWith('sale_ship_')) {
        extractedSaleId = liveTx.id.substring('sale_ship_'.length);
      }
      if (extractedSaleId != null) {
        for (final s in sales) {
          if (s.id == extractedSaleId) {
            return SaleDetailScreen(sale: s);
          }
        }
      }

      // If this is a sale-related transaction but sales are still loading,
      // show a loading indicator instead of the generic detail screen.
      if (salesAsync is AsyncLoading || (effectiveSaleId != null && sales.isEmpty)) {
        return Scaffold(
          backgroundColor: AppColors.backgroundLight,
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
            ),
            title: Text(
              AppLocalizations.of(context)!.transactionDetail,
              style: AppTypography.h3.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            centerTitle: true,
          ),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
    }

    // 3) Bosta daily grouped transactions → show full breakdown view
    if (liveTx.isEstimate || liveTx.isReconciliation) {
      return _BostaBreakdownView(transaction: liveTx);
    }

    final displayTransaction = liveTx;

    final isIncome = displayTransaction.amount > 0;
    final currency = ref.watch(appSettingsProvider).currency;
    final formattedAmount =
        '${isIncome ? '+' : '-'}$currency ${NumberFormat('#,##0.00', 'en').format(displayTransaction.amount.abs())}';

    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
        ),
        title: Text(
          l10n.transactionDetail,
          style: AppTypography.h3.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded, color: AppColors.textSecondary),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  context.pushNamed('EditTransactionScreen', extra: {'transaction': displayTransaction});
                case 'duplicate':
                  HapticFeedback.lightImpact();
                  final dup = displayTransaction.copyWith(
                    id: const Uuid().v4(),
                    dateTime: DateTime.now(),
                    createdAt: DateTime.now(),
                    saleId: null,
                  );
                  ref.read(transactionsProvider.notifier).addTransaction(dup);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.transactionDuplicated)));
                  }
                case 'delete':
                  _showDeleteDialog(context, displayTransaction, ref);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', child: Row(children: [const Icon(Icons.edit_outlined, size: 18), const SizedBox(width: 8), Text(l10n.edit)])),
              PopupMenuItem(value: 'duplicate', child: Row(children: [const Icon(Icons.content_copy_rounded, size: 18), const SizedBox(width: 8), Text(l10n.duplicateAction)])),
              PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger), const SizedBox(width: 8), Text(l10n.delete, style: const TextStyle(color: AppColors.danger))])),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            const SizedBox(height: 16),

            // ─── Amount + Payee + Status ───
            _buildAmountSection(displayTransaction, formattedAmount, isIncome),

            const SizedBox(height: 24),

            // ─── Detail Info Rows ───
            _buildInfoCard(context, displayTransaction),

            const SizedBox(height: 20),

            // ─── Bottom Actions ───
            _buildBottomActions(context, displayTransaction, ref),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountSection(Transaction currentTx, String formattedAmount, bool isIncome) {
    return Column(
      children: [
        // Icon
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
              ),
            ],
          ),
          child: Icon(CategoryData.findById(currentTx.categoryId).iconData,
              color: AppColors.textSecondary, size: 30),
        ),
        const SizedBox(height: 14),

        // Amount
        Text(
          formattedAmount,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryNavy,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 4),

        // Payee name
        Text(
          currentTx.title,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),

        // Status badge
        Builder(builder: (context) {
          final isCancelled = currentTx.excludeFromPL || currentTx.title.startsWith('[Cancelled]');
          final badgeColor = isCancelled ? AppColors.danger : AppColors.success;
          final bgColor = isCancelled ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4);
          final borderColor = isCancelled ? const Color(0xFFFECACA) : const Color(0xFFBBF7D0);
          final label = isCancelled ? AppLocalizations.of(context)!.cancelledStatus : AppLocalizations.of(context)!.completedStatus;
          final icon = isCancelled ? Icons.cancel_rounded : Icons.check_circle_rounded;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: badgeColor),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: AppTypography.captionSmall.copyWith(
                    color: badgeColor,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildInfoCard(BuildContext context, Transaction currentTx) {
    final l10n = AppLocalizations.of(context)!;
    final hasNote = currentTx.note != null && currentTx.note!.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          _infoRow(
            l10n.dateAndTime,
            currentTx.formattedTime,
            isLast: false,
          ),
          _infoRow(
            l10n.category,
            CategoryData.findById(currentTx.categoryId).localizedName(AppLocalizations.of(context)!),
            isLast: false,
            leadingWidget: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF8B5CF6), // purple
              ),
            ),
          ),
          _infoRow(
            l10n.paymentMethodLabel,
            currentTx.paymentMethod,
            isLast: false,
            leadingWidget: Icon(Icons.payments_rounded,
                size: 14, color: AppColors.textTertiary),
          ),
          if (hasNote)
            _infoRow(
              l10n.noteLabel,
              currentTx.note!,
              isLast: false,
            ),
          _infoRow(
            l10n.transactionId,
            '#${currentTx.id}',
            isLast: true,
            isMono: true,
            trailingWidget: GestureDetector(
              onTap: () {
                Clipboard.setData(
                    ClipboardData(text: currentTx.id));
              },
              child: const Icon(Icons.content_copy_rounded,
                  size: 16, color: AppColors.accentOrange),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(
    String label,
    String value, {
    bool isLast = false,
    bool isMono = false,
    Widget? leadingWidget,
    Widget? trailingWidget,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: AppColors.borderLight.withValues(alpha: 0.5),
                ),
              ),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (leadingWidget != null) ...[
                  leadingWidget,
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    value,
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontFamily: isMono ? 'monospace' : 'Inter',
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    textAlign: TextAlign.end,
                  ),
                ),
                if (trailingWidget != null) ...[
                  const SizedBox(width: 8),
                  trailingWidget,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, Transaction transaction, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.deleteTransaction, style: AppTypography.h3),
        content: Text(l10n.deleteTransactionConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () {
              // Keep a copy for undo
              final deleted = transaction;
              ref.read(transactionsProvider.notifier).removeTransaction(transaction.id);
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) context.pop();
              });
              messenger.showSnackBar(
                SnackBar(
                  content: Text(l10n.transactionDeleted),
                  backgroundColor: AppColors.primaryNavy,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  action: SnackBarAction(
                    label: l10n.undoLabel,
                    textColor: AppColors.accentOrange,
                    onPressed: () {
                      ref.read(transactionsProvider.notifier).addTransaction(deleted);
                    },
                  ),
                ),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context, Transaction currentTx, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        // Duplicate button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              HapticFeedback.lightImpact();
              final dup = currentTx.copyWith(
                id: const Uuid().v4(),
                dateTime: DateTime.now(),
                createdAt: DateTime.now(),
                saleId: null,
              );
              ref.read(transactionsProvider.notifier).addTransaction(dup);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.transactionDuplicated)));
            },
            icon: const Icon(Icons.content_copy_rounded, size: 18),
            label: Text(l10n.duplicateTransaction),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.borderLight),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Delete button
        TextButton(
          onPressed: () => _showDeleteDialog(context, currentTx, ref),
          child: Text(
            l10n.deleteTransaction,
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.danger,
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Full Bosta Daily Transaction Breakdown View
// ══════════════════════════════════════════════════════════════

class _BostaBreakdownView extends StatelessWidget {
  final Transaction transaction;
  const _BostaBreakdownView({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final feeFmt = NumberFormat('#,##0.00');
    final isEstimate = transaction.isEstimate;
    final typeColor =
        isEstimate ? const Color(0xFF3B82F6) : AppColors.accentOrange;

    // Extract date from ID
    String dateStr = '';
    if (transaction.id.startsWith('bosta_est_daily_')) {
      dateStr = transaction.id.substring('bosta_est_daily_'.length);
    } else if (transaction.id.startsWith('bosta_rec_daily_')) {
      dateStr = transaction.id.substring('bosta_rec_daily_'.length);
    }

    final txField = isEstimate
        ? 'estimate_transaction_id'
        : 'reconciliation_transaction_id';

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(
              Icons.arrow_back_rounded, color: AppColors.textPrimary),
        ),
        title: Text(
          isEstimate
              ? l10n.bostaEstimateTransaction
              : l10n.bostaReconciliationTransaction,
          style: AppTypography.h3.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
      ),
      body: FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance
            .collection('bosta_shipments')
            .where('user_id',
                isEqualTo: FirebaseAuth.instance.currentUser?.uid)
            .where(txField, isEqualTo: transaction.id)
            .get(),
        builder: (context, snap) {
          final shipments = (snap.data?.docs ?? [])
              .map((d) => BostaShipment.fromJson(
                  d.data() as Map<String, dynamic>))
              .toList();

          // Stats
          final totalEstimated = shipments.fold<double>(
              0, (acc, s) => acc + (s.estimatedFee ?? 0));
          final settledCount =
              shipments.where((s) => s.totalFees != null).length;
          final totalActual = shipments.fold<double>(
              0, (acc, s) => acc + (s.totalFees ?? 0));
          final totalAdjustment =
              settledCount > 0 ? totalActual - totalEstimated : 0.0;

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Hero Amount ──
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isEstimate
                              ? Icons.calculate_rounded
                              : Icons.swap_vert_rounded,
                          color: typeColor,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'EGP ${feeFmt.format(transaction.amount.abs())}',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryNavy,
                          fontFamily: 'Inter',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateStr,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Type badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: typeColor.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          isEstimate
                              ? l10n.bostaEstimateTransaction
                              : l10n.bostaReconciliationTransaction,
                          style: AppTypography.captionSmall.copyWith(
                            color: typeColor,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Summary Stats ──
                if (snap.connectionState == ConnectionState.done)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppColors.borderLight
                              .withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      children: [
                        _summaryRow(
                          l10n.bostaShipmentCount,
                          '${shipments.length}',
                        ),
                        _summaryRow(
                          l10n.bostaTotalEstimates,
                          'EGP ${feeFmt.format(totalEstimated)}',
                        ),
                        if (settledCount > 0) ...[
                          _summaryRow(
                            l10n.bostaReconciled,
                            '$settledCount / ${shipments.length}',
                            valueColor: settledCount == shipments.length
                                ? AppColors.success
                                : AppColors.warning,
                          ),
                          _summaryRow(
                            l10n.bostaNetActual,
                            'EGP ${feeFmt.format(totalActual)}',
                          ),
                          _summaryRow(
                            l10n.bostaTotalAdjustments,
                            '${totalAdjustment > 0 ? '+' : ''}${feeFmt.format(totalAdjustment)}',
                            valueColor: totalAdjustment.abs() < 0.01
                                ? AppColors.textTertiary
                                : totalAdjustment > 0
                                    ? AppColors.danger
                                    : AppColors.success,
                            isLast: true,
                          ),
                        ] else
                          _summaryRow(
                            l10n.bostaPendingSettlement,
                            '${shipments.length} ${l10n.bostaShipmentCount.toLowerCase()}',
                            valueColor: AppColors.warning,
                            isLast: true,
                          ),
                      ],
                    ),
                  ),

                const SizedBox(height: 24),

                // ── Shipment Breakdown ──
                Text(
                  l10n.bostaShipmentCount,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),

                if (snap.connectionState == ConnectionState.waiting)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (shipments.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        l10n.bostaShipmentsEmpty,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  )
                else
                  ...shipments.map(
                    (s) => _ShipmentBreakdownTile(
                      shipment: s,
                      onTap: () => context.push(
                        AppRoutes.bostaShipmentDetail,
                        extra: {'shipment': s},
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                // ── Audit link ──
                Center(
                  child: TextButton.icon(
                    onPressed: () => context.push(AppRoutes.bostaAudit),
                    icon: const Icon(Icons.fact_check_rounded, size: 16),
                    label: Text(l10n.bostaViewAudit),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primaryNavy,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    Color? valueColor,
    bool isLast = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: AppColors.borderLight.withValues(alpha: 0.4),
                ),
              ),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: AppTypography.labelMedium.copyWith(
              color: valueColor ?? AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShipmentBreakdownTile extends StatelessWidget {
  final BostaShipment shipment;
  final VoidCallback onTap;

  const _ShipmentBreakdownTile({
    required this.shipment,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final feeFmt = NumberFormat('#,##0.00');
    final dateFmt = DateFormat('MMM dd, yyyy');

    final estimated = shipment.estimatedFee ?? 0;
    final actual = shipment.totalFees;
    final hasActual = actual != null && actual > 0;
    final adjustment = hasActual ? (actual - estimated) : 0.0;

    // Status
    final isReconciled = shipment.isReconciled;
    final hasEstimate = shipment.estimateRecorded;
    final statusColor = isReconciled
        ? AppColors.success
        : hasEstimate
            ? const Color(0xFF3B82F6)
            : AppColors.warning;
    final statusLabel = isReconciled
        ? '✓ Settled'
        : hasEstimate
            ? 'Est. Only'
            : 'Pending';

    // State
    final stateColor = _stateColor(shipment.state);
    final stateIcon = _stateIcon(shipment.state);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.borderLight.withValues(alpha: 0.4)),
          ),
          child: Column(
            children: [
              // Row 1: State icon + tracking + status badge
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: stateColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(stateIcon, size: 16, color: stateColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      shipment.trackingNumber,
                      style: AppTypography.labelSmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      statusLabel,
                      style: AppTypography.captionSmall.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 9,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded,
                      size: 16, color: AppColors.textTertiary),
                ],
              ),

              const SizedBox(height: 10),

              // Row 2: Fee breakdown
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    // Estimated
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            'Estimated',
                            style: AppTypography.captionSmall.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 9,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            estimated > 0
                                ? feeFmt.format(estimated)
                                : '-',
                            style: AppTypography.labelSmall.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Arrow
                    Icon(Icons.arrow_forward_rounded,
                        size: 12, color: AppColors.textTertiary),
                    // Actual
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            'Actual',
                            style: AppTypography.captionSmall.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 9,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            hasActual ? feeFmt.format(actual) : '—',
                            style: AppTypography.labelSmall.copyWith(
                              fontWeight: FontWeight.w700,
                              color: hasActual
                                  ? AppColors.textPrimary
                                  : AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // = Adjustment
                    if (hasActual) ...[
                      Text('=',
                          style: TextStyle(
                              color: AppColors.textTertiary, fontSize: 12)),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              'Adj.',
                              style: AppTypography.captionSmall.copyWith(
                                color: AppColors.textTertiary,
                                fontSize: 9,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              adjustment.abs() < 0.01
                                  ? '±0'
                                  : '${adjustment > 0 ? '+' : ''}${feeFmt.format(adjustment)}',
                              style: AppTypography.labelSmall.copyWith(
                                fontWeight: FontWeight.w700,
                                color: adjustment.abs() < 0.01
                                    ? AppColors.textTertiary
                                    : adjustment > 0
                                        ? AppColors.danger
                                        : AppColors.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Row 3: Dates
              if (shipment.bostaCreatedAt != null ||
                  shipment.depositedAt != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (shipment.bostaCreatedAt != null) ...[
                      Icon(Icons.flight_takeoff_rounded,
                          size: 10, color: AppColors.textTertiary),
                      const SizedBox(width: 3),
                      Text(
                        dateFmt.format(shipment.bostaCreatedAt!),
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 9,
                        ),
                      ),
                    ],
                    if (shipment.bostaCreatedAt != null &&
                        shipment.depositedAt != null)
                      const SizedBox(width: 12),
                    if (shipment.depositedAt != null) ...[
                      Icon(Icons.account_balance_rounded,
                          size: 10, color: AppColors.success),
                      const SizedBox(width: 3),
                      Text(
                        dateFmt.format(shipment.depositedAt!),
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.success,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Color _stateColor(int state) {
    return switch (state) {
      45 => AppColors.success,
      60 => AppColors.danger,
      46 => AppColors.warning,
      _ => AppColors.textTertiary,
    };
  }

  static IconData _stateIcon(int state) {
    return switch (state) {
      45 => Icons.check_circle_rounded,
      60 => Icons.undo_rounded,
      46 => Icons.assignment_return_rounded,
      _ => Icons.local_shipping_rounded,
    };
  }
}
