import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../shared/models/goods_receipt_model.dart';
import '../../shared/models/product_model.dart';
import '../../shared/models/purchase_model.dart';
import '../../shared/models/supplier_model.dart';
import '../../shared/widgets/discard_changes_dialog.dart';
import '../../shared/utils/safe_pop.dart';
import '../../l10n/app_localizations.dart';

/// Screen to receive goods against a purchase order (Growth tier).
class ReceiveGoodsScreen extends ConsumerStatefulWidget {
  final String? preselectedSupplierId;
  final String? preselectedPurchaseId;

  const ReceiveGoodsScreen({
    super.key,
    this.preselectedSupplierId,
    this.preselectedPurchaseId,
  });

  @override
  ConsumerState<ReceiveGoodsScreen> createState() =>
      _ReceiveGoodsScreenState();
}

class _ReceiveGoodsScreenState extends ConsumerState<ReceiveGoodsScreen> {
  AppLocalizations get l10n => AppLocalizations.of(context)!;

  static const List<String> _variantNameSeparators = [' \u2014 ', ' \u2013 ', ' - '];

  final _notesCtrl = TextEditingController();
  DateTime _receiptDate = DateTime.now();
  String? _selectedSupplierId;
  String? _selectedSupplierName;
  String? _selectedPurchaseId;
  final List<_ReceiptLine> _items = [];
  bool _syncToInventory = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedSupplierId = widget.preselectedSupplierId;
    _addLine();

