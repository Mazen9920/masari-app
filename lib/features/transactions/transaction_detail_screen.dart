import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../dashboard/widgets/recent_transactions.dart';
import '../../shared/models/transaction_model.dart';
import '../../shared/models/category_data.dart';
import 'edit_transaction_screen.dart';

/// Transaction detail screen showing full info for one transaction.
/// Reached by tapping a transaction from the dashboard or transaction list.
class TransactionDetailScreen extends StatelessWidget {
  final TransactionItem transaction;

  const TransactionDetailScreen({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isIncome = transaction.amount > 0;
    final formattedAmount =
        '${isIncome ? '+' : '-'}EGP ${transaction.amount.abs().toStringAsFixed(0)}';

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
        ),
        title: Text(
          'Transaction Detail',
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
                  // Convert TransactionItem (UI model) to Transaction (Data model)
                  final trueAmount = transaction.amount;
                  
                  final dataTransaction = Transaction(
                    id: DateTime.now().millisecondsSinceEpoch.toString(), // Use actual ID from DB in real implementation
                    title: transaction.title,
                    amount: trueAmount,
                    dateTime: DateTime.now(), // Use actual Date from DB in real implementation
                    category: CategoryData.all.firstWhere((c) => c.name == transaction.title, orElse: () => CategoryData.all.first),
                    note: null,
                    paymentMethod: 'Cash', // Uses actual method in real implementation
                  );
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EditTransactionScreen(transaction: dataTransaction),
                    ),
                  );
                case 'duplicate':
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaction duplicated')));
                case 'delete':
                  _showDeleteDialog(context);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text('Edit')])),
              const PopupMenuItem(value: 'duplicate', child: Row(children: [Icon(Icons.content_copy_rounded, size: 18), SizedBox(width: 8), Text('Duplicate')])),
              PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger), SizedBox(width: 8), Text('Delete', style: TextStyle(color: AppColors.danger))])),
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
            _buildAmountSection(formattedAmount, isIncome),

            const SizedBox(height: 24),

            // ─── Quick Action Buttons ───
            _buildQuickActions(),

            const SizedBox(height: 24),

            // ─── Detail Info Rows ───
            _buildInfoCard(),

            const SizedBox(height: 16),

            // ─── AI Note ───
            _buildAINote(),

            const SizedBox(height: 16),

            // ─── Attachments ───
            _buildAttachments(),

            const SizedBox(height: 20),

            // ─── Bottom Actions ───
            _buildBottomActions(context),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountSection(String formattedAmount, bool isIncome) {
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
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
              ),
            ],
          ),
          child: Icon(transaction.icon,
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
          transaction.title,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),

        // Status badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4), // green-50
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFBBF7D0)), // green-200
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_rounded,
                  size: 14, color: AppColors.success),
              const SizedBox(width: 5),
              Text(
                'COMPLETED',
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _actionButton(Icons.receipt_long_rounded, 'Download\nReceipt'),
        _actionButton(Icons.auto_fix_high_rounded, 'Categorize\nAI'),
        _actionButton(Icons.flag_rounded, 'Report\nIssue'),
      ],
    );
  }

  Widget _actionButton(IconData icon, String label) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 6,
              ),
            ],
          ),
          child: Icon(icon, size: 22, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: AppTypography.captionSmall.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildInfoCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          _infoRow(
            'Date & Time',
            transaction.subtitle,
            isLast: false,
          ),
          _infoRow(
            'Category',
            transaction.category,
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
            'Payment Method',
            'Cash',
            isLast: false,
            leadingWidget: Icon(Icons.payments_rounded,
                size: 14, color: AppColors.textTertiary),
          ),
          _infoRow(
            'Transaction ID',
            '#TX-8920394',
            isLast: true,
            isMono: true,
            trailingWidget: GestureDetector(
              onTap: () {
                Clipboard.setData(
                    const ClipboardData(text: 'TX-8920394'));
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
                  color: AppColors.borderLight.withOpacity(0.5),
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

  Widget _buildAINote() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF).withOpacity(0.6), // blue-50
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)), // blue-200
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  size: 18, color: AppColors.secondaryBlue),
              const SizedBox(width: 8),
              Text(
                'AI Note',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              children: [
                const TextSpan(text: 'This is '),
                TextSpan(
                  text: '12% higher',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryNavy,
                  ),
                ),
                const TextSpan(
                  text:
                      ' than your average bill for this category. It usually occurs on the 10th of each month.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachments() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Attachments',
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          height: 90,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.borderLight,
              style: BorderStyle.solid,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.backgroundLight,
                ),
                child: const Icon(Icons.add_a_photo_rounded,
                    size: 18, color: AppColors.textTertiary),
              ),
              const SizedBox(height: 6),
              Text(
                'Add Receipt',
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Transaction', style: AppTypography.h3),
        content: const Text('This action cannot be undone. Are you sure you want to delete this transaction?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaction deleted')));
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    return Column(
      children: [
        // Duplicate button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaction duplicated')));
            },
            icon: const Icon(Icons.content_copy_rounded, size: 18),
            label: const Text('Duplicate Transaction'),
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
          onPressed: () => _showDeleteDialog(context),
          child: Text(
            'Delete Transaction',
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.danger,
            ),
          ),
        ),
      ],
    );
  }
}
