import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/models/supplier_model.dart';
import '../../shared/models/product_model.dart';
import '../../features/suppliers/widgets/item_selection_sheet.dart';
import 'add_supplier_screen.dart';

/// Record Purchase form — supplier, items, totals, payment status.
class RecordPurchaseScreen extends ConsumerStatefulWidget {
  final String? preselectedSupplierId;
  const RecordPurchaseScreen({super.key, this.preselectedSupplierId});

  @override
  ConsumerState<RecordPurchaseScreen> createState() =>
      _RecordPurchaseScreenState();
}

class _RecordPurchaseScreenState extends ConsumerState<RecordPurchaseScreen> {
  String? _selectedSupplierId;
  DateTime _purchaseDate = DateTime.now();
  final _refCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  int _paymentStatus = 0; // 0=Unpaid, 1=Partial, 2=Fully Paid
  DateTime? _dueDate;
  final _paidAmountCtrl = TextEditingController();

  final List<_PurchaseItem> _items = [
    _PurchaseItem(name: 'Premium Flour (50kg)', category: 'Inventory', qty: 2, unitPrice: 800),
    _PurchaseItem(name: 'Yeast Packets', category: 'Supplies', qty: 10, unitPrice: 45),
  ];

  double get _subtotal =>
      _items.fold<double>(0, (s, item) => s + item.total);

  double get _tax => double.tryParse(_taxCtrl.text) ?? 0;

  double get _total => _subtotal + _tax;

  @override
  void dispose() {
    _refCtrl.dispose();
    _taxCtrl.dispose();
    _paidAmountCtrl.dispose();
    super.dispose();
  }

  void _save() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Purchase recorded'),
        backgroundColor: AppColors.primaryNavy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(suppliersProvider);
    final inventory = ref.watch(inventoryProvider);
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
                    _buildItemsSection(fmt, inventory)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 60.ms),
                    const SizedBox(height: 16),
                    // Totals section
                    _buildTotalsSection(fmt)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 120.ms),
                    const SizedBox(height: 16),
                    // Payment status section
                    _buildPaymentStatusSection()
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
              color: const Color(0xFFE67E22),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE67E22).withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Confirm Purchase',
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
                'Record Purchase',
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
                'Save',
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
      title: 'DETAILS',
      children: [
        // Supplier picker
        _Label('Supplier'),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => _showSupplierPicker(suppliers),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
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
                        : suppliers.isNotEmpty
                            ? suppliers.first.name
                            : 'Select a supplier',
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
                  _Label('Purchase Date'),
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
                        color: const Color(0xFFF8FAFC),
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
                  _Label('Reference No.'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _refCtrl,
                    decoration: InputDecoration(
                      hintText: 'Optional',
                      hintStyle: TextStyle(
                          color: AppColors.textTertiary, fontSize: 14),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
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
                'Select Supplier',
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
                          color: Color(0xFFE67E22))
                      : null,
                  onTap: () {
                    setState(() => _selectedSupplierId = s.id);
                    Navigator.of(ctx).pop();
                  },
                )),
            // Add new supplier option
            ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFE67E22).withValues(alpha: 0.1),
                child: const Icon(Icons.add_rounded,
                    color: Color(0xFFE67E22), size: 20),
              ),
              title: const Text('+ Add New Supplier',
                  style: TextStyle(
                      color: Color(0xFFE67E22),
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
  //  SECTION 2 — ITEMS
  // ═══════════════════════════════════════════════════════
  Widget _buildItemsSection(NumberFormat fmt, List<Product> inventory) {
    return _Card(
      title: 'ITEMS PURCHASED',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primaryNavy.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${_items.length} Items',
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
                          'ITEM',
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
                            final result = await showModalBottomSheet<ItemSelectionResult>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (context) => ItemSelectionSheet(inventory: inventory),
                            );

                            if (result != null) {
                              setState(() {
                                if (result.product != null) {
                                  final p = result.product!;
                                  _items[i] = item.copyWith(
                                    name: p.name,
                                    category: p.isMaterial ? 'Raw Material' : p.category,
                                    unitPrice: p.costPrice,
                                  );
                                } else if (result.customName != null && result.customName!.isNotEmpty) {
                                  _items[i] = item.copyWith(
                                    name: result.customName,
                                    category: 'General',
                                  );
                                }
                              });
                            }
                          },
                          child: Container(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.name.isEmpty ? 'Tap to select item' : item.name,
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
                          child: Text(
                            item.category,
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Qty
                  Column(
                    children: [
                      Text(
                        'QTY',
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
                          textAlign: TextAlign.center,
                          onChanged: (v) {
                            setState(() {
                              _items[i] = item.copyWith(
                                  qty: int.tryParse(v) ?? item.qty);
                            });
                          },
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
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
                        'UNIT PRICE',
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
                          textAlign: TextAlign.right,
                          onChanged: (v) {
                            setState(() {
                              _items[i] = item.copyWith(
                                  unitPrice:
                                      double.tryParse(v) ?? item.unitPrice);
                            });
                          },
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
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
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() {
              _items.add(_PurchaseItem(
                name: 'New Item',
                category: 'General',
                qty: 1,
                unitPrice: 0,
              ));
            });
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFE67E22).withValues(alpha: 0.3),
                style: BorderStyle.solid,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_circle_outline_rounded,
                    color: const Color(0xFFE67E22), size: 20),
                const SizedBox(width: 8),
                Text(
                  'Add Another Item',
                  style: TextStyle(
                    color: const Color(0xFFE67E22),
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
  Widget _buildTotalsSection(NumberFormat fmt) {
    return _Card(
      children: [
        // Subtotal
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Subtotal',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
            Text('${fmt.format(_subtotal)} EGP',
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
                Text('Tax ',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
                Text('(Optional)',
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
                    textAlign: TextAlign.right,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: '0.00',
                      hintStyle: TextStyle(
                          color: AppColors.textTertiary, fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
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
                Text('EGP',
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
              'Total Amount',
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
                    text: ' EGP',
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
  Widget _buildPaymentStatusSection() {
    final statusLabels = ['Unpaid', 'Partial', 'Fully Paid'];

    return _Card(
      title: 'PAYMENT STATUS',
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
          _Label('Due Date'),
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
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.borderLight.withValues(alpha: 0.7),
                ),
              ),
              child: Text(
                _dueDate != null
                    ? DateFormat('yyyy-MM-dd').format(_dueDate!)
                    : 'Select due date',
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
                'Alert will be sent on this date.',
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
          _Label('Amount Paid'),
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
                  'EGP',
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
              fillColor: const Color(0xFFF8FAFC),
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
          _Label('Due Date for Remaining'),
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
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.borderLight.withValues(alpha: 0.7),
                ),
              ),
              child: Text(
                _dueDate != null
                    ? DateFormat('yyyy-MM-dd').format(_dueDate!)
                    : 'Select due date',
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
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF16A34A), size: 20),
                const SizedBox(width: 8),
                Text(
                  'This purchase is fully paid',
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
                if (trailing != null) trailing!,
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
class _PurchaseItem {
  final String name;
  final String category;
  final int qty;
  final double unitPrice;

  const _PurchaseItem({
    required this.name,
    required this.category,
    required this.qty,
    required this.unitPrice,
  });

  double get total => qty * unitPrice;

  _PurchaseItem copyWith({
    String? name,
    String? category,
    int? qty,
    double? unitPrice,
  }) {
    return _PurchaseItem(
      name: name ?? this.name,
      category: category ?? this.category,
      qty: qty ?? this.qty,
      unitPrice: unitPrice ?? this.unitPrice,
    );
  }
}