    // Auto-populate from preselected purchase
    if (widget.preselectedPurchaseId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final purchases = ref.read(purchasesProvider).value ?? [];
        final match = purchases
            .where((p) => p.id == widget.preselectedPurchaseId)
            .toList();
        if (match.isNotEmpty) {
          _populateFromPurchase(match.first);
        }
      });
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    for (final li in _items) {
      li.nameCtrl.dispose();
      li.orderedCtrl.dispose();
      li.receivedCtrl.dispose();
      li.costCtrl.dispose();
    }
    super.dispose();
  }

  void _addLine() {
    setState(() {
      _items.add(_ReceiptLine(
        nameCtrl: TextEditingController(),
        orderedCtrl: TextEditingController(),
        receivedCtrl: TextEditingController(),
        costCtrl: TextEditingController(),
      ));
    });
  }

  void _removeLine(int idx) {
    if (_items.length <= 1) return;
    setState(() {
      _items[idx].nameCtrl.dispose();
      _items[idx].orderedCtrl.dispose();
      _items[idx].receivedCtrl.dispose();
      _items[idx].costCtrl.dispose();
      _items.removeAt(idx);
    });
  }

  double get _totalCost {
    double sum = 0;
    for (final li in _items) {
      final received = double.tryParse(li.receivedCtrl.text) ?? 0;
      final cost = double.tryParse(li.costCtrl.text) ?? 0;
      sum += received * cost;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyProvider);
    final suppliers = ref.watch(suppliersProvider).value ?? [];

    // Resolve supplier name
    if (_selectedSupplierId != null && _selectedSupplierName == null) {
      final match = suppliers
          .where((s) => s.id == _selectedSupplierId)
          .toList();
      if (match.isNotEmpty) _selectedSupplierName = match.first.name;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await showDiscardChangesDialog(context);
        if (shouldPop && context.mounted) context.safePop();
      },
      child: Scaffold(
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
                    _buildSupplierSection(suppliers)
                        .animate()
                        .fadeIn(duration: 250.ms),
                    const SizedBox(height: 14),
                    _buildItemsSection(currency)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 60.ms),
                    const SizedBox(height: 14),
                    _buildTotalSection(currency)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 120.ms),
                    const SizedBox(height: 14),
                    _buildSyncToggle()
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 180.ms),
                    const SizedBox(height: 14),
                    _buildNotesSection()
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 240.ms),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomSheet: _buildBottomCTA(currency),
    ),
    );
  }

  // ── Header ───────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
              color: AppColors.borderLight.withValues(alpha: 0.3)),
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
                l10n.receiveGoods,
                style: AppTypography.h2.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Semantics(
            button: true,
            label: l10n.saveGoodsReceipt,
            child: GestureDetector(
            onTap: _save,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                l10n.save,
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.accentOrange,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          ),
        ],
      ),
    );
  }

  // ── Supplier ─────────────────────────────────────────────

  Widget _buildSupplierSection(List<Supplier> suppliers) {
    final purchases = ref.watch(purchasesProvider).value ?? [];
    final supplierPurchases = _selectedSupplierId != null
        ? purchases.where((p) =>
            p.supplierId == _selectedSupplierId && !p.isFullyReceived).toList()
        : <Purchase>[];

    return _Card(
      title: l10n.supplierAndPurchase,
      children: [
        GestureDetector(
          onTap: () => _pickSupplier(suppliers),
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
                Icon(Icons.storefront_rounded,
                    size: 20, color: AppColors.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedSupplierName ?? l10n.selectSupplier,
                    style: AppTypography.bodyMedium.copyWith(
                      color: _selectedSupplierName != null
                          ? AppColors.textPrimary
                          : AppColors.textTertiary,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildDatePicker(),
        // Purchase picker (only shown when a supplier is selected and has unfulfilled purchases)
        if (supplierPurchases.isNotEmpty) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => _pickPurchase(supplierPurchases),
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
                  Icon(Icons.receipt_long_rounded,
                      size: 20, color: AppColors.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedPurchaseId != null
                          ? (supplierPurchases.firstWhere((p) => p.id == _selectedPurchaseId, orElse: () => supplierPurchases.first).referenceNo.isNotEmpty ? l10n.poPrefix(supplierPurchases.firstWhere((p) => p.id == _selectedPurchaseId, orElse: () => supplierPurchases.first).referenceNo) : _selectedPurchaseId!.substring(0, 8))
                          : l10n.linkToPurchaseOrderOptional,
                      style: AppTypography.bodyMedium.copyWith(
                        color: _selectedPurchaseId != null
                            ? AppColors.textPrimary
                            : AppColors.textTertiary,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 20, color: AppColors.textTertiary),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _pickSupplier(List<Supplier> suppliers) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              child: Text(l10n.chooseSupplier,
                  style: AppTypography.h3.copyWith(
                      color: AppColors.primaryNavy,
                      fontWeight: FontWeight.w700)),
            ),
            for (final s in suppliers)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFF1F5F9),
                  child: Text(s.name.isNotEmpty ? s.name[0] : '?',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700)),
                ),
                title: Text(s.name),
                trailing: _selectedSupplierId == s.id
                    ? const Icon(Icons.check_rounded,
                        color: AppColors.success)
                    : null,
                onTap: () {
                  setState(() {
                    _selectedSupplierId = s.id;
                    _selectedSupplierName = s.name;
                    _selectedPurchaseId = null; // Reset purchase on supplier change
                  });
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _pickPurchase(List<Purchase> purchases) {
    final fmt = NumberFormat('#,##0', 'en');
    final currency = ref.read(currencyProvider);
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(l10n.linkToPurchaseOrder,
                  style: AppTypography.h3.copyWith(
                      color: AppColors.primaryNavy,
                      fontWeight: FontWeight.w700)),
            ),
            // Option: no purchase (manual entry)
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFF1F5F9),
                child: Icon(Icons.edit_note_rounded, size: 20),
              ),
              title: Text(l10n.manualEntryNoPO),
              trailing: _selectedPurchaseId == null
                  ? const Icon(Icons.check_rounded, color: AppColors.success)
                  : null,
              onTap: () {
                setState(() => _selectedPurchaseId = null);
                Navigator.pop(ctx);
              },
            ),
            for (final p in purchases)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFF1F5F9),
                  child: Text(
                    p.referenceNo.isNotEmpty
                        ? p.referenceNo.substring(0, 1)
                        : '#',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                title: Text(
                  p.referenceNo.isNotEmpty
                      ? l10n.poPrefix(p.referenceNo)
                      : l10n.purchaseFallback(p.id.substring(0, 8)),
                ),
                subtitle: Text(
                  '${p.items.length} items · $currency ${fmt.format(p.total)} · ${DateFormat('MMM dd').format(p.date)}',
                  style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
                trailing: _selectedPurchaseId == p.id
                    ? const Icon(Icons.check_rounded, color: AppColors.success)
                    : null,
                onTap: () async {
                  await _populateFromPurchase(p);
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Populate receipt lines from a purchase order's items.
  Future<void> _populateFromPurchase(Purchase purchase) async {
    // Dispose old controllers
    for (final li in _items) {
      li.nameCtrl.dispose();
      li.orderedCtrl.dispose();
      li.receivedCtrl.dispose();
      li.costCtrl.dispose();
    }

    // Load all products (async) so we have full list for matching
    await ref.read(inventoryProvider.notifier).loadAll();
    final products = ref.read(inventoryProvider).value ?? [];

    setState(() {
      _selectedPurchaseId = purchase.id;
      _items.clear();
      for (final pi in purchase.items) {
        final remaining = pi.qty - pi.receivedQty;
        if (remaining <= 0) continue; // Skip fully received items

        // Robust product + variant matching
        final match = _matchProductByName(pi.name, products);

        _items.add(_ReceiptLine(
          productId: match?.$1.id,
          nameCtrl: TextEditingController(text: pi.name),
          orderedCtrl: TextEditingController(text: remaining.toString()),
          receivedCtrl:
              TextEditingController(text: remaining.round().toString()),
          costCtrl: TextEditingController(text: pi.unitPrice.toStringAsFixed(2)),
        )..variantId = match?.$2);
      }
      // If all items are already fully received (shouldn't happen but safety)
      if (_items.isEmpty) _addLine();
    });
  }

  /// Matches a purchase item name to an inventory product.
  /// Handles multi-variant names like "Product — Variant" and "Product – Variant".
  /// Returns (Product, variantId) or null.
  (Product, String?)? _matchProductByName(String itemName, List<Product> products) {
    final nameLower = itemName.toLowerCase().trim();

    // 1. Exact match on product name
    for (final p in products) {
      if (p.name.toLowerCase() == nameLower) {
        return (p, p.variants.isNotEmpty ? p.variants.first.id : null);
      }
    }

    // 2. Try splitting on " — " (em dash) or " – " (en dash) or " - " (hyphen)
    //    Purchase items for multi-variant products are stored as "ProductName — VariantDisplayName"
    for (final sep in _variantNameSeparators) {
      final idx = nameLower.indexOf(sep);
      if (idx > 0) {
        final baseName = nameLower.substring(0, idx).trim();
        final variantPart = nameLower.substring(idx + sep.length).trim();
        for (final p in products) {
          if (p.name.toLowerCase() == baseName) {
            // Try to find the specific variant by display name
            for (final v in p.variants) {
              if (v.displayName.toLowerCase() == variantPart) {
                return (p, v.id);
              }
            }
            // Fallback: base name matched but variant name didn't — use first variant
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

  Widget _buildDatePicker() {
    final formatted = DateFormat('MMM dd, yyyy').format(_receiptDate);
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _receiptDate,
          firstDate: DateTime(DateTime.now().year - 1, 1, 1),
          lastDate: DateTime.now().add(const Duration(days: 1)),
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
    );
  }

  // ── Items ────────────────────────────────────────────────

  Widget _buildItemsSection(String currency) {
    return _Card(
      title: l10n.itemsReceived,
      trailing: GestureDetector(
        onTap: _addLine,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.accentOrange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded,
                  size: 16, color: AppColors.accentOrange),
              const SizedBox(width: 4),
              Text(l10n.add,
                  style: AppTypography.labelSmall.copyWith(
                      color: AppColors.accentOrange,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
      children: [
        for (int i = 0; i < _items.length; i++) ...[
          if (i > 0)
            Divider(
                color: AppColors.borderLight.withValues(alpha: 0.5),
                height: 24),
          _buildLineRow(i, currency),
        ],
      ],
    );
  }

  Widget _buildLineRow(int idx, String currency) {
    final li = _items[idx];
    final products = ref.watch(inventoryProvider).value ?? [];
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _productAutocomplete(
                controller: li.nameCtrl,
                products: products,
                onSelected: (product) {
                  if (product.hasVariants && product.variants.length > 1) {
                    _showReceiptVariantPicker(idx, product, li);
                  } else {
                    final variant = product.variants.first;
                    setState(() {
                      li.productId = product.id;
                      li.variantId = variant.id;
                      li.nameCtrl.text = product.name;
                      if (li.costCtrl.text.isEmpty ||
                          li.costCtrl.text == '0.00') {
                        li.costCtrl.text =
                            variant.costPrice.toStringAsFixed(2);
                      }
                    });
                  }
                },
              ),
            ),
            if (_items.length > 1) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _removeLine(idx),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.dangerLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.remove_rounded,
                      size: 18, color: AppColors.danger),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _compactField(
                controller: li.orderedCtrl,
                label: l10n.ordered,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _compactField(
                controller: li.receivedCtrl,
                label: l10n.received,
                keyboardType: const TextInputType.numberWithOptions(decimal: false),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _compactField(
                controller: li.costCtrl,
                label: l10n.unitCost,
                prefix: currency,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Total ────────────────────────────────────────────────

  Widget _buildTotalSection(String currency) {
    final fmt = NumberFormat('#,##0.00', 'en');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFF10B981).withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(l10n.totalCost,
              style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700)),
          Text('$currency ${fmt.format(_totalCost)}',
              style: AppTypography.labelMedium.copyWith(
                  color: const Color(0xFF10B981),
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // ── Sync Toggle ──────────────────────────────────────────

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
                    ? const Color(0xFF10B981)
                    : AppColors.textTertiary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.updateInventoryStock,
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.increaseProductQuantities,
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
              activeTrackColor: const Color(0xFF10B981),
              activeThumbColor: Colors.white,
            ),
          ],
        ),
      ],
    );
  }

  // ── Notes ────────────────────────────────────────────────

  Widget _buildNotesSection() {
    return _Card(
      title: l10n.notes,
      children: [
        _textField(
          controller: _notesCtrl,
          hint: l10n.deliveryNotesOptional,
          icon: Icons.notes_rounded,
          maxLines: 3,
        ),
      ],
    );
  }

  // ── Bottom CTA ───────────────────────────────────────────

  Widget _buildBottomCTA(String currency) {
    final fmt = NumberFormat('#,##0.00', 'en');
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
        onTap: _isSaving ? null : _save,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: _isSaving
                ? AppColors.accentOrange.withValues(alpha: 0.6)
                : AppColors.accentOrange,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.accentOrange.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: _isSaving
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      l10n.saving,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                )
              : Text(
                  l10n.confirmReceiptTotal(currency, fmt.format(_totalCost)),
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

  // ── Save ─────────────────────────────────────────────────

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      await _doSave();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _doSave() async {
    if (_selectedSupplierId == null) {
      _showError(l10n.pleaseSelectSupplier);
      return;
    }

    bool hasValid = false;
    for (final li in _items) {
      if (li.nameCtrl.text.trim().isNotEmpty &&
          (int.tryParse(li.receivedCtrl.text) ?? 0) > 0) {
        hasValid = true;
        break;
      }
    }

    if (!hasValid) {
      _showError(l10n.addAtLeastOneItem);
      return;
    }

    // Validate received qty does not exceed ordered qty (when linked to a purchase)
    if (_selectedPurchaseId != null) {
      for (final li in _items) {
        final received = int.tryParse(li.receivedCtrl.text) ?? 0;
        final ordered = double.tryParse(li.orderedCtrl.text) ?? 0;
        if (received <= 0) continue;
        if (ordered > 0 && received.toDouble() > ordered) {
          _showError(
            l10n.receivedExceedsOrdered(
              li.nameCtrl.text.trim(),
              received.toString(),
              ordered.toString(),
            ),
          );
          return;
        }
      }
    }

    HapticFeedback.mediumImpact();

    final uid = ref.read(authProvider).user?.id ?? 'unknown';
    final receiptItems = <ReceiptItem>[];

    for (final li in _items) {
      final name = li.nameCtrl.text.trim();
      final received = int.tryParse(li.receivedCtrl.text) ?? 0;
      if (name.isEmpty || received <= 0) continue;

      receiptItems.add(ReceiptItem(
        productId: li.productId,
        variantId: li.variantId,
        productName: name,
        orderedQty: double.tryParse(li.orderedCtrl.text) ?? received.toDouble(),
        receivedQty: received.toDouble(),
        unitCost: double.tryParse(li.costCtrl.text) ?? 0,
      ));
    }

    final receipt = GoodsReceipt(
      id: const Uuid().v4(),
      userId: uid,
      purchaseId: _selectedPurchaseId,
      supplierId: _selectedSupplierId!,
      supplierName: _selectedSupplierName ?? '',
      date: _receiptDate,
      items: receiptItems,
      status: ReceiptStatus.confirmed,
      notes: _notesCtrl.text.trim().isEmpty
          ? null
          : _notesCtrl.text.trim(),
      createdAt: DateTime.now(),
    );

    final receiptResult =
        await ref.read(goodsReceiptsProvider.notifier).addReceipt(receipt);
    if (!receiptResult.isSuccess) {
      _showError(receiptResult.error ?? l10n.failedToSaveGoodsReceipt);
      return;
    }

    // Sync received quantities to inventory stock
    if (_syncToInventory) {
      // Ensure ALL products are loaded (not just the first page)
      await ref.read(inventoryProvider.notifier).loadAll();
      final products = ref.read(inventoryProvider).value ?? [];
      int syncErrors = 0;

      for (final item in receiptItems) {
        String? pid = item.productId;
        String? variantId = item.variantId;

        // If productId wasn't set, use robust name-matching
        if (pid == null) {
          final match = _matchProductByName(item.productName, products);
          if (match != null) {
            pid = match.$1.id;
            variantId ??= match.$2;
          }
        }

        if (pid != null && item.receivedQty > 0) {
          // Resolve variant ID from the actual product if still missing
          Product? matchedProduct;
          if (variantId == null || variantId.isEmpty) {
            matchedProduct = products
                .whereType<Product>()
                .where((p) => p.id == pid)
                .firstOrNull;
            if (matchedProduct != null) {
              variantId = matchedProduct.variants.isNotEmpty
                  ? matchedProduct.variants.first.id
                  : null;
            }
          } else {
            matchedProduct = products
                .whereType<Product>()
                .where((p) => p.id == pid)
                .firstOrNull;
          }

          // Skip cost layer creation for manufactured products
          final skipCost = matchedProduct?.isManufactured ?? false;

          if (variantId != null) {
            final result = await ref.read(inventoryProvider.notifier).adjustStock(
                  pid,
                  variantId,
              item.receivedQty.round(),
                  'Restock \u2013 goods receipt',
                  unitCost: item.unitCost,
                  valuationMethod: ref.read(appSettingsProvider).valuationMethod,
                  supplierName: _selectedSupplierName,
                  skipCostLayer: skipCost,
                );
            if (!result.isSuccess) syncErrors++;
          } else {
            syncErrors++;
          }
        }
      }

      if (syncErrors > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.itemsCouldNotSync(syncErrors)),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    }

    // Update linked purchase's receivedQty per item (Step 8)
    if (_selectedPurchaseId != null) {
      final purchases = ref.read(purchasesProvider).value ?? [];
      final matchIdx = purchases.indexWhere((p) => p.id == _selectedPurchaseId);
      if (matchIdx >= 0) {
        final purchase = purchases[matchIdx];
        final updatedItems = purchase.items.map((pi) {
          // Find matching receipt item by name
          final matched = receiptItems.where((ri) =>
              ri.productName.toLowerCase() == pi.name.toLowerCase());
          if (matched.isNotEmpty) {
            final addedQty = matched.first.receivedQty.round();
            return pi.copyWith(receivedQty: pi.receivedQty + addedQty);
          }
          return pi;
        }).toList();

        final updatedPurchase = purchase.copyWith(items: updatedItems);
        ref.read(purchasesProvider.notifier).updatePurchase(updatedPurchase);
      }
    }

    if (!mounted) return;
    final currency = ref.read(currencyProvider);
    final fmt = NumberFormat('#,##0.00', 'en');
    final messenger = ScaffoldMessenger.of(context);

    // Build price change alerts (≥10% change from previous cost)
    final allProducts = ref.read(inventoryProvider).value ?? [];
    final priceAlerts = <String>[];
    for (final item in receiptItems) {
      if (item.unitCost <= 0 || item.productId == null) continue;
      final product = allProducts
          .whereType<Product>()
          .where((p) => p.id == item.productId)
          .firstOrNull;
      if (product == null) continue;
      final variant = item.variantId != null
          ? product.variantById(item.variantId!)
          : product.variants.firstOrNull;
      if (variant == null || variant.costPrice <= 0) continue;
      final prev = variant.costPrice;
      final newCost = item.unitCost;
      final changePct = ((newCost - prev) / prev * 100).roundToDouble();
      if (changePct.abs() >= 10) {
        final dir = changePct > 0 ? '↑' : '↓';
        priceAlerts.add(
            '${item.productName}: $dir${changePct.abs().toStringAsFixed(0)}% ($currency ${fmt.format(prev)} → $currency ${fmt.format(newCost)})');
      }
    }

    context.safePop();

    if (priceAlerts.isNotEmpty && mounted) {
      _showPriceAlertDialog(priceAlerts);
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text(
            l10n.receivedGoodsWorth(currency, fmt.format(receipt.totalCost))),
        backgroundColor: AppColors.primaryNavy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  void _showPriceAlertDialog(List<String> alerts) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.trending_up_rounded,
                color: AppColors.accentOrange, size: 22),
            const SizedBox(width: 8),
            Text(
              l10n.priceChangeAlert,
              style: AppTypography.h3.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.significantCostChange,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            ...alerts.map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ',
                          style: TextStyle(
                              color: AppColors.accentOrange,
                              fontWeight: FontWeight.w700)),
                      Expanded(
                        child: Text(a,
                            style: AppTypography.bodySmall
                                .copyWith(color: AppColors.textPrimary)),
                      ),
                    ],
                  ),
                )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              l10n.gotIt,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.primaryNavy,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.danger,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Helpers ──────────────────────────────────────────────

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    IconData? icon,
    String? prefixText,
    TextInputType? keyboardType,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTypography.bodySmall
            .copyWith(color: AppColors.textTertiary),
        prefixIcon: icon != null
            ? Icon(icon, size: 20, color: AppColors.textSecondary)
            : null,
        prefixText: prefixText != null ? '$prefixText ' : null,
        prefixStyle: AppTypography.bodyMedium.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 44, minHeight: 0),
        filled: true,
        fillColor: AppColors.surfaceSubtle,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: AppColors.borderLight.withValues(alpha: 0.7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
              color: AppColors.primaryNavy, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  /// Compact number field with a floating label instead of hint + icon
  /// so text isn't truncated on small screens.
  Widget _compactField({
    required TextEditingController controller,
    required String label,
    String? prefix,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      style: AppTypography.bodyMedium.copyWith(
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: AppColors.textTertiary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        prefixText: prefix != null ? '$prefix ' : null,
        prefixStyle: AppTypography.bodyMedium.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: AppColors.surfaceSubtle,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: AppColors.borderLight.withValues(alpha: 0.7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
              color: AppColors.primaryNavy, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    );
  }

  /// Shows variant picker bottom sheet for multi-variant products on the
  /// receive goods screen.
  void _showReceiptVariantPicker(int idx, Product product, _ReceiptLine li) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.selectVariantTitle(product.name),
                style: AppTypography.h3.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: product.variants.length,
                separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: AppColors.borderLight.withValues(alpha: 0.3)),
                itemBuilder: (_, i) {
                  final v = product.variants[i];
                  final isDefault =
                      !product.hasVariants || product.variants.length == 1;
                  final variantLabel =
                      isDefault ? product.name : '${product.name} — ${v.localizedDisplayName(l10n)}';
                  return ListTile(
                    title: Text(
                      variantLabel,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.primaryNavy,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      l10n.costStockInfo(v.costPrice.toStringAsFixed(2), v.currentStock.toString()),
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textTertiary),
                    ),
                    trailing: v.currentStock <= 0
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(l10n.outLabel,
                                style: AppTypography.caption
                                    .copyWith(color: AppColors.danger)),
                          )
                        : null,
                    onTap: () {
                      context.safePop();
                      setState(() {
                        li.productId = product.id;
                        li.variantId = v.id;
                        li.nameCtrl.text = variantLabel;
                        li.costCtrl.text = v.costPrice > 0
                            ? v.costPrice.toStringAsFixed(2)
                            : '';
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Autocomplete product name field — searches inventory products & raw
  /// materials and lets the user pick or type freely.
  Widget _productAutocomplete({
    required TextEditingController controller,
    required List<dynamic> products,
    required ValueChanged<Product> onSelected,
  }) {
    return Autocomplete<Product>(
      displayStringForOption: (p) => p.name,
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) return const Iterable.empty();
        final query = textEditingValue.text.toLowerCase();
        return products.cast<Product>().where(
              (p) => p.name.toLowerCase().contains(query),
            );
      },
      onSelected: (product) => onSelected(product),
      fieldViewBuilder: (ctx, textController, focusNode, onFieldSubmitted) {
        // Sync the external controller with autocomplete's internal one
        // (guard against disposed controller after row removal)
        try {
          if (textController.text != controller.text) {
            textController.text = controller.text;
          }
        } catch (_) {
          // controller already disposed — nothing to sync
        }
        return TextField(
          controller: textController,
          focusNode: focusNode,
          onChanged: (value) {
            // Sync free-text typing back to the external controller
            try {
              if (controller.text != value) {
                controller.text = value;
              }
            } catch (_) {
              // controller disposed — ignore
            }
          },
          decoration: InputDecoration(
            hintText: l10n.searchProductOrMaterial,
            hintStyle: AppTypography.bodySmall
                .copyWith(color: AppColors.textTertiary),
            prefixIcon: const Icon(Icons.search_rounded,
                size: 20, color: AppColors.textSecondary),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 44, minHeight: 0),
            filled: true,
            fillColor: AppColors.surfaceSubtle,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: AppColors.borderLight.withValues(alpha: 0.7)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                  color: AppColors.primaryNavy, width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        );
      },
      optionsViewBuilder: (ctx, onSel, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200),
              width: 280,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.borderLight.withValues(alpha: 0.5)),
              ),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: AppColors.borderLight.withValues(alpha: 0.3)),
                itemBuilder: (_, i) {
                  final product = options.elementAt(i);
                  final isMulti = product.hasVariants && product.variants.length > 1;
                  return ListTile(
                    dense: true,
                    leading: product.imageUrl != null && product.imageUrl!.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              product.imageUrl!,
                              width: 32,
                              height: 32,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Icon(
                                product.isMaterial
                                    ? Icons.science_rounded
                                    : Icons.inventory_2_rounded,
                                size: 18,
                                color: product.isMaterial
                                    ? const Color(0xFFE67E22)
                                    : const Color(0xFF7C3AED),
                              ),
                            ),
                          )
                        : Icon(
                            product.isMaterial
                                ? Icons.science_rounded
                                : Icons.inventory_2_rounded,
                            size: 18,
                            color: product.isMaterial
                                ? const Color(0xFFE67E22)
                                : const Color(0xFF7C3AED),
                          ),
                    title: Text(
                      product.name,
                      style: TextStyle(
                        color: AppColors.primaryNavy,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      isMulti
                          ? '${product.category} · ${product.variants.length} variants · Stock: ${product.currentStock}'
                          : '${product.category} · Stock: ${product.currentStock}',
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 11),
                    ),
                    trailing: isMulti
                        ? const Icon(Icons.chevron_right_rounded,
                            size: 18, color: AppColors.textTertiary)
                        : null,
                    onTap: () => onSel(product),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Private helpers ────────────────────────────────────────

class _ReceiptLine {
  String? productId;
  String? variantId;
  final TextEditingController nameCtrl;
  final TextEditingController orderedCtrl;
  final TextEditingController receivedCtrl;
  final TextEditingController costCtrl;

  _ReceiptLine({
    this.productId,
    required this.nameCtrl,
    required this.orderedCtrl,
    required this.receivedCtrl,
    required this.costCtrl,
  });
}

class _Card extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final List<Widget> children;

  const _Card({this.title, this.trailing, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.borderLight.withValues(alpha: 0.4)),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title!,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
          ],
          ...children,
        ],
      ),
    );
  }
}
