import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import 'screens/report_preview_screen.dart';

class ExportShareScreen extends StatefulWidget {
  const ExportShareScreen({super.key});

  @override
  State<ExportShareScreen> createState() => _ExportShareScreenState();
}

class _ExportShareScreenState extends State<ExportShareScreen> {
  String _selectedMonth = 'February 2026';
  String _selectedBank = 'All Bank Accounts';
  DateTime _fromDate = DateTime(2026, 2, 1);
  DateTime _toDate = DateTime(2026, 2, 28);
  int _transactionExportFormatIdx = 0; // 0: Excel, 1: CSV
  int _profitLossPeriodIdx = 0; // 0: Monthly, 1: Quarterly, 2: Annual

      Future<void> _selectDate(bool isFrom) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _fromDate : _toDate,
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primaryNavy,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
          if (_toDate.isBefore(_fromDate)) _toDate = _fromDate;
        } else {
          _toDate = picked;
          if (_fromDate.isAfter(_toDate)) _fromDate = _toDate;
        }
      });
    }
  }

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
                              firstDate: DateTime(2023),
                              lastDate: DateTime(2030),
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
                              firstDate: DateTime(2023),
                              lastDate: DateTime(2030),
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

  @override
  Widget build(BuildContext context) {
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
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMonthlyReportSection(),
                    const SizedBox(height: 24),
                    _buildTransactionExportSection(),
                    const SizedBox(height: 24),
                    _buildProfitLossSection(),
                    const SizedBox(height: 32),
                    _buildShareSection(),
                    const SizedBox(height: 32),
                    _buildRecentExportsSection(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
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

  Widget _buildMonthlyReportSection() {
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
                      'Professional one-page summary with charts',
                      style: AppTypography.captionSmall.copyWith(color: AppColors.textTertiary, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Content
          Row(
            children: [
              // Thumbnail placeholder
              Container(
                width: 80,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderLight),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.visibility_outlined, color: AppColors.textTertiary.withValues(alpha: 0.5), size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    // Month Picker
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.backgroundLight,
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedMonth,
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
                            if (v != null) setState(() => _selectedMonth = v);
                          },
                          items: ['February 2026', 'January 2026', 'December 2025']
                              .map((m) => DropdownMenuItem(
                                    value: m,
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 16),
                                      child: Text(m, style: TextStyle(color: AppColors.textPrimary)),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Bank Account Picker
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.backgroundLight,
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedBank,
                          isExpanded: true,
                          dropdownColor: Colors.white,
                          icon: const Padding(
                            padding: EdgeInsets.only(right: 16),
                            child: Icon(Icons.account_balance_rounded, color: Colors.grey, size: 18),
                          ),
                          style: AppTypography.bodySmall.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          onChanged: (v) {
                            if (v != null) setState(() => _selectedBank = v);
                          },
                          items: ['All Bank Accounts', 'CIB Bank', 'QNB Bank', 'Cash']
                              .map((m) => DropdownMenuItem(
                                    value: m,
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 16),
                                      child: Text(m, style: TextStyle(color: AppColors.textPrimary)),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Generate Button
                    ElevatedButton.icon(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ReportPreviewScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentOrange,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shadowColor: AppColors.accentOrange.withValues(alpha: 0.3),
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                      ),
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 20),
                      label: const Text('Generate PDF', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ],
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
                      'All transactions in spreadsheet format',
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
          // Actions
          Row(
            children: [
              // Toggle
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Row(
                  children: [
                    _buildPillButton('Excel', 0, _transactionExportFormatIdx, (i) => setState(() => _transactionExportFormatIdx = i)),
                    _buildPillButton('CSV', 1, _transactionExportFormatIdx, (i) => setState(() => _transactionExportFormatIdx = i)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaction data exported')));
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryNavy,
                    side: BorderSide(color: AppColors.primaryNavy),
                    minimumSize: const Size(0, 40),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                  ),
                  child: const Text('Export', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
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
                      'Detailed P&L breakdown',
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
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('P&L Statement generated')));
            },
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

  Widget _buildPillButton(String text, int index, int selectedIndex, Function(int) onTap) {
    final isSelected = index == selectedIndex;
    return GestureDetector(
      onTap: () => onTap(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(50),
          boxShadow: isSelected
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))]
              : null,
        ),
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

  Widget _buildShareSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Share via',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primaryNavy.withValues(alpha: 0.7)),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _buildShareIcon(icon: Icons.chat_rounded, color: const Color(0xFF25D366), label: 'WhatsApp', isWhiteIcon: true),
              _buildShareIcon(icon: Icons.mail_outline_rounded, color: Colors.grey.shade200, label: 'Email'),
              _buildShareIcon(icon: Icons.send_rounded, color: Colors.grey.shade200, label: 'Telegram'),
              _buildShareIcon(icon: Icons.link_rounded, color: Colors.grey.shade200, label: 'Copy Link'),
              _buildShareIcon(icon: Icons.more_horiz_rounded, color: Colors.grey.shade100, label: 'More', isBordered: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShareIcon({
    required IconData icon,
    required Color color,
    required String label,
    bool isWhiteIcon = false,
    bool isBordered = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: isBordered ? Border.all(color: AppColors.borderLight) : null,
              boxShadow: !isBordered && isWhiteIcon
                  ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))]
                  : null,
            ),
            child: Icon(
              icon,
              color: isWhiteIcon ? Colors.white : (isBordered ? Colors.grey.shade500 : Colors.grey.shade700),
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentExportsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Recent Exports',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primaryNavy.withValues(alpha: 0.7)),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildRecentExportItem(
                icon: Icons.picture_as_pdf_rounded,
                iconColor: Colors.red.shade500,
                bgBg: Colors.red.shade50,
                name: 'January_2026_Report.pdf',
                size: '1.2 MB',
                date: '02 Feb 2026',
              ),
              Divider(height: 1, color: AppColors.borderLight),
              _buildRecentExportItem(
                icon: Icons.table_view_rounded,
                iconColor: Colors.green.shade600,
                bgBg: Colors.green.shade50,
                name: 'Q4_2025_Transactions.xlsx',
                size: '450 KB',
                date: '15 Jan 2026',
              ),
              Divider(height: 1, color: AppColors.borderLight),
              _buildRecentExportItem(
                icon: Icons.article_rounded,
                iconColor: Colors.blue.shade600,
                bgBg: Colors.blue.shade50,
                name: 'Profit_Loss_2025_Final.pdf',
                size: '2.8 MB',
                date: '10 Jan 2026',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecentExportItem({
    required IconData icon,
    required Color iconColor,
    required Color bgBg,
    required String name,
    required String size,
    required String date,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: bgBg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(size, style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                    Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey.shade300),
                    ),
                    Text(date, style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report re-downloaded')));
            },
            icon: const Icon(Icons.download_rounded),
            color: Colors.grey.shade400,
          ),
        ],
      ),
    );
  }
}
