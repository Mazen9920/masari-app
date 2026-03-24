import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../l10n/app_localizations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../shared/models/transaction_model.dart';
import '../../shared/models/category_data.dart';
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leadingWidget != null) ...[
                leadingWidget,
                const SizedBox(width: 6),
              ],
              Text(
                value,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontFamily: isMono ? 'monospace' : 'Inter',
                ),
              ),
              if (trailingWidget != null) ...[
                const SizedBox(width: 8),
                trailingWidget,
              ],
            ],
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
