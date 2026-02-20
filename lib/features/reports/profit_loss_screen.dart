import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../features/ai/ai_chat_screen.dart';
import '../../shared/models/transaction_model.dart';
import '../transactions/transactions_list_screen.dart';
import 'export_share_screen.dart';
class ProfitLossScreen extends StatefulWidget {
  const ProfitLossScreen({super.key});

  @override
  State<ProfitLossScreen> createState() => _ProfitLossScreenState();
}

class _ProfitLossScreenState extends State<ProfitLossScreen> {
  // Mock Data
  // State
  DateTime _selectedDate = DateTime.now();
  bool _isMonthly = true;

  // Mock Data
  final double _revenue = 45200;
  final double _expenses = 31800;
  double get _netProfit => _revenue - _expenses;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primaryNavy,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'en');

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: Stack(
        children: [
          // Scrollable Content
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                // Controls (Month/Yearly)
                _buildControls(),
                const SizedBox(height: 16),

                // AI Insight Banner
                _buildInsightBanner()
                    .animate()
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.1, end: 0,curve: Curves.easeOut),
                const SizedBox(height: 24),

                // KPI Row
                _buildKPIRow(fmt),
                const SizedBox(height: 24),

                // Funnel Chart
                _buildFunnelChart(fmt)
                    .animate()
                    .fadeIn(duration: 400.ms, delay: 100.ms)
                    .slideY(begin: 0.1, end: 0, curve: Curves.easeOut),
                const SizedBox(height: 24),

                // Income Breakdown
                _buildBreakdownSection(
                  title: 'Where Your Money Comes From',
                  items: [
                    _BreakdownItem(
                      label: 'Services',
                      amount: 31640,
                      color: const Color(0xFF10B981), // Green-500
                      percentage: 0.7,
                    ),
                    _BreakdownItem(
                      label: 'Products',
                      amount: 13560,
                      color: const Color(0xFF86EFAC), // Green-300
                      percentage: 0.3,
                    ),
                  ],
                  fmt: fmt,
                ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
                const SizedBox(height: 24),

                // Expenses Breakdown
                _buildBreakdownSection(
                  title: 'Where Your Money Goes',
                  items: [
                    _BreakdownItem(
                      label: 'Payroll',
                      amount: 15000,
                      color: const Color(0xFFF87171), // Red-400
                      percentage: 0.47,
                    ),
                    _BreakdownItem(
                      label: 'Software Subscriptions',
                      amount: 10200,
                      color: const Color(0xFFFCA5A5), // Red-300
                      percentage: 0.32,
                    ),
                    _BreakdownItem(
                      label: 'Office Rent',
                      amount: 6600,
                      color: const Color(0xFFFECACA), // Red-200
                      percentage: 0.21,
                    ),
                  ],
                  fmt: fmt,
                ).animate().fadeIn(duration: 400.ms, delay: 300.ms),
                const SizedBox(height: 24),

                // Net Profit Summary (Now scrollable)
                _buildNetProfitCard(fmt)
                    .animate()
                    .fadeIn(duration: 400.ms, delay: 400.ms)
                    .slideY(begin: 0.1, end: 0, curve: Curves.easeOut),
              ],
            ),
          ),

          // Sticky Bottom Actions
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildStickyBottomActions(),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  WIDGETS
  // ═══════════════════════════════════════════════════════

  Widget _buildControls() {
    final dateStr = _isMonthly
        ? DateFormat('MMM yyyy').format(_selectedDate)
        : DateFormat('yyyy').format(_selectedDate);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Date Selector
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            _pickDate();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.borderLight),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_rounded,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  dateStr,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more_rounded,
                    size: 16, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
        // Toggle (Monthly/Yearly)
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              _buildToggleOption('Monthly', true),
              _buildToggleOption('Yearly', false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToggleOption(String text, bool isOptionMonthly) {
    final isSelected = _isMonthly == isOptionMonthly;
    return GestureDetector(
      onTap: () {
        if (!isSelected) {
          HapticFeedback.lightImpact();
          setState(() => _isMonthly = isOptionMonthly);
        }
      },
      child: AnimatedContainer(
        duration: 200.ms,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : [],
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isSelected ? AppColors.textPrimary : AppColors.textTertiary,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 11,
          ),
        ),
      ),
    );
  }



  Widget _buildInsightBanner() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFEBF5FB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE)), // Blue-100
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: Color(0xFF3B82F6), size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Great news!',
                      style: TextStyle(
                        color: const Color(0xFF1E3A8A), // Blue-900
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your profit margin improved by 3% compared to last month. Keep an eye on marketing spend.',
                      style: TextStyle(
                        color: const Color(0xFF1E40AF), // Blue-800
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Decorative circle
          Positioned(
            right: -24,
            top: -24,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: const Color(0xFFBFDBFE).withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
            ).animate().scale(duration: 1.seconds, curve: Curves.elasticOut),
          ),
        ],
      ),
    );
  }

  Widget _buildKPIRow(NumberFormat fmt) {
    return Row(
      children: [
        Expanded(
          child: _buildKPICard(
            label: 'Money In',
            amount: '45.2k',
            color: const Color(0xFF10B981), // Green
            barColor: const Color(0xFF10B981),
            pctChange: 12, // +12%
            isPositiveChange: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKPICard(
            label: 'Money Out',
            amount: '31.8k',
            color: AppColors.textPrimary,
            barColor: const Color(0xFFEF4444), // Red
            pctChange: 5, // +5% (more expenses is bad usually, but here just showing direction)
            isPositiveChange: false, // Red indicator for expenses increasing
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKPICard(
            label: "What's Left",
            amount: '13.4k',
            color: AppColors.primaryNavy, // Brand primary
            barColor: AppColors.accentOrange,
            isPrimary: true,
            pctChange: 8,
            isPositiveChange: true,
          ),
        ),
      ],
    );
  }

  Widget _buildKPICard({
    required String label,
    required String amount,
    required Color color,
    required Color barColor,
    bool isPrimary = false,
    int? pctChange,
    bool isPositiveChange = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isPrimary ? AppColors.accentOrange : AppColors.textTertiary,
                letterSpacing: 0.5,
              ),
            ),
            if (pctChange != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: isPositiveChange
                      ? const Color(0xFFDCFCE7) // Green-100
                      : const Color(0xFFFEE2E2), // Red-100
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(
                      isPositiveChange
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 10,
                      color: isPositiveChange
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFDC2626),
                    ),
                    Text(
                      '$pctChange%',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: isPositiveChange
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'EGP $amount',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: isPrimary ? AppColors.accentOrange : AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 4,
          width: 32,
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }

  bool _showTrend = false;

  Widget _buildFunnelChart(NumberFormat fmt) {
    return _ReportCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _showTrend ? '6-Month Trend' : 'This Month in One View',
                style: AppTypography.h3.copyWith(fontSize: 16),
              ),
              // View Toggle
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    _buildChartToggle(Icons.filter_list_rounded, !_showTrend, () {
                      setState(() => _showTrend = false);
                    }),
                    _buildChartToggle(Icons.show_chart_rounded, _showTrend, () {
                      setState(() => _showTrend = true);
                    }),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          AnimatedCrossFade(
            firstChild: _buildFunnelBody(fmt),
            secondChild: _buildTrendChart(fmt),
            crossFadeState: _showTrend
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: 300.ms,
          ),
        ],
      ),
    );
  }

  Widget _buildChartToggle(IconData icon, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        if (!isSelected) {
          HapticFeedback.lightImpact();
          onTap();
        }
      },
      child: AnimatedContainer(
        duration: 200.ms,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                  ),
                ]
              : [],
        ),
        child: Icon(
          icon,
          size: 18,
          color: isSelected ? AppColors.textPrimary : AppColors.textTertiary,
        ),
      ),
    );
  }

  Widget _buildFunnelBody(NumberFormat fmt) {
    return Stack(
      children: [
        // Connector Line
        Positioned(
          left: 24,
          top: 24,
          bottom: 24,
          child: Container(
            width: 2,
            decoration: const BoxDecoration(
              color: AppColors.backgroundLight,
              border: Border(
                left: BorderSide(
                  color: Color(0xFFE2E8F0),
                  width: 2,
                  style: BorderStyle.solid,
                ),
              ),
            ),
          ),
        ),
        Column(
          children: [
            _buildFunnelItem(
              icon: Icons.arrow_downward_rounded,
              iconColor: const Color(0xFF16A34A),
              iconBg: const Color(0xFFF0FDF4),
              label: 'Revenue',
              amount: _revenue,
              barColor: const Color(0xFF22C55E),
              barWidthFactor: 1.0,
              fmt: fmt,
            ),
            const SizedBox(height: 16),
            _buildFunnelItem(
              icon: Icons.arrow_upward_rounded,
              iconColor: const Color(0xFFEF4444),
              iconBg: const Color(0xFFFEF2F2),
              label: 'Expenses',
              amount: -_expenses,
              barColor: const Color(0xFFF87171),
              barWidthFactor: 0.7,
              fmt: fmt,
            ),
            const SizedBox(height: 16),
            _buildFunnelItem(
              icon: Icons.savings_rounded,
              iconColor: AppColors.accentOrange,
              iconBg: AppColors.accentOrange.withValues(alpha: 0.1),
              label: 'Net Profit',
              amount: _netProfit,
              barColor: AppColors.accentOrange,
              barWidthFactor: 0.3,
              fmt: fmt,
              isProfit: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTrendChart(NumberFormat fmt) {
    // Mock Data for last 6 months
    final data = [
      {'month': 'Sep', 'amount': 8500.0},
      {'month': 'Oct', 'amount': 11200.0},
      {'month': 'Nov', 'amount': 9800.0},
      {'month': 'Dec', 'amount': 15400.0},
      {'month': 'Jan', 'amount': 12100.0},
      {'month': 'Feb', 'amount': 13400.0}, // Current
    ];

    final maxAmount = 16000.0;

    return Container(
      height: 180,
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: data.map((d) {
          final amount = d['amount'] as double;
          final heightFactor = amount / maxAmount;
          final isCurrent = d == data.last;

          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Tooltip-ish label
              if (isCurrent)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryNavy,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    d['month'] as String,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .moveY(begin: 0, end: -4, duration: 1.seconds, curve: Curves.easeInOut),

              // Bar
              TweenAnimationBuilder<double>(
                duration: 600.ms,
                curve: Curves.easeOutBack,
                tween: Tween(begin: 0, end: heightFactor),
                builder: (context, val, _) {
                  return Container(
                    width: 32,
                    height: 140 * val, // Max bar height
                    decoration: BoxDecoration(
                      color: isCurrent ? AppColors.accentOrange : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              // Label
              if (!isCurrent)
                Text(
                  d['month'] as String,
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFunnelItem({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String label,
    required double amount,
    required Color barColor,
    required double barWidthFactor,
    required NumberFormat fmt,
    bool isProfit = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: iconBg,
            shape: BoxShape.circle,
            border: Border.all(color: iconColor.withValues(alpha: 0.2)),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label,
                      style: TextStyle(
                        color: isProfit
                            ? AppColors.accentOrange
                            : AppColors.textSecondary,
                        fontWeight:
                            isProfit ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 12,
                      )),
                  Text(
                    '${amount < 0 ? "-" : ""}EGP ${fmt.format(amount.abs())}',
                    style: TextStyle(
                      color:
                          isProfit ? AppColors.accentOrange : AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LayoutBuilder(builder: (context, constraints) {
                return Stack(
                  children: [
                    Container(
                      height: 32,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: barColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    AnimatedContainer(
                      duration: 800.ms,
                      curve: Curves.easeOutQuart,
                      height: 32,
                      width: constraints.maxWidth * barWidthFactor,
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBreakdownSection({
    required String title,
    required List<_BreakdownItem> items,
    required NumberFormat fmt,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: AppTypography.h3.copyWith(fontSize: 14),
          ),
        ),
        _ReportCard(
          child: Column(
            children: items.map((item) {
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _navigateToCategoryTransactions(item.label);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: item.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  item.label,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Text(
                                  'EGP ${fmt.format(item.amount)}',
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right_rounded,
                                    size: 14, color: AppColors.textTertiary),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: item.percentage,
                            backgroundColor: AppColors.backgroundLight,
                            valueColor: AlwaysStoppedAnimation(item.color),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  void _navigateToCategoryTransactions(String category) {
    // Construct filter for selected category
    final filter = TransactionFilter(
        type: TransactionType.all,
        amountRange: const RangeValues(0, 1000000), // Wide range
        selectedCategories: {category},
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransactionsListScreen(
          pageTitle: '$category Transactions',
          showBackButton: true,
          initialFilter: filter,
        ),
      ),
    );
  }

  Widget _buildNetProfitCard(NumberFormat fmt) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4).withValues(alpha: 0.9), // Green-50
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCFCE7)), // Green-100
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04), // Reduced shadow
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Net Profit',
                style: TextStyle(
                  color: const Color(0xFF15803D), // Green-700
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                'EGP ${fmt.format(_netProfit)}',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.trending_up_rounded,
                color: Color(0xFF16A34A)),
          ),
        ],
      ),
    );
  }

  Widget _buildStickyBottomActions() {
    return Container(
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.white.withValues(alpha: 0.95),
            Colors.white.withValues(alpha: 0.8),
            Colors.white.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.6, 1.0],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton.icon(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ExportShareScreen(),
                ),
              );
            },
            icon: const Icon(Icons.ios_share_rounded, size: 16),
            label: const Text('Share', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.textPrimary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              minimumSize: const Size(0, 36), // Compact height
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: AppColors.borderLight),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () {
              HapticFeedback.mediumImpact();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AiChatScreen(contextType: 'ProfitLoss'),
                ),
              );
            },
            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
            label: const Text('Ask AI', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentOrange,
              foregroundColor: Colors.white,
              elevation: 2, // Reduced elevation
              shadowColor: AppColors.accentOrange.withValues(alpha: 0.4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              minimumSize: const Size(0, 36), // Compact height
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  HELPERS
// ═══════════════════════════════════════════════════════

class _ReportCard extends StatelessWidget {
  final Widget child;
  const _ReportCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _BreakdownItem {
  final String label;
  final double amount;
  final Color color;
  final double percentage;

  _BreakdownItem({
    required this.label,
    required this.amount,
    required this.color,
    required this.percentage,
  });
}
