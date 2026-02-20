import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import 'export_share_screen.dart';
import '../../core/providers/app_providers.dart';
import '../inventory/inventory_list_screen.dart';
import '../suppliers/suppliers_overview_screen.dart';

class BalanceSheetScreen extends ConsumerStatefulWidget {
  const BalanceSheetScreen({super.key});

  @override
  ConsumerState<BalanceSheetScreen> createState() => _BalanceSheetScreenState();
}

class _BalanceSheetScreenState extends ConsumerState<BalanceSheetScreen> {
  // Mock Data & Editable State
  double _bankAccounts = 85000;
  double _cashOnHand = 15000;
  double _unpaidInvoices = 45000;
  double _loans = 40000;
  double _unpaidSalaries = 10000;

  bool _showTrend = false;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'en');

    // Real Data from Providers
    final inventoryProducts = ref.watch(inventoryProvider);
    final suppliersList = ref.watch(suppliersProvider);

    final double inventoryValue = inventoryProducts.fold(0.0, (sum, p) => sum + p.totalValue);
    final double suppliersOwing = suppliersList.fold(0.0, (sum, s) => sum + s.balance);

    // Totals
    final double totalAssets = _bankAccounts + _cashOnHand + _unpaidInvoices + inventoryValue;
    final double totalLiabilities = suppliersOwing + _loans + _unpaidSalaries;
    final double netEquity = totalAssets - totalLiabilities;

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                // Header / Trend Toggle
                _buildHeaderControls(),
                const SizedBox(height: 16),

                // Net Equity / Trend Section
                 AnimatedCrossFade(
                  firstChild: _buildNetEquitySection(fmt, netEquity, totalAssets, totalLiabilities),
                  secondChild: _buildTrendChart(fmt),
                  crossFadeState: _showTrend ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  duration: 300.ms,
                ),
                const SizedBox(height: 24),

                // Assets (What You Own)
                _buildCollapsibleSection(
                  title: 'What You Own',
                  subtitle: 'Total Assets',
                  amount: totalAssets,
                  icon: Icons.account_balance_wallet_rounded,
                  iconColor: const Color(0xFF2563EB), // Blue-600
                  iconBg: const Color(0xFFEFF6FF), // Blue-50
                  items: [
                    _SheetItem(
                      label: 'Bank Accounts',
                      amount: _bankAccounts,
                      icon: Icons.account_balance_rounded,
                      pct: _bankAccounts / totalAssets,
                      onTap: () => _showEditDialog('Bank Accounts', _bankAccounts, (v) => setState(() => _bankAccounts = v)),
                      isEditable: true,
                    ),
                    _SheetItem(
                      label: 'Cash on Hand',
                      amount: _cashOnHand,
                      icon: Icons.payments_rounded,
                      pct: _cashOnHand / totalAssets,
                      onTap: () => _showEditDialog('Cash on Hand', _cashOnHand, (v) => setState(() => _cashOnHand = v)),
                      isEditable: true,
                    ),
                    _SheetItem(
                      label: 'Inventory',
                      amount: inventoryValue,
                      icon: Icons.inventory_2_rounded,
                      pct: (totalAssets > 0) ? inventoryValue / totalAssets : 0,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InventoryListScreen())),
                      showChevron: true,
                    ),
                    _SheetItem(
                      label: 'Unpaid Invoices',
                      amount: _unpaidInvoices,
                      icon: Icons.receipt_long_rounded,
                      pct: _unpaidInvoices / totalAssets,
                      onTap: () => _showEditDialog('Unpaid Invoices', _unpaidInvoices, (v) => setState(() => _unpaidInvoices = v)),
                      isEditable: true,
                    ),
                  ],
                  fmt: fmt,
                  isAssets: true,
                ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
                const SizedBox(height: 16),

                // Liabilities (What You Owe)
                _buildCollapsibleSection(
                  title: 'What You Owe',
                  subtitle: 'Total Liabilities',
                  amount: totalLiabilities,
                  icon: Icons.money_off_rounded,
                  iconColor: const Color(0xFFDC2626), // Red-600
                  iconBg: const Color(0xFFFEF2F2), // Red-50
                  items: [
                    _SheetItem(
                      label: 'Suppliers',
                      amount: suppliersOwing,
                      icon: Icons.local_shipping_rounded,
                      pct: (totalLiabilities > 0) ? suppliersOwing / totalLiabilities : 0,
                       onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SuppliersOverviewScreen())),
                      showChevron: true,
                    ),
                    _SheetItem(
                      label: 'Loans',
                      amount: _loans,
                      icon: Icons.credit_card_rounded,
                      pct: (totalLiabilities > 0) ? _loans / totalLiabilities : 0,
                       onTap: () => _showEditDialog('Loans', _loans, (v) => setState(() => _loans = v)),
                       isEditable: true,
                    ),
                    _SheetItem(
                      label: 'Unpaid Salaries',
                      amount: _unpaidSalaries,
                      icon: Icons.people_rounded,
                      pct: (totalLiabilities > 0) ? _unpaidSalaries / totalLiabilities : 0,
                      onTap: () => _showEditDialog('Unpaid Salaries', _unpaidSalaries, (v) => setState(() => _unpaidSalaries = v)),
                      isEditable: true,
                    ),
                  ],
                  fmt: fmt,
                  isAssets: false,
                ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
                const SizedBox(height: 32),

                // AI Insight
                _buildAIInsightCard()
                    .animate()
                    .fadeIn(duration: 400.ms, delay: 300.ms)
                    .scale(begin: const Offset(0.95, 0.95)),
              ],
            ),
          ),

          // Download Button
          Positioned(
            left: 24,
            right: 24,
            bottom: 24,
            child: _buildDownloadButton()
                .animate()
                .fadeIn(duration: 400.ms, delay: 400.ms)
                .slideY(begin: 0.2, end: 0, curve: Curves.easeOutBack),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  WIDGETS
  // ═══════════════════════════════════════════════════════

  Widget _buildHeaderControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              _buildChartToggle(Icons.table_chart_rounded, !_showTrend, () {
                setState(() => _showTrend = false);
              }),
              _buildChartToggle(Icons.show_chart_rounded, _showTrend, () {
                setState(() => _showTrend = true);
              }),
            ],
          ),
        ),
      ],
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

  Widget _buildTrendChart(NumberFormat fmt) {
     // Mock Data for Net Equity Trend
    final data = [
      {'month': 'Sep', 'amount': 98000.0},
      {'month': 'Oct', 'amount': 102500.0},
      {'month': 'Nov', 'amount': 105000.0},
      {'month': 'Dec', 'amount': 108200.0},
      {'month': 'Jan', 'amount': 107500.0}, // Slight dip
      {'month': 'Feb', 'amount': 113000.0}, // Current
    ];

    final maxAmount = 120000.0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NET WORTH TREND',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            height: 220,
            padding: const EdgeInsets.only(top: 20),
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
                    // Tooltip-ish label for current
                    if (isCurrent)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryNavy,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${(amount/1000).toStringAsFixed(0)}k',
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
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: isCurrent
                                  ? [AppColors.primaryNavy, const Color(0xFF6366F1)]
                                  : [const Color(0xFFE2E8F0), const Color(0xFFCBD5E1)],
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    // Label
                    Text(
                      d['month'] as String,
                      style: TextStyle(
                        color: isCurrent ? AppColors.textPrimary : AppColors.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetEquitySection(NumberFormat fmt, double netEquity, double totalAssets, double totalLiabilities) {
    // Avoid division by zero
    final total = totalAssets + totalLiabilities;
    final assetPct = total > 0 ? totalAssets / total : 0.5;
    final liabilityPct = total > 0 ? totalLiabilities / total : 0.5;

    return Column(
      children: [
        const Text(
          'NET EQUITY POSITION',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'EGP',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              fmt.format(netEquity),
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -1.0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4), // Green-50
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFDCFCE7)), // Green-100
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.trending_up_rounded,
                  size: 16, color: Color(0xFF16A34A)), // Green-600
              const SizedBox(width: 4),
              const Text(
                '+5.2% vs last month',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF15803D), // Green-700
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Distribution Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Distribution',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 16,
                  child: Row(
                    children: [
                      Expanded(
                        flex: (assetPct * 100).toInt(),
                        child: Container(color: const Color(0xFF2563EB)), // Blue
                      ),
                      Container(width: 2, color: Colors.white),
                      Expanded(
                        flex: (liabilityPct * 100).toInt(),
                        child: Container(color: const Color(0xFFDC2626)), // Red
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Legend
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildLegendItem(
                    label: 'Assets',
                    amount: 'EGP ${(totalAssets / 1000).toStringAsFixed(0)}k',
                    color: const Color(0xFF2563EB),
                  ),
                  Container(
                    width: 1,
                    height: 32,
                    color: AppColors.borderLight,
                  ),
                  _buildLegendItem(
                    label: 'Liabilities',
                    amount: 'EGP ${(totalLiabilities / 1000).toStringAsFixed(0)}k',
                    color: const Color(0xFFDC2626),
                    alignRight: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem({
    required String label,
    required String amount,
    required Color color,
    bool alignRight = false,
  }) {
    return Column(
      crossAxisAlignment:
          alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!alignRight) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary,
                letterSpacing: 0.5,
              ),
            ),
            if (alignRight) ...[
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: EdgeInsets.only(
              left: alignRight ? 0 : 16, right: alignRight ? 16 : 0),
          child: Text(
            amount,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  // Collapsible Section with Clickable Items
  Widget _buildCollapsibleSection({
    required String title,
    required String subtitle,
    required double amount,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required List<_SheetItem> items,
    required NumberFormat fmt,
    required bool isAssets,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(), // Remove default borders
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.h3.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${(amount / 1000).toStringAsFixed(0)}k',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          children: items.map((item) {
            final color = isAssets ? const Color(0xFF2563EB) : const Color(0xFFDC2626);
            return GestureDetector(
              onTap: () {
                if (item.onTap != null) {
                  HapticFeedback.lightImpact();
                  item.onTap!();
                }
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.backgroundLight,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(item.icon,
                                  size: 16, color: AppColors.textTertiary),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            if (item.isEditable)
                               Padding(
                                 padding: const EdgeInsets.only(left: 6),
                                 child: Icon(Icons.edit_rounded, size: 12, color: AppColors.textTertiary.withValues(alpha: 0.5)),
                               ),
                          ],
                        ),
                        Row(
                          children: [
                            Text(
                              fmt.format(item.amount),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (item.showChevron)
                               const Padding(
                                 padding: EdgeInsets.only(left: 6),
                                 child: Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textTertiary),
                               ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: item.pct,
                        backgroundColor: AppColors.backgroundLight,
                        valueColor: AlwaysStoppedAnimation(color.withValues(alpha: 0.7)),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _showEditDialog(String title, double currentValue, Function(double) onSave) async {
    final controller = TextEditingController(text: currentValue.toStringAsFixed(0));
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit $title', style: AppTypography.h3),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Amount (EGP)',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final val = double.tryParse(controller.text) ?? currentValue;
              onSave(val);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }



  Widget _buildAIInsightCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.9),
            const Color(0xFFF0F9FF).withValues(alpha: 0.8), // Light Blue
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)], // Indigo-Purple
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: Colors.white, size: 14),
              ),
              const SizedBox(width: 8),
              Text(
                'MASARI AI',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: const Color(0xFF4338CA), // Indigo-800
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white),
                ),
                child: Text(
                  'New Insight',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Your cash on hand is high compared to your debt. Consider paying down the loan to reduce interest expenses next month.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              // Future: Navigate to full analysis
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'View Full Analysis',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF4F46E5), // Indigo-600
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_rounded,
                    size: 14, color: Color(0xFF4F46E5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadButton() {
    return ElevatedButton.icon(
      onPressed: () {
        HapticFeedback.mediumImpact();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ExportShareScreen(),
          ),
        );
      },
      icon: const Icon(Icons.download_rounded, size: 20),
      label: const Text('Download Report'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryNavy,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        elevation: 8,
        shadowColor: AppColors.primaryNavy.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SheetItem {
  final String label;
  final double amount;
  final IconData icon;
  final double pct;
  final VoidCallback? onTap;
  final bool isEditable;
  final bool showChevron;

  _SheetItem({
    required this.label,
    required this.amount,
    required this.icon,
    required this.pct,
    this.onTap,
    this.isEditable = false,
    this.showChevron = false,
  });
}
