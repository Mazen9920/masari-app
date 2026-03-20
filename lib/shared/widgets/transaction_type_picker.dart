import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../l10n/app_localizations.dart';

/// Result of the transaction-type picker.
enum TransactionType { sale, expense, otherIncome }

/// Bottom sheet that lets the user choose: Sale / Expense / Other Income.
/// Returns the chosen [TransactionType] or null if dismissed.
Future<TransactionType?> showTransactionTypePicker(BuildContext context) {
  return showModalBottomSheet<TransactionType>(
    context: context,
    useRootNavigator: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    backgroundColor: Colors.white,
    builder: (_) => const _PickerBody(),
  );
}

class _PickerBody extends StatelessWidget {
  const _PickerBody();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
               'New Transaction',
              style: AppTypography.h2.copyWith(
                color: AppColors.primaryNavy,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 6),
            Text(
               'What would you like to record?',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 13,
              ),
            ),
            SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _TypeCard(
                    icon: Icons.point_of_sale_rounded,
                    label: l10n.saleAction,
                    subtitle: l10n.recordSaleOrder,
                    color: const Color(0xFF10B981),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      context.pop(TransactionType.sale);
                    },
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _TypeCard(
                    icon: Icons.trending_down_rounded,
                    label: l10n.expense,
                    subtitle: l10n.recordPaymentOut,
                    color: AppColors.danger,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      context.pop(TransactionType.expense);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TypeCard(
                    icon: Icons.trending_up_rounded,
                    label: l10n.otherIncome,
                    subtitle: l10n.recordOtherIncome,
                    color: const Color(0xFF3B82F6),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      context.pop(TransactionType.otherIncome);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _TypeCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                subtitle,
                maxLines: 1,
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
