import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers/app_providers.dart';
import '../../core/repositories/sale_repository.dart' show StockDeduction;
import '../../core/providers/app_settings_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../shared/models/sale_model.dart';
import '../../shared/models/product_model.dart';
import '../../shared/models/transaction_model.dart';
import '../../shared/widgets/discard_changes_dialog.dart';
import '../shopify/providers/shopify_sync_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/safe_pop.dart';

/// Screen to record a new sale (Growth tier).
class RecordSaleScreen extends ConsumerStatefulWidget {
  final Sale? existingSale; // non-null when editing a sale

  const RecordSaleScreen({super.key, this.existingSale});

  @override
  ConsumerState<RecordSaleScreen> createState() => _RecordSaleScreenState();
}

class _RecordSaleScreenState extends ConsumerState<RecordSaleScreen> {
  bool get _isEditing => widget.existingSale != null;
  AppLocalizations get l10n => AppLocalizations.of(context)!;

  final _customerCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();

  // Shipping
  final _shippingAddressCtrl = TextEditingController();
  final _shippingCostCtrl = TextEditingController();
  final _shippingNotesCtrl = TextEditingController();
  final _shippingMethodCtrl = TextEditingController();
  final _trackingCtrl = TextEditingController();
  bool _showShipping = false;
  bool _showShippingAdvanced = false;
  int _deliveryStatusIdx = 0; // 0=pending, 1=shipped, 2=delivered

  DateTime _saleDate = DateTime.now();
  int _methodIdx = 0;
  int _statusIdx = 2; // default: paid
  final _amountPaidCtrl = TextEditingController();
  final List<_LineItem> _items = [];

