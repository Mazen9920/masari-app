import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../shared/models/purchase_model.dart';
import '../../shared/models/supplier_model.dart';
import 'record_payment_screen.dart';
import 'record_purchase_screen.dart';
import 'supplier_detail_screen.dart';

/// Purchase receipt detail — status hero, supplier info, items breakdown,
/// payment terms, sticky action bar.
class PurchaseDetailScreen extends ConsumerWidget {
  final Supplier? supplier;
  final Purchase? purchase;
  const PurchaseDetailScreen({super.key, this.supplier, this.purchase});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final fmt = NumberFormat('#,##0', 'en');

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                child: Column(
                  children: [
                    // Status hero card
                    _StatusHero(fmt: fmt, purchase: purchase, currency: currency)
                        .animate()
                        .fadeIn(duration: 250.ms),
                    const SizedBox(height: 14),
                    // Supplier info
                    _SupplierInfo(supplier: supplier, purchase: purchase)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 60.ms),
                    const SizedBox(height: 14),
                    // Items breakdown
                    _ItemsBreakdown(fmt: fmt, purchase: purchase, currency: currency)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 120.ms),
                    const SizedBox(height: 14),
                    // Payment terms
                    _PaymentTermsCard(purchase: purchase, supplier: supplier)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 180.ms),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      // Sticky dual CTA
      bottomSheet: _BottomActions(supplier: supplier, purchase: purchase),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
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
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.textSecondary,
          ),
          Expanded(
            child: Center(
              child: Text(
                'Purchase Details',
                style: AppTypography.h2.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () => HapticFeedback.lightImpact(),
            icon: const Icon(Icons.ios_share_rounded),
            color: AppColors.primaryNavy,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  STATUS HERO — amount, status badge, reference
// ═══════════════════════════════════════════════════════
class _StatusHero extends StatelessWidget {
  final NumberFormat fmt;
  final Purchase? purchase;
  final String currency;
  const _StatusHero({required this.fmt, this.purchase, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.borderLight.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Orange top bar
          Positioned(
            top: -28,
            left: -20,
            right: -20,
            child: Container(
              height: 4,
              color: const Color(0xFFE67E22),
            ),
          ),
          Column(
            children: [
              // Status badge
              Builder(builder: (_) {
                final status = purchase?.paymentStatus ?? 0;
                final label = purchase?.statusLabel.toUpperCase() ?? 'UNPAID';
                final color = status == 2
                    ? const Color(0xFF27AE60)
                    : status == 1
                        ? const Color(0xFFD97706)
                        : const Color(0xFFD97706);
                final bgColor = status == 2
                    ? const Color(0xFFF0FDF4)
                    : const Color(0xFFFEF3C7);
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              );
              }),
              const SizedBox(height: 14),
              // Amount label
              Text(
                'Total Amount',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              // Total
              Text(
                '$currency ${fmt.format(purchase?.total ?? 0)}',
                style: TextStyle(
                  color: AppColors.primaryNavy,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              // Reference
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  purchase?.referenceNo ?? '',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _initialsFromName(String name) {
  if (name.trim().isEmpty) return '?';
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  if (name.length >= 2) return name.substring(0, 2).toUpperCase();
  return name.toUpperCase();
}

// ═══════════════════════════════════════════════════════
//  SUPPLIER INFO SECTION
// ═══════════════════════════════════════════════════════
class _SupplierInfo extends StatelessWidget {
  final Supplier? supplier;
  final Purchase? purchase;
  const _SupplierInfo({this.supplier, this.purchase});

  @override
  Widget build(BuildContext context) {
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
      child: Column(
        children: [
          // Supplier row
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryNavy.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.borderLight.withValues(alpha: 0.4),
                  ),
                ),
                child: Center(
                  child: Text(
                    _initialsFromName(supplier?.name ?? purchase?.supplierName ?? ''),
                    style: TextStyle(
                      color: supplier?.avatarTextColor ?? AppColors.primaryNavy,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
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
                      'Supplier',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      (supplier?.name ?? purchase?.supplierName ?? ''),
                      style: TextStyle(
                        color: AppColors.primaryNavy,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  if (supplier != null) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SupplierDetailScreen(supplier: supplier!),
                      ),
                    );
                  }
                },
                child: Text(
                  'View Profile',
                  style: TextStyle(
                    color: const Color(0xFF3498DB),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Divider
          Divider(
              height: 1,
              color: AppColors.borderLight.withValues(alpha: 0.4)),
          const SizedBox(height: 14),
          // Date & Category
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Date Issued',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_today_rounded,
                            color: AppColors.textTertiary, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          purchase != null ? DateFormat('MM/dd/yyyy').format(purchase!.date) : '-',
                          style: TextStyle(
                            color: AppColors.primaryNavy,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Category',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.category_rounded,
                            color: AppColors.textTertiary, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          (supplier?.category ?? ''),
                          style: TextStyle(
                            color: AppColors.primaryNavy,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
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
}

// ═══════════════════════════════════════════════════════
//  ITEMS BREAKDOWN
// ═══════════════════════════════════════════════════════
class _ItemsBreakdown extends StatelessWidget {
  final NumberFormat fmt;
  final Purchase? purchase;
  final String currency;
  const _ItemsBreakdown({required this.fmt, this.purchase, required this.currency});

  @override
  Widget build(BuildContext context) {
    final items = purchase?.items ?? [];
    final subtotal = purchase?.subtotal ?? 0;
    final tax = purchase?.tax ?? 0;
    final total = purchase?.total ?? 0;

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
        children: [
          // Header
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(
                bottom: BorderSide(
                  color: AppColors.borderLight.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Text(
              'Items Breakdown',
              style: TextStyle(
                color: AppColors.primaryNavy,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          // Items
          ...items.map((item) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: TextStyle(
                          color: AppColors.primaryNavy,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item.qty} x $currency ${fmt.format(item.unitPrice)}',
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$currency ${fmt.format(item.total)}',
                  style: TextStyle(
                    color: AppColors.primaryNavy,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          )),
          // Totals
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC).withValues(alpha: 0.5),
              border: Border(
                top: BorderSide(
                  color: AppColors.borderLight.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Column(
              children: [
                _totalRow('Subtotal', '$currency ${fmt.format(subtotal)}', false),
                const SizedBox(height: 8),
                _totalRow('Tax', '$currency ${fmt.format(tax)}', false),
                const SizedBox(height: 10),
                Divider(
                    height: 1,
                    color: AppColors.borderLight.withValues(alpha: 0.5)),
                const SizedBox(height: 10),
                _totalRow('Total', '$currency ${fmt.format(total)}', true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value, bool isBold) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isBold ? AppColors.primaryNavy : AppColors.textTertiary,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
            fontSize: isBold ? 15 : 13,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: isBold ? AppColors.primaryNavy : AppColors.primaryNavy,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            fontSize: isBold ? 18 : 13,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
//  PAYMENT TERMS CARD
// ═══════════════════════════════════════════════════════
class _PaymentTermsCard extends StatelessWidget {
  final Purchase? purchase;
  final Supplier? supplier;
  const _PaymentTermsCard({this.purchase, this.supplier});
  @override
  Widget build(BuildContext context) {
    final dueDate = purchase?.dueDate;
    final terms = supplier?.paymentTerms ?? 'On Receipt';
    final isPaid = (purchase?.paymentStatus ?? 0) == 2;
    final isOverdue = !isPaid && dueDate != null && dueDate.isBefore(DateTime.now());
    final dueDateColor = isOverdue ? const Color(0xFFC0392B) : AppColors.primaryNavy;
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Payment Terms',
            style: TextStyle(
              color: AppColors.primaryNavy,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Due Date',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(isOverdue ? Icons.event_busy_rounded : Icons.event_rounded,
                            color: dueDateColor, size: 15),
                        const SizedBox(width: 4),
                        Text(
                          dueDate != null ? DateFormat('MM/dd/yyyy').format(dueDate) : 'N/A',
                          style: TextStyle(
                            color: dueDateColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Terms',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      terms,
                      style: TextStyle(
                        color: AppColors.primaryNavy,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(
              height: 1,
              color: AppColors.borderLight.withValues(alpha: 0.3)),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  color: AppColors.textTertiary, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  terms == 'On Receipt'
                      ? 'Payment is due upon receipt of goods.'
                      : 'Payment is due within ${terms.replaceAll('Net ', '')} days of receipt date.',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  BOTTOM ACTIONS — Record Payment + Edit Purchase
// ═══════════════════════════════════════════════════════
class _BottomActions extends StatelessWidget {
  final Supplier? supplier;
  final Purchase? purchase;
  const _BottomActions({this.supplier, this.purchase});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        border: Border(
          top: BorderSide(
              color: AppColors.borderLight.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          // Record Payment (outline)
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RecordPaymentScreen(
                      preselectedSupplierId: supplier?.id ?? purchase?.supplierId,
                      preselectedPurchaseId: purchase?.id,
                    ),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFE67E22),
                    width: 2,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.payments_rounded,
                        color: Color(0xFFE67E22), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Record Payment',
                      style: TextStyle(
                        color: Color(0xFFE67E22),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Edit Purchase (filled)
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RecordPurchaseScreen(
                      preselectedSupplierId: supplier?.id ?? purchase?.supplierId,
                    ),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color: AppColors.primaryNavy,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryNavy.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.edit_rounded,
                        color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Edit Purchase',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
