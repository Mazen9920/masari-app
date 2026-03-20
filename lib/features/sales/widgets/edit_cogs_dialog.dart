import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../shared/models/sale_model.dart';
import '../../../shared/models/transaction_model.dart' as txn;
import '../../../shared/utils/money_utils.dart';

/// Dialog that lets users enter/edit the cost price for each line item
/// of a sale whose COGS is zero or needs correction.
///
/// On save it updates:
///  1. The Sale document (items with updated costPrice)
///  2. The COGS transaction (`sale_cogs_{saleId}`) with the new total
class EditCogsDialog extends ConsumerStatefulWidget {
  final Sale sale;
  final String currency;

  const EditCogsDialog({
    super.key,
    required this.sale,
    required this.currency,
  });

  @override
  ConsumerState<EditCogsDialog> createState() => _EditCogsDialogState();
}

class _EditCogsDialogState extends ConsumerState<EditCogsDialog> {
  late List<TextEditingController> _controllers;
  bool _saving = false;
  final _fmt = NumberFormat('#,##0.00', 'en');

  @override
  void initState() {
    super.initState();
    _controllers = widget.sale.items.map((item) {
      return TextEditingController(
        text: item.costPrice > 0 ? item.costPrice.toStringAsFixed(2) : '',
      );
    }).toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  double _parsedCost(int index) {
    final v = double.tryParse(_controllers[index].text) ?? 0;
    return v < 0 ? 0 : v;
  }

  double get _newTotalCogs {
    double total = 0;
    for (int i = 0; i < widget.sale.items.length; i++) {
      total += roundMoney(widget.sale.items[i].quantity * _parsedCost(i));
    }
    return roundMoney(total);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      // 1. Build updated items with new cost prices
      final updatedItems = <SaleItem>[];
      for (int i = 0; i < widget.sale.items.length; i++) {
        updatedItems.add(
          widget.sale.items[i].copyWith(costPrice: _parsedCost(i)),
        );
      }

      final updatedSale = widget.sale.copyWith(items: updatedItems);
      final newTotalCogs = updatedSale.totalCogs;

      // 2. Update the Sale document
      await ref.read(salesProvider.notifier).updateSale(updatedSale);

      // 3. Update the COGS transaction
      final cogsId = 'sale_cogs_${widget.sale.id}';
      final txnRepo = ref.read(transactionRepositoryProvider);
      final txnResult = await txnRepo.getTransactionById(cogsId);

      if (txnResult.isSuccess && txnResult.data != null) {
        final updated = txnResult.data!.copyWith(
          amount: -newTotalCogs, // COGS is stored as negative
        );
        await ref
            .read(transactionsProvider.notifier)
            .updateTransaction(updated);
      } else {
        // COGS transaction doesn't exist yet — create it
        final newCogsTxn = txn.Transaction(
          id: cogsId,
          userId: widget.sale.userId,
          title: 'Cost of Goods Sold',
          amount: -newTotalCogs,
          dateTime: widget.sale.date,
          categoryId: 'cat_cogs',
          saleId: widget.sale.id,
        );
        await ref
            .read(transactionsProvider.notifier)
            .addTransaction(newCogsTxn);
      }

      if (mounted) {
        Navigator.of(context).pop(true); // true = saved
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'COGS updated — ${widget.currency} ${_fmt.format(newTotalCogs)}',
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update COGS: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sale = widget.sale;
    final currency = widget.currency;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.edit_note_rounded,
                        color: AppColors.warning, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Cost of Goods',
                          style: AppTypography.h3.copyWith(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Enter the cost price per unit for each item',
                          style: AppTypography.captionSmall
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Item list ──
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: sale.items.length,
                separatorBuilder: (_, _) => Divider(
                  color: AppColors.borderLight.withValues(alpha: 0.5),
                  height: 20,
                ),
                itemBuilder: (context, i) {
                  final item = sale.items[i];
                  return _buildItemCostRow(item, i, currency);
                },
              ),
            ),

            // ── Footer with totals + save ──
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: AppColors.borderLight.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total COGS',
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '$currency ${_fmt.format(_newTotalCogs)}',
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed:
                              _saving ? null : () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: AppColors.borderLight
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _saving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryNavy,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Save',
                                  style: AppTypography.labelSmall.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCostRow(SaleItem item, int index, String currency) {
    final lineCogs = roundMoney(item.quantity * _parsedCost(index));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Product name + qty
        Row(
          children: [
            Expanded(
              child: Text(
                item.productName,
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              'Qty: ${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity}',
              style: AppTypography.captionSmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
        if (item.variantName != null && item.variantName!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            item.variantName!,
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textTertiary,
              fontSize: 11,
            ),
          ),
        ],
        const SizedBox(height: 8),
        // Cost input + line total
        Row(
          children: [
            // Cost per unit input
            Expanded(
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _controllers[index],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}')),
                  ],
                  onChanged: (_) => setState(() {}),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    prefixText: '$currency ',
                    prefixStyle: AppTypography.captionSmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    hintText: '0.00',
                    hintStyle: AppTypography.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: AppColors.borderLight.withValues(alpha: 0.5),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: AppColors.borderLight.withValues(alpha: 0.5),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppColors.primaryNavy,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Line COGS total
            SizedBox(
              width: 90,
              child: Text(
                '= $currency ${_fmt.format(lineCogs)}',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
