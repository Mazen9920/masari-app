import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../shared/models/goods_receipt_model.dart';
import '../../shared/models/product_model.dart';
import '../../shared/utils/safe_pop.dart';
import '../../l10n/app_localizations.dart';

/// Screen to edit an existing goods receipt — quantities, date, status, notes.
/// All changes are synced back to linked purchases and inventory.
class EditReceiptScreen extends ConsumerStatefulWidget {
  final GoodsReceipt receipt;
  const EditReceiptScreen({super.key, required this.receipt});

  @override
  ConsumerState<EditReceiptScreen> createState() => _EditReceiptScreenState();
}

class _EditReceiptScreenState extends ConsumerState<EditReceiptScreen> {
  AppLocalizations get l10n => AppLocalizations.of(context)!;
  late DateTime _receiptDate;
  late ReceiptStatus _status;
  late TextEditingController _notesCtrl;
  late List<_EditLine> _lines;
  bool _syncToInventory = true;

  @override
  void initState() {
    super.initState();
    final r = widget.receipt;
    _receiptDate = r.date;
    _status = r.status;
    _notesCtrl = TextEditingController(text: r.notes ?? '');
    _lines = r.items
        .map((item) => _EditLine(
              productId: item.productId,
              variantId: item.variantId,
              nameCtrl: TextEditingController(text: item.productName),
              orderedCtrl: TextEditingController(
                  text: item.orderedQty.toStringAsFixed(0)),
              receivedCtrl: TextEditingController(
                  text: item.receivedQty.toStringAsFixed(0)),
              costCtrl: TextEditingController(
                  text: item.unitCost.toStringAsFixed(2)),
              originalReceivedQty: item.receivedQty,
            ))
        .toList();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    for (final l in _lines) {
      l.nameCtrl.dispose();
      l.orderedCtrl.dispose();
      l.receivedCtrl.dispose();
      l.costCtrl.dispose();
    }
    super.dispose();
  }

