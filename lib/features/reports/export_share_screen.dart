import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/providers/export_providers.dart';
import '../../core/services/share_service.dart';
import '../../shared/models/sale_model.dart';
import '../../shared/utils/money_utils.dart';

const _plExcludedCats = {'cat_investments'};

class ExportShareScreen extends ConsumerStatefulWidget {
  const ExportShareScreen({super.key});

  @override
  ConsumerState<ExportShareScreen> createState() => _ExportShareScreenState();
}

class _ExportShareScreenState extends ConsumerState<ExportShareScreen> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _fromDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _toDate = DateTime.now();
  int _profitLossPeriodIdx = 0; // 0: Monthly, 1: Quarterly, 2: Annual
  bool _busy = false;

  /// Build dynamic list of months from transactions.
  List<DateTime> _availableMonths(List<DateTime> txDates) {
    final now = DateTime.now();
    final months = <String, DateTime>{};
    // Always include current month
    months[_monthKey(now)] = DateTime(now.year, now.month);
    for (final d in txDates) {
      months[_monthKey(d)] = DateTime(d.year, d.month);
    }
    final sorted = months.values.toList()..sort((a, b) => b.compareTo(a));
    return sorted;
  }

  String _monthKey(DateTime d) => '${d.year}-${d.month}';
  String _monthLabel(DateTime d) => DateFormat('MMMM yyyy').format(d);

  Future<void> _withBusy(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ───────────────────── Actions ─────────────────────

  Future<void> _generateMonthlyReport() => _withBusy(() async {
    HapticFeedback.mediumImpact();
    final transactions = ref.read(transactionsProvider).value ?? [];
    final sales = ref.read(salesProvider).value ?? [];
    final products = ref.read(inventoryProvider).value ?? [];
    final bs = ref.read(balanceSheetEntriesProvider);
    final purchases = ref.read(purchasesProvider);
    final settings = ref.read(appSettingsProvider);
    final currency = settings.currency;
    final openingCash = settings.openingCashBalance;
    final businessName = settings.businessName;

    final double suppliersOwing = roundMoney(purchases.fold(0.0, (sum, p) {
      final received = p.totalReceivedValue;
      return sum + (received - p.amountPaid).clamp(0.0, double.maxFinite);
    }));
    final double supplierPrepayments = roundMoney(purchases.fold(0.0, (sum, p) {
      final received = p.totalReceivedValue;
      return sum + (p.amountPaid - received).clamp(0.0, double.maxFinite);
    }));

    final reportService = ref.read(reportServiceProvider);
    final shareService = ref.read(shareServiceProvider);

    final pdfBytes = await reportService.generateMonthlyReportPdf(
      transactions: transactions,
      sales: sales,
      products: products,
      bs: bs,
      suppliersOwing: suppliersOwing,
      supplierPrepayments: supplierPrepayments,
      currency: currency,
      month: _selectedMonth,
      openingBalance: openingCash,
      businessName: businessName.isEmpty ? null : businessName,
    );

    final filename = 'Monthly_Report_${DateFormat('MMM_yyyy').format(_selectedMonth)}.pdf';
    if (!mounted) return;
    await shareService.sharePdf(
      pdfBytes, filename,
      subject: 'Monthly Financial Report – ${_monthLabel(_selectedMonth)}',
      origin: ShareService.originFrom(context),
    );
  });

  Future<void> _exportTransactions() => _withBusy(() async {
    HapticFeedback.mediumImpact();
    final transactions = ref.read(transactionsProvider).value ?? [];
    final settings = ref.read(appSettingsProvider);
    final currency = settings.currency;

    final filtered = transactions.where((tx) =>
        !tx.dateTime.isBefore(_fromDate) &&
        !tx.dateTime.isAfter(DateTime(_toDate.year, _toDate.month, _toDate.day, 23, 59, 59))).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    if (filtered.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No transactions in selected range')),
        );
      }
      return;
    }

    final reportService = ref.read(reportServiceProvider);
    final shareService = ref.read(shareServiceProvider);
    final csvString = reportService.exportTransactionsCsv(filtered, currency);
    final filename = 'Transactions_${DateFormat('dd_MMM_yy').format(_fromDate)}_to_${DateFormat('dd_MMM_yy').format(_toDate)}.csv';

    if (!mounted) return;
    await shareService.shareCsv(
      csvString, filename,
      subject: 'Transaction Export',
      origin: ShareService.originFrom(context),
    );
  });

  Future<void> _exportPnl() => _withBusy(() async {
    HapticFeedback.mediumImpact();
    final transactions = ref.read(transactionsProvider).value ?? [];
    final settings = ref.read(appSettingsProvider);
    final currency = settings.currency;
    final businessName = settings.businessName;

    // Filter out investments for P&L
    final plTransactions = transactions.where((tx) =>
        !_plExcludedCats.contains(tx.categoryId)).toList();

    final now = DateTime.now();
    late DateTime periodStart;
    late bool isMonthly;

    switch (_profitLossPeriodIdx) {
      case 0: // Monthly
        periodStart = DateTime(now.year, now.month);
        isMonthly = true;
        break;
      case 1: // Quarterly — start of current quarter
        final qMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        periodStart = DateTime(now.year, qMonth);
        isMonthly = false;
        break;
      case 2: // Annual
      default:
        periodStart = DateTime(now.year);
        isMonthly = false;
        break;
    }

    final reportService = ref.read(reportServiceProvider);
    final shareService = ref.read(shareServiceProvider);

    final pdfBytes = await reportService.generatePnlPdf(
      transactions: plTransactions,
      currency: currency,
      periodStart: periodStart,
      isMonthly: isMonthly,
      businessName: businessName.isEmpty ? null : businessName,
    );

    final periodLabel = isMonthly
        ? DateFormat('MMM_yyyy').format(periodStart)
        : _profitLossPeriodIdx == 1
            ? 'Q${((periodStart.month - 1) ~/ 3) + 1}_${periodStart.year}'
            : '${periodStart.year}';
    final filename = 'PnL_$periodLabel.pdf';

    if (!mounted) return;
    await shareService.sharePdf(
      pdfBytes, filename,
      subject: 'Profit & Loss Statement',
      origin: ShareService.originFrom(context),
    );
  });

  // ───────────────────── Date picker helpers ─────────────────────

  void _showCompactDateRangePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select Date Range', style: AppTypography.h3),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDateInput(
                          label: 'FROM',
                          date: _fromDate,
                          onTap: () async {
                            final DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: _fromDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setModalState(() => _fromDate = picked);
                              setState(() => _fromDate = picked);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildDateInput(
                          label: 'TO',
                          date: _toDate,
                          onTap: () async {
                            final DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: _toDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setModalState(() => _toDate = picked);
                              setState(() => _toDate = picked);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryNavy,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Confirm Filter', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          }
        );
      },
    );
  }

  Widget _buildDateInput({required String label, required DateTime date, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.backgroundLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text(
              DateFormat('dd MMM yyyy').format(date),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────── Build ─────────────────────

  @override
  Widget build(BuildContext context) {
    final transactionsAsync = ref.watch(transactionsProvider);
    final txDates = (transactionsAsync.value ?? []).map((t) => t.dateTime).toList();
    final months = _availableMonths(txDates);

    // Ensure selected month is in the list
    if (!months.any((m) => _monthKey(m) == _monthKey(_selectedMonth))) {
      _selectedMonth = months.first;
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundLight,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primaryNavy),
        ),
        title: Text(
          'Export & Share',
          style: AppTypography.h3.copyWith(fontWeight: FontWeight.bold, color: AppColors.primaryNavy),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildMonthlyReportSection(months),
                        const SizedBox(height: 24),
                        _buildTransactionExportSection(),
                        const SizedBox(height: 24),
                        _buildProfitLossSection(),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_busy)
              Container(
                color: Colors.black.withValues(alpha: 0.15),
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildMonthlyReportSection(List<DateTime> months) {
    return _buildSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.picture_as_pdf_rounded, color: Colors.red.shade500),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Monthly Financial Report', style: AppTypography.labelLarge),
                    const SizedBox(height: 4),
                    Text(
                      'P&L, cash flow, sales & inventory summary',
                      style: AppTypography.captionSmall.copyWith(color: AppColors.textTertiary, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Month Picker
          Container(
            decoration: BoxDecoration(
              color: AppColors.backgroundLight,
              borderRadius: BorderRadius.circular(50),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _monthKey(_selectedMonth),
                isExpanded: true,
                dropdownColor: Colors.white,
                icon: const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Icon(Icons.expand_more_rounded, color: Colors.grey),
                ),
                style: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                onChanged: (v) {
                  if (v != null) {
                    final m = months.firstWhere((m) => _monthKey(m) == v);
                    setState(() => _selectedMonth = m);
                  }
                },
                items: months
                    .map((m) => DropdownMenuItem(
                          value: _monthKey(m),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Text(_monthLabel(m), style: TextStyle(color: AppColors.textPrimary)),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Generate Button
          ElevatedButton.icon(
            onPressed: _busy ? null : _generateMonthlyReport,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentOrange,
              foregroundColor: Colors.white,
              elevation: 4,
              shadowColor: AppColors.accentOrange.withValues(alpha: 0.3),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
            ),
            icon: const Icon(Icons.auto_fix_high_rounded, size: 20),
            label: const Text('Generate & Share PDF', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionExportSection() {
    return _buildSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.table_view_rounded, color: Colors.green.shade600),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Transaction Data', style: AppTypography.labelLarge),
                    const SizedBox(height: 4),
                    Text(
                      'All transactions in CSV spreadsheet format',
                      style: AppTypography.captionSmall.copyWith(color: AppColors.textTertiary, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Date Range
          GestureDetector(
            onTap: _showCompactDateRangePicker,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('FROM', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade500)),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              DateFormat('dd MMM yy').format(_fromDate),
                              style: AppTypography.labelMedium.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const Icon(Icons.calendar_today_rounded, size: 16, color: Colors.grey),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('TO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade500)),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              DateFormat('dd MMM yy').format(_toDate),
                              style: AppTypography.labelMedium.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const Icon(Icons.calendar_today_rounded, size: 16, color: Colors.grey),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Export button
          OutlinedButton.icon(
            onPressed: _busy ? null : _exportTransactions,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryNavy,
              side: BorderSide(color: AppColors.primaryNavy),
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
            ),
            icon: const Icon(Icons.file_download_rounded, size: 20),
            label: const Text('Export CSV', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildProfitLossSection() {
    return _buildSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.article_rounded, color: Colors.blue.shade600),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Profit & Loss Statement', style: AppTypography.labelLarge),
                    const SizedBox(height: 4),
                    Text(
                      'Detailed P&L breakdown PDF',
                      style: AppTypography.captionSmall.copyWith(color: AppColors.textTertiary, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Segmented Control
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.backgroundLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(child: _buildSegmentButton('Monthly', 0, _profitLossPeriodIdx, (i) => setState(() => _profitLossPeriodIdx = i))),
                Expanded(child: _buildSegmentButton('Quarterly', 1, _profitLossPeriodIdx, (i) => setState(() => _profitLossPeriodIdx = i))),
                Expanded(child: _buildSegmentButton('Annual', 2, _profitLossPeriodIdx, (i) => setState(() => _profitLossPeriodIdx = i))),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _busy ? null : _exportPnl,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryNavy,
              foregroundColor: Colors.white,
              elevation: 4,
              shadowColor: AppColors.primaryNavy.withValues(alpha: 0.3),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
            ),
            icon: const Icon(Icons.file_download_rounded, size: 20),
            label: const Text('Export PDF', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentButton(String text, int index, int selectedIndex, Function(int) onTap) {
    final isSelected = index == selectedIndex;
    return GestureDetector(
      onTap: () => onTap(index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppColors.primaryNavy : AppColors.textTertiary,
          ),
        ),
      ),
    );
  }
}
