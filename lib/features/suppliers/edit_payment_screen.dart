import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/models/supplier_model.dart';
import '../../shared/models/payment_model.dart';
import '../../shared/models/purchase_model.dart';

/// Edit Payment — pre-filled form for modifying an existing payment.
class EditPaymentScreen extends ConsumerStatefulWidget {
  final String? supplierId;
  final Payment? payment;
  const EditPaymentScreen({super.key, this.supplierId, this.payment});

  @override
  ConsumerState<EditPaymentScreen> createState() => _EditPaymentScreenState();
}

class _EditPaymentScreenState extends ConsumerState<EditPaymentScreen> {
  AppLocalizations get l10n => AppLocalizations.of(context)!;

  String _localizedMethodName(String method) {
    switch (method) {
      case 'Cash': return l10n.cash;
      case 'Bank Transfer': return l10n.bankTransfer;
      case 'InstaPay': return l10n.instaPay;
      case 'Vodafone Cash': return l10n.vodafoneCash;
      default: return method;
    }
  }

  late final TextEditingController _amountCtrl;
  late final TextEditingController _notesCtrl;
  DateTime _paymentDate = DateTime.now();
  int _methodIdx = 0;

  final _methods = [
    _PayMethod(Icons.payments_rounded, 'Cash'),
    _PayMethod(Icons.account_balance_rounded, 'Bank Transfer'),
    _PayMethod(Icons.qr_code_2_rounded, 'InstaPay'),
    _PayMethod(Icons.phone_iphone_rounded, 'Vodafone Cash'),
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.payment;
    _amountCtrl = TextEditingController(text: p != null ? (p.amount == p.amount.truncateToDouble() ? p.amount.toStringAsFixed(0) : p.amount.toStringAsFixed(2)) : '');
    _notesCtrl = TextEditingController(text: p?.notes ?? '');
    if (p != null) {
      _paymentDate = p.date;
      _methodIdx = _methods.indexWhere((m) => m.label == p.method);
      if (_methodIdx < 0) _methodIdx = 0;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    if (amount <= 0 || widget.payment == null) return;
    HapticFeedback.mediumImpact();

    final oldPayment = widget.payment!;
    final oldAmount = oldPayment.amount;
    final delta = amount - oldAmount;

    final updated = oldPayment.copyWith(
      amount: amount,
      date: _paymentDate,
      method: _methods[_methodIdx].label,
      notes: _notesCtrl.text.trim(),
    );

    ref.read(paymentsProvider.notifier).updatePayment(updated);

    // C1: Adjust supplier balance by the delta
    if (delta > 0) {
      // Paid more → reduce supplier balance
      ref.read(suppliersProvider.notifier).recordPayment(widget.supplierId!, delta);
    } else if (delta < 0) {
      // Paid less → increase supplier balance
      ref.read(suppliersProvider.notifier).recordPurchase(widget.supplierId!, -delta);
    }

    // C3: Reverse old purchase allocations and reapply with new amount
    if (oldPayment.appliedToPurchaseIds.isNotEmpty) {
      _reversePurchaseAllocations(oldPayment);
      _applyPurchaseAllocations(oldPayment.appliedToPurchaseIds, amount);
    }

    // C6: Recalculate supplier dueDate from earliest unpaid purchase
    _recalcSupplierDueDate();

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.paymentUpdated),
        backgroundColor: AppColors.primaryNavy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// Reverse payment allocations on affected purchases (set them back to
  /// the state before this payment was applied).
  void _reversePurchaseAllocations(Payment payment) {
    final purchasesNotifier = ref.read(purchasesProvider.notifier);
    final allPurchases = ref.read(purchasesProvider).value ?? [];
    var remaining = payment.amount;

    for (final pid in payment.appliedToPurchaseIds) {
      if (remaining <= 0) break;
      final purchase = allPurchases.cast<Purchase?>().firstWhere(
        (p) => p!.id == pid,
        orElse: () => null,
      );
      if (purchase == null) continue;

      // How much of this payment was allocated to this purchase?
      // Mirror the original allocation logic from record_payment_screen:
      final purchaseTotal = purchase.total;
      final wasFullyPaidByThis = purchase.paymentStatus == 2;

      double allocated;
      if (wasFullyPaidByThis) {
        // This payment may have topped it off
        allocated = (purchaseTotal - (purchase.amountPaid - remaining).clamp(0, purchaseTotal))
            .clamp(0, remaining);
        // Simpler: undo to the extent of remaining
        allocated = remaining.clamp(0, purchase.amountPaid);
      } else {
        allocated = remaining.clamp(0, purchase.amountPaid);
      }

      final newPaid = (purchase.amountPaid - allocated).clamp(0.0, purchaseTotal);
      final newStatus = newPaid <= 0 ? 0 : (newPaid >= purchaseTotal ? 2 : 1);

      purchasesNotifier.updatePurchase(purchase.copyWith(
        paymentStatus: newStatus,
        amountPaid: newPaid,
      ));

      remaining -= allocated;
    }
  }

  /// Apply a payment amount across the given purchase IDs (same logic as
  /// record_payment_screen._save).
  void _applyPurchaseAllocations(List<String> purchaseIds, double amount) {
    final purchasesNotifier = ref.read(purchasesProvider.notifier);
    final allPurchases = ref.read(purchasesProvider).value ?? [];
    var remaining = amount;

    for (final pid in purchaseIds) {
      if (remaining <= 0) break;
      final purchase = allPurchases.cast<Purchase?>().firstWhere(
        (p) => p!.id == pid,
        orElse: () => null,
      );
      if (purchase == null) continue;

      final newPaid = purchase.amountPaid + remaining;
      final purchaseTotal = purchase.total;

      if (newPaid >= purchaseTotal) {
        purchasesNotifier.updatePurchase(purchase.copyWith(
          paymentStatus: 2,
          amountPaid: purchaseTotal,
        ));
        remaining -= (purchaseTotal - purchase.amountPaid);
      } else {
        purchasesNotifier.updatePurchase(purchase.copyWith(
          paymentStatus: 1,
          amountPaid: newPaid,
        ));
        remaining = 0;
      }
    }
  }

  /// C6: Recalculate the supplier's dueDate as the earliest due date among
  /// all unpaid/partial purchases for this supplier. Clears dueDate if none.
  void _recalcSupplierDueDate() {
    if (widget.supplierId == null) return;
    final allPurchases = ref.read(purchasesProvider).value ?? [];
    final unpaid = allPurchases
        .where((p) =>
            p.supplierId == widget.supplierId &&
            p.paymentStatus != 2 &&
            p.dueDate != null)
        .toList();

    DateTime? earliest;
    for (final p in unpaid) {
      if (earliest == null || p.dueDate!.isBefore(earliest)) {
        earliest = p.dueDate;
      }
    }

    // Update supplier with the earliest unpaid due date (or null if none)
    final suppliers = ref.read(suppliersProvider).value ?? [];
    final supplier = suppliers.cast<Supplier?>().firstWhere(
      (s) => s!.id == widget.supplierId,
      orElse: () => null,
    );
    if (supplier != null && supplier.dueDate != earliest) {
      ref.read(suppliersProvider.notifier).updateSupplier(
        supplier.id,
        supplier.copyWith(dueDate: earliest),
      );
    }
  }

  void _confirmDelete() {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx)!;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(l10n.deletePaymentTitle),
          content: Text(
            l10n.deletePaymentConfirmation,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.cancel,
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (widget.payment != null) {
                final payment = widget.payment!;

                // C2: Reverse supplier balance (add back the payment amount)
                if (widget.supplierId != null) {
                  ref.read(suppliersProvider.notifier).recordPurchase(
                    widget.supplierId!,
                    payment.amount,
                  );
                }

                // C3: Reverse purchase payment allocations
                if (payment.appliedToPurchaseIds.isNotEmpty) {
                  _reversePurchaseAllocations(payment);
                }

                // C6: Recalculate supplier dueDate from earliest unpaid purchase
                _recalcSupplierDueDate();

                ref.read(paymentsProvider.notifier).removePayment(payment.id);
              }
              Navigator.of(context).pop();
            },
            child: Text(l10n.delete,
                style: TextStyle(
                    color: AppColors.chartRed, fontWeight: FontWeight.w600)),
          ),
        ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(suppliersProvider).value ?? [];
    final supplier = suppliers.isNotEmpty
        ? suppliers.firstWhere(
            (s) => s.id == widget.supplierId,
            orElse: () => suppliers.first,
          )
        : null;
    final fmt = NumberFormat('#,##0');

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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Supplier (read-only)
                    if (supplier != null)
                      _buildSupplierCard(supplier, fmt)
                          .animate()
                          .fadeIn(duration: 250.ms),
                    const SizedBox(height: 16),