  double get _totalCost {
    double sum = 0;
    for (final l in _lines) {
      final received = double.tryParse(l.receivedCtrl.text) ?? 0;
      final cost = double.tryParse(l.costCtrl.text) ?? 0;
      sum += received * cost;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyProvider);
    final fmt = NumberFormat('#,##0.00', 'en');

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
                child: Column(
                  children: [
                    _buildDatePicker()
                        .animate()
                        .fadeIn(duration: 250.ms),
                    const SizedBox(height: 14),
                    _buildStatusPicker()
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 40.ms),
                    const SizedBox(height: 14),
                    _buildItemsSection(currency)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 80.ms),
                    const SizedBox(height: 14),
                    _buildSyncToggle()
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 120.ms),
                    const SizedBox(height: 14),
                    _buildNotesSection()
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 160.ms),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomSheet: _buildBottomCTA(currency, fmt),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  HEADER
  // ═══════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom:
              BorderSide(color: AppColors.borderLight.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.safePop(),
            icon: const Icon(Icons.close_rounded),
            iconSize: 26,
            color: AppColors.textSecondary,
          ),
          Expanded(
            child: Center(
              child: Text(
                l10n.editReceipt,
                style: AppTypography.h2.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  DATE PICKER
  // ═══════════════════════════════════════════════════════

  Widget _buildDatePicker() {
    final formatted = DateFormat( 'MMM dd, yyyy').format(_receiptDate);
    return _Card(
      title: l10n.date,
      children: [
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _receiptDate,
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
            );
            if (picked != null) setState(() => _receiptDate = picked);
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.borderLight.withValues(alpha: 0.7)),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today_rounded,
                    size: 20, color: AppColors.textSecondary),
                const SizedBox(width: 12),
                Text(formatted,
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.textPrimary)),
                const Spacer(),
                Icon(Icons.chevron_right_rounded,
                    color: AppColors.textTertiary, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  //  STATUS PICKER
  // ═══════════════════════════════════════════════════════

  Widget _buildStatusPicker() {
    return _Card(
      title: l10n.status,
      children: [
        Row(
          children: ReceiptStatus.values.map((s) {
            final selected = _status == s;
            final colors = _statusChipColors(s);
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _status = s),
                child: Container(
                  margin: EdgeInsets.only(
                      right: s != ReceiptStatus.rejected ? 8 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? colors.$1 : AppColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? colors.$2
                          : AppColors.borderLight.withValues(alpha: 0.5),
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      s == ReceiptStatus.pending
                          ? 'Pending'
                          : s == ReceiptStatus.confirmed
                              ? 'Confirmed'
                              : 'Rejected',
                      style: TextStyle(
                        color: selected
                            ? colors.$2
                            : AppColors.textSecondary,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  //  ITEMS
  // ═══════════════════════════════════════════════════════

  Widget _buildItemsSection(String currency) {
    return _Card(
      title: l10n.items,
      children: [
        for (int i = 0; i < _lines.length; i++) ...[
          _buildLineItem(i, currency),
          if (i < _lines.length - 1)
            Divider(
                height: 20,
                color: AppColors.borderLight.withValues(alpha: 0.3)),
        ],
      ],
    );
  }

  Widget _buildLineItem(int idx, String currency) {
    final l = _lines[idx];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.nameCtrl.text,
          style: TextStyle(
            color: AppColors.primaryNavy,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _textField(
                controller: l.receivedCtrl,
                label: l10n.received,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _textField(
                controller: l.costCtrl,
                label: l10n.unitCost,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  //  SYNC TOGGLE
  // ═══════════════════════════════════════════════════════

  Widget _buildSyncToggle() {
    return _Card(
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _syncToInventory
                    ? const Color(0xFFECFDF5)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.inventory_rounded,
                size: 18,
                color: _syncToInventory
                    ? AppColors.chartGreen
                    : AppColors.textTertiary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                     'Update Inventory Stock',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                     'Adjust stock for quantity changes',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: _syncToInventory,
              onChanged: (v) => setState(() => _syncToInventory = v),
              activeTrackColor: AppColors.chartGreen,
              activeThumbColor: Colors.white,
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  //  NOTES
  // ═══════════════════════════════════════════════════════

  Widget _buildNotesSection() {
    return _Card(
      title: l10n.notes,
      children: [
        _textField(
          controller: _notesCtrl,
          label: l10n.deliveryNotesOptional,
          maxLines: 3,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  //  BOTTOM CTA
  // ═══════════════════════════════════════════════════════

  Widget _buildBottomCTA(String currency, NumberFormat fmt) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
              color: AppColors.borderLight.withValues(alpha: 0.5)),
        ),
      ),
      child: GestureDetector(
        onTap: _save,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.accentOrange,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.accentOrange.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
             'Save Changes · $currency ${fmt.format(_totalCost)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  PRODUCT MATCHING
  // ═══════════════════════════════════════════════════════

  /// Matches a receipt item name to an inventory product.
  /// Handles multi-variant names like "Product — Variant" and "Product – Variant".
  (Product, String?)? _matchProductByName(String itemName, List<Product> products) {
    final nameLower = itemName.toLowerCase().trim();

    // 1. Exact match on product name
    for (final p in products) {
      if (p.name.toLowerCase() == nameLower) {
        return (p, p.variants.isNotEmpty ? p.variants.first.id : null);
      }
    }

    // 2. Try splitting on " — " (em dash) or " – " (en dash) or " - " (hyphen)
    for (final sep in [' \u2014 ', ' \u2013 ', ' - ']) {
      final idx = nameLower.indexOf(sep);
      if (idx > 0) {
        final baseName = nameLower.substring(0, idx).trim();
        final variantPart = nameLower.substring(idx + sep.length).trim();
        for (final p in products) {
          if (p.name.toLowerCase() == baseName) {
            for (final v in p.variants) {
              if (v.displayName.toLowerCase() == variantPart) {
                return (p, v.id);
              }
            }
            return (p, p.variants.isNotEmpty ? p.variants.first.id : null);
          }
        }
      }
    }

    // 3. Partial match: product name starts the item name
    for (final p in products) {
      if (nameLower.startsWith(p.name.toLowerCase())) {
        return (p, p.variants.isNotEmpty ? p.variants.first.id : null);
      }
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════
  //  SAVE
  // ═══════════════════════════════════════════════════════

  Future<void> _save() async {
    HapticFeedback.mediumImpact();

    final old = widget.receipt;

    // Ensure ALL products are loaded for accurate variant resolution
    await ref.read(inventoryProvider.notifier).loadAll();
    final products = ref.read(inventoryProvider).value ?? [];

    // Build updated items
    final updatedItems = <ReceiptItem>[];
    for (int i = 0; i < _lines.length; i++) {
      final l = _lines[i];
      final received = double.tryParse(l.receivedCtrl.text) ?? 0;
      final cost = double.tryParse(l.costCtrl.text) ?? 0;
      final ordered = double.tryParse(l.orderedCtrl.text) ?? received;
      // L4: clamp receivedQty ≤ orderedQty
      final clampedReceived = ordered > 0 ? received.clamp(0.0, ordered) : received;

      // Try to resolve productId if not already set
      String? pid = l.productId;
      Product? matchedProduct;
      if (pid == null) {
        final match = _matchProductByName(l.nameCtrl.text.trim(), products);
        if (match != null) {
          pid = match.$1.id;
          matchedProduct = match.$1;
        }
      } else {
        matchedProduct = products.cast<dynamic>().firstWhere(
              (p) => p.id == pid,
              orElse: () => null,
            ) as Product?;
      }

      // Resolve variant ID from actual product
      String? resolvedVariantId = l.variantId;
      if (resolvedVariantId == null || resolvedVariantId.isEmpty) {
        if (pid != null && matchedProduct == null) {
          // We have pid but haven't looked up the product yet
          final match = _matchProductByName(l.nameCtrl.text.trim(), products);
          matchedProduct = match?.$1;
          resolvedVariantId = match?.$2;
        } else if (matchedProduct != null) {
          resolvedVariantId = matchedProduct.variants.isNotEmpty
              ? matchedProduct.variants.first.id
              : null;
        }
      }

      updatedItems.add(ReceiptItem(
        productId: pid,
        variantId: resolvedVariantId,
        productName: l.nameCtrl.text.trim(),
        orderedQty: ordered,
        receivedQty: clampedReceived,
        unitCost: cost,
      ));
    }

    // Inventory adjustments: delta between old and new received quantities
    if (_syncToInventory) {
      for (int i = 0; i < _lines.length; i++) {
        final l = _lines[i];
        final rawNewQty = double.tryParse(l.receivedCtrl.text) ?? 0;
        final orderedQty = double.tryParse(l.orderedCtrl.text) ?? rawNewQty;
        final newQty = orderedQty > 0 ? rawNewQty.clamp(0.0, orderedQty) : rawNewQty;
        final oldQty = l.originalReceivedQty;
        final delta = (newQty - oldQty).toInt();
        if (delta != 0) {
          final String? pid = updatedItems[i].productId;
          final String? variantId = updatedItems[i].variantId;
          if (pid != null && variantId != null) {
            await ref.read(inventoryProvider.notifier).adjustStock(
                  pid,
                  variantId,
                  delta,
                  delta > 0
                      ? 'Receipt edit \u2013 added'
                      :  'Receipt edit \u2013 reduced',
                  valuationMethod: ref.read(appSettingsProvider).valuationMethod,
                );
          }
        }
      }
    }

    // Build updated receipt
    final updated = old.copyWith(
      date: _receiptDate,
      status: _status,
      items: updatedItems,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      updatedAt: DateTime.now(),
    );

    // Persist
    ref.read(goodsReceiptsProvider.notifier).updateReceipt(updated);

    // Update linked purchase receivedQty
    if (old.purchaseId != null) {
      final purchases = ref.read(purchasesProvider).value ?? [];
      final pIdx = purchases.indexWhere((p) => p.id == old.purchaseId);
      if (pIdx >= 0) {
        final purchase = purchases[pIdx];
        final updatedPurchaseItems = purchase.items.map((pi) {
          // Find the matching receipt line by name
          final oldMatch = old.items.where(
              (ri) => ri.productName.toLowerCase() == pi.name.toLowerCase());
          final newMatch = updatedItems.where(
              (ri) => ri.productName.toLowerCase() == pi.name.toLowerCase());

          if (oldMatch.isNotEmpty && newMatch.isNotEmpty) {
            final delta =
                newMatch.first.receivedQty.toInt() -
                oldMatch.first.receivedQty.toInt();
            if (delta != 0) {
              return pi.copyWith(
                  receivedQty:
                      (pi.receivedQty + delta).clamp(0, pi.qty));
            }
          }
          return pi;
        }).toList();

        ref.read(purchasesProvider.notifier).updatePurchase(
              purchase.copyWith(items: updatedPurchaseItems),
            );
      }
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    context.safePop();

    messenger.showSnackBar(SnackBar(
      content: Text(l10n.receiptUpdated),
      backgroundColor: AppColors.primaryNavy,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ═══════════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════════

  Widget _textField({
    required TextEditingController controller,
    required String label,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: onChanged,
      style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            TextStyle(color: AppColors.textTertiary, fontSize: 13),
        filled: true,
        fillColor: AppColors.surfaceSubtle,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: AppColors.borderLight.withValues(alpha: 0.7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.primaryNavy, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  (Color, Color) _statusChipColors(ReceiptStatus s) {
    switch (s) {
      case ReceiptStatus.confirmed:
        return (AppColors.badgeBgPositive, const Color(0xFF166534));
      case ReceiptStatus.rejected:
        return (AppColors.badgeBgNegative, AppColors.badgeTextNegative);
      case ReceiptStatus.pending:
        return (const Color(0xFFF3E8FF), AppColors.shopifyPurple);
    }
  }
}

// ── Private helpers ────────────────────────────────────────

class _EditLine {
  final String? productId;
  final String? variantId;
  final TextEditingController nameCtrl;
  final TextEditingController orderedCtrl;
  final TextEditingController receivedCtrl;
  final TextEditingController costCtrl;
  final double originalReceivedQty;

  _EditLine({
    this.productId,
    this.variantId,
    required this.nameCtrl,
    required this.orderedCtrl,
    required this.receivedCtrl,
    required this.costCtrl,
    required this.originalReceivedQty,
  });
}

class _Card extends StatelessWidget {
  final String? title;
  final List<Widget> children;

  const _Card({this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppColors.borderLight.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
          ],
          ...children,
        ],
      ),
    );
  }
}
