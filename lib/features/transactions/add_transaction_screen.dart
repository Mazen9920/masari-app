import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/models/transaction_model.dart';
import '../../shared/models/category_data.dart';
import '../auth/widgets/form_components.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  bool _isExpense = true;
  String _amount = '0';
  int _selectedCategoryIndex = 0;
  int _selectedPaymentIndex = 0;
  bool _isRecurring = false;
  final _noteController = TextEditingController();

  // ─── Category Data ───
  final List<_Category> _expenseCategories = [
    _Category('Food', Icons.restaurant_rounded, AppColors.accentOrange),
    _Category('Transport', Icons.directions_bus_rounded, const Color(0xFF2E86C1)),
    _Category('Shopping', Icons.shopping_bag_rounded, const Color(0xFF8E44AD)),
    _Category('Rent', Icons.home_rounded, const Color(0xFF27AE60)),
    _Category('Entertainment', Icons.movie_rounded, const Color(0xFFE74C3C)),
    _Category('Health', Icons.medical_services_rounded, const Color(0xFF1ABC9C)),
    _Category('Education', Icons.school_rounded, const Color(0xFF3498DB)),
    _Category('More', Icons.grid_view_rounded, AppColors.textTertiary),
  ];

  final List<_PaymentMethod> _paymentMethods = [
    _PaymentMethod('Cash', Icons.payments_rounded),
    _PaymentMethod('Card', Icons.credit_card_rounded),
    _PaymentMethod('Bank', Icons.account_balance_rounded),
    _PaymentMethod('Wallet', Icons.account_balance_wallet_rounded),
  ];

  final List<_QuickTag> _quickTags = [
    _QuickTag('Marketing', 'Meta Ads'),
    _QuickTag('Transport', 'Uber'),
    _QuickTag('Food', 'Talabat'),
    _QuickTag('Office', 'Electricity'),
  ];

  @override
  void dispose() {
    _noteController.dispose();
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

  void _onSave() {
    HapticFeedback.mediumImpact();
    
    // Create transaction object
    final amount = double.tryParse(_amount) ?? 0;
    if (amount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }
    
    // Get the selected category
    final selectedCategoryData = _expenseCategories[_selectedCategoryIndex];
    final category = CategoryData.findByName(selectedCategoryData.name);
    
    // Get payment method name
    final paymentMethodName = _paymentMethods[_selectedPaymentIndex].name;
    
    // Get note text
    final noteText = _noteController.text.trim();
    
    final transaction = Transaction(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: category.name,
      amount: _isExpense ? -amount : amount,
      dateTime: DateTime.now(),
      category: category,
      note: noteText.isNotEmpty ? noteText : null,
      paymentMethod: paymentMethodName,
    );
    
    // Save to provider
    ref.read(transactionsProvider.notifier).addTransaction(transaction);
    
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
          ),
          Text(
            'New Transaction',
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
                            .withOpacity(0.25),
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
                      setState(() => _isExpense = true);
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
                      setState(() => _isExpense = false);
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
                'EGP ',
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
                  'MOST USED',
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.accentOrange,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  'RECENT',
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
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
              itemCount: _quickTags.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final tag = _quickTags[index];
                return Container(
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
                        tag.category,
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        ' · ${tag.detail}',
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
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
          top: BorderSide(color: AppColors.borderLight.withOpacity(0.5)),
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

          // ─── Recurring Toggle ───
          _buildRecurringToggle(),

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
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: _expenseCategories.length,
      itemBuilder: (context, index) {
        final cat = _expenseCategories[index];
        final isSelected = _selectedCategoryIndex == index;
        return GestureDetector(
          onTap: () => setState(() => _selectedCategoryIndex = index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isSelected
                  ? cat.color.withOpacity(0.08)
                  : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: isSelected
                  ? Border.all(color: cat.color.withOpacity(0.3))
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
                    color: isSelected
                        ? cat.color
                        : AppColors.backgroundLight,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: cat.color.withOpacity(0.3),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    cat.icon,
                    size: 20,
                    color: isSelected ? Colors.white : AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  cat.name,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? cat.color : AppColors.textSecondary,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFEBF5FB), // blue-50
            ),
            child: const Icon(Icons.storefront_rounded,
                size: 18, color: AppColors.secondaryBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Payee',
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
                Text(
                  'Select Supplier',
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              size: 20, color: AppColors.textTertiary),
        ],
      ),
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
    return Container(
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
            'Today, Feb 16',
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ],
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

  Widget _buildRecurringToggle() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF3E8FF), // purple-50
            ),
            child: const Icon(Icons.loop_rounded,
                size: 20, color: Color(0xFF8B5CF6)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recurring',
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                if (_isRecurring)
                  Text(
                    'Monthly',
                    style: AppTypography.captionSmall.copyWith(
                      color: const Color(0xFF8B5CF6),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          Switch(
            value: _isRecurring,
            onChanged: (v) => setState(() => _isRecurring = v),
            activeColor: const Color(0xFF8B5CF6),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  BOTTOM BAR: summary + save button
  // ═══════════════════════════════════════════════════
  Widget _buildBottomBar() {
    final cat = _expenseCategories[_selectedCategoryIndex];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.borderLight.withOpacity(0.5)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
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
                        ' · EGP $_formattedAmount',
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

            // Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Column(
                children: [
                  MasariPrimaryButton(
                    text: 'Save Transaction',
                    icon: Icons.check_rounded,
                    onPressed: _amount != '0' ? _onSave : null,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _amount != '0'
                        ? () {
                            _onSave();
                            // TODO: reset form and stay on screen
                          }
                        : null,
                    child: Text(
                      'Save & Add Another',
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
class _Category {
  final String name;
  final IconData icon;
  final Color color;
  const _Category(this.name, this.icon, this.color);
}

class _PaymentMethod {
  final String name;
  final IconData icon;
  const _PaymentMethod(this.name, this.icon);
}

class _QuickTag {
  final String category;
  final String detail;
  const _QuickTag(this.category, this.detail);
}
