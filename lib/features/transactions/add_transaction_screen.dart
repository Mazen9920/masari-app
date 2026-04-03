import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../l10n/app_localizations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../shared/models/transaction_model.dart';
import '../../shared/models/category_data.dart';
import '../../shared/widgets/discard_changes_dialog.dart';
import '../auth/widgets/form_components.dart';
import '../../shared/utils/safe_pop.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  final bool initialIsExpense;
  final bool hideToggle;

  const AddTransactionScreen({
    super.key,
    this.initialIsExpense = true,
    this.hideToggle = false,
  });

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  AppLocalizations get l10n => AppLocalizations.of(context)!;

  late bool _isExpense = widget.initialIsExpense;
  String _amount = '0';
  int _selectedPaymentIndex = 0;
  final _noteController = TextEditingController();

  DateTime _selectedDate = DateTime.now();

  String? _selectedCategoryId;
  String? _selectedSupplierId;
  final _payeeController = TextEditingController();

  final List<_PaymentMethod> _paymentMethods = const [
    _PaymentMethod('Cash', Icons.payments_rounded),
    _PaymentMethod('Card', Icons.credit_card_rounded),
    _PaymentMethod('Bank', Icons.account_balance_rounded),
    _PaymentMethod('Wallet', Icons.account_balance_wallet_rounded),
  ];

  @override
  void initState() {
    super.initState();
    // Pre-select first category if available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cats = _displayCategories;
      if (cats.isNotEmpty) {
        setState(() => _selectedCategoryId = cats.first.id);
      }
    });
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

  bool _isCategoryExpanded = false;
  bool _isCustomCategory = false;
  final _customCategoryController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    _payeeController.dispose();
    _customCategoryController.dispose();
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

  String _localizedPaymentMethod(String name) {
    switch (name) {
      case 'Cash': return l10n.paymentCash;
      case 'Card': return l10n.paymentCard;
      case 'Bank': return l10n.paymentBank;
      case 'Wallet': return l10n.paymentWallet;
      default: return name;
    }
  }

  /// Builds and saves the transaction. Returns true on success.
  Future<bool> _saveTransaction() async {
    HapticFeedback.mediumImpact();
    
    // Create transaction object
    final amount = double.tryParse(_amount) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pleaseEnterValidAmount)),
      );
      return false;
    }
    
    // Get payee name if selected or custom
    final suppliers = ref.read(suppliersProvider).value ?? [];
    final supplierName = suppliers.where((s) => s.id == _selectedSupplierId).firstOrNull?.name;
    final customPayee = _payeeController.text.trim();
    final customCatText = _customCategoryController.text.trim();
    
    String finalCategoryId = _selectedCategoryId ?? '';
    if (customCatText.isNotEmpty) {
      finalCategoryId = 'cat_uncategorized';
    }

    final category = CategoryData.findById(finalCategoryId);
    
    // Title order of precedence: Custom Payee > Selected Supplier > Custom Category > Category Name
    String finalTitle = category.name;
    if (customPayee.isNotEmpty) {
      finalTitle = customPayee;
    } else if (supplierName != null) {
      finalTitle = supplierName;
    } else if (customCatText.isNotEmpty) {
       finalTitle = customCatText;
    }
    
    // Get payment method name
    final paymentMethodName = _paymentMethods[_selectedPaymentIndex].name;
    
    // Get note text
    final noteText = _noteController.text.trim();
    
    final transaction = Transaction(
      id: const Uuid().v4(),
      userId: ref.read(authProvider).user?.id ?? '',
      title: finalTitle,
      amount: _isExpense ? -amount : amount,
      dateTime: _selectedDate,
      categoryId: category.id,
      note: noteText.isNotEmpty ? noteText : null,
      paymentMethod: paymentMethodName,
    );
    
    // Save to provider
    await ref.read(transactionsProvider.notifier).addTransaction(transaction);
    return true;
  }

  Future<void> _onSave() async {
    final saved = await _saveTransaction();
    if (!saved || !mounted) return;
    context.safePop();
  }

  Future<void> _onSaveAndAnother() async {
    final saved = await _saveTransaction();
    if (!saved || !mounted) return;

    // Reset form for next entry
    setState(() {
      _amount = '0';
      _selectedSupplierId = null;
      _isCustomCategory = false;
      _selectedDate = DateTime.now();
    });
    _noteController.clear();
    _payeeController.clear();
    _customCategoryController.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.savedReadyForNext)),
    );
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

            // ─── Expense / Income toggle (hidden when coming from picker) ───
            if (!widget.hideToggle)
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

                    // Quick tags
                    _buildQuickTags(),

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
            widget.hideToggle
                ? (_isExpense ? l10n.newExpense : l10n.newOtherIncome)
                : l10n.newTransaction,
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
                      if (!_isExpense) {
                        setState(() {
                          _isExpense = true;
                          final cats = _displayCategories;
                          _selectedCategoryId = cats.isNotEmpty ? cats.first.id : null;
                        });
                      }
                    },
                    child: Center(
                      child: Text(
                        l10n.expense,
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
                      if (_isExpense) {
                        setState(() {
                          _isExpense = false;
                          final cats = _displayCategories;
                          _selectedCategoryId = cats.isNotEmpty ? cats.first.id : null;
                        });
                      }
                    },
                    child: Center(
                      child: Text(
                        l10n.income,
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
            l10n.amountLabel,
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
  //  QUICK TAGS
  // ═══════════════════════════════════════════════════
  Widget _buildQuickTags() {
    final transactions = ref.watch(transactionsProvider).value ?? [];
    final filteredTxs = transactions.where((t) =>
        t.isIncome == !_isExpense &&
        t.categoryId != 'cat_cogs' &&
        t.categoryId != 'cat_shipping' &&
        t.categoryId != 'cat_sales_revenue').toList();
    
    if (filteredTxs.isEmpty) return const SizedBox.shrink();

    // Most Used
    final freq = <String, int>{}; 
    for (final t in filteredTxs) {
      freq[t.title] = (freq[t.title] ?? 0) + 1;
    }
    var sortedByFreq = freq.entries.toList()..sort((a,b) => b.value.compareTo(a.value));
    final mostUsedTitles = sortedByFreq.take(2).map((e) => e.key).toList();
    
    // Recent
    var sortedByDate = List.of(filteredTxs)..sort((a,b) => b.dateTime.compareTo(a.dateTime));
    final recentTitles = sortedByDate.map((t) => t.title).where((title) => !mostUsedTitles.contains(title)).toSet().take(2).toList();
    
    final quickTxs = <Transaction>[];
    for (final title in [...mostUsedTitles, ...recentTitles]) {
      final tx = filteredTxs.firstWhere((t) => t.title == title);
      quickTxs.add(tx);
    }

    if (quickTxs.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  l10n.mostUsedAndRecent,
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.accentOrange,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: quickTxs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final tx = quickTxs[index];
                final cat = CategoryData.findById(tx.categoryId);
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _amount = tx.amount.abs().toString();
                      if (_amount.endsWith('.0')) _amount = _amount.replaceAll('.0', '');
                      _selectedCategoryId = tx.categoryId;
                      if (tx.title != cat.name) {
                        _payeeController.text = tx.title; // if it was a custom payee/title, set payee
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundLight,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          cat.localizedName(AppLocalizations.of(context)!),
                          style: AppTypography.captionSmall.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          ' · ${tx.title}',
                          style: AppTypography.captionSmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

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
          _sectionHeader(l10n.category, showSeeAll: false),
          const SizedBox(height: 12),
          _buildCategorySection(),

          const SizedBox(height: 24),

          // ─── Payee ───
          _buildPayeeRow(),

          const SizedBox(height: 20),

          // ─── Payment Method ───
          _sectionHeader(l10n.paymentMethodLabel),
          const SizedBox(height: 10),
          _buildPaymentMethods(),

          const SizedBox(height: 20),

          // ─── Date ───
          _buildDateField(),

          const SizedBox(height: 14),

          // ─── Note ───
          _buildNoteField(),

          const SizedBox(height: 14),

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
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.allCategoriesComingSoon)));
            },
            child: Text(
              l10n.seeAllLabel,
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
    
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: !_isCategoryExpanded && cats.length > 7 ? 8 : cats.length,
      itemBuilder: (context, index) {
        if (!_isCategoryExpanded && index == 7 && cats.length > 7) {
           return GestureDetector(
             onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _isCategoryExpanded = true);
             },
             child: Column(
               mainAxisAlignment: MainAxisAlignment.center,
               children: [
                 Container(
                   width: 40, height: 40,
                   decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.backgroundLight),
                   child: const Icon(Icons.grid_view_rounded, size: 20, color: AppColors.textTertiary)
                 ),
                 const SizedBox(height: 6),
                 Text(l10n.moreLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.textSecondary))
               ]
             )
           );
        }
        
        final cat = cats[index];
        final isSelected = _selectedCategoryId == cat.id;

        // Fallback for missing colors just in case
        final catColor = cat.displayColor;
        
        return GestureDetector(
          onTap: () => setState(() {
            _selectedCategoryId = cat.id;
            _customCategoryController.clear();
            _isCustomCategory = false;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isSelected && !_isCustomCategory
                  ? catColor.withValues(alpha: 0.08)
                  : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: isSelected && !_isCustomCategory
                  ? Border.all(color: catColor.withValues(alpha: 0.3))
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected && !_isCustomCategory
                        ? catColor
                        : AppColors.backgroundLight,
                    boxShadow: isSelected && !_isCustomCategory
                        ? [
                            BoxShadow(
                              color: catColor.withValues(alpha: 0.3),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    cat.iconData,
                    size: 20,
                    color: isSelected && !_isCustomCategory ? Colors.white : AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  cat.localizedName(AppLocalizations.of(context)!),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected && !_isCustomCategory ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected && !_isCustomCategory ? catColor : AppColors.textSecondary,
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

  Widget _buildCategorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCategoryGrid(),
        const SizedBox(height: 16),
        if (_isCustomCategory)
          TextField(
            controller: _customCategoryController,
            decoration: InputDecoration(
               hintText: l10n.enterCustomCategory,
               border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
               contentPadding: const EdgeInsets.symmetric(horizontal: 16),
               suffixIcon: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() { _isCustomCategory = false; _customCategoryController.clear(); })),
               focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.accentOrange, width: 2)),
            ),
            onChanged: (v) {
               if (v.isNotEmpty) setState(() => _selectedCategoryId = 'cat_uncategorized');
            },
          )
        else
          GestureDetector(
            onTap: () => setState(() => _isCustomCategory = true),
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(l10n.addCustomCategory, style: const TextStyle(color: AppColors.accentOrange, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ),
      ],
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
                hintText: selectedSupplier?.name ?? l10n.payeeNameOptional,
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
              Text(l10n.selectPayee, style: AppTypography.h3),
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
                    _localizedPaymentMethod(method.name),
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
        ? '${l10n.periodToday}, ${DateFormat('MMM d').format(_selectedDate)}'
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
          hintText: l10n.addNoteOptional,
          hintStyle: AppTypography.bodyMedium.copyWith(
            color: AppColors.textTertiary,
          ),
          border: InputBorder.none,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  BOTTOM BAR: summary + save button
  // ═══════════════════════════════════════════════════
  Widget _buildBottomBar() {
    final cat = CategoryData.findById(_selectedCategoryId ?? '');
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
                        _isExpense ? l10n.expense : l10n.income,
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
                    '${cat.localizedName(AppLocalizations.of(context)!)} · ${l10n.periodToday}',
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Column(
                children: [
                  RevvoPrimaryButton(
                    text: l10n.saveTransaction,
                    icon: Icons.check_rounded,
                    onPressed: _amount != '0' ? _onSave : null,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _amount != '0'
                        ? _onSaveAndAnother
                        : null,
                    child: Text(
                      l10n.saveAndAddAnother,
                      style: AppTypography.captionSmall.copyWith(
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
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
