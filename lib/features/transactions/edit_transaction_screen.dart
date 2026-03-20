import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../shared/models/transaction_model.dart';
import '../../shared/models/category_data.dart';
import '../../shared/models/payment_model.dart';
import '../auth/widgets/form_components.dart';
import '../../shared/utils/safe_pop.dart';
import '../../shared/widgets/discard_changes_dialog.dart';

class EditTransactionScreen extends ConsumerStatefulWidget {
  final Transaction transaction;
  const EditTransactionScreen({super.key, required this.transaction});

  @override
  ConsumerState<EditTransactionScreen> createState() => _EditTransactionScreenState();
}

class _EditTransactionScreenState extends ConsumerState<EditTransactionScreen> {
  bool _isExpense = true;
  String _amount = '0';
  String? _selectedCategoryId;
  String? _expenseCategoryId;
  String? _incomeCategoryId;
  int _selectedPaymentIndex = 0;
  final _noteController = TextEditingController();
  late DateTime _selectedDate;

  final List<_PaymentMethod> _paymentMethods = [
    _PaymentMethod('Cash', Icons.payments_rounded),
    _PaymentMethod('Card', Icons.credit_card_rounded),
    _PaymentMethod('Bank', Icons.account_balance_rounded),
    _PaymentMethod('Wallet', Icons.account_balance_wallet_rounded),
  ];

  bool _isCategoryExpanded = false;
  String? _selectedSupplierId;
  final _payeeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Prepopulate data
    final t = widget.transaction;
    _amount = t.amount.abs().toString();
    if (_amount.endsWith('.0')) _amount = _amount.substring(0, _amount.length - 2);
    _isExpense = t.amount < 0;
    
    _selectedCategoryId = t.categoryId;
    if (_isExpense) {
      _expenseCategoryId = t.categoryId;
    } else {
      _incomeCategoryId = t.categoryId;
    }

    // Find payment method index
    final payIndex = _paymentMethods.indexWhere((p) => p.name == t.paymentMethod);
    if (payIndex != -1) _selectedPaymentIndex = payIndex;

    _noteController.text = t.note ?? '';
    _selectedDate = t.dateTime;

    _selectedSupplierId = t.supplierId;
    