  static const _methods = [
    _PaymentMethod(Icons.payments_rounded, 'Cash'),
    _PaymentMethod(Icons.account_balance_rounded, 'Bank Transfer'),
    _PaymentMethod(Icons.qr_code_2_rounded, 'InstaPay'),
    _PaymentMethod(Icons.phone_iphone_rounded, 'Vodafone Cash'),
  ];

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final s = widget.existingSale!;
      _customerCtrl.text = s.customerName ?? '';
      _phoneCtrl.text = s.customerPhone ?? '';
      _emailCtrl.text = s.customerEmail ?? '';
      _notesCtrl.text = s.notes ?? '';
      _taxCtrl.text = s.taxAmount > 0 ? _cleanNumber(s.taxAmount) : '';
      _discountCtrl.text = s.discountAmount > 0 ? _cleanNumber(s.discountAmount) : '';
      _saleDate = s.date;
      _statusIdx = s.paymentStatus.index;
      _amountPaidCtrl.text = s.amountPaid > 0 ? s.amountPaid.toStringAsFixed(2) : '';
      _methodIdx = _methods.indexWhere((m) => m.label == s.paymentMethod);
      if (_methodIdx < 0) _methodIdx = 0;
      // Shipping
      _shippingAddressCtrl.text = s.shippingAddress ?? '';
      _shippingCostCtrl.text = s.shippingCost > 0 ? _cleanNumber(s.shippingCost) : '';
      _shippingNotesCtrl.text = s.shippingNotes ?? '';
      _shippingMethodCtrl.text = s.shippingMethod ?? '';
      _trackingCtrl.text = s.trackingNumber ?? '';
      _showShipping = s.shippingAddress != null && s.shippingAddress!.isNotEmpty;
      _showShippingAdvanced = s.shippingMethod != null || s.trackingNumber != null;
      _deliveryStatusIdx = switch (s.deliveryStatus) {
        'Shipped' => 1,
        'Delivered' => 2,
        _ => 0,
      };
      for (final item in s.items) {
        _items.add(_LineItem(
          productId: item.productId,
          variantId: item.variantId,
          variantName: item.variantName,
          nameCtrl: TextEditingController(text: item.productName),
          qtyCtrl: TextEditingController(text: _cleanNumber(item.quantity)),
          priceCtrl: TextEditingController(text: _cleanNumber(item.unitPrice)),
          costPrice: item.costPrice,
        ));
      }
    }
    if (_items.isEmpty) _addLineItem();
  }

  @override
  void dispose() {
    _customerCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _notesCtrl.dispose();
    _taxCtrl.dispose();
    _discountCtrl.dispose();
    _amountPaidCtrl.dispose();
    _shippingAddressCtrl.dispose();
    _shippingCostCtrl.dispose();
    _shippingNotesCtrl.dispose();
    _shippingMethodCtrl.dispose();
    _trackingCtrl.dispose();
    for (final li in _items) {
      li.nameCtrl.dispose();
      li.qtyCtrl.dispose();
      li.priceCtrl.dispose();
    }
    super.dispose();
  }

  void _addLineItem() {
    setState(() {
      _items.add(_LineItem(
        nameCtrl: TextEditingController(),
        qtyCtrl: TextEditingController(text: '1'),
        priceCtrl: TextEditingController(),
      ));
    });
  }

  void _removeLineItem(int idx) {
    if (_items.length <= 1) return;
    setState(() {
      _items[idx].nameCtrl.dispose();
      _items[idx].qtyCtrl.dispose();
      _items[idx].priceCtrl.dispose();
      _items.removeAt(idx);
    });
  }

  double get _subtotal {
    double sum = 0;
    for (final li in _items) {
      final qty = double.tryParse(li.qtyCtrl.text) ?? 0;
      final price = double.tryParse(li.priceCtrl.text) ?? 0;
      sum += qty * price;
    }
    return sum;
  }

  double get _tax {
    final v = double.tryParse(_taxCtrl.text) ?? 0;
    return v < 0 ? 0 : v;
  }
  double get _discount {
    final v = double.tryParse(_discountCtrl.text) ?? 0;
    if (v < 0) return 0;
    final sub = _subtotal;
    return v > sub ? sub : v;
  }
  double get _shippingCost {
    final v = double.tryParse(_shippingCostCtrl.text) ?? 0;
    return v < 0 ? 0 : v;
  }
  double get _total => _subtotal + _tax - _discount + _shippingCost;

  // ── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyProvider);

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
                    _buildCustomerSection()
                        .animate()
                        .fadeIn(duration: 250.ms),
                    const SizedBox(height: 14),
                    _buildShippingSection()
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 40.ms),
                    const SizedBox(height: 14),
                    _buildLineItemsSection(currency)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 80.ms),
                    const SizedBox(height: 14),
                    _buildTotalsSection(currency)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 120.ms),
                    const SizedBox(height: 14),
                    _buildPaymentSection()
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 160.ms),
                    const SizedBox(height: 14),
                    _buildNotesSection()
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 200.ms),
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
                _isEditing ? l10n.editSale : l10n.recordSale,
                style: AppTypography.h2.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Semantics(
            button: true,
            label: l10n.saveSale,
            child: GestureDetector(
            onTap: _save,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                l10n.saveSaleButton,
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

  // ── Customer ─────────────────────────────────────────────

  Widget _buildCustomerSection() {
    return _Card(
      title: l10n.customer,
      children: [
        _textField(
          controller: _customerCtrl,
          hint: l10n.customerNameOptional,
          icon: Icons.person_rounded,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _textField(
                controller: _phoneCtrl,
                hint: l10n.phone,
                icon: Icons.phone_rounded,
                keyboardType: TextInputType.phone,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _textField(
                controller: _emailCtrl,
                hint: l10n.email,
                icon: Icons.email_rounded,
                keyboardType: TextInputType.emailAddress,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildDatePicker(),
      ],
    );
  }

  // ── Shipping ─────────────────────────────────────────────

  Widget _buildShippingSection() {
    return _Card(
      title: l10n.shipping,
      trailing: GestureDetector(
        onTap: () => setState(() => _showShipping = !_showShipping),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _showShipping
                ? AppColors.primaryNavy.withValues(alpha: 0.1)
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _showShipping ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                size: 18,
                color: _showShipping ? AppColors.primaryNavy : AppColors.textTertiary,
              ),
              const SizedBox(width: 4),
              Text(
                _showShipping ? l10n.on : l10n.off,
                style: AppTypography.labelSmall.copyWith(
                  color: _showShipping ? AppColors.primaryNavy : AppColors.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
      children: [
        if (!_showShipping)
          Text(
            l10n.toggleShippingHint,
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
          )
        else ...[
          _textField(
            controller: _shippingAddressCtrl,
            hint: l10n.shippingAddress,
            icon: Icons.location_on_rounded,
            maxLines: 2,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _textField(
                  controller: _shippingCostCtrl,
                  hint: l10n.shippingCost,
                  prefixText: ref.watch(currencyProvider),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _textField(
                  controller: _shippingMethodCtrl,
                  hint: l10n.shippingMethodHint,
                  icon: Icons.local_shipping_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _textField(
            controller: _trackingCtrl,
            hint: l10n.trackingNumberOrLink,
            icon: Icons.qr_code_rounded,
          ),
          const SizedBox(height: 10),
          // Advanced toggle
          GestureDetector(
            onTap: () => setState(() => _showShippingAdvanced = !_showShippingAdvanced),
            child: Row(
              children: [
                Icon(
                  _showShippingAdvanced
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 4),
                Text(
                  _showShippingAdvanced ? l10n.lessDetails : l10n.moreDetails,
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (_showShippingAdvanced) ...[
            const SizedBox(height: 10),
            _textField(
              controller: _shippingNotesCtrl,
              hint: l10n.shippingNotesOptional,
              icon: Icons.notes_rounded,
            ),
            const SizedBox(height: 10),
            // Delivery status chips
            Row(
              children: List.generate(3, (i) {
                final labels = [l10n.pending, l10n.shipped, l10n.delivered];
                final colors = [AppColors.warning, const Color(0xFF3B82F6), AppColors.success];
                final isSelected = _deliveryStatusIdx == i;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                        left: i == 0 ? 0 : 4, right: i == 2 ? 0 : 4),
                    child: GestureDetector(
                      onTap: () => setState(() => _deliveryStatusIdx = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colors[i].withValues(alpha: 0.12)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? colors[i]
                                : AppColors.borderLight.withValues(alpha: 0.6),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            labels[i],
                            style: AppTypography.labelSmall.copyWith(
                              color: isSelected ? colors[i] : AppColors.textSecondary,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildDatePicker() {
    final formatted = DateFormat('MMM dd, yyyy').format(_saleDate);
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _saleDate,
          firstDate: DateTime(DateTime.now().year - 1, 1, 1),
          lastDate: DateTime.now().add(const Duration(days: 1)),
        );
        if (picked != null) setState(() => _saleDate = picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
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

  // ── Line Items ───────────────────────────────────────────

  Widget _buildLineItemsSection(String currency) {
    return _Card(
      title: l10n.items,
      trailing: GestureDetector(
        onTap: _addLineItem,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
              Text(l10n.addItem,
                  style: AppTypography.labelSmall
                      .copyWith(color: AppColors.accentOrange, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
      children: [
        for (int i = 0; i < _items.length; i++) ...[
          if (i > 0)
            Divider(color: AppColors.borderLight.withValues(alpha: 0.5),
                height: 24),
          _buildLineItemRow(i, currency),
        ],
      ],
    );
  }

  Widget _buildLineItemRow(int idx, String currency) {
    final li = _items[idx];
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _textField(
                controller: li.nameCtrl,
                hint: l10n.productItemName,
                icon: Icons.shopping_bag_rounded,
              ),
            ),
            const SizedBox(width: 8),
            // Inventory picker button
            GestureDetector(
              onTap: () => _showInventoryPicker(idx),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                  ),
                ),
                child: const Icon(Icons.inventory_2_rounded,
                    size: 20, color: Color(0xFF7C3AED)),
              ),
            ),
            if (_items.length > 1) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _removeLineItem(idx),
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
              child: _textField(
                controller: li.qtyCtrl,
                hint: l10n.qty,
                icon: Icons.tag_rounded,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: _textField(
                controller: li.priceCtrl,
                hint: l10n.unitPrice,
                prefixText: currency,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        // Show cost price + stock info when product is linked
        if (li.productId != null) ...[
          const SizedBox(height: 8),
          _buildLinkedProductInfo(idx, currency),
        ],
      ],
    );
  }

  /// Shows cost price and stock info when a product is linked from inventory.
  Widget _buildLinkedProductInfo(int idx, String currency) {
    final li = _items[idx];
    final products = ref.watch(inventoryProvider).value ?? [];
    final product = products.cast<Product?>().firstWhere(
      (p) => p!.id == li.productId,
      orElse: () => null,
    );
    final fmt = NumberFormat('#,##0.00', 'en');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF7C3AED).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 14, color: Color(0xFF7C3AED)),
          const SizedBox(width: 8),
          Text(
            l10n.costLabel(currency, fmt.format(li.costPrice)),
            style: const TextStyle(
              color: Color(0xFF7C3AED),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          if (product != null) ...[
            const SizedBox(width: 12),
            Text(
              l10n.stockLabel(product.currentStock),
              style: TextStyle(
                color: product.currentStock > 0
                    ? AppColors.textSecondary
                    : AppColors.danger,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
          const Spacer(),
          GestureDetector(
            onTap: () {
              setState(() {
                li.productId = null;
                li.costPrice = 0;
              });
            },
            child: const Icon(Icons.close_rounded,
                size: 16, color: Color(0xFF7C3AED)),
          ),
        ],
      ),
    );
  }

  /// Opens a bottom sheet with the full product list + search for picking a product.
  void _showInventoryPicker(int idx) {
    final products = ref.read(filteredInventoryProvider).value ?? [];
    final sellable = products.where((p) => !p.isMaterial).toList();
    if (sellable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.noProductsInInventory),
        backgroundColor: AppColors.primaryNavy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }

    final currency = ref.read(currencyProvider);
    final fmt = NumberFormat('#,##0.00', 'en');
    String searchQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final filtered = searchQuery.isEmpty
              ? sellable
              : sellable
                  .where((p) =>
                      p.name.toLowerCase().contains(searchQuery.toLowerCase()))
                  .toList();
          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.3,
            maxChildSize: 0.85,
            expand: false,
            builder: (ctx2, scrollCtrl) => Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    l10n.selectProduct,
                    style: AppTypography.h2.copyWith(
                      color: AppColors.primaryNavy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Search field
                  TextField(
                    onChanged: (v) => setSheetState(() => searchQuery = v),
                    decoration: InputDecoration(
                      hintText: l10n.searchProducts,
                      hintStyle: AppTypography.bodySmall
                          .copyWith(color: AppColors.textTertiary),
                      prefixIcon: const Icon(Icons.search_rounded,
                          size: 20, color: Color(0xFF7C3AED)),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 44, minHeight: 0),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: AppColors.borderLight
                                .withValues(alpha: 0.7)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: Color(0xFF7C3AED), width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              l10n.noProductsFound,
                              style: TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: 14),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollCtrl,
                            itemCount: filtered.length,
                            separatorBuilder: (context, index) => Divider(
                                height: 1,
                                color: AppColors.borderLight
                                    .withValues(alpha: 0.3)),
                            itemBuilder: (_, i) {
                              final product = filtered[i];
                              final isMultiVariant = product.hasVariants && product.variants.length > 1;
                              final isSelected =
                                  _items[idx].productId == product.id;
                              return ListTile(
                                onTap: () {
                                  Navigator.of(ctx2).pop();
                                  _selectProduct(idx, product);
                                },
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 4),
                                leading: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF7C3AED)
                                        : product.color.withValues(alpha: 0.1),
                                    borderRadius:
                                        BorderRadius.circular(10),
                                  ),
                                  child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: isSelected
                                              ? ColorFiltered(
                                                  colorFilter: const ColorFilter.mode(
                                                    Color(0xFF7C3AED),
                                                    BlendMode.color,
                                                  ),
                                                  child: CachedNetworkImage(
                                                    imageUrl: product.imageUrl!,
                                                    fit: BoxFit.cover,
                                                    width: 42,
                                                    height: 42,
                                                    memCacheWidth: 84,
                                                    memCacheHeight: 84,
                                                  ),
                                                )
                                              : CachedNetworkImage(
                                                  imageUrl: product.imageUrl!,
                                                  fit: BoxFit.cover,
                                                  width: 42,
                                                  height: 42,
                                                  memCacheWidth: 84,
                                                  memCacheHeight: 84,
                                                  placeholder: (_, _) => Icon(
                                                    product.icon,
                                                    color: product.color,
                                                    size: 20,
                                                  ),
                                                  errorWidget: (_, _, _) => Icon(
                                                    product.icon,
                                                    color: product.color,
                                                    size: 20,
                                                  ),
                                                ),
                                        )
                                      : Icon(
                                          product.icon,
                                          color: isSelected
                                              ? Colors.white
                                              : product.color,
                                          size: 20,
                                        ),
                                ),
                                title: Text(
                                  product.name,
                                  style: TextStyle(
                                    color: AppColors.primaryNavy,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Text(
                                  isMultiVariant
                                      ? l10n.variantsStockInfo(product.variants.length, product.currentStock)
                                      : l10n.productPriceInfo(currency, fmt.format(product.sellingPrice), currency, fmt.format(product.costPrice), product.currentStock),
                                  style: TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 11,
                                  ),
                                ),
                                trailing: isSelected
                                    ? const Icon(Icons.check_circle_rounded,
                                        color: Color(0xFF7C3AED))
                                    : isMultiVariant
                                        ? const Icon(Icons.chevron_right_rounded,
                                            color: AppColors.textTertiary, size: 20)
                                        : null,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _selectProduct(int idx, Product product) {
    if (product.hasVariants && product.variants.length > 1) {
      _showVariantPicker(idx, product);
    } else {
      final variant = product.variants.first;
      setState(() {
        _items[idx].productId = product.id;
        _items[idx].variantId = variant.id;
        _items[idx].variantName = variant.isDefault ? null : variant.displayName;
        _items[idx].nameCtrl.text = product.name;
        _items[idx].priceCtrl.text = variant.sellingPrice.toString();
        _items[idx].costPrice = variant.costPrice;
      });
    }
  }

  void _showVariantPicker(int idx, Product product) {
    final currency = ref.read(currencyProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
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
                l10n.selectVariant(product.name),
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textPrimary,
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
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (_, i) {
                  final v = product.variants[i];
                  return ListTile(
                    title: Text(
                      v.localizedDisplayName(l10n),
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      l10n.variantPriceStock(currency, v.sellingPrice.toStringAsFixed(2), v.currentStock),
                      style: AppTypography.captionSmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    trailing: v.currentStock <= 0
                        ? Text(l10n.outOfStock,
                            style: AppTypography.captionSmall
                                .copyWith(color: AppColors.danger))
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _items[idx].productId = product.id;
                        _items[idx].variantId = v.id;
                        _items[idx].variantName =
                            v.isDefault ? null : v.displayName;
                        _items[idx].nameCtrl.text = v.isDefault
                            ? product.name
                            : '${product.name} — ${v.localizedDisplayName(l10n)}';
                        _items[idx].priceCtrl.text =
                            v.sellingPrice.toString();
                        _items[idx].costPrice = v.costPrice;
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

  // ── Totals ───────────────────────────────────────────────

  Widget _buildTotalsSection(String currency) {
    final fmt = NumberFormat('#,##0.00', 'en');
    return _Card(
      title: l10n.summary,
      children: [
        Row(
          children: [
            Expanded(
              child: _textField(
                controller: _taxCtrl,
                hint: l10n.tax,
                prefixText: currency,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _textField(
                controller: _discountCtrl,
                hint: l10n.discount,
                prefixText: currency,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              _summaryRow(l10n.subtotal, '$currency ${fmt.format(_subtotal)}'),
              if (_tax > 0) ...[
                const SizedBox(height: 6),
                _summaryRow(l10n.tax, '+ $currency ${fmt.format(_tax)}'),
              ],
              if (_discount > 0) ...[
                const SizedBox(height: 6),
                _summaryRow(
                    l10n.discount, '- $currency ${fmt.format(_discount)}'),
              ],
              if (_shippingCost > 0) ...[
                const SizedBox(height: 6),
                _summaryRow(
                    l10n.shipping, '+ $currency ${fmt.format(_shippingCost)}'),
              ],
              const Divider(height: 16),
              _summaryRow(
                l10n.total,
                '$currency ${fmt.format(_total)}',
                bold: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: AppTypography.bodySmall.copyWith(
              color: bold ? AppColors.textPrimary : AppColors.textSecondary,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            )),
        Text(value,
            style: AppTypography.bodySmall.copyWith(
              color:
                  bold ? const Color(0xFF10B981) : AppColors.textPrimary,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            )),
      ],
    );
  }

  // ── Payment ──────────────────────────────────────────────

  Widget _buildPaymentSection() {
    return _Card(
      title: l10n.payment,
      children: [
        // Status chips
        Row(
          children: List.generate(3, (i) {
            final labels = [l10n.unpaid, l10n.partial, l10n.paid];
            final colors = [AppColors.danger, AppColors.warning, AppColors.success];
            final isSelected = _statusIdx == i;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                    left: i == 0 ? 0 : 4, right: i == 2 ? 0 : 4),
                child: GestureDetector(
                  onTap: () => setState(() => _statusIdx = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colors[i].withValues(alpha: 0.12)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? colors[i]
                            : AppColors.borderLight.withValues(alpha: 0.6),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        labels[i],
                        style: AppTypography.labelSmall.copyWith(
                          color: isSelected
                              ? colors[i]
                              : AppColors.textSecondary,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),

        // Amount paid field — shown for Partial status
        if (_statusIdx == 1) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _amountPaidCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.amountPaidLabel,
              hintText: '0.00',
              prefixIcon: const Icon(Icons.attach_money_rounded, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],

        const SizedBox(height: 14),
        // Method grid
        GridView.count(
          crossAxisCount: 2,
          childAspectRatio: 2.4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: List.generate(_methods.length, (i) {
            final m = _methods[i];
            final isSelected = _methodIdx == i;
            return GestureDetector(
              onTap: () => setState(() => _methodIdx = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primaryNavy
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primaryNavy
                        : AppColors.borderLight.withValues(alpha: 0.7),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(m.icon,
                        size: 18,
                        color: isSelected
                            ? Colors.white
                            : AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        switch (m.label) {
                          'Cash' => l10n.cash,
                          'Bank Transfer' => l10n.bankTransfer,
                          'InstaPay' => l10n.instaPay,
                          'Vodafone Cash' => l10n.vodafoneCash,
                          _ => m.label,
                        },
                        style: AppTypography.captionSmall.copyWith(
                          color: isSelected
                              ? Colors.white
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
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
          hint: l10n.addNotesOptional,
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
      child: Semantics(
        button: true,
        label: _isEditing ? l10n.updateSale : l10n.confirmSale,
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
            _isEditing
                ? l10n.updateSale
                : l10n.confirmSaleTotal(currency, fmt.format(_total)),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ),
      ),
      ),
    );
  }

  // ── Save ─────────────────────────────────────────────────

  Future<void> _save() async {
    // Validate at least one item with name, price, AND quantity
    bool hasValidItem = false;
    for (final li in _items) {
      if (li.nameCtrl.text.trim().isNotEmpty &&
          (double.tryParse(li.priceCtrl.text) ?? 0) > 0 &&
          (double.tryParse(li.qtyCtrl.text) ?? 0) > 0) {
        hasValidItem = true;
        break;
      }
    }

    if (!hasValidItem) {
      _showError(l10n.errorAddItem);
      return;
    }

    if (_total <= 0) {
      _showError(l10n.errorTotalZero);
      return;
    }

    // Validate partial payment amount
    if (_statusIdx == 1) {
      final partialAmount = double.tryParse(_amountPaidCtrl.text) ?? 0;
      if (partialAmount <= 0) {
        _showError(l10n.errorPartialZero);
        return;
      }
      if (partialAmount >= _total) {
        _showError(l10n.errorPartialExceedsTotal);
        return;
      }
    }

    HapticFeedback.mediumImpact();

    final uid = ref.read(authProvider).user?.id ?? 'unknown';
    final saleItems = <SaleItem>[];

    final valMethod = ref.read(appSettingsProvider).valuationMethod;
    final products = ref.read(inventoryProvider).value ?? [];

    for (final li in _items) {
      final name = li.nameCtrl.text.trim();
      final qty = double.tryParse(li.qtyCtrl.text) ?? 0;
      final price = double.tryParse(li.priceCtrl.text) ?? 0;
      if (name.isEmpty || price <= 0 || qty <= 0) continue;

      // Use FIFO/LIFO/Average-aware COGS if product is tracked
      var effectiveCost = li.costPrice;
      if (li.productId != null) {
        final product = products.cast<Product?>().firstWhere(
              (p) => p!.id == li.productId,
              orElse: () => null,
            );
        if (product != null) {
          final vid = li.variantId ?? '${li.productId}_v0';
          final variant = product.variantById(vid);
          if (variant != null) {
            effectiveCost = variant.cogsPerUnit(qty.toInt(), valMethod);
          }
        }
      }

      saleItems.add(SaleItem(
        productId: li.productId,
        variantId: li.variantId,
        variantName: li.variantName,
        productName: name,
        quantity: qty,
        unitPrice: price,
        costPrice: effectiveCost,
      ));
    }

    if (saleItems.isEmpty) {
      _showError(l10n.errorNoValidItems);
      return;
    }

    // ── Stock validation ──────────────────────────────────
    final stockWarnings = <String>[];
    final costWarnings = <String>[];

    for (final si in saleItems) {
      if (si.productId == null) continue;
      final product = products.cast<Product?>().firstWhere(
            (p) => p!.id == si.productId,
            orElse: () => null,
          );
      if (product == null) continue;

      // Check insufficient stock (use variant-level stock when available)
      final variantStock = (si.variantId != null)
          ? (product.variantById(si.variantId!)?.currentStock ?? product.currentStock)
          : product.currentStock;
      if (si.quantity > variantStock) {
        stockWarnings.add(
          '${si.productName}: need ${si.quantity.toStringAsFixed(0)}, '
          'have $variantStock',
        );
      }

      // Check below-cost selling price (use item-level costPrice which reflects FIFO/average)
      final effectiveCostForWarning = si.costPrice > 0 ? si.costPrice : product.costPrice;
      if (effectiveCostForWarning > 0 && si.unitPrice < effectiveCostForWarning) {
        costWarnings.add(
          '${si.productName}: selling at ${si.unitPrice.toStringAsFixed(2)} '
          'below cost ${effectiveCostForWarning.toStringAsFixed(2)}',
        );
      }
    }

    if (stockWarnings.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.insufficientStock),
          content: Text(
            l10n.insufficientStockMsg(stockWarnings.join('\n')),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.continueAction),
            ),
          ],
        ),
      );
      if (proceed != true) return;
      if (!mounted) return;
    }

    if (costWarnings.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.belowCostPrice),
          content: Text(
            l10n.belowCostMsg(costWarnings.join('\n')),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              child: Text(l10n.sellAnyway),
            ),
          ],
        ),
      );
      if (proceed != true) return;
      if (!mounted) return;
    }

    // Generate sequential order number for new manual orders
    int? orderNumber;
    if (!_isEditing) {
      final existingSales = ref.read(salesProvider).value ?? [];
      final maxExisting = existingSales
          .where((s) => s.orderNumber != null)
          .fold<int>(0, (max, s) => s.orderNumber! > max ? s.orderNumber! : max);
      orderNumber = maxExisting < 1000 ? 1001 : maxExisting + 1;
    }

    final sale = Sale(
      id: _isEditing ? widget.existingSale!.id : const Uuid().v4(),
      userId: uid,
      customerName:
          _customerCtrl.text.trim().isEmpty ? null : _customerCtrl.text.trim(),
      customerPhone:
          _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      customerEmail:
          _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      date: _saleDate,
      items: saleItems,
      taxAmount: _tax,
      discountAmount: _discount,
      shippingAddress: _shippingAddressCtrl.text.trim().isEmpty
          ? null
          : _shippingAddressCtrl.text.trim(),
      shippingCost: _shippingCost,
      shippingNotes: _shippingNotesCtrl.text.trim().isEmpty
          ? null
          : _shippingNotesCtrl.text.trim(),
      shippingMethod: _shippingMethodCtrl.text.trim().isEmpty
          ? null
          : _shippingMethodCtrl.text.trim(),
      trackingNumber:
          _trackingCtrl.text.trim().isEmpty ? null : _trackingCtrl.text.trim(),
      deliveryStatus: ['Pending', 'Shipped', 'Delivered'][_deliveryStatusIdx],
      fulfillmentStatus: _deliveryStatusIdx == 2
          ? FulfillmentStatus.fulfilled
          : _deliveryStatusIdx == 1
              ? FulfillmentStatus.partial
              : FulfillmentStatus.unfulfilled,
      paymentMethod: _methods[_methodIdx].label,
      paymentStatus: PaymentStatus.values[_statusIdx],
      amountPaid: _statusIdx == 2
          ? _total
          : _statusIdx == 1
              ? (double.tryParse(_amountPaidCtrl.text) ?? 0)
              : 0,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      createdAt: _isEditing ? widget.existingSale!.createdAt : DateTime.now(),
      orderNumber: _isEditing
          ? widget.existingSale!.orderNumber
          : orderNumber,
    );

    // ── Shopify line-item change warning (edit only) ──────
    if (_isEditing &&
        widget.existingSale!.externalSource == 'shopify' &&
        widget.existingSale!.externalOrderId != null) {
      // Check if line items were modified
      final oldItems = widget.existingSale!.items;
      final itemsChanged = oldItems.length != saleItems.length ||
          !_sameLineItems(oldItems, saleItems);
      if (itemsChanged) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.shopifyOrderWarning),
            content: Text(
              l10n.shopifyOrderWarningMsg,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style:
                    TextButton.styleFrom(foregroundColor: Colors.orange),
                child: Text(l10n.saveAnyway),
              ),
            ],
          ),
        );
        if (proceed != true) return;
        if (!mounted) return;
      }
    }

    if (_isEditing) {
      ref.read(salesProvider.notifier).updateSale(sale);

      // ── Stock delta adjustment (variant-aware) ─────────
      final oldItems = widget.existingSale!.items;
      // Use composite key: "productId:variantId"
      final oldQtyMap = <String, double>{};
      final variantMap = <String, String>{}; // compositeKey → variantId
      final productMap = <String, String>{}; // compositeKey → productId
      final oldCostMap = <String, double>{}; // compositeKey → costPrice
      for (final oi in oldItems) {
        if (oi.productId != null) {
          final vid = oi.variantId ?? '${oi.productId}_v0';
          final key = '${oi.productId}:$vid';
          oldQtyMap[key] = (oldQtyMap[key] ?? 0) + oi.quantity;
          variantMap[key] = vid;
          productMap[key] = oi.productId!;
          if (oi.costPrice > 0) oldCostMap[key] = oi.costPrice;
        }
      }
      final newQtyMap = <String, double>{};
      for (final ni in saleItems) {
        if (ni.productId != null) {
          final vid = ni.variantId ?? '${ni.productId}_v0';
          final key = '${ni.productId}:$vid';
          newQtyMap[key] = (newQtyMap[key] ?? 0) + ni.quantity;
          variantMap[key] = vid;
          productMap[key] = ni.productId!;
        }
      }
      final allKeys = {...oldQtyMap.keys, ...newQtyMap.keys};
      for (final key in allKeys) {
        final oldQty = oldQtyMap[key] ?? 0;
        final newQty = newQtyMap[key] ?? 0;
        final delta = oldQty - newQty;
        if (delta != 0) {
          ref.read(inventoryProvider.notifier).adjustStock(
                productMap[key]!,
                variantMap[key]!,
                delta.round(),
                'Sale edit adjustment',
                unitCost: delta > 0 ? oldCostMap[key] : null,
                valuationMethod: valMethod,
              );
        }
      }

      // ── Update linked revenue + COGS transactions ──────
      final allTxns = ref.read(transactionsProvider).value ?? [];
      final transNotifier = ref.read(transactionsProvider.notifier);
      final revTxn = allTxns.cast<Transaction?>().firstWhere(
        (t) => t!.saleId == sale.id && t.categoryId == 'cat_sales_revenue',
        orElse: () => null,
      );
      final cogsTxn = allTxns.cast<Transaction?>().firstWhere(
        (t) => t!.saleId == sale.id && t.categoryId == 'cat_cogs',
        orElse: () => null,
      );
      // Accrual accounting: revenue recognised at point of sale,
      // regardless of payment status. Never exclude from P&L.
      if (revTxn != null) {
        transNotifier.updateTransaction(revTxn.copyWith(
          amount: sale.netRevenue,
          dateTime: sale.date,
          title: 'Sale${sale.customerName != null ? ' to ${sale.customerName}' : ''}',
          excludeFromPL: false,
        ));
      }
      if (cogsTxn != null) {
        transNotifier.updateTransaction(cogsTxn.copyWith(
          amount: -sale.totalCogs,
          dateTime: sale.date,
          excludeFromPL: false,
        ));
      }

      // ── Update / create / delete linked Shipping transaction ──
      final shipTxn = allTxns.cast<Transaction?>().firstWhere(
        (t) => t!.saleId == sale.id && t.categoryId == 'cat_shipping',
        orElse: () => null,
      );
      if (sale.shippingCost > 0) {
        if (shipTxn != null) {
          transNotifier.updateTransaction(shipTxn.copyWith(
            amount: sale.shippingCost,
            dateTime: sale.date,
            excludeFromPL: false,
          ));
        } else {
          final newShipTxn = Transaction(
            id: 'sale_ship_${sale.id}',
            userId: uid,
            title: 'Shipping — ${sale.customerName ?? 'Sale'}',
            amount: sale.shippingCost,
            dateTime: sale.date,
            categoryId: 'cat_shipping',
            note: 'Auto-generated shipping revenue',
            saleId: sale.id,
            excludeFromPL: false,
            createdAt: DateTime.now(),
          );
          transNotifier.addTransaction(newShipTxn);
        }
      } else if (shipTxn != null) {
        transNotifier.removeTransaction(shipTxn.id);
      }
    } else {
      // Auto-create Revenue + COGS transactions for P&L integration
      // Revenue = netRevenue (subtotal − discount), excluding tax
      // (collected liability) and shipping (separate revenue transaction).
      // Accrual accounting: always include in P&L at point of sale.
      final revTxn = Transaction(
        id: 'sale_rev_${sale.id}',
        userId: uid,
        title: 'Sale${sale.customerName != null ? ' to ${sale.customerName}' : ''}',
        amount: sale.netRevenue,
        dateTime: sale.date,
        categoryId: 'cat_sales_revenue',
        note: sale.notes,
        paymentMethod: sale.paymentMethod,
        saleId: sale.id,
        excludeFromPL: false,
        createdAt: DateTime.now(),
      );
      final cogsTxn = Transaction(
        id: 'sale_cogs_${sale.id}',
        userId: uid,
        title: 'COGS — ${saleItems.map((i) => i.productName).join(', ')}',
        amount: -sale.totalCogs,
        dateTime: sale.date,
        categoryId: 'cat_cogs',
        note: 'Auto-generated from sale',
        saleId: sale.id,
        excludeFromPL: false,
        createdAt: DateTime.now(),
      );

      // Shipping revenue transaction (if applicable)
      final List<Transaction> saleTxns = [revTxn, cogsTxn];
      if (sale.shippingCost > 0) {
        saleTxns.add(Transaction(
          id: 'sale_ship_${sale.id}',
          userId: uid,
          title: 'Shipping — ${sale.customerName ?? 'Sale'}',
          amount: sale.shippingCost,
          dateTime: sale.date,
          categoryId: 'cat_shipping',
          note: 'Auto-generated shipping revenue',
          saleId: sale.id,
          excludeFromPL: false,
          createdAt: DateTime.now(),
        ));
      }

      // Build stock deductions for atomic write
      final deductions = <StockDeduction>[];
      if (ref.read(appSettingsProvider).autoUpdateStock) {
        for (final item in saleItems) {
          if (item.productId != null && item.quantity > 0) {
            deductions.add(StockDeduction(
              productId: item.productId!,
              variantId: item.variantId ?? '${item.productId}_v0',
              quantity: item.quantity.round(),
              valuationMethod: valMethod,
            ));
          }
        }
      }

      // Atomic write: sale + transactions + stock deductions in one transaction
      final success = await ref.read(salesProvider.notifier).addSaleAtomic(
        sale,
        saleTxns,
        stockDeductions: deductions,
      );

      if (!success) {
        if (mounted) _showError(l10n.failedToSaveSale);
        return;
      }
      if (!mounted) return;
    }

    // ── Shopify sync (fire-and-forget) ─────────────────────
    // On edit: push allowed changes to linked Shopify order.
    // On create: no auto-push (manual sales stay local-only).
    if (_isEditing &&
        sale.externalSource == 'shopify' &&
        sale.externalOrderId != null) {
      ref.read(shopifySyncProvider.notifier).syncOrder(sale);
    }

    final currency = ref.read(currencyProvider);
    final fmt = NumberFormat('#,##0.00', 'en');
    final messenger = ScaffoldMessenger.of(context);

    context.safePop();
    messenger.showSnackBar(SnackBar(
      content: Text(
          _isEditing ? l10n.saleUpdated(currency, fmt.format(sale.total)) : l10n.saleRecorded(currency, fmt.format(sale.total))),
      backgroundColor: AppColors.primaryNavy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.danger,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  /// Checks whether two SaleItem lists have the same content
  /// (product, variant, quantity, unitPrice). Order-insensitive.
  static bool _sameLineItems(List<SaleItem> a, List<SaleItem> b) {
    if (a.length != b.length) return false;
    final keyA = <String, double>{};
    for (final i in a) {
      final k = '${i.productId}:${i.variantId}:${i.unitPrice}';
      keyA[k] = (keyA[k] ?? 0) + i.quantity;
    }
    final keyB = <String, double>{};
    for (final i in b) {
      final k = '${i.productId}:${i.variantId}:${i.unitPrice}';
      keyB[k] = (keyB[k] ?? 0) + i.quantity;
    }
    if (keyA.length != keyB.length) return false;
    for (final entry in keyA.entries) {
      if (keyB[entry.key] != entry.value) return false;
    }
    return true;
  }

  /// Format a double for display in text fields: removes trailing .0
  static String _cleanNumber(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
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
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: onChanged,
      inputFormatters: inputFormatters,
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
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: AppColors.borderLight.withValues(alpha: 0.7)),
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
}

// ── Private helpers ────────────────────────────────────────

class _PaymentMethod {
  final IconData icon;
  final String label;
  const _PaymentMethod(this.icon, this.label);
}

class _LineItem {
  String? productId;
  String? variantId;
  String? variantName;
  final TextEditingController nameCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController priceCtrl;
  double costPrice;

  _LineItem({
    this.productId,
    this.variantId,
    this.variantName,
    required this.nameCtrl,
    required this.qtyCtrl,
    required this.priceCtrl,
    this.costPrice = 0,
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
