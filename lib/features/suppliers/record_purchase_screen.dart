import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_localizations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../shared/models/supplier_model.dart';
import '../../shared/models/product_model.dart';
import 'package:uuid/uuid.dart';
import '../../shared/models/purchase_model.dart';
import '../../features/suppliers/widgets/item_selection_sheet.dart';
import 'add_supplier_screen.dart';

/// Record Purchase form — supplier, items, totals, payment status.
class RecordPurchaseScreen extends ConsumerStatefulWidget {
  final String? preselectedSupplierId;
  final dynamic purchaseToEdit;
  const RecordPurchaseScreen({super.key, this.preselectedSupplierId, this.purchaseToEdit});

  @override
  ConsumerState<RecordPurchaseScreen> createState() =>
      _RecordPurchaseScreenState();
}

class _RecordPurchaseScreenState extends ConsumerState<RecordPurchaseScreen> {
  AppLocalizations get l10n => AppLocalizations.of(context)!;

  String _localizedItemTypeLabel(_ItemType type) {
    switch (type) {
      case _ItemType.rawMaterial:
        return l10n.rawMaterialLabel;
      case _ItemType.product:
        return l10n.productLabel;
      case _ItemType.manufacturingFee:
        return l10n.manufacturingFee;
    }
  }

  String? _selectedSupplierId;
  DateTime _purchaseDate = DateTime.now();
  final _refCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  int _paymentStatus = 0; // 0=Unpaid, 1=Partial, 2=Fully Paid
  DateTime? _dueDate;
  final _paidAmountCtrl = TextEditingController();

  final List<_PurchaseItem> _items = [];

  double get _subtotal =>
      _items.fold<double>(0, (s, item) => s + item.total);

  double get _tax {
    final v = double.tryParse(_taxCtrl.text) ?? 0;
    return v < 0 ? 0 : v;
  }

  double get _total => _subtotal + _tax;