                    // Amount
                    _buildAmountSection(fmt)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 60.ms),
                    const SizedBox(height: 16),

                    // Date & Method
                    _buildDateMethod()
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 100.ms),
                    const SizedBox(height: 16),

                    // Invoices
                    _buildInvoices(fmt)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 140.ms),
                    const SizedBox(height: 16),

                    // Notes
                    _buildNotes()
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 160.ms),
                    const SizedBox(height: 24),

                    // Delete
                    Center(
                      child: GestureDetector(
                        onTap: _confirmDelete,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 40),
                          child: Text(
                            l10n.deletePaymentTitle,
                            style: TextStyle(
                              color: AppColors.chartRed,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildSaveButton(),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  HEADER
  // ═══════════════════════════════════════════════════════
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom:
              BorderSide(color: AppColors.borderLight.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Text(
              l10n.cancel,
              style: TextStyle(
                color: AppColors.primaryNavy,
                fontSize: 15,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                l10n.editPaymentTitle,
                style: AppTypography.h2.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: _save,
            child: Text(
              l10n.save,
              style: TextStyle(
                color: AppColors.accentOrange,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  SUPPLIER CARD (read-only)
  // ═══════════════════════════════════════════════════════
  Widget _buildSupplierCard(Supplier supplier, NumberFormat fmt) {
    return _card(
      child: Row(
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
                  l10n.payingTo,
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
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              l10n.lockedLabel,
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  AMOUNT
  // ═══════════════════════════════════════════════════════
  Widget _buildAmountSection(NumberFormat fmt) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.paymentAmountSection,
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                ref.watch(currencyProvider),
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 32,
                    letterSpacing: -0.5,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  DATE & METHOD
  // ═══════════════════════════════════════════════════════
  Widget _buildDateMethod() {
    return _card(
      child: Column(
        children: [
          // Date
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _paymentDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _paymentDate = picked);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded,
                      color: AppColors.textTertiary, size: 20),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.paymentDateLabel,
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        DateFormat('MMM dd, yyyy').format(_paymentDate),
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Icon(Icons.edit_rounded,
                      color: AppColors.textTertiary, size: 18),
                ],
              ),
            ),
          ),
          Divider(
              height: 1,
              color: AppColors.borderLight.withValues(alpha: 0.3)),
          const SizedBox(height: 10),
          // Methods
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.paymentMethodLabel,
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _methods.asMap().entries.map((e) {
                  final i = e.key;
                  final m = e.value;
                  final selected = _methodIdx == i;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _methodIdx = i);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primaryNavy.withValues(alpha: 0.08)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? AppColors.primaryNavy
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(m.icon,
                              size: 18,
                              color: selected
                                  ? AppColors.primaryNavy
                                  : AppColors.textTertiary),
                          const SizedBox(width: 6),
                          Text(
                            _localizedMethodName(m.label),
                            style: TextStyle(
                              color: selected
                                  ? AppColors.primaryNavy
                                  : AppColors.textSecondary,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  INVOICES
  // ═══════════════════════════════════════════════════════
  Widget _buildInvoices(NumberFormat fmt) {
    final currency = ref.watch(currencyProvider);
    final allPurchases = ref.watch(purchasesProvider).value ?? [];
    final appliedIds = widget.payment?.appliedToPurchaseIds ?? [];
    final appliedPurchases = allPurchases.where((p) => appliedIds.contains(p.id)).toList();

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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(
              l10n.appliedToInvoices,
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Divider(
              height: 1,
              color: AppColors.borderLight.withValues(alpha: 0.3)),
          if (appliedPurchases.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.noLinkedInvoices,
                style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
              ),
            )
          else
            ...appliedPurchases.asMap().entries.map((e) {
              final i = e.key;
              final purchase = e.value;
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: i < appliedPurchases.length - 1
                      ? Border(
                          bottom: BorderSide(
                            color: AppColors.borderLight
                                .withValues(alpha: 0.3),
                          ),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(Icons.receipt_long_rounded,
                        color: AppColors.textTertiary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            purchase.referenceNo.isNotEmpty ? purchase.referenceNo : '#${purchase.id.substring(0, 8)}',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            DateFormat('MMM dd, yyyy').format(purchase.date),
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$currency ${fmt.format(purchase.total)}',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: purchase.paymentStatus == 2
                                ? AppColors.chartGreenLight
                                : const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            purchase.localizedStatusLabel(l10n),
                            style: TextStyle(
                              color: purchase.paymentStatus == 2
                                  ? AppColors.success
                                  : AppColors.accentOrange,
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  NOTES
  // ═══════════════════════════════════════════════════════
  Widget _buildNotes() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.notes,
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              height: 1.5,
            ),
            decoration: InputDecoration(
              hintText: l10n.addNoteHint,
              hintStyle:
                  TextStyle(color: AppColors.textTertiary, fontSize: 14),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  SAVE BUTTON
  // ═══════════════════════════════════════════════════════
  Widget _buildSaveButton() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
              color: AppColors.borderLight.withValues(alpha: 0.4)),
        ),
      ),
      child: GestureDetector(
        onTap: _save,
        child: Container(
          width: double.infinity,
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
              const Icon(Icons.check_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                l10n.saveChanges,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  SHARED
  // ═══════════════════════════════════════════════════════
  Widget _card({required Widget child}) {
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
      child: child,
    );
  }
}

class _PayMethod {
  final IconData icon;
  final String label;
  const _PayMethod(this.icon, this.label);
}
