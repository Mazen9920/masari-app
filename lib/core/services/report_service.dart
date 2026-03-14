import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../shared/models/transaction_model.dart';
import '../../shared/models/sale_model.dart';
import '../../shared/models/product_model.dart';
import '../../shared/models/balance_sheet_entries.dart';
import '../../shared/models/category_data.dart';
import 'package:csv/csv.dart' as csv_lib;

/// Centralised report generation service.
/// Produces real PDF bytes and CSV strings from live app data.
class ReportService {
  // ──────────────────────────────────────────────────────
  //  COLOUR PALETTE (PdfColors for PDF widgets)
  // ──────────────────────────────────────────────────────
  static const _navy = PdfColor.fromInt(0xFF1B4F72);
  static const _green = PdfColor.fromInt(0xFF10B981);
  static const _red = PdfColor.fromInt(0xFFEF4444);
  static const _blue = PdfColor.fromInt(0xFF3B82F6);
  static const _grey = PdfColor.fromInt(0xFF6B7280);
  static const _lightGrey = PdfColor.fromInt(0xFFF3F4F6);
  static const _white = PdfColors.white;

  // ──────────────────────────────────────────────────────
  //  FONT LOADING
  // ──────────────────────────────────────────────────────

  pw.ThemeData? _cachedTheme;

