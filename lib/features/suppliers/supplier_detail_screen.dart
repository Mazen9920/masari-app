import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/models/supplier_model.dart';
import 'purchase_detail_screen.dart';
import 'record_purchase_screen.dart';
import 'edit_supplier_screen.dart';
import 'payments_summary_screen.dart';
import 'payment_detail_screen.dart';

/// Supplier profile — avatar, balance, contact actions, stats, recent activity.
class SupplierDetailScreen extends ConsumerWidget {
  final Supplier supplier;
  const SupplierDetailScreen({super.key, required this.supplier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch for live updates
    final suppliers = ref.watch(suppliersProvider);
    final live = suppliers.firstWhere(
      (s) => s.id == supplier.id,
      orElse: () => supplier,
    );
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
                    _BalanceCard(balance: live.balance, fmt: fmt)
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
      // Sticky CTA
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
        child: GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RecordPurchaseScreen(
                  preselectedSupplierId: live.id,
                ),
              ),
            );
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
                Icon(Icons.add_rounded, color: Colors.white, size: 22),
                SizedBox(width: 8),
                Text(
                  'Record New Purchase',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
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
            onPressed: () => Navigator.of(context).pop(),
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
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EditSupplierScreen(supplier: live),
                ),
              );
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
          child: Center(
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
  const _BalanceCard({required this.balance, required this.fmt});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const PaymentsSummaryScreen(),
          ),
        );
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
                  'EGP ${fmt.format(balance)}',
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
            onTap: () => HapticFeedback.lightImpact(),
          ),
          const SizedBox(width: 12),
          _contactButton(
            icon: Icons.chat_rounded,
            label: 'WhatsApp',
            color: const Color(0xFF22C55E),
            onTap: () => HapticFeedback.lightImpact(),
          ),
          const SizedBox(width: 12),
          _contactButton(
            icon: Icons.email_rounded,
            label: 'Email',
            color: const Color(0xFF3498DB),
            onTap: () => HapticFeedback.lightImpact(),
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
//  STATS ROW — Total Spend, Last Purchase
// ═══════════════════════════════════════════════════════
class _StatsRow extends StatelessWidget {
  final Supplier supplier;
  final NumberFormat fmt;
  final DateFormat dateFmt;
  const _StatsRow(
      {required this.supplier, required this.fmt, required this.dateFmt});

  @override
  Widget build(BuildContext context) {
    // Mock total spend as balance * 5 for demo
    final totalSpend = supplier.balance * 5 + 15000;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _statCard('Total Spend', 'EGP ${fmt.format(totalSpend)}'),
          const SizedBox(width: 12),
          _statCard(
              'Last Purchase', dateFmt.format(supplier.lastTransaction)),
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
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  RECENT ACTIVITY LIST
// ═══════════════════════════════════════════════════════
class _RecentActivity extends StatelessWidget {
  final Supplier supplier;
  final NumberFormat fmt;
  final DateFormat dateFmt;
  const _RecentActivity(
      {required this.supplier, required this.fmt, required this.dateFmt});

  @override
  Widget build(BuildContext context) {
    // Sample activity data
    final activities = _sampleActivities(supplier);

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
              children: List.generate(activities.length, (i) {
                final a = activities[i];
                return Column(
                  children: [
                    if (i > 0)
                      Divider(
                          height: 1,
                          color:
                              AppColors.borderLight.withValues(alpha: 0.3)),
                    _activityRow(context, a),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _activityRow(BuildContext context, _Activity a) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        // Navigate to purchase detail if it's a purchase
        if (a.type != _ActivityType.payment) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PurchaseDetailScreen(supplier: supplier),
            ),
          );
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const PaymentDetailScreen(),
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: a.iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(a.icon, color: a.iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.title,
                    style: TextStyle(
                      color: AppColors.primaryNavy,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    a.date,
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
                  a.amount,
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
                    color: a.statusBg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    a.status,
                    style: TextStyle(
                      color: a.statusColor,
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

  List<_Activity> _sampleActivities(Supplier s) {
    return [
      _Activity(
        type: _ActivityType.payment,
        icon: Icons.arrow_upward_rounded,
        iconBg: const Color(0xFFDCFCE7),
        iconColor: const Color(0xFF16A34A),
        title: 'Payment Made',
        date: '10/26/2023',
        amount: '- EGP 5,000',
        status: 'Completed',
        statusBg: const Color(0xFFDCFCE7),
        statusColor: const Color(0xFF166534),
      ),
      _Activity(
        type: _ActivityType.purchase,
        icon: Icons.shopping_cart_rounded,
        iconBg: const Color(0xFFFEF3C7),
        iconColor: const Color(0xFFEA580C),
        title: 'Purchase #PR-902',
        date: '10/24/2023',
        amount: '+ EGP 2,050',
        status: 'Unpaid',
        statusBg: const Color(0xFFFEF3C7),
        statusColor: const Color(0xFF92400E),
      ),
      _Activity(
        type: _ActivityType.purchase,
        icon: Icons.receipt_long_rounded,
        iconBg: const Color(0xFFDBEAFE),
        iconColor: const Color(0xFF2563EB),
        title: 'Purchase #PR-885',
        date: '10/10/2023',
        amount: '+ EGP 4,150',
        status: 'Paid',
        statusBg: const Color(0xFFDCFCE7),
        statusColor: const Color(0xFF166534),
      ),
    ];
  }
}

enum _ActivityType { payment, purchase }

class _Activity {
  final _ActivityType type;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String date;
  final String amount;
  final String status;
  final Color statusBg;
  final Color statusColor;

  const _Activity({
    required this.type,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.date,
    required this.amount,
    required this.status,
    required this.statusBg,
    required this.statusColor,
  });
}