  @override
  void initState() {
    super.initState();
    _selectedSupplierId = widget.preselectedSupplierId;
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    _taxCtrl.dispose();
    _paidAmountCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (_items.isEmpty) return;
    if (_selectedSupplierId == null) return;

    // Filter out invalid items (qty <= 0 or unitPrice <= 0)
    final validItems = _items.where((item) => item.qty > 0 && item.unitPrice > 0).toList();
    if (validItems.isEmpty) return;

    final suppliers = ref.read(suppliersProvider).value ?? [];
    final supplierId = _selectedSupplierId!;
    final supplierName = suppliers
        .cast<Supplier?>()
        .firstWhere((s) => s!.id == supplierId, orElse: () => null)
        ?.name ?? '';
    if (supplierId.isEmpty) return;

    final purchase = Purchase(
      id: const Uuid().v4(),
      supplierId: supplierId,
      supplierName: supplierName,
      date: _purchaseDate,
      referenceNo: _refCtrl.text.trim(),
      items: validItems.map((item) => PurchaseItem(
        name: item.name,
        category: item.category,
        qty: item.qty,
        unitPrice: item.unitPrice,
        productId: item.productId,
        variantId: item.variantId,
        variantName: item.variantName,
      )).toList(),
      tax: _tax,
      paymentStatus: _paymentStatus,
      amountPaid: _paymentStatus == 2
          ? (_subtotal + _tax)
          : (double.tryParse(_paidAmountCtrl.text) ?? 0).clamp(0, _subtotal + _tax).toDouble(),
      dueDate: _dueDate,
      createdAt: DateTime.now(),
    );

    ref.read(purchasesProvider.notifier).addPurchase(purchase);

    // Update supplier balance (increase by outstanding amount)
    final outstandingAmount = purchase.outstanding;
    if (outstandingAmount > 0) {
      ref.read(suppliersProvider.notifier).recordPurchase(
        supplierId,
        outstandingAmount,
        dueDate: _dueDate,
      );
    }

    HapticFeedback.mediumImpact();
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.purchaseRecorded),
        backgroundColor: AppColors.primaryNavy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(suppliersProvider).value ?? [];
    final inventory = ref.watch(inventoryProvider).value ?? [];
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Column(
                  children: [
                    // Details section
                    _buildDetailsSection(suppliers)
                        .animate()
                        .fadeIn(duration: 250.ms),
                    const SizedBox(height: 16),
                    // Items section
                    // Items section
                    _buildItemsSection(fmt, inventory, currency)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 60.ms),
                    const SizedBox(height: 16),
                    // Totals section
                    _buildTotalsSection(fmt, currency)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 120.ms),
                    const SizedBox(height: 16),
                    // Payment status section
                    _buildPaymentStatusSection(currency)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 180.ms),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      // Sticky confirm button
      bottomSheet: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.97),
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  l10n.confirmPurchase,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.check_rounded,
                    color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  HEADER
  // ═══════════════════════════════════════════════════════
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
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
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            iconSize: 26,
            color: AppColors.textTertiary,
          ),
          Expanded(
            child: Center(
              child: Text(
                l10n.recordPurchaseTitle,
                style: AppTypography.h2.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: _save,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                l10n.save,
                style: TextStyle(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  SECTION 1 — DETAILS
  // ═══════════════════════════════════════════════════════
  Widget _buildDetailsSection(List<Supplier> suppliers) {
    return _Card(
      title: l10n.detailsSection,
      children: [
        // Supplier picker
        _Label(l10n.supplier),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => _showSupplierPicker(suppliers),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.borderLight.withValues(alpha: 0.7),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedSupplierId != null
                        ? suppliers
                            .firstWhere((s) => s.id == _selectedSupplierId,
                                orElse: () => suppliers.first)
                            .name
                        : l10n.selectASupplier,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                    ),
                  ),
                ),
                Icon(Icons.expand_more_rounded,
                    color: AppColors.textTertiary, size: 22),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Date & Reference
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Label(l10n.purchaseDateLabel),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _purchaseDate,
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) setState(() => _purchaseDate = d);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color:
                              AppColors.borderLight.withValues(alpha: 0.7),
                        ),
                      ),
                      child: Text(
                        DateFormat('yyyy-MM-dd').format(_purchaseDate),
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Label(l10n.referenceNoLabel),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _refCtrl,
                    decoration: InputDecoration(
                      hintText: l10n.optionalHint,
                      hintStyle: TextStyle(
                          color: AppColors.textTertiary, fontSize: 14),
                      filled: true,
                      fillColor: AppColors.surfaceSubtle,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color:
                              AppColors.borderLight.withValues(alpha: 0.7),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color:
                              AppColors.borderLight.withValues(alpha: 0.7),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            BorderSide(color: AppColors.primaryNavy),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                    ),
                    style: TextStyle(
                        color: AppColors.textPrimary, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showSupplierPicker(List<Supplier> suppliers) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.selectSupplierTitle,
                style: AppTypography.h2.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ),
            ...suppliers.map((s) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: s.avatarBg,
                    child: Text(s.initials,
                        style: TextStyle(
                            color: s.avatarTextColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                  ),
                  title: Text(s.name),
                  subtitle: Text(s.category,
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 12)),
                  trailing: _selectedSupplierId == s.id
                      ? const Icon(Icons.check_rounded,
                          color: AppColors.accentOrange)
                      : null,
                  onTap: () {
                    setState(() => _selectedSupplierId = s.id);
                    Navigator.of(ctx).pop();
                  },
                )),
            // Add new supplier option
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.accentOrange.withValues(alpha: 0.1),
                child: const Icon(Icons.add_rounded,
                    color: AppColors.accentOrange, size: 20),
              ),
              title: Text(l10n.addNewSupplierPlus,
                  style: TextStyle(
                      color: AppColors.accentOrange,
                      fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AddSupplierScreen()),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  ADD ITEM TYPE PICKER
  // ═══════════════════════════════════════════════════════
  void _showAddItemTypePicker(List<Product> inventory, String currency) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.whatAreYouPurchasing,
                style: AppTypography.h2.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 16),
              ..._ItemType.values.map((type) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _addItemOfType(type, inventory, currency);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: type.bgColor.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: type.color.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: type.bgColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(type.icon, color: type.color, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _localizedItemTypeLabel(type),
                                style: TextStyle(
                                  color: AppColors.primaryNavy,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                type == _ItemType.rawMaterial
                                    ? l10n.materialsUsedInProduction
                                    : type == _ItemType.product
                                        ? l10n.finishedGoodsForResale
                                        : l10n.processingAndAssemblyCosts,
                                style: TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded,
                            color: AppColors.textTertiary, size: 16),
                      ],
                    ),
                  ),
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addItemOfType(_ItemType type, List<Product> inventory, String currency) async {
    if (type == _ItemType.manufacturingFee) {
      setState(() {
        _items.add(_PurchaseItem(
          name: '',
          category: 'Manufacturing Fee',
          itemType: type,
          qty: 1,
          unitPrice: 0,
        ));
      });
      return;
    }

    // Filter inventory based on type
    final filtered = type == _ItemType.rawMaterial
        ? inventory.where((p) => p.isMaterial).toList()
        : inventory.where((p) => !p.isMaterial).toList();

    final result = await showModalBottomSheet<ItemSelectionResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ItemSelectionSheet(
        inventory: filtered,
        currency: currency,
      ),
    );

    if (result != null) {
      setState(() {
        if (result.product != null) {
          final p = result.product!;
          final v = result.variant;
          _items.add(_PurchaseItem(
            name: p.name,
            category: p.isMaterial ? 'Raw Material' : p.category,
            itemType: type,
            qty: 1,
            unitPrice: v?.costPrice ?? p.costPrice,
            productId: p.id,
            variantId: v?.id,
            variantName: v != null && !v.isDefault ? v.displayName : null,
          ));
        } else if (result.customName != null && result.customName!.isNotEmpty) {
          _items.add(_PurchaseItem(
            name: result.customName!,
            category: type == _ItemType.rawMaterial ? 'Raw Material' : 'General',
            itemType: type,
            qty: 1,
            unitPrice: 0,
          ));
        }
      });
    }
  }

  // ═══════════════════════════════════════════════════════
  //  SECTION 2 — ITEMS
  // ═══════════════════════════════════════════════════════
  Widget _buildItemsSection(NumberFormat fmt, List<Product> inventory, String currency) {
    return _Card(
      title: l10n.itemsPurchasedSection,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primaryNavy.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${_items.length} ${l10n.items}',
          style: TextStyle(
            color: AppColors.primaryNavy,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      children: [
        ..._items.asMap().entries.map((e) {
          final i = e.key;
          final item = e.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: i < _items.length - 1
                    ? Border(
                        bottom: BorderSide(
                          color:
                              AppColors.borderLight.withValues(alpha: 0.3),
                        ),
                      )
                    : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.itemLabel,
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        GestureDetector(
                          onTap: () async {
                            if (item.itemType == _ItemType.manufacturingFee) {
                              // For mfg fees, just let them edit inline (name field)
                              return;
                            }
                            final filtered = item.itemType == _ItemType.rawMaterial
                                ? inventory.where((p) => p.isMaterial).toList()
                                : inventory.where((p) => !p.isMaterial).toList();
                            final result = await showModalBottomSheet<ItemSelectionResult>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (context) => ItemSelectionSheet(inventory: filtered, currency: currency),
                            );

                            if (result != null) {
                              setState(() {
                                if (result.product != null) {
                                  final p = result.product!;
                                  final v = result.variant;
                                  _items[i] = item.copyWith(
                                    name: p.name,
                                    category: p.isMaterial ? 'Raw Material' : p.category,
                                    unitPrice: v?.costPrice ?? p.costPrice,
                                    productId: p.id,
                                    variantId: v?.id,
                                    variantName: v != null && !v.isDefault ? v.displayName : null,
                                  );
                                } else if (result.customName != null && result.customName!.isNotEmpty) {
                                  _items[i] = item.copyWith(
                                    name: result.customName,
                                    category: item.itemType == _ItemType.rawMaterial ? 'Raw Material' : 'General',
                                  );
                                }
                              });
                            }
                          },
                          child: item.itemType == _ItemType.manufacturingFee
                            ? SizedBox(
                                height: 32,
                                child: TextField(
                                  controller: TextEditingController(text: item.name),
                                  onChanged: (v) {
                                    _items[i] = item.copyWith(name: v);
                                  },
                                  decoration: InputDecoration(
                                    hintText: l10n.manufacturingFeeHint,
                                    hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                                    filled: true,
                                    fillColor: AppColors.surfaceSubtle,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: BorderSide(color: AppColors.borderLight.withValues(alpha: 0.5)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: BorderSide(color: AppColors.borderLight.withValues(alpha: 0.5)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: BorderSide(color: AppColors.primaryNavy),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                  ),
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              )
                            : Container(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceSubtle,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.name.isEmpty ? l10n.tapToSelectItem : item.name,
                                    style: TextStyle(
                                      color: item.name.isEmpty ? AppColors.textTertiary : AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(Icons.arrow_drop_down_rounded, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: item.itemType.bgColor,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _localizedItemTypeLabel(item.itemType),
                                  style: TextStyle(
                                    color: item.itemType.color,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (item.variantName != null || item.category.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    item.variantName != null
                                        ? '${item.category} • ${item.variantName}'
                                        : item.category,
                                    style: TextStyle(
                                      color: AppColors.textTertiary,
                                      fontSize: 11,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Qty
                  Column(
                    children: [
                      Text(
                        l10n.qtyLabel,
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      SizedBox(
                        width: 50,
                        height: 32,
                        child: TextField(
                          controller: TextEditingController(
                              text: '${item.qty}'),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          textAlign: TextAlign.center,
                          onChanged: (v) {
                            final parsed = int.tryParse(v);
                            if (parsed != null && parsed > 0) {
                              setState(() {
                                _items[i] = item.copyWith(qty: parsed);
                              });
                            }
                          },
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: AppColors.surfaceSubtle,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(
                                color: AppColors.borderLight
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(
                                color: AppColors.borderLight
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(
                                  color: AppColors.primaryNavy),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  // Unit price
                  Column(
                    children: [
                      Text(
                        l10n.unitPriceLabel,
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      SizedBox(
                        width: 72,
                        height: 32,
                        child: TextField(
                          controller: TextEditingController(
                              text: '${item.unitPrice.toInt()}'),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                          textAlign: TextAlign.right,
                          onChanged: (v) {
                            final parsed = double.tryParse(v);
                            if (parsed != null && parsed >= 0) {
                              setState(() {
                                _items[i] = item.copyWith(unitPrice: parsed);
                              });
                            }
                          },
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: AppColors.surfaceSubtle,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(
                                color: AppColors.borderLight
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(
                                color: AppColors.borderLight
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(
                                  color: AppColors.primaryNavy),
                            ),
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 6),
                          ),
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        // Add item button
        GestureDetector(
          onTap: () => _showAddItemTypePicker(inventory, currency),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.accentOrange.withValues(alpha: 0.3),
                style: BorderStyle.solid,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_circle_outline_rounded,
                    color: AppColors.accentOrange, size: 20),
                const SizedBox(width: 8),
                Text(
                  l10n.addItem,
                  style: TextStyle(
                    color: AppColors.accentOrange,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  //  SECTION 3 — TOTALS
  // ═══════════════════════════════════════════════════════
  Widget _buildTotalsSection(NumberFormat fmt, String currency) {
    return _Card(
      children: [
        // Subtotal
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l10n.subtotal,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
            Text('${fmt.format(_subtotal)} $currency',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 12),
        // Tax
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(l10n.taxLabel,
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
                Text(l10n.optionalLabel,
                    style: TextStyle(
                        color: AppColors.textTertiary, fontSize: 11)),
              ],
            ),
            Row(
              children: [
                SizedBox(
                  width: 90,
                  height: 32,
                  child: TextField(
                    controller: _taxCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                    textAlign: TextAlign.right,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: '0.00',
                      hintStyle: TextStyle(
                          color: AppColors.textTertiary, fontSize: 13),
                      filled: true,
                      fillColor: AppColors.surfaceSubtle,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color:
                              AppColors.borderLight.withValues(alpha: 0.5),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color:
                              AppColors.borderLight.withValues(alpha: 0.5),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            BorderSide(color: AppColors.primaryNavy),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(currency,
                    style: TextStyle(
                        color: AppColors.textTertiary, fontSize: 11)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Divider(color: AppColors.borderLight.withValues(alpha: 0.5)),
        const SizedBox(height: 12),
        // Total
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.totalAmountLabel,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: fmt.format(_total),
                    style: TextStyle(
                      color: AppColors.primaryNavy,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                  TextSpan(
                    text: ' $currency',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  //  SECTION 4 — PAYMENT STATUS
  // ═══════════════════════════════════════════════════════
  Widget _buildPaymentStatusSection(String currency) {
    final statusLabels = [l10n.unpaid, l10n.partial, l10n.fullyPaid];

    return _Card(
      title: l10n.paymentStatusSection,
      children: [
        // Segmented control
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: List.generate(3, (i) {
              final selected = _paymentStatus == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _paymentStatus = i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color:
                                    Colors.black.withValues(alpha: 0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : [],
                    ),
                    child: Text(
                      statusLabels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected
                            ? AppColors.primaryNavy
                            : AppColors.textTertiary,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 16),
        // Conditional fields
        if (_paymentStatus == 0) ...[
          // Unpaid — show due date
          _Label(l10n.dueDateLabel),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 30)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (d != null) setState(() => _dueDate = d);
            },
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.borderLight.withValues(alpha: 0.7),
                ),
              ),
              child: Text(
                _dueDate != null
                    ? DateFormat('yyyy-MM-dd').format(_dueDate!)
                    : l10n.selectDueDateHint,
                style: TextStyle(
                  color: _dueDate != null
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 14, color: AppColors.textTertiary),
              const SizedBox(width: 4),
              Text(
                l10n.alertWillBeSent,
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
        if (_paymentStatus == 1) ...[
          // Partial — show amount paid
          _Label(l10n.amountPaid),
          const SizedBox(height: 6),
          TextField(
            controller: _paidAmountCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: '0.00',
              hintStyle:
                  TextStyle(color: AppColors.textTertiary, fontSize: 14),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 14, right: 8),
                child: Text(
                  currency,
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 0, minHeight: 0),
              filled: true,
              fillColor: AppColors.surfaceSubtle,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppColors.borderLight.withValues(alpha: 0.7),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppColors.borderLight.withValues(alpha: 0.7),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.primaryNavy),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
            style: TextStyle(
                color: AppColors.textPrimary, fontSize: 15),
          ),
          const SizedBox(height: 12),
          _Label(l10n.dueDateForRemaining),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _dueDate ??
                    DateTime.now().add(const Duration(days: 30)),
                firstDate: DateTime.now(),
                lastDate:
                    DateTime.now().add(const Duration(days: 365)),
              );
              if (d != null) setState(() => _dueDate = d);
            },
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.borderLight.withValues(alpha: 0.7),
                ),
              ),
              child: Text(
                _dueDate != null
                    ? DateFormat('yyyy-MM-dd').format(_dueDate!)
                    : l10n.selectDueDateHint,
                style: TextStyle(
                  color: _dueDate != null
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
        if (_paymentStatus == 2) ...[
          // Fully paid
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.badgeBgPositive,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF16A34A), size: 20),
                const SizedBox(width: 8),
                Text(
                  l10n.purchaseFullyPaid,
                  style: TextStyle(
                    color: const Color(0xFF166534),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
//  SHARED WIDGETS
// ═══════════════════════════════════════════════════════
class _Card extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final List<Widget> children;

  const _Card({this.title, this.trailing, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.borderLight.withValues(alpha: 0.4),
        ),
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
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.8,
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
          ],
          ...children,
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: AppColors.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

/// Purchase item data
enum _ItemType { rawMaterial, product, manufacturingFee }

extension _ItemTypeExt on _ItemType {
  Color get color {
    switch (this) {
      case _ItemType.rawMaterial:
        return const Color(0xFF0F766E);
      case _ItemType.product:
        return const Color(0xFF4F46E5);
      case _ItemType.manufacturingFee:
        return const Color(0xFFD97706);
    }
  }

  Color get bgColor {
    switch (this) {
      case _ItemType.rawMaterial:
        return const Color(0xFFCCFBF1);
      case _ItemType.product:
        return const Color(0xFFE0E7FF);
      case _ItemType.manufacturingFee:
        return const Color(0xFFFEF3C7);
    }
  }

  IconData get icon {
    switch (this) {
      case _ItemType.rawMaterial:
        return Icons.science_rounded;
      case _ItemType.product:
        return Icons.inventory_2_rounded;
      case _ItemType.manufacturingFee:
        return Icons.precision_manufacturing_rounded;
    }
  }
}

class _PurchaseItem {
  final String name;
  final String category;
  final _ItemType itemType;
  final int qty;
  final double unitPrice;
  final String? productId;
  final String? variantId;
  final String? variantName;

  const _PurchaseItem({
    required this.name,
    required this.category,
    required this.itemType,
    required this.qty,
    required this.unitPrice,
    this.productId,
    this.variantId,
    this.variantName,
  });

  double get total => qty * unitPrice;

  _PurchaseItem copyWith({
    String? name,
    String? category,
    _ItemType? itemType,
    int? qty,
    double? unitPrice,
    String? productId,
    String? variantId,
    String? variantName,
  }) {
    return _PurchaseItem(
      name: name ?? this.name,
      category: category ?? this.category,
      itemType: itemType ?? this.itemType,
      qty: qty ?? this.qty,
      unitPrice: unitPrice ?? this.unitPrice,
      productId: productId ?? this.productId,
      variantId: variantId ?? this.variantId,
      variantName: variantName ?? this.variantName,
    );
  }
}