    // Check if title is custom payee
    final category = CategoryData.findById(t.categoryId);
    if (t.supplierId == null && t.title != category.name && t.title != 'Uncategorized') {
      _payeeController.text = t.title;
    }
  }

  List<CategoryData> get _displayCategories {
    final categories = ref.watch(categoriesProvider).value ?? [];
    if (categories.isEmpty) return [];

    final filtered = categories.where((c) => c.isExpense == _isExpense).toList();

    // Sort by most used, but push COGS and Shipping to the end
    const pinToEnd = {'cat_cogs', 'cat_shipping', 'cat_sales_revenue'};
    final transactions = ref.read(transactionsProvider).value ?? [];
    final usageCount = <String, int>{};
    for (final t in transactions) {
      usageCount[t.categoryId] = (usageCount[t.categoryId] ?? 0) + 1;
    }
    filtered.sort((a, b) {
      final aPinned = pinToEnd.contains(a.id) ? 1 : 0;
      final bPinned = pinToEnd.contains(b.id) ? 1 : 0;
      if (aPinned != bPinned) return aPinned - bPinned;
      return (usageCount[b.id] ?? 0).compareTo(usageCount[a.id] ?? 0);
    });

    return filtered;
  }

  @override
  void dispose() {
    _noteController.dispose();
    _payeeController.dispose();
    super.dispose();
  }

  // ─── Numpad Logic ───
  void _onNumberTap(String value) {
    HapticFeedback.lightImpact();
    setState(() {
      if (value == '.' && _amount.contains('.')) return;
      if (_amount.contains('.') && _amount.split('.').last.length >= 2) return;
      if (_amount == '0' && value != '.') {
        _amount = value;
      } else {
        _amount += value;
      }
    });
  }

  void _onBackspace() {
    HapticFeedback.lightImpact();
    setState(() {
      if (_amount.length <= 1) {
        _amount = '0';
      } else {
        _amount = _amount.substring(0, _amount.length - 1);
      }
    });
  }

  String get _formattedAmount {
    final parsed = double.tryParse(_amount) ?? 0;
    if (_amount.contains('.')) {
      return _amount;
    }
    return parsed.toStringAsFixed(parsed == parsed.roundToDouble() ? 0 : 2);
  }

  Future<void> _onSave() async {
    HapticFeedback.mediumImpact();
    
    // Create transaction object
    final amount = double.tryParse(_amount) ?? 0;
    if (amount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }
    
    // Get payee name if selected or custom
    final suppliers = ref.read(suppliersProvider).value ?? [];
    final supplierName = suppliers.where((s) => s.id == _selectedSupplierId).firstOrNull?.name;
    final customPayee = _payeeController.text.trim();
    
    String finalCategoryId = _selectedCategoryId ?? '';
    final category = CategoryData.findById(finalCategoryId);
    
    // Title order of precedence: Custom Payee > Selected Supplier > Category Name
    String finalTitle = category.name;
    if (customPayee.isNotEmpty) {
      finalTitle = customPayee;
    } else if (supplierName != null) {
      finalTitle = supplierName;
    }
    
    // Get payment method name
    final paymentMethodName = _paymentMethods[_selectedPaymentIndex].name;
    
    // Get note text
    final noteText = _noteController.text.trim();
    
    // Re-create transaction object directly keeping ID & Dates
    final updatedTransaction = Transaction(
      id: widget.transaction.id,
      userId: widget.transaction.userId,
      title: finalTitle,
      amount: _isExpense ? -amount : amount,
      categoryId: category.id,
      dateTime: _selectedDate,
      note: noteText.isNotEmpty ? noteText : null,
      paymentMethod: paymentMethodName,
      supplierId: _selectedSupplierId, 
      createdAt: widget.transaction.createdAt,
      updatedAt: DateTime.now(), // Update timestamp
      saleId: widget.transaction.saleId,
      excludeFromPL: widget.transaction.excludeFromPL,
    );
    
    final transNotifier = ref.read(transactionsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    // Optimistic update — state changes immediately before Firestore write
    await transNotifier.updateTransaction(updatedTransaction);

    // ── Sync supplier payment if this is a supplier-payment transaction ──
    if (widget.transaction.categoryId == 'cat_supplier_payment' &&
        widget.transaction.supplierId != null) {
      _syncSupplierPayment(
        ref,
        originalTransaction: widget.transaction,
        updatedTransaction: updatedTransaction,
      );
    }

    if (!mounted) return;
    context.safePop();
    
    // Show success feedback
    messenger.showSnackBar(
      const SnackBar(content: Text('Transaction updated')),
    );
  }

  /// When a supplier-payment transaction is edited, sync the amount and date
  /// changes back to the corresponding [Payment] and the supplier balance.
  void _syncSupplierPayment(
    WidgetRef ref, {
    required Transaction originalTransaction,
    required Transaction updatedTransaction,
  }) {
    final oldAmount = originalTransaction.amount.abs();
    final newAmount = updatedTransaction.amount.abs();
    final amountDiff = newAmount - oldAmount;

    // Find the linked Payment by transactionId first, then fallback to matching
    final payments = ref.read(paymentsProvider).value ?? [];
    final linkedPayment = payments.cast<Payment?>().firstWhere(
      (p) => p!.transactionId == originalTransaction.id,
      orElse: () => null,
    ) ?? payments.cast<Payment?>().firstWhere(
      (p) =>
          p!.supplierId == originalTransaction.supplierId &&
          p.amount == oldAmount &&
          p.date.year == originalTransaction.dateTime.year &&
          p.date.month == originalTransaction.dateTime.month &&
          p.date.day == originalTransaction.dateTime.day,
      orElse: () => null,
    );

    if (linkedPayment != null) {
      // Update the Payment record
      ref.read(paymentsProvider.notifier).updatePayment(
        linkedPayment.copyWith(
          amount: newAmount,
          date: updatedTransaction.dateTime,
          method: updatedTransaction.paymentMethod,
          notes: updatedTransaction.note ?? linkedPayment.notes,
        ),
      );
    }

    // Adjust supplier balance for the difference
    if (amountDiff != 0 && originalTransaction.supplierId != null) {
      ref
          .read(suppliersProvider.notifier)
          .recordPayment(originalTransaction.supplierId!, amountDiff);

      // Recalculate purchase payment statuses based on updated payment amounts
      _recalcPurchaseStatuses(ref, originalTransaction.supplierId!);
    }
  }

  /// Recalculate purchase payment statuses for a supplier based on all
  /// Payment records that reference those purchases.
  void _recalcPurchaseStatuses(WidgetRef ref, String supplierId) {
    final allPayments = ref.read(paymentsProvider).value ?? [];
    final allPurchases = ref.read(purchasesProvider).value ?? [];
    final supplierPurchases =
        allPurchases.where((p) => p.supplierId == supplierId).toList();

    for (final purchase in supplierPurchases) {
      final totalPaidFromPayments = allPayments
          .where((pay) => pay.appliedToPurchaseIds.contains(purchase.id))
          .fold<double>(0, (s, pay) => s + pay.amount);

      int newStatus;
      double newAmountPaid;
      if (totalPaidFromPayments >= purchase.total) {
        newStatus = 2; // Fully Paid
        newAmountPaid = purchase.total;
      } else if (totalPaidFromPayments > 0) {
        newStatus = 1; // Partial
        newAmountPaid = totalPaidFromPayments;
      } else {
        newStatus = 0; // Unpaid
        newAmountPaid = 0;
      }

      if (purchase.paymentStatus != newStatus ||
          purchase.amountPaid != newAmountPaid) {
        ref.read(purchasesProvider.notifier).updatePurchase(
              purchase.copyWith(
                  paymentStatus: newStatus, amountPaid: newAmountPaid),
            );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await showDiscardChangesDialog(context);
        if (shouldPop && context.mounted) context.safePop();
      },
      child: Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Top bar: close + title ───
            _buildTopBar(),

            // ─── Expense / Income toggle ───
            _buildToggle(),

            // ─── Scrollable content ───
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    // Amount display
                    _buildAmountDisplay(),

                    // Numpad
                    _buildNumpad(),

                    const SizedBox(height: 8),

                    // Removed quick tags

                    // Details section (rounded top)
                    _buildDetailsSection(),
                  ],
                ),
              ),
            ),

            // ─── Sticky bottom: summary + save ───
            _buildBottomBar(),
          ],
        ),
      ),
    ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  TOP BAR
  // ═══════════════════════════════════════════════════
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => context.safePop(),
            icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
          ),
          Text(
            'Edit Transaction',
            style: AppTypography.h3.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 48), // balance spacer
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  EXPENSE / INCOME TOGGLE
  // ═══════════════════════════════════════════════════
  Widget _buildToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.backgroundLight,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Stack(
          children: [
            // Animated background pill
            AnimatedAlign(
              alignment: _isExpense
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                child: Container(
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: _isExpense ? AppColors.danger : AppColors.success,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: (_isExpense ? AppColors.danger : AppColors.success)
                            .withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Button labels
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _incomeCategoryId = _selectedCategoryId;
                        _isExpense = true;
                        _selectedCategoryId = _expenseCategoryId ?? (_displayCategories.isNotEmpty ? _displayCategories.first.id : null);
                      });
                    },
                    child: Center(
                      child: Text(
                        'Expense',
                        style: AppTypography.labelMedium.copyWith(
                          color: _isExpense ? Colors.white : AppColors.textTertiary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _expenseCategoryId = _selectedCategoryId;
                        _isExpense = false;
                        _selectedCategoryId = _incomeCategoryId ?? (_displayCategories.isNotEmpty ? _displayCategories.first.id : null);
                      });
                    },
                    child: Center(
                      child: Text(
                        'Income',
                        style: AppTypography.labelMedium.copyWith(
                          color: !_isExpense ? Colors.white : AppColors.textTertiary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  AMOUNT DISPLAY
  // ═══════════════════════════════════════════════════
  Widget _buildAmountDisplay() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Text(
            'AMOUNT',
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${ref.watch(appSettingsProvider).currency} ',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textTertiary,
                  fontFamily: 'Inter',
                ),
              ),
              Text(
                _formattedAmount,
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryNavy,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  NUMPAD
  // ═══════════════════════════════════════════════════
  Widget _buildNumpad() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.6,
        children: [
          ...[1, 2, 3, 4, 5, 6, 7, 8, 9].map((n) => _numKey('$n')),
          _numKey('.'),
          _numKey('0'),
          _backspaceKey(),
        ],
      ),
    );
  }

  Widget _numKey(String value) {
    return Material(
      color: AppColors.backgroundLight,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _onNumberTap(value),
        borderRadius: BorderRadius.circular(14),
        child: Center(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              fontFamily: 'Inter',
            ),
          ),
        ),
      ),
    );
  }

  Widget _backspaceKey() {
    return Material(
      color: AppColors.backgroundLight,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: _onBackspace,
        onLongPress: () {
          HapticFeedback.mediumImpact();
          setState(() => _amount = '0');
        },
        borderRadius: BorderRadius.circular(14),
        child: const Center(
          child: Icon(
            Icons.backspace_outlined,
            color: AppColors.textSecondary,
            size: 22,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // ═══════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════
  //  DETAILS SECTION (categories, payment, date, note, recurring)
  // ═══════════════════════════════════════════════════
  Widget _buildDetailsSection() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: AppColors.borderLight.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Category Grid ───
          _sectionHeader('Category', showSeeAll: true),
          const SizedBox(height: 12),
          _buildCategoryGrid(),

          const SizedBox(height: 24),

          // ─── Payee ───
          _buildPayeeRow(),

          const SizedBox(height: 20),

          // ─── Payment Method ───
          _sectionHeader('Payment Method'),
          const SizedBox(height: 10),
          _buildPaymentMethods(),

          const SizedBox(height: 20),

          // ─── Date ───
          _buildDateField(),

          const SizedBox(height: 14),

          // ─── Note ───
          _buildNoteField(),

          const SizedBox(height: 14),

          // Removed Recurring Toggle

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, {bool showSeeAll = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (showSeeAll)
          GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All categories view coming soon')));
            },
            child: Text(
              'See All',
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.accentOrange,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCategoryGrid() {
    final cats = _displayCategories;
    final displayLimit = _isCategoryExpanded ? cats.length : 7;
    
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: cats.length > displayLimit ? displayLimit + 1 : cats.length,
      itemBuilder: (context, index) {
        // "More" button
        if (index == displayLimit && cats.length > displayLimit) {
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _isCategoryExpanded = true);
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.backgroundLight,
                    ),
                    child: const Icon(
                      Icons.more_horiz_rounded,
                      size: 20,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'More',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        final cat = cats[index];
        final isSelected = _selectedCategoryId == cat.id;

        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => _selectedCategoryId = cat.id);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isSelected ? cat.displayColor.withValues(alpha: 0.08) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: isSelected ? Border.all(color: cat.displayColor.withValues(alpha: 0.3)) : Border.all(color: Colors.transparent),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? cat.displayColor : cat.displayBgColor,
                    boxShadow: isSelected
                        ? [BoxShadow(color: cat.displayColor.withValues(alpha: 0.3), blurRadius: 8)]
                        : null,
                  ),
                  child: Icon(
                    cat.iconData,
                    size: 20,
                    color: isSelected ? Colors.white : cat.displayColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  cat.name,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? cat.displayColor : AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPayeeRow() {
    final suppliers = ref.watch(suppliersProvider).value ?? [];
    final selectedSupplier = suppliers.where((s) => s.id == _selectedSupplierId).firstOrNull;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFEBF5FB), // blue-50
            ),
            child: const Icon(Icons.storefront_rounded,
                size: 18, color: AppColors.secondaryBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _payeeController,
              decoration: InputDecoration(
                hintText: selectedSupplier?.name ?? 'Payee Name (Optional)',
                hintStyle: AppTypography.labelMedium.copyWith(
                  color: AppColors.textTertiary,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textPrimary,
              ),
              onChanged: (val) {
                // If they start typing, clear the selected supplier ID so it uses custom text
                if (_selectedSupplierId != null) {
                  setState(() => _selectedSupplierId = null);
                }
              },
            ),
          ),
          if (selectedSupplier != null || _payeeController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textTertiary),
              onPressed: () {
                setState(() {
                  _selectedSupplierId = null;
                  _payeeController.clear();
                });
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            )
          else
            IconButton(
              icon: const Icon(Icons.list_alt_rounded, size: 20, color: AppColors.textTertiary),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  useRootNavigator: true,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (ctx) => _buildSupplierSelector(suppliers),
                );
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  Widget _buildSupplierSelector(List<dynamic> suppliers) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Select Payee', style: AppTypography.h3),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => context.safePop(),
              )
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: suppliers.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final s = suppliers[i];
                return ListTile(
                  leading: const Icon(Icons.storefront_rounded, color: AppColors.textSecondary),
                  title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.borderLight),
                  onTap: () {
                    setState(() {
                      _selectedSupplierId = s.id;
                      _payeeController.clear(); // Clear custom text since a supplier is selected
                    });
                    Navigator.pop(ctx);
                  }
                );
              }
            )
          )
        ]
      )
    );
  }

  Widget _buildPaymentMethods() {
    return Row(
      children: List.generate(_paymentMethods.length, (index) {
        final method = _paymentMethods[index];
        final isSelected = _selectedPaymentIndex == index;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedPaymentIndex = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(
                right: index < _paymentMethods.length - 1 ? 8 : 0,
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected
                      ? AppColors.accentOrange
                      : AppColors.borderLight,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    method.icon,
                    size: 22,
                    color: isSelected
                        ? AppColors.accentOrange
                        : AppColors.textTertiary,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    method.name,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                      color: isSelected
                          ? AppColors.accentOrange
                          : AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildDateField() {
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());
    final label = isToday
        ? 'Today, ${DateFormat('MMM d').format(_selectedDate)}'
        : DateFormat('EEE, MMM d, y').format(_selectedDate);
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (picked != null) {
          setState(() => _selectedDate = picked);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded,
                size: 20, color: AppColors.textTertiary),
            const SizedBox(width: 12),
            Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            const Icon(Icons.arrow_drop_down_rounded,
                size: 20, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: _noteController,
        style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary),
        decoration: InputDecoration(
          icon: const Icon(Icons.edit_note_rounded,
              size: 22, color: AppColors.textTertiary),
          hintText: 'Add a note (optional)',
          hintStyle: AppTypography.bodyMedium.copyWith(
            color: AppColors.textTertiary,
          ),
          border: InputBorder.none,
        ),
      ),
    );
  }

  // Removed _buildRecurringToggle as it is unused

  // ═══════════════════════════════════════════════════
  //  BOTTOM BAR: summary + save button
  // ═══════════════════════════════════════════════════
  Widget _buildBottomBar() {
    final cats = _displayCategories;
    CategoryData? cat;
    if (cats.isNotEmpty) {
      cat = cats.firstWhere(
        (c) => c.id == _selectedCategoryId, 
        orElse: () => CategoryData.findById(_selectedCategoryId ?? ''),
      );
    } else {
      cat = CategoryData.findById(_selectedCategoryId ?? '');
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.borderLight.withValues(alpha: 0.5)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Summary strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              color: AppColors.backgroundLight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isExpense ? AppColors.danger : AppColors.success,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isExpense ? 'Expense' : 'Income',
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        ' · ${ref.watch(appSettingsProvider).currency} $_formattedAmount',
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${cat.name} · Today',
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: MasariPrimaryButton(
                text: 'Save Changes',
                icon: Icons.check_rounded,
                onPressed: _amount != '0' ? _onSave : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Data Models ───

class _PaymentMethod {
  final String name;
  final IconData icon;
  const _PaymentMethod(this.name, this.icon);
}


