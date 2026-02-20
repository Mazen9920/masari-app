import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../inventory/inventory_list_screen.dart';
import '../inventory/add_product_screen.dart';
import '../categories/categories_list_screen.dart';
import '../categories/add_category_sheet.dart';
import '../suppliers/suppliers_overview_screen.dart';
import 'hub_settings_screen.dart';

/// Management Hub — provides access to Inventory, Suppliers, and Categories.
class ManageScreen extends ConsumerWidget {
  const ManageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Live stats
    final products = ref.watch(inventoryProvider);
    final categories = ref.watch(categoriesProvider);
    final suppliers = ref.watch(suppliersProvider);
    final lowStockCount =
        products.where((p) => p.status.name == 'lowStock').length;

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Management Cards ──
                    _ManagementCard(
                      icon: Icons.inventory_2_rounded,
                      iconBgColor: const Color(0xFFEFF6FF),
                      iconColor: AppColors.primaryNavy,
                      title: 'Inventory',
                      subtitle: 'Track stock, products & reorders',
                      badge: lowStockCount > 0
                          ? _Badge(
                              icon: Icons.warning_rounded,
                              label: '$lowStockCount low stock items',
                              bgColor: const Color(0xFFFEF2F2),
                              textColor: const Color(0xFFDC2626),
                            )
                          : null,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const InventoryListScreen()),
                        );
                      },
                    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05),

                    const SizedBox(height: 12),

                    _ManagementCard(
                      icon: Icons.local_shipping_rounded,
                      iconBgColor: const Color(0xFFECFDF5),
                      iconColor: const Color(0xFF059669),
                      title: 'Suppliers',
                      subtitle: 'Manage vendors & payables',
                      badge: _Badge(
                        icon: Icons.payments_rounded,
                        label: '${suppliers.where((s) => s.hasDue).length} with dues',
                        bgColor: const Color(0xFFFFFBEB),
                        textColor: const Color(0xFFB45309),
                      ),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SuppliersOverviewScreen(),
                          ),
                        );
                      },
                    )
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 50.ms)
                        .slideY(begin: 0.05),

                    const SizedBox(height: 12),

                    _ManagementCard(
                      icon: Icons.category_rounded,
                      iconBgColor: const Color(0xFFF5F3FF),
                      iconColor: const Color(0xFF7C3AED),
                      title: 'Categories',
                      subtitle: 'Organize expenses & income',
                      badge: _Badge(
                        icon: Icons.sell_rounded,
                        label: '${categories.length} active categories',
                        bgColor: const Color(0xFFF1F5F9),
                        textColor: const Color(0xFF475569),
                      ),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const CategoriesListScreen()),
                        );
                      },
                    )
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 100.ms)
                        .slideY(begin: 0.05),

                    const SizedBox(height: 28),

                    // ── Quick Actions ──
                    Text(
                      'QUICK ACTIONS',
                      style: AppTypography.captionSmall.copyWith(
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        fontSize: 11,
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 140.ms),

                    const SizedBox(height: 12),

                    GridView.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 2.8,
                      children: [
                        _QuickAction(
                          icon: Icons.add_rounded,
                          iconBg: AppColors.primaryNavy.withValues(alpha: 0.08),
                          iconColor: AppColors.primaryNavy,
                          label: 'Add Product',
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const AddProductScreen()),
                            );
                          },
                        ),
                        _QuickAction(
                          icon: Icons.add_rounded,
                          iconBg:
                              const Color(0xFF059669).withValues(alpha: 0.08),
                          iconColor: const Color(0xFF059669),
                          label: 'New Supplier',
                          onTap: () {
                            HapticFeedback.lightImpact();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    const Text('Suppliers — coming soon'),
                                backgroundColor: AppColors.primaryNavy,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            );
                          },
                        ),
                        _QuickAction(
                          icon: Icons.add_rounded,
                          iconBg:
                              const Color(0xFF7C3AED).withValues(alpha: 0.08),
                          iconColor: const Color(0xFF7C3AED),
                          label: 'New Category',
                          onTap: () {
                            HapticFeedback.lightImpact();
                            showAddCategorySheet(context);
                          },
                        ),
                        _QuickAction(
                          icon: Icons.settings_rounded,
                          iconBg: const Color(0xFFF1F5F9),
                          iconColor: AppColors.textTertiary,
                          label: 'Hub Settings',
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const HubSettingsScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    )
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 160.ms),

                    const SizedBox(height: 24),

                    // ── Insights banner ──
                    _InsightsBanner()
                        .animate()
                        .fadeIn(duration: 300.ms, delay: 200.ms),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  HEADER
// ═══════════════════════════════════════════════════════════
class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Title + bell
          Row(
            children: [
              Text(
                'Management Hub',
                style: AppTypography.h2.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w800,
                  fontSize: 24,
                  letterSpacing: -0.3,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => HapticFeedback.lightImpact(),
                icon: const Icon(Icons.notifications_none_rounded, size: 24),
                color: AppColors.textTertiary,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Search
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.borderLight.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded,
                    size: 20, color: AppColors.textTertiary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Search inventory, suppliers…',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  MANAGEMENT CARD
// ═══════════════════════════════════════════════════════════
class _ManagementCard extends StatelessWidget {
  final IconData icon;
  final Color iconBgColor;
  final Color iconColor;
  final String title;
  final String subtitle;
  final _Badge? badge;
  final VoidCallback onTap;

  const _ManagementCard({
    required this.icon,
    required this.iconBgColor,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppColors.borderLight.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon circle
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: iconBgColor,
                ),
                child: Icon(icon, size: 26, color: iconColor),
              ),
              const SizedBox(width: 14),
              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: AppTypography.labelLarge.copyWith(
                              color: AppColors.primaryNavy,
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            size: 20, color: AppColors.textTertiary),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (badge != null) ...[
                      const SizedBox(height: 10),
                      badge!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  BADGE
// ═══════════════════════════════════════════════════════════
class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bgColor;
  final Color textColor;

  const _Badge({
    required this.icon,
    required this.label,
    required this.bgColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: textColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  QUICK ACTION
// ═══════════════════════════════════════════════════════════
class _QuickAction extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: AppColors.borderLight.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: iconBg,
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.primaryNavy,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  INSIGHTS BANNER
// ═══════════════════════════════════════════════════════════
class _InsightsBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [AppColors.primaryNavy, Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryNavy.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            right: -16,
            bottom: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            right: -8,
            top: -24,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          // Content
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
                child:
                    const Icon(Icons.insights_rounded, size: 18, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                'Weekly Insights Ready',
                style: AppTypography.labelLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Review your inventory turnover rate for this week.',
                style: AppTypography.bodySmall.copyWith(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