  /// Load Roboto from Google Fonts (supports full Unicode).
  /// Falls back to default PDF fonts if loading fails.
  Future<pw.ThemeData> _loadTheme() async {
    if (_cachedTheme != null) return _cachedTheme!;
    try {
      final regular = await PdfGoogleFonts.robotoRegular();
      final bold = await PdfGoogleFonts.robotoBold();
      final italic = await PdfGoogleFonts.robotoItalic();
      final boldItalic = await PdfGoogleFonts.robotoBoldItalic();
      _cachedTheme = pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        italic: italic,
        boldItalic: boldItalic,
      );
    } catch (_) {
      // Fallback to built-in Helvetica if Google Fonts fail
      _cachedTheme = pw.ThemeData.withFont();
    }
    return _cachedTheme!;
  }

  // ═══════════════════════════════════════════════════════
  //  1) PROFIT & LOSS PDF
  // ═══════════════════════════════════════════════════════

  /// Generates a Profit & Loss PDF for [month] (if non-null, monthly;
  /// otherwise annual for year of [periodStart]).
  Future<Uint8List> generatePnlPdf({
    required List<Transaction> transactions,
    required String currency,
    required DateTime periodStart,
    required bool isMonthly,
    String? businessName,
  }) async {
    final theme = await _loadTheme();
    final pdf = pw.Document(
      theme: theme,
      title:  'Profit & Loss Statement',
      author: businessName ?? 'Masari',
    );

    // ── Filter by period ──
    final filtered = transactions.where((tx) {
      if (tx.excludeFromPL) return false;
      if (isMonthly) {
        return tx.dateTime.year == periodStart.year &&
            tx.dateTime.month == periodStart.month;
      }
      return tx.dateTime.year == periodStart.year;
    }).toList();

    // ── Aggregate ──
    double salesRevenue = 0, cogs = 0, otherIncome = 0, opex = 0;
    final Map<String, double> revenueMap = {};
    final Map<String, double> cogsMap = {};
    final Map<String, double> opexMap = {};

    for (final tx in filtered) {
      final amt = tx.amount.abs();
      if (tx.categoryId == 'cat_sales_revenue') {
        salesRevenue += amt;
        revenueMap[tx.categoryId] = (revenueMap[tx.categoryId] ?? 0) + amt;
      } else if (tx.categoryId == 'cat_cogs') {
        cogs += amt;
        cogsMap[tx.categoryId] = (cogsMap[tx.categoryId] ?? 0) + amt;
      } else if (tx.isIncome) {
        otherIncome += amt;
        revenueMap[tx.categoryId] = (revenueMap[tx.categoryId] ?? 0) + amt;
      } else {
        opex += amt;
        opexMap[tx.categoryId] = (opexMap[tx.categoryId] ?? 0) + amt;
      }
    }
    final totalRevenue = salesRevenue + otherIncome;
    final grossProfit = salesRevenue - cogs;
    final netProfit = grossProfit + otherIncome - opex;
    final fmt = NumberFormat('#,##0.00', 'en');
    final periodLabel = isMonthly
        ? DateFormat( 'MMMM yyyy').format(periodStart)
        :  'Year ${periodStart.year}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (ctx) => _pdfHeader(
           'Profit & Loss Statement',
          periodLabel,
          businessName,
        ),
        footer: (ctx) => _pdfFooter(ctx),
        build: (ctx) => [
          // KPI row
          _kpiRow(fmt, currency, [
            ( 'Total Revenue', totalRevenue, _green),
            ( 'Gross Profit', grossProfit, _blue),
            ( 'Net Profit', netProfit, netProfit >= 0 ? _green : _red),
          ]),
          pw.SizedBox(height: 20),

          // Revenue breakdown
          _sectionTitle( 'Revenue Sources'),
          _breakdownTable(revenueMap, totalRevenue, currency, fmt),
          pw.SizedBox(height: 16),

          // COGS breakdown
          _sectionTitle( 'Cost of Goods Sold'),
          _breakdownTable(cogsMap, cogs, currency, fmt),
          pw.SizedBox(height: 16),

          // OpEx breakdown
          _sectionTitle( 'Operating Expenses'),
          _breakdownTable(opexMap, opex, currency, fmt),
          pw.SizedBox(height: 24),

          // Summary
          _summaryTable(fmt, currency, [
            ( 'Sales Revenue', salesRevenue),
            ( 'Cost of Goods Sold', -cogs),
            ( 'Gross Profit', grossProfit),
            ( 'Other Income', otherIncome),
            ( 'Operating Expenses', -opex),
            ( 'Net Profit', netProfit),
          ]),
        ],
      ),
    );

    return pdf.save();
  }

  // ═══════════════════════════════════════════════════════
  //  2) BALANCE SHEET PDF
  // ═══════════════════════════════════════════════════════

  Future<Uint8List> generateBalanceSheetPdf({
    required BalanceSheetEntries bs,
    required double inventoryValue,
    required double accountsReceivable,
    required double supplierPrepayments,
    required double suppliersOwing,
    required String currency,
    String? businessName,
  }) async {
    final theme = await _loadTheme();
    final pdf = pw.Document(
      theme: theme,
      title:  'Balance Sheet',
      author: businessName ?? 'Masari',
    );
    final fmt = NumberFormat('#,##0.00', 'en');
    final dateLabel = DateFormat('dd MMMM yyyy').format(DateTime.now());

    final totalAssets = bs.bankAccounts +
        bs.cashOnHand +
        bs.unpaidInvoices +
        inventoryValue +
        accountsReceivable +
        supplierPrepayments;
    final totalLiabilities = suppliersOwing + bs.loans + bs.unpaidSalaries;
    final netEquity = totalAssets - totalLiabilities;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (ctx) => _pdfHeader( 'Balance Sheet',  'As of $dateLabel', businessName),
        footer: (ctx) => _pdfFooter(ctx),
        build: (ctx) => [
          // Assets
          _sectionTitle( 'Assets (What You Own)'),
          _balanceTable(fmt, currency, [
            ( 'Bank Accounts', bs.bankAccounts),
            ( 'Cash on Hand', bs.cashOnHand),
            ('Inventory', inventoryValue),
            ( 'Unpaid Invoices', bs.unpaidInvoices),
            ('Receivables', accountsReceivable),
            ('Supplier Prepayments', supplierPrepayments),
          ], totalAssets,  'Total Assets'),
          pw.SizedBox(height: 20),

          // Liabilities
          _sectionTitle( 'Liabilities (What You Owe)'),
          _balanceTable(fmt, currency, [
            ('Supplier Payable', suppliersOwing),
            ('Loans', bs.loans),
            ( 'Unpaid Salaries', bs.unpaidSalaries),
          ], totalLiabilities,  'Total Liabilities'),
          pw.SizedBox(height: 20),

          // Net Equity
          _netEquityRow(fmt, currency, netEquity),
        ],
      ),
    );
    return pdf.save();
  }

  // ═══════════════════════════════════════════════════════
  //  3) CASH FLOW PDF
  // ═══════════════════════════════════════════════════════

  Future<Uint8List> generateCashFlowPdf({
    required List<Transaction> transactions,
    required String currency,
    required DateTime periodStart,
    required bool isMonthly,
    required double openingBalance,
    String? businessName,
  }) async {
    final theme = await _loadTheme();
    final pdf = pw.Document(
      theme: theme,
      title:  'Cash Flow Statement',
      author: businessName ?? 'Masari',
    );
    final fmt = NumberFormat('#,##0.00', 'en');
    final periodLabel = isMonthly
        ? DateFormat( 'MMMM yyyy').format(periodStart)
        :  'Year ${periodStart.year}';

    final filtered = transactions.where((tx) {
      if (isMonthly) {
        return tx.dateTime.year == periodStart.year &&
            tx.dateTime.month == periodStart.month;
      }
      return tx.dateTime.year == periodStart.year;
    }).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    double totalInflow = 0, totalOutflow = 0;
    final Map<String, double> inflowByCat = {};
    final Map<String, double> outflowByCat = {};

    for (final tx in filtered) {
      if (tx.amount > 0) {
        totalInflow += tx.amount;
        inflowByCat[tx.categoryId] =
            (inflowByCat[tx.categoryId] ?? 0) + tx.amount;
      } else {
        totalOutflow += tx.amount.abs();
        outflowByCat[tx.categoryId] =
            (outflowByCat[tx.categoryId] ?? 0) + tx.amount.abs();
      }
    }
    final netCashFlow = totalInflow - totalOutflow;
    final closingBalance = openingBalance + netCashFlow;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (ctx) =>
            _pdfHeader( 'Cash Flow Statement', periodLabel, businessName),
        footer: (ctx) => _pdfFooter(ctx),
        build: (ctx) => [
          _kpiRow(fmt, currency, [
            ( 'Total Inflow', totalInflow, _green),
            ( 'Total Outflow', totalOutflow, _red),
            ( 'Net Cash Flow', netCashFlow, netCashFlow >= 0 ? _green : _red),
          ]),
          pw.SizedBox(height: 20),

          // Cash Inflows
          _sectionTitle( 'Cash Inflows'),
          _breakdownTable(inflowByCat, totalInflow, currency, fmt),
          pw.SizedBox(height: 16),

          // Cash Outflows
          _sectionTitle( 'Cash Outflows'),
          _breakdownTable(outflowByCat, totalOutflow, currency, fmt),
          pw.SizedBox(height: 24),

          // Summary
          _summaryTable(fmt, currency, [
            ( 'Opening Balance', openingBalance),
            ( 'Total Cash Inflow', totalInflow),
            ( 'Total Cash Outflow', -totalOutflow),
            ( 'Net Cash Flow', netCashFlow),
            ( 'Closing Balance', closingBalance),
          ]),
        ],
      ),
    );
    return pdf.save();
  }

  // ═══════════════════════════════════════════════════════
  //  4) MONTHLY FINANCIAL REPORT PDF (comprehensive)
  // ═══════════════════════════════════════════════════════

  Future<Uint8List> generateMonthlyReportPdf({
    required List<Transaction> transactions,
    required List<Sale> sales,
    required List<Product> products,
    required BalanceSheetEntries bs,
    required double suppliersOwing,
    required double supplierPrepayments,
    required String currency,
    required DateTime month,
    required double openingBalance,
    String? businessName,
  }) async {
    final theme = await _loadTheme();
    final pdf = pw.Document(
      theme: theme,
      title:  'Monthly Financial Report',
      author: businessName ?? 'Masari',
    );
    final fmt = NumberFormat('#,##0.00', 'en');
    final periodLabel = DateFormat( 'MMMM yyyy').format(month);

    // ── P&L aggregation ──
    final plTx = transactions.where((tx) {
      if (tx.excludeFromPL) return false;
      return tx.dateTime.year == month.year &&
          tx.dateTime.month == month.month;
    }).toList();

    double salesRevenue = 0, cogsCost = 0, otherIncome = 0, opex = 0;
    for (final tx in plTx) {
      final amt = tx.amount.abs();
      if (tx.categoryId == 'cat_sales_revenue') {
        salesRevenue += amt;
      } else if (tx.categoryId == 'cat_cogs') {
        cogsCost += amt;
      } else if (tx.isIncome) {
        otherIncome += amt;
      } else {
        opex += amt;
      }
    }
    final grossProfit = salesRevenue - cogsCost;
    final netProfit = grossProfit + otherIncome - opex;

    // ── Cash flow aggregation ──
    final cfTx = transactions.where((tx) =>
        tx.dateTime.year == month.year &&
        tx.dateTime.month == month.month).toList();
    double totalInflow = 0, totalOutflow = 0;
    for (final tx in cfTx) {
      if (tx.amount > 0) {
        totalInflow += tx.amount;
      } else {
        totalOutflow += tx.amount.abs();
      }
    }
    final netCash = totalInflow - totalOutflow;

    // ── Sales aggregation ──
    final monthSales = sales.where((s) =>
        s.orderStatus != OrderStatus.cancelled &&
        s.date.year == month.year &&
        s.date.month == month.month).toList();
    final totalSalesCount = monthSales.length;
    final totalSalesValue =
        monthSales.fold<double>(0, (s, sale) => s + sale.total);
    final totalSalesOutstanding =
        monthSales.fold<double>(0, (s, sale) => s + sale.outstanding);

    // ── Inventory snapshot ──
    final double inventoryValue =
        products.fold<double>(0, (s, p) => s + p.totalCostValue);
    final lowStockCount =
        products.where((p) => p.status == StockStatus.lowStock).length;
    final outOfStockCount =
        products.where((p) => p.status == StockStatus.outOfStock).length;

    // ── Balance sheet ──
    final accountsReceivable = sales
        .where((s) => s.orderStatus != OrderStatus.cancelled)
        .fold<double>(0, (sum, s) => sum + s.outstanding);
    final totalAssets = bs.bankAccounts +
        bs.cashOnHand +
        bs.unpaidInvoices +
        inventoryValue +
        accountsReceivable +
        supplierPrepayments;
    final totalLiabilities = suppliersOwing + bs.loans + bs.unpaidSalaries;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (ctx) => _pdfHeader(
             'Monthly Financial Report', periodLabel, businessName),
        footer: (ctx) => _pdfFooter(ctx),
        build: (ctx) => [
          // === P&L Summary ===
          _sectionTitle( 'Profit & Loss'),
          _summaryTable(fmt, currency, [
            ( 'Sales Revenue', salesRevenue),
            ( 'Cost of Goods Sold', -cogsCost),
            ( 'Gross Profit', grossProfit),
            ( 'Other Income', otherIncome),
            ( 'Operating Expenses', -opex),
            ( 'Net Profit', netProfit),
          ]),
          pw.SizedBox(height: 24),

          // === Cash Flow Summary ===
          _sectionTitle( 'Cash Flow'),
          _summaryTable(fmt, currency, [
            ( 'Opening Balance', openingBalance),
            ( 'Cash Inflow', totalInflow),
            ( 'Cash Outflow', -totalOutflow),
            ( 'Net Cash Flow', netCash),
            ( 'Closing Balance', openingBalance + netCash),
          ]),
          pw.SizedBox(height: 24),

          // === Sales Summary ===
          _sectionTitle( 'Sales Overview'),
          _twoColumnKpis(fmt, currency, [
            ( 'Total Orders', totalSalesCount.toString()),
            ( 'Total Sales Value', '$currency ${fmt.format(totalSalesValue)}'),
            ('Outstanding', '$currency ${fmt.format(totalSalesOutstanding)}'),
          ]),
          pw.SizedBox(height: 24),

          // === Inventory Snapshot ===
          _sectionTitle( 'Inventory Snapshot'),
          _twoColumnKpis(fmt, currency, [
            ( 'Total Inventory Value', '$currency ${fmt.format(inventoryValue)}'),
            ('Products', '${products.length}'),
            ('Low Stock Filter', '$lowStockCount'),
            ('Out of Stock Filter', '$outOfStockCount'),
          ]),
          pw.SizedBox(height: 24),

          // === Balance Sheet Summary ===
          _sectionTitle( 'Balance Sheet'),
          _summaryTable(fmt, currency, [
            ( 'Total Assets', totalAssets),
            ( 'Total Liabilities', -totalLiabilities),
            ( 'Net Equity', totalAssets - totalLiabilities),
          ]),
        ],
      ),
    );
    return pdf.save();
  }

  // ═══════════════════════════════════════════════════════
  //  5) CSV EXPORTS
  // ═══════════════════════════════════════════════════════

  /// Export transactions as CSV string.
  String exportTransactionsCsv(
      List<Transaction> transactions, String currency) {
    final rows = <List<dynamic>>[
      [
         'Date',
         'Title',
         'Amount ($currency)',
         'Type',
        'Category',
         'Payment Method',
         'Note',
      ],
      ...transactions.map((tx) => [
            DateFormat('yyyy-MM-dd').format(tx.dateTime),
            tx.title,
            tx.amount.toStringAsFixed(2),
            tx.isIncome ? 'Income' : 'Expense',
            CategoryData.findById(tx.categoryId).name,
            tx.paymentMethod,
            tx.note ?? '',
          ]),
    ];
    return const csv_lib.ListToCsvConverter().convert(rows);
  }

  /// Export sales as CSV string.
  String exportSalesCsv(List<Sale> sales, String currency) {
    final rows = <List<dynamic>>[
      [
         'Date',
         'Customer',
         'Items',
         'Subtotal ($currency)',
         'Tax',
         'Discount',
         'Shipping',
         'Total ($currency)',
         'Paid ($currency)',
         'Outstanding ($currency)',
         'Payment Status',
         'Order Status',
      ],
      ...sales.map((s) => [
            DateFormat('yyyy-MM-dd').format(s.date),
            s.customerName ?? 'Walk-in',
            s.items.map((i) => '${i.productName} x${i.quantity}').join('; '),
            s.subtotal.toStringAsFixed(2),
            s.taxAmount.toStringAsFixed(2),
            s.discountAmount.toStringAsFixed(2),
            s.shippingCost.toStringAsFixed(2),
            s.total.toStringAsFixed(2),
            s.amountPaid.toStringAsFixed(2),
            s.outstanding.toStringAsFixed(2),
            s.paymentStatus.name,
            s.orderStatus.name,
          ]),
    ];
    return const csv_lib.ListToCsvConverter().convert(rows);
  }

  /// Export inventory as CSV string.
  /// Multi-variant products produce one row per variant with variant detail;
  /// single-variant products produce a single row with aggregate values.
  String exportInventoryCsv(List<Product> products, String currency) {
    final rows = <List<dynamic>>[
      [
         'SKU',
         'Name',
         'Variant',
        'Category',
        'Supplier Label',
         'Cost Price ($currency)',
         'Selling Price ($currency)',
         'Stock',
         'Unit',
         'Stock Value ($currency)',
         'Status',
      ],
      for (final p in products)
        if (p.hasVariants)
          for (final v in p.variants)
            [
              v.sku,
              p.name,
              v.displayName,
              p.category,
              p.supplier,
              v.costPrice.toStringAsFixed(2),
              v.sellingPrice.toStringAsFixed(2),
              v.currentStock,
              p.unitOfMeasure,
              v.totalCostValue.toStringAsFixed(2),
              v.status.name,
            ]
        else
          [
            p.sku,
            p.name,
            '',
            p.category,
            p.supplier,
            p.costPrice.toStringAsFixed(2),
            p.sellingPrice.toStringAsFixed(2),
            p.currentStock,
            p.unitOfMeasure,
            p.totalCostValue.toStringAsFixed(2),
            p.status.name,
          ],
    ];
    return const csv_lib.ListToCsvConverter().convert(rows);
  }

  // ═══════════════════════════════════════════════════════
  //  PRIVATE PDF HELPERS
  // ═══════════════════════════════════════════════════════

  static pw.Widget _pdfHeader(
      String title, String subtitle, String? businessName) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 20),
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _navy, width: 2)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title,
                  style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: _navy)),
              pw.SizedBox(height: 4),
              pw.Text(subtitle,
                  style: const pw.TextStyle(fontSize: 11, color: _grey)),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(businessName ?? 'Masari',
                  style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: _navy)),
              pw.SizedBox(height: 2),
              pw.Text(
                   'Generated ${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 9, color: _grey)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _pdfFooter(pw.Context ctx) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _lightGrey, width: 1)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text( 'Masari App - Financial Report',
              style: const pw.TextStyle(fontSize: 8, color: _grey)),
          pw.Text( 'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: _grey)),
        ],
      ),
    );
  }

  static pw.Widget _kpiRow(
      NumberFormat fmt, String currency, List<(String, double, PdfColor)> items) {
    return pw.Row(
      children: items
          .map((item) => pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  margin: const pw.EdgeInsets.symmetric(horizontal: 4),
                  decoration: pw.BoxDecoration(
                    color: item.$3.shade(0.95),
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(color: item.$3.shade(0.8)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(item.$1,
                          style: const pw.TextStyle(
                              fontSize: 9, color: _grey)),
                      pw.SizedBox(height: 4),
                      pw.Text('$currency ${fmt.format(item.$2)}',
                          style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                              color: item.$3)),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }

  static pw.Widget _sectionTitle(String title) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8, top: 4),
      child: pw.Text(title,
          style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: _navy)),
    );
  }

  static pw.Widget _breakdownTable(
    Map<String, double> map,
    double total,
    String currency,
    NumberFormat fmt,
  ) {
    if (map.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: _lightGrey,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Text( 'No data for this period',
            style: const pw.TextStyle(fontSize: 10, color: _grey)),
      );
    }
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return pw.Table(
      border: pw.TableBorder.all(color: _lightGrey),
      columnWidths: {
        0: const pw.FlexColumnWidth(4),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _lightGrey),
          children: [
            _tableCell('Category', bold: true),
            _tableCell( 'Amount ($currency)', bold: true, align: pw.TextAlign.right),
            _tableCell('%', bold: true, align: pw.TextAlign.right),
          ],
        ),
        ...sorted.map((e) {
          final pct = total > 0 ? (e.value / total * 100) : 0;
          return pw.TableRow(children: [
            _tableCell(CategoryData.findById(e.key).name),
            _tableCell(fmt.format(e.value), align: pw.TextAlign.right),
            _tableCell('${pct.toStringAsFixed(1)}%',
                align: pw.TextAlign.right),
          ]);
        }),
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _lightGrey),
          children: [
            _tableCell('Total', bold: true),
            _tableCell(fmt.format(total),
                bold: true, align: pw.TextAlign.right),
            _tableCell('100%', bold: true, align: pw.TextAlign.right),
          ],
        ),
      ],
    );
  }

  static pw.Widget _summaryTable(
      NumberFormat fmt, String currency, List<(String, double)> rows) {
    return pw.Table(
      border: pw.TableBorder.all(color: _lightGrey),
      columnWidths: {
        0: const pw.FlexColumnWidth(3),
        1: const pw.FlexColumnWidth(2),
      },
      children: rows.map((row) {
        final isTotal = row.$1.contains('Net') || row.$1.contains('Closing');
        return pw.TableRow(
          decoration:
              isTotal ? const pw.BoxDecoration(color: _lightGrey) : null,
          children: [
            _tableCell(row.$1, bold: isTotal),
            _tableCell(
              '${row.$2 < 0 ? "(" : ""}$currency ${fmt.format(row.$2.abs())}${row.$2 < 0 ? ")" : ""}',
              bold: isTotal,
              align: pw.TextAlign.right,
              color: row.$2 < 0 ? _red : null,
            ),
          ],
        );
      }).toList(),
    );
  }

  static pw.Widget _balanceTable(
    NumberFormat fmt,
    String currency,
    List<(String, double)> items,
    double total,
    String totalLabel,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: _lightGrey),
      columnWidths: {
        0: const pw.FlexColumnWidth(3),
        1: const pw.FlexColumnWidth(2),
      },
      children: [
        ...items.map((item) => pw.TableRow(children: [
              _tableCell(item.$1),
              _tableCell('$currency ${fmt.format(item.$2)}',
                  align: pw.TextAlign.right),
            ])),
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _lightGrey),
          children: [
            _tableCell(totalLabel, bold: true),
            _tableCell('$currency ${fmt.format(total)}',
                bold: true, align: pw.TextAlign.right),
          ],
        ),
      ],
    );
  }

  static pw.Widget _netEquityRow(
      NumberFormat fmt, String currency, double equity) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _navy,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text( 'Net Equity',
              style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: _white)),
          pw.Text('$currency ${fmt.format(equity)}',
              style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: _white)),
        ],
      ),
    );
  }

  static pw.Widget _twoColumnKpis(
      NumberFormat fmt, String currency, List<(String, String)> items) {
    return pw.Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items
          .map((item) => pw.Container(
                width: 160,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: _lightGrey,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(item.$1,
                        style: const pw.TextStyle(fontSize: 9, color: _grey)),
                    pw.SizedBox(height: 3),
                    pw.Text(item.$2,
                        style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: _navy)),
                  ],
                ),
              ))
          .toList(),
    );
  }

  static pw.Widget _tableCell(
    String text, {
    bool bold = false,
    pw.TextAlign align = pw.TextAlign.left,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: bold ? pw.FontWeight.bold : null,
          color: color ?? _navy,
        ),
      ),
    );
  }
}
