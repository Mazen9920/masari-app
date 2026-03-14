import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../shared/models/supplier_model.dart';
import '../../shared/models/purchase_model.dart';
import '../../shared/models/payment_model.dart';
import '../../shared/models/goods_receipt_model.dart';
import '../../shared/utils/safe_pop.dart';

/// Supplier profile — avatar, balance, contact actions, stats, recent activity.
class SupplierDetailScreen extends ConsumerWidget {
  final Supplier supplier;
  const SupplierDetailScreen({super.key, required this.supplier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch for live updates
    final suppliers = ref.watch(suppliersProvider).value ?? [];
    final live = suppliers.firstWhere(
      (s) => s.id == supplier.id,
      orElse: () => supplier,
    );
    final currency = ref.watch(currencyProvider);
    final fmt = NumberFormat('#,##0', 'en');
    final dateFmt = DateFormat('MM/dd/yyyy');

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context, live),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 120),
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    // Avatar & name
                    _ProfileSection(supplier: live)
                        .animate()
                        .fadeIn(duration: 250.ms),
                    const SizedBox(height: 20),
                    // Total Due card
                    _BalanceCard(balance: live.balance, fmt: fmt, currency: currency)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 60.ms),
                    const SizedBox(height: 16),
                    // Contact action buttons
                    _ContactActions(supplier: live)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 100.ms),
                    const SizedBox(height: 16),
                    // Stats row
                    _StatsRow(supplier: live, fmt: fmt, dateFmt: dateFmt)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 140.ms),
                    const SizedBox(height: 20),
                    // Recent activity
                    _RecentActivity(supplier: live, fmt: fmt, dateFmt: dateFmt)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 180.ms),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      // Sticky CTA — two buttons
      bottomSheet: Container(
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
            Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  context.pushNamed('RecordPurchaseScreen', extra: {'preselectedSupplierId': live.id});
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE67E22),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE67E22).withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.add_rounded, color: Colors.white, size: 20),
                      SizedBox(width: 6),
                      Text(
                        'Purchase',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  context.pushNamed('ReceiveGoodsScreen', extra: {'preselectedSupplierId': live.id});
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.inventory_2_rounded, color: Colors.white, size: 20),
                      SizedBox(width: 6),
                      Text(
                        'Receive Goods',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Supplier live) {
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
            onPressed: () => context.safePop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.textSecondary,
          ),
          Expanded(
            child: Center(
              child: Text(
                'Supplier Detail',
                style: AppTypography.h2.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              context.pushNamed('EditSupplierScreen', extra: {'supplier': live});
            },
            icon: const Icon(Icons.edit_rounded),
            color: AppColors.primaryNavy,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  PROFILE SECTION — avatar + name + category
// ═══════════════════════════════════════════════════════
class _ProfileSection extends StatelessWidget {
  final Supplier supplier;
  const _ProfileSection({required this.supplier});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: supplier.avatarBg,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipOval(
            child: supplier.imageUrl != null && supplier.imageUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: supplier.imageUrl!,
                    fit: BoxFit.cover,
                    width: 80,
                    height: 80,
                    placeholder: (_, __) => Center(
                      child: Text(
                        supplier.initials,
                        style: TextStyle(
                          color: supplier.avatarTextColor,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      supplier.initials,
                      style: TextStyle(
                        color: supplier.avatarTextColor,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          supplier.name,
          style: AppTypography.h1.copyWith(
            color: AppColors.primaryNavy,
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Category: ${supplier.category}',
          style: TextStyle(
            color: AppColors.textTertiary,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
//  BALANCE CARD — Total Due
// ═══════════════════════════════════════════════════════
class _BalanceCard extends StatelessWidget {
  final double balance;
  final NumberFormat fmt;
  final String currency;
  const _BalanceCard({required this.balance, required this.fmt, required this.currency});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        context.pushNamed('PaymentsSummaryScreen');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
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
          alignment: Alignment.center,
          children: [
            // Watermark icon
            Positioned(
              right: 16,
              top: 0,
              child: Icon(
                Icons.account_balance_wallet_rounded,
                size: 56,
                color: const Color(0xFFE67E22).withValues(alpha: 0.06),
              ),
            ),
            Column(
              children: [
                Text(
                  'TOTAL DUE',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$currency ${fmt.format(balance)}',
                  style: const TextStyle(
                    color: Color(0xFFE67E22),
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  CONTACT ACTIONS — Call, WhatsApp, Email
// ═══════════════════════════════════════════════════════
class _ContactActions extends StatelessWidget {
  final Supplier supplier;
  const _ContactActions({required this.supplier});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _contactButton(
            icon: Icons.call_rounded,
            label: 'Call',
            color: const Color(0xFF3498DB),
            onTap: () {
              HapticFeedback.lightImpact();
              if (supplier.phone.isNotEmpty) {
                launchUrl(Uri.parse('tel:${supplier.phone}'));
              }
            },
          ),
          const SizedBox(width: 12),
          _contactButton(
            icon: Icons.chat_rounded,
            label: 'WhatsApp',
            color: const Color(0xFF22C55E),
            onTap: () {
              HapticFeedback.lightImpact();
              if (supplier.phone.isNotEmpty) {
                final phone = supplier.phone.replaceAll(RegExp(r'[^0-9+]'), '');
                launchUrl(Uri.parse('https://wa.me/$phone'));
              }
            },
          ),
          const SizedBox(width: 12),
          _contactButton(
            icon: Icons.email_rounded,
            label: 'Email',
            color: const Color(0xFF3498DB),
            onTap: () {
              HapticFeedback.lightImpact();
              if (supplier.email.isNotEmpty) {
                launchUrl(Uri.parse('mailto:${supplier.email}'));
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _contactButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.borderLight.withValues(alpha: 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  STATS ROW — Total Spend, Last Purchase, Goods Received
// ═══════════════════════════════════════════════════════
class _StatsRow extends ConsumerWidget {
  final Supplier supplier;
  final NumberFormat fmt;
  final DateFormat dateFmt;
  const _StatsRow(
      {required this.supplier, required this.fmt, required this.dateFmt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final purchases = ref.watch(purchasesProvider);
    final supplierPurchases = purchases.where((p) => p.supplierId == supplier.id).toList();
    final totalSpend = supplierPurchases.fold<double>(0, (s, p) => s + p.total);

    final allReceipts = ref.watch(goodsReceiptsProvider);
    final supplierReceipts = allReceipts.where((r) => r.supplierId == supplier.id).toList();
    final totalReceived = supplierReceipts.fold<double>(0, (s, r) => s + r.totalCost);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.borderLight.withValues(alpha: 0.4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Purchased',
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$currency ${fmt.format(totalSpend)}',
                        style: TextStyle(
                          color: AppColors.primaryNavy,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _statCard(
                  'Last Purchase', dateFmt.format(supplier.lastTransaction)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.borderLight.withValues(alpha: 0.4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.inventory_2_rounded,
                              size: 14, color: const Color(0xFF7C3AED)),
                          const SizedBox(width: 4),
                          Text(
                            'Goods Received',
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$currency ${fmt.format(totalReceived)}',
                        style: const TextStyle(
                          color: Color(0xFF7C3AED),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _statCard(
                '${supplierReceipts.length} Receipt${supplierReceipts.length == 1 ? '' : 's'}',
                supplierReceipts.isNotEmpty
                    ? dateFmt.format(supplierReceipts.first.date)
                    : '—',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.borderLight.withValues(alpha: 0.4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: AppColors.primaryNavy,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  RECENT ACTIVITY LIST — purchases + payments + goods receipts
// ═══════════════════════════════════════════════════════
class _RecentActivity extends ConsumerWidget {
  final Supplier supplier;
  final NumberFormat fmt;
  final DateFormat dateFmt;
  const _RecentActivity(
      {required this.supplier, required this.fmt, required this.dateFmt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final allPurchases = ref.watch(purchasesProvider);
    final allPayments = ref.watch(paymentsProvider);
    final allReceipts = ref.watch(goodsReceiptsProvider);
    final purchases = allPurchases
        .where((p) => p.supplierId == supplier.id)
        .toList();
    final payments = allPayments
        .where((p) => p.supplierId == supplier.id)
        .toList();
    final receipts = allReceipts
        .where((r) => r.supplierId == supplier.id)
        .toList();

    // Build a unified timeline of _ActivityItem sorted by date descending
    final items = <_ActivityItem>[
      ...purchases.map((p) => _ActivityItem(
            date: p.date,
            type: _ActivityType.purchase,
            purchase: p,
          )),
      ...payments.map((p) => _ActivityItem(
            date: p.date,
            type: _ActivityType.payment,
            payment: p,
          )),
      ...receipts.map((r) => _ActivityItem(
            date: r.date,
            type: _ActivityType.goodsReceipt,
            receipt: r,
          )),
    ]..sort((a, b) => b.date.compareTo(a.date));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'Recent Activity',
              style: AppTypography.h2.copyWith(
                color: AppColors.primaryNavy,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          if (items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.borderLight.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                children: [
                  Icon(Icons.receipt_long_rounded,
                      color: AppColors.textTertiary, size: 36),
                  const SizedBox(height: 10),
                  Text(
                    'No activity yet',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Record a purchase, payment, or receive goods to get started.',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            Container(
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
                children: List.generate(items.length, (i) {
                  final item = items[i];
                  return Column(
                    children: [
                      if (i > 0)
                        Divider(
                            height: 1,
                            color: AppColors.borderLight.withValues(alpha: 0.3)),
                      if (item.type == _ActivityType.purchase)
                        _buildPurchaseRow(context, item.purchase!, currency)
                      else if (item.type == _ActivityType.payment)
                        _buildPaymentRow(context, item.payment!, currency)
                      else
                        _buildReceiptRow(context, item.receipt!, currency, ref),
                    ],
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPurchaseRow(BuildContext context, Purchase p, String currency) {
    final statusColors = _statusColors(p.paymentStatus);
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        context.pushNamed('PurchaseDetailScreen',
            extra: {'supplier': supplier, 'purchase': p});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFFFEF3C7),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shopping_cart_rounded,
                  color: Color(0xFFEA580C), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.referenceNo.isNotEmpty
                        ? 'Purchase #${p.referenceNo}'
                        : 'Purchase — ${p.items.length} item${p.items.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: AppColors.primaryNavy,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    dateFmt.format(p.date),
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$currency ${fmt.format(p.total)}',
                  style: TextStyle(
                    color: AppColors.primaryNavy,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColors.$1,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    p.statusLabel,
                    style: TextStyle(
                      color: statusColors.$2,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentRow(BuildContext context, Payment p, String currency) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        context.pushNamed('PaymentDetailScreen',
            extra: {'payment': p, 'supplier': supplier});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFFDCFCE7),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.payments_rounded,
                  color: Color(0xFF166534), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Payment — ${p.method}',
                    style: TextStyle(
                      color: AppColors.primaryNavy,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    dateFmt.format(p.date),
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '- $currency ${fmt.format(p.amount)}',
                  style: const TextStyle(
                    color: Color(0xFF166534),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'PAID',
                    style: TextStyle(
                      color: Color(0xFF166534),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }

  (Color, Color) _statusColors(int status) {
    switch (status) {
      case 2:
        return (const Color(0xFFDCFCE7), const Color(0xFF166534));
      case 1:
        return (const Color(0xFFDBEAFE), const Color(0xFF1D4ED8));
      default:
        return (const Color(0xFFFEF3C7), const Color(0xFF92400E));
    }
  }

  Widget _buildReceiptRow(
      BuildContext context, GoodsReceipt r, String currency, WidgetRef ref) {
    final receiptStatusColors = _receiptStatusColors(r.status);
    final totalItems =
        r.items.fold<double>(0, (s, i) => s + i.receivedQty);
    final itemNames =
        r.items.map((i) => i.productName).take(2).join(', ');
    final overflow =
        r.items.length > 2 ? ' +${r.items.length - 2}' : '';
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        context.pushNamed('ReceiptDetailScreen', extra: {'receipt': r});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFFF3E8FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.inventory_2_rounded,
                  color: Color(0xFF7C3AED), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Received ${totalItems.toInt()} item${totalItems.toInt() == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: AppColors.primaryNavy,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$itemNames$overflow \u00b7 ${dateFmt.format(r.date)}',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$currency ${fmt.format(r.totalCost)}',
                  style: const TextStyle(
                    color: Color(0xFF7C3AED),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: receiptStatusColors.$1,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    r.statusLabel.toUpperCase(),
                    style: TextStyle(
                      color: receiptStatusColors.$2,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 2),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded,
                  color: AppColors.textTertiary, size: 20),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onSelected: (v) {
                if (v == 'details') {
                  context.pushNamed('ReceiptDetailScreen',
                      extra: {'receipt': r});
                } else if (v == 'edit') {
                  context.pushNamed('EditReceiptScreen',
                      extra: {'receipt': r});
                } else if (v == 'delete') {
                  _confirmDeleteReceipt(context, r, ref, currency);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'details',
                    child: Row(children: [
                      Icon(Icons.visibility_rounded,
                          size: 18, color: Color(0xFF7C3AED)),
                      SizedBox(width: 8),
                      Text('View Details'),
                    ])),
                PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit_rounded,
                          size: 18, color: Color(0xFFEA580C)),
                      SizedBox(width: 8),
                      Text('Edit Receipt'),
                    ])),
                PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_rounded,
                          size: 18, color: Color(0xFFDC2626)),
                      SizedBox(width: 8),
                      Text('Delete Receipt',
                          style: TextStyle(color: Color(0xFFDC2626))),
                    ])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteReceipt(
      BuildContext context, GoodsReceipt r, WidgetRef ref, String currency) {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Receipt'),
        content: const Text(
          'This will delete the receipt and reverse the inventory stock adjustment. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();

              // Reverse inventory adjustments
              final products = ref.read(inventoryProvider).value ?? [];
              for (final item in r.items) {
                if (item.receivedQty > 0) {
                  String? pid = item.productId;
                  if (pid == null) {
                    final match = products.cast<dynamic>().firstWhere(
                          (p) =>
                              p.name.toString().toLowerCase() ==
                              item.productName.toLowerCase(),
                          orElse: () => null,
                        );
                    pid = match?.id as String?;
                  }
                  if (pid != null) {
                    ref.read(inventoryProvider.notifier).adjustStock(
                          pid,
                          item.variantId ?? '${pid}_v0',
                          -item.receivedQty.toInt(),
                          'Receipt deleted \u2013 reversal',
                          valuationMethod: ref.read(appSettingsProvider).valuationMethod,
                        );
                  }
                }
              }

              // Reverse linked purchase receivedQty
              if (r.purchaseId != null) {
                final purchases = ref.read(purchasesProvider);
                final pIdx =
                    purchases.indexWhere((p) => p.id == r.purchaseId);
                if (pIdx >= 0) {
                  final purchase = purchases[pIdx];
                  final updatedItems = purchase.items.map((pi) {
                    final matched = r.items.where((ri) =>
                        ri.productName.toLowerCase() ==
                        pi.name.toLowerCase());
                    if (matched.isNotEmpty) {
                      final removedQty =
                          matched.first.receivedQty.toInt();
                      return pi.copyWith(
                        receivedQty:
                            (pi.receivedQty - removedQty).clamp(0, pi.qty),
                      );
                    }
                    return pi;
                  }).toList();
                  ref.read(purchasesProvider.notifier).updatePurchase(
                        purchase.copyWith(items: updatedItems),
                      );
                }
              }

              // Delete the receipt
              ref
                  .read(goodsReceiptsProvider.notifier)
                  .removeReceipt(r.id);

              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: const Text('Receipt deleted'),
                backgroundColor: AppColors.danger,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ));
            },
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFDC2626))),
          ),
        ],
      ),
    );
  }

  (Color, Color) _receiptStatusColors(ReceiptStatus status) {
    switch (status) {
      case ReceiptStatus.confirmed:
        return (const Color(0xFFDCFCE7), const Color(0xFF166534));
      case ReceiptStatus.rejected:
        return (const Color(0xFFFEE2E2), const Color(0xFFDC2626));
      case ReceiptStatus.pending:
        return (const Color(0xFFF3E8FF), const Color(0xFF7C3AED));
    }
  }
}

// ── Helper types for unified activity timeline ──

enum _ActivityType { purchase, payment, goodsReceipt }

class _ActivityItem {
  final DateTime date;
  final _ActivityType type;
  final Purchase? purchase;
  final Payment? payment;
  final GoodsReceipt? receipt;

  const _ActivityItem({
    required this.date,
    required this.type,
    this.purchase,
    this.payment,
    this.receipt,
  });
}
