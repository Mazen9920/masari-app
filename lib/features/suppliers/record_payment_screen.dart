import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../shared/models/supplier_model.dart';
import '../../shared/models/payment_model.dart';
import '../../shared/models/purchase_model.dart';
import 'add_supplier_screen.dart';

/// Record Payment form — supplier info, amount, method, invoice allocation, notes.
class RecordPaymentScreen extends ConsumerStatefulWidget {
  final String? preselectedSupplierId;
  final String? preselectedPurchaseId;
  const RecordPaymentScreen({super.key, this.preselectedSupplierId, this.preselectedPurchaseId});

  @override
  ConsumerState<RecordPaymentScreen> createState() =>
      _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends ConsumerState<RecordPaymentScreen> {
  String? _selectedSupplierId;
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime _paymentDate = DateTime.now();
  int _methodIdx = 0; // 0=Cash, 1=Bank, 2=InstaPay, 3=VodafoneCash
  final Set<String> _selectedPurchaseIds = {};

  final _methods = [
    _PaymentMethod(Icons.payments_rounded, 'Cash'),
    _PaymentMethod(Icons.account_balance_rounded, 'Bank Transfer'),
    _PaymentMethod(Icons.qr_code_2_rounded, 'InstaPay'),
    _PaymentMethod(Icons.phone_iphone_rounded, 'Vodafone Cash'),
  ];

  double get _payAmount => double.tryParse(_amountCtrl.text) ?? 0;

  @override
  void initState() {
    super.initState();
    _selectedSupplierId = widget.preselectedSupplierId;
    if (widget.preselectedPurchaseId != null) {
      _selectedPurchaseIds.add(widget.preselectedPurchaseId!);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (_payAmount <= 0) return;
    final suppliers = ref.read(suppliersProvider).value ?? [];
    final supplierId = _selectedSupplierId ?? (suppliers.isNotEmpty ? suppliers.first.id : '');
    final supplierName = suppliers
        .cast<Supplier?>()
        .firstWhere((s) => s!.id == supplierId, orElse: () => null)
        ?.name ?? '';
    if (supplierId.isEmpty) return;

    final payment = Payment(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      supplierId: supplierId,
      supplierName: supplierName,
      amount: _payAmount,
      date: _paymentDate,
      method: _methods[_methodIdx].label,
      notes: _notesCtrl.text.trim(),
      appliedToPurchaseIds: _selectedPurchaseIds.toList(),
      createdAt: DateTime.now(),
    );

    ref.read(paymentsProvider.notifier).addPayment(payment);

    // Also record on supplier balance
    ref.read(suppliersProvider.notifier).recordPayment(supplierId, _payAmount);

    // Update purchase payment status for applied purchases
    if (_selectedPurchaseIds.isNotEmpty) {
      final purchasesNotifier = ref.read(purchasesProvider.notifier);
      final allPurchases = ref.read(purchasesProvider);
      var remaining = _payAmount;

      for (final pid in _selectedPurchaseIds) {
        if (remaining <= 0) break;
        final purchase = allPurchases.cast<Purchase?>().firstWhere(
          (p) => p!.id == pid,
          orElse: () => null,
        );
        if (purchase == null) continue;

        final newPaid = purchase.amountPaid + remaining;
        final purchaseTotal = purchase.total;

        if (newPaid >= purchaseTotal) {
          // Fully paid
          purchasesNotifier.updatePurchase(purchase.copyWith(
            paymentStatus: 2,
            amountPaid: purchaseTotal,
          ));
          remaining -= (purchaseTotal - purchase.amountPaid);
        } else {
          // Partial
          purchasesNotifier.updatePurchase(purchase.copyWith(
            paymentStatus: 1,
            amountPaid: newPaid,
          ));
          remaining = 0;
        }
      }
    }

    HapticFeedback.mediumImpact();
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Payment recorded'),
        backgroundColor: AppColors.primaryNavy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
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
                  subtitle: Row(
                    children: [
                      Text(s.category,
                          style: TextStyle(
                              color: AppColors.textTertiary, fontSize: 12)),
                      if (s.hasDue) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${ref.read(currencyProvider)} ${NumberFormat('#,##0').format(s.balance)} due',
                          style: const TextStyle(
                            color: Color(0xFFE67E22),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
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

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(suppliersProvider).value ?? [];
    final purchases = ref.watch(purchasesProvider);
    final currency = ref.watch(currencyProvider);
    final supplier = _selectedSupplierId != null
        ? suppliers.cast<Supplier?>().firstWhere(
              (s) => s!.id == _selectedSupplierId,
              orElse: () => null,
            )
        : null;
    // Filter purchases to the selected supplier's unpaid/partial purchases
    final supplierPurchases = _selectedSupplierId != null
        ? purchases.where((p) => p.supplierId == _selectedSupplierId && p.paymentStatus < 2).toList()
        : <Purchase>[];
    final fmt = NumberFormat('#,##0', 'en');

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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                child: Column(
                  children: [
                    // Supplier picker
                    _buildSupplierPicker(suppliers, supplier, fmt, currency)
                        .animate()
                        .fadeIn(duration: 250.ms),
                    const SizedBox(height: 14),
                    // Payment details
                    _buildPaymentDetails(fmt)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 60.ms),
                    const SizedBox(height: 14),
                    // Open invoices
                    _buildInvoices(fmt, supplierPurchases, currency)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 120.ms),
                    const SizedBox(height: 14),
                    // Notes & attachments
                    _buildNotesSection()
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 180.ms),
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
                  'Confirm Payment',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                if (_payAmount > 0) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$currency ${fmt.format(_payAmount)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── SUPPLIER PICKER ───
  Widget _buildSupplierPicker(
      List<Supplier> suppliers, Supplier? supplier, NumberFormat fmt, String currency) {
    return GestureDetector(
      onTap: () => _showSupplierPicker(suppliers),
      child: Container(
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
        child: supplier != null
            ? Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: supplier.avatarBg,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            supplier.initials,
                            style: TextStyle(
                              color: supplier.avatarTextColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PAYING TO',
                              style: TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.8,
                              ),
                            ),
                            Text(
                              supplier.name,
                              style: TextStyle(
                                color: AppColors.primaryNavy,
                                fontWeight: FontWeight.w700,
                                fontSize: 17,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'Change',
                        style: TextStyle(
                          color: const Color(0xFF3498DB),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.expand_more_rounded,
                          color: AppColors.textTertiary, size: 22),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Divider(
                      height: 1,
                      color: AppColors.borderLight.withValues(alpha: 0.3)),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Total Balance Due',
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '$currency ${fmt.format(supplier.balance)}',
                        style: const TextStyle(
                          color: Color(0xFFE67E22),
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primaryNavy.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.store_rounded,
                        color: AppColors.textTertiary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Select a supplier',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(Icons.expand_more_rounded,
                      color: AppColors.textTertiary, size: 22),
                ],
              ),
      ),
    );
  }

  // ─── HEADER ───
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
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            iconSize: 26,
            color: AppColors.textSecondary,
          ),
          Expanded(
            child: Center(
              child: Text(
                'Record Payment',
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

  // ─── PAYMENT DETAILS SECTION ───
  Widget _buildPaymentDetails(NumberFormat fmt) {
    final dateFmt = DateFormat('MMM dd, yyyy');
    final currency = ref.watch(currencyProvider);

    return _Card(
      children: [
        // Amount input
        Text(
          'Amount to Pay',
          style: TextStyle(
            color: AppColors.textTertiary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          style: TextStyle(
            color: AppColors.primaryNavy,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Text(
                currency,
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 0),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppColors.borderLight.withValues(alpha: 0.7),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppColors.borderLight.withValues(alpha: 0.7),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.primaryNavy, width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
        const SizedBox(height: 18),
        // Date row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Payment Date',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            GestureDetector(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _paymentDate,
                  firstDate:
                      DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _paymentDate = d);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.borderLight.withValues(alpha: 0.7),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_rounded,
                        color: AppColors.textTertiary, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      dateFmt.format(_paymentDate),
                      style: TextStyle(
                        color: AppColors.primaryNavy,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Divider(
            height: 28,
            color: AppColors.borderLight.withValues(alpha: 0.3)),
        // Payment method
        Text(
          'Payment Method',
          style: TextStyle(
            color: AppColors.textTertiary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: List.generate(_methods.length, (i) {
            final selected = _methodIdx == i;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _methodIdx = i);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primaryNavy.withValues(alpha: 0.05)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? AppColors.primaryNavy
                        : AppColors.borderLight.withValues(alpha: 0.7),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _methods[i].icon,
                      size: 24,
                      color: selected
                          ? AppColors.primaryNavy
                          : AppColors.textTertiary,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _methods[i].label,
                      style: TextStyle(
                        color: selected
                            ? AppColors.primaryNavy
                            : AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
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

  // ─── OPEN INVOICES SECTION ───
  Widget _buildInvoices(NumberFormat fmt, List<Purchase> openPurchases, String currency) {
    return _Card(
      headerTitle: 'Open Invoices',
      headerTrailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${openPurchases.length} Open',
          style: const TextStyle(
            color: Color(0xFFD97706),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      noPadding: true,
      children: [
        if (openPurchases.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              child: Text(
                'No open invoices for this supplier',
                style: TextStyle(color: AppColors.textTertiary),
              ),
            ),
          )
        else
          ...List.generate(openPurchases.length, (i) {
            final purchase = openPurchases[i];
            final checked = _selectedPurchaseIds.contains(purchase.id);
            final isUnpaid = purchase.paymentStatus == 0;

          return Column(
            children: [
              if (i > 0)
                Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: AppColors.borderLight.withValues(alpha: 0.3)),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    if (checked) {
                      _selectedPurchaseIds.remove(purchase.id);
                    } else {
                      _selectedPurchaseIds.add(purchase.id);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  color: checked
                      ? AppColors.primaryNavy.withValues(alpha: 0.02)
                      : Colors.transparent,
                  child: Row(
                    children: [
                      // Checkbox
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: checked
                              ? AppColors.primaryNavy
                              : Colors.white,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: checked
                                ? AppColors.primaryNavy
                                : AppColors.borderLight,
                            width: 1.5,
                          ),
                        ),
                        child: checked
                            ? const Icon(Icons.check_rounded,
                                color: Colors.white, size: 16)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: checked ? 1.0 : 0.6,
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    purchase.referenceNo.isNotEmpty ? purchase.referenceNo : '#${purchase.id.substring(0, 8)}',
                                    style: TextStyle(
                                      color: AppColors.primaryNavy,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '$currency ${fmt.format(purchase.outstanding)}',
                                    style: TextStyle(
                                      color: AppColors.primaryNavy,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    DateFormat('MMM dd, yyyy').format(purchase.date),
                                    style: TextStyle(
                                      color: AppColors.textTertiary,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isUnpaid
                                          ? const Color(0xFFFFF7ED)
                                          : const Color(0xFFF8FAFC),
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      purchase.statusLabel,
                                      style: TextStyle(
                                        color: isUnpaid
                                            ? const Color(0xFFEA580C)
                                            : AppColors.textTertiary,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  // ─── NOTES & ATTACHMENTS ───
  Widget _buildNotesSection() {
    return _Card(
      children: [
        Text(
          'Notes',
          style: TextStyle(
            color: AppColors.textTertiary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _notesCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Add payment reference details...',
            hintStyle:
                TextStyle(color: AppColors.textTertiary, fontSize: 14),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppColors.borderLight.withValues(alpha: 0.7),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppColors.borderLight.withValues(alpha: 0.7),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.primaryNavy),
            ),
            contentPadding: const EdgeInsets.all(14),
          ),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
        ),
        const SizedBox(height: 14),
        // Upload receipt button (dashed border)
        GestureDetector(
          onTap: () => HapticFeedback.lightImpact(),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.borderLight,
                style: BorderStyle.solid,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.camera_alt_rounded,
                    color: AppColors.textSecondary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Upload Receipt',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
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
}


// ═══════════════════════════════════════════════════════
//  GENERIC CARD WRAPPER
// ═══════════════════════════════════════════════════════
class _Card extends StatelessWidget {
  final String? headerTitle;
  final Widget? headerTrailing;
  final List<Widget> children;
  final bool noPadding;

  const _Card({
    this.headerTitle,
    this.headerTrailing,
    required this.children,
    this.noPadding = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
          if (headerTitle != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC).withValues(alpha: 0.5),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.borderLight.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    headerTitle!,
                    style: TextStyle(
                      color: AppColors.primaryNavy,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  if (headerTrailing != null) headerTrailing!,
                ],
              ),
            ),
          Padding(
            padding: noPadding ? EdgeInsets.zero : const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentMethod {
  final IconData icon;
  final String label;
  const _PaymentMethod(this.icon, this.label);
}
