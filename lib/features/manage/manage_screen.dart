import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/app_router.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/hub_settings_provider.dart';
import '../../core/providers/notifications_provider.dart';
import '../categories/add_category_sheet.dart';
import '../shopify/widgets/shopify_sync_status_widget.dart';

/// Management Hub — provides access to Inventory, Suppliers, and Categories.
class ManageScreen extends ConsumerStatefulWidget {
  const ManageScreen({super.key});

  @override
  ConsumerState<ManageScreen> createState() => _ManageScreenState();
}

class _ManageScreenState extends ConsumerState<ManageScreen> {
  @override
  Widget build(BuildContext context) {
    // Live stats
    final products = ref.watch(inventoryProvider).value ?? [];
    final categories = ref.watch(categoriesProvider).value ?? [];
    final suppliers = ref.watch(suppliersProvider).value ?? [];
    final lowStockCount =
        products.where((p) => p.status.name == 'lowStock').length;
    final dueCount = suppliers.where((s) => s.hasDue).length;

    // Hub settings
    final settings = ref.watch(hubSettingsProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Header ──
          SliverToBoxAdapter(
            child: _CleanHeader(),
          ),

          // ── Main Sections ──
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            sliver: SliverToBoxAdapter(
              child: _buildSectionsContent(
                settings: settings,
                productCount: products.length,
                lowStockCount: lowStockCount,
                categoryCount: categories.length,
                supplierCount: suppliers.length,
                dueCount: dueCount,
              ),
            ),
          ),

          // ── Shopify Sync Status (shown when connected) ──
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: const SliverToBoxAdapter(
              child: ShopifySyncStatusWidget(),
            ),
          ),

          // ── Quick Actions ──
          if (settings.showQuickActions)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'QUICK ACTIONS',
                      style: AppTypography.captionSmall.copyWith(
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        fontSize: 11,
                      ),
                    ).animate().fadeIn(duration: 200.ms, delay: 140.ms),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _QuickActionPill(
                          icon: Icons.add_box_rounded,
                          label: 'Product',
                          color: AppColors.primaryNavy,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            context.pushNamed("AddProductScreen");
                          },
                        ),
                        const SizedBox(width: 10),
                        _QuickActionPill(
                          icon: Icons.person_add_rounded,
                          label: 'Supplier',
                          color: const Color(0xFF059669),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            context.pushNamed('AddSupplierScreen');
                          },
                        ),
                        const SizedBox(width: 10),
                        _QuickActionPill(
                          icon: Icons.new_label_rounded,
                          label: 'Category',
                          color: const Color(0xFF7C3AED),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            showAddCategorySheet(context);
                          },
                        ),
                        const SizedBox(width: 10),
                        _QuickActionPill(
                          icon: Icons.tune_rounded,
                          label: 'Settings',
                          color: AppColors.textSecondary,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            context.pushNamed('HubSettingsScreen');
                          },
                        ),
                      ],
                    )
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 160.ms),
                  ],
                ),
              ),
            ),

          // ── Insights Banner ──
          if (settings.showInsightsBanner)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              sliver: SliverToBoxAdapter(
                child: _InsightsBanner()
                    .animate()
                    .fadeIn(duration: 300.ms, delay: 200.ms),
              ),
            ),

          // ── Bottom padding ──
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  SECTIONS CONTENT — handles list/grid layout and section filtering
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildSectionsContent({
    required HubSettingsState settings,
    required int productCount,
    required int lowStockCount,
    required int categoryCount,
    required int supplierCount,
    required int dueCount,
  }) {
    // Build shared chips
    final inventoryChip = (settings.showStatBadges &&
            settings.lowStockAlerts &&
            lowStockCount > 0)
        ? _StatChip(label: '$lowStockCount low', color: AppColors.danger)
        : _StatChip(label: '$productCount items', color: AppColors.primaryNavy);

    final suppliersChip = (settings.showStatBadges &&
            settings.paymentDueReminders &&
            dueCount > 0)
        ? _StatChip(label: '$dueCount dues', color: AppColors.warning)
        : _StatChip(
            label: '$supplierCount vendors', color: const Color(0xFF059669));

    final categoriesChip = settings.showStatBadges
        ? _StatChip(
            label: '$categoryCount active', color: const Color(0xFF7C3AED))
        : null;

    const sectionLabel = Text(
      'YOUR WORKSPACE',
      style: TextStyle(
        color: AppColors.textTertiary,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        fontSize: 11,
      ),
    );

    // ── Grid layout ──
    if (settings.layoutIndex == 0) {
      final gridItems = <_GridSectionData>[
        _GridSectionData(
            icon: Icons.inventory_2_rounded,
            gradient: const [Color(0xFF1B4F72), Color(0xFF2E86C1)],
            title: 'Inventory',
            badge: inventoryChip,
            onTap: () {
              HapticFeedback.lightImpact();
              context.push(AppRoutes.inventory);
            },
          ),
        _GridSectionData(
            icon: Icons.local_shipping_rounded,
            gradient: const [Color(0xFF059669), Color(0xFF34D399)],
            title: 'Suppliers',
            badge: suppliersChip,
            onTap: () {
              HapticFeedback.lightImpact();
              context.push(AppRoutes.suppliers);
            },
          ),
        _GridSectionData(
            icon: Icons.category_rounded,
            gradient: const [Color(0xFF7C3AED), Color(0xFFA78BFA)],
            title: 'Categories',
            badge: categoriesChip,
            onTap: () {
              HapticFeedback.lightImpact();
              context.push(AppRoutes.categories);
            },
          ),
      ];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionLabel.animate().fadeIn(duration: 200.ms),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.1,
            ),
            itemCount: gridItems.length,
            itemBuilder: (context, i) {
              final item = gridItems[i];
              return _SectionGridCard(
                icon: item.icon,
                iconGradient: item.gradient,
                title: item.title,
                badge: item.badge,
                onTap: item.onTap,
              ).animate().fadeIn(duration: 250.ms, delay: (i * 30).ms);
            },
          ),
        ],
      );
    }

    // ── List layout (default) ──
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionLabel.animate().fadeIn(duration: 200.ms),
        const SizedBox(height: 14),
        _SectionTile(
            icon: Icons.inventory_2_rounded,
            iconGradient: const [Color(0xFF1B4F72), Color(0xFF2E86C1)],
            title: 'Inventory',
            subtitle: 'Products, stock & reorders',
            trailing: inventoryChip,
            onTap: () {
              HapticFeedback.lightImpact();
              context.push(AppRoutes.inventory);
            },
          ).animate().fadeIn(duration: 250.ms).slideX(begin: -0.03),
        const SizedBox(height: 10),
        _SectionTile(
            icon: Icons.local_shipping_rounded,
            iconGradient: const [Color(0xFF059669), Color(0xFF34D399)],
            title: 'Suppliers',
            subtitle: 'Vendors, purchases & payables',
            trailing: suppliersChip,
            onTap: () {
              HapticFeedback.lightImpact();
              context.push(AppRoutes.suppliers);
            },
          )
              .animate()
              .fadeIn(duration: 250.ms, delay: 50.ms)
              .slideX(begin: -0.03),
        const SizedBox(height: 10),
        _SectionTile(
            icon: Icons.category_rounded,
            iconGradient: const [Color(0xFF7C3AED), Color(0xFFA78BFA)],
            title: 'Categories',
            subtitle: 'Organize expenses & income',
            trailing: categoriesChip,
            onTap: () {
              HapticFeedback.lightImpact();
              context.push(AppRoutes.categories);
            },
          )
              .animate()
              .fadeIn(duration: 250.ms, delay: 100.ms)
              .slideX(begin: -0.03),
        const SizedBox(height: 10),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  HEADER — clean style matching the dashboard
// ═══════════════════════════════════════════════════════════
class _CleanHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: Column(
        children: [
          // Title row
          Row(
            children: [
              Text(
                'Management Hub',
                style: AppTypography.h1.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              // Notification bell — same style as dashboard
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  context.push(AppRoutes.notifications);
                },
                child: Consumer(builder: (ctx, ref, _) {
                  final notifCount = ref.watch(notificationCountProvider);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(color: AppColors.borderLight),
                        ),
                        child: const Icon(
                          Icons.notifications_outlined,
                          color: AppColors.textSecondary,
                          size: 22,
                        ),
                      ),
                      if (notifCount > 0)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: AppColors.accentOrange,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                            child: Text(
                              notifCount > 9 ? '9+' : '$notifCount',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                }),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Search bar
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              context.push(AppRoutes.inventory);
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.borderLight.withValues(alpha: 0.6)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded,
                      size: 20, color: AppColors.textTertiary),
                  const SizedBox(width: 10),
                  Text(
                    'Search inventory, suppliers…',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  SECTION TILE — modern card for each hub section
// ═══════════════════════════════════════════════════════════
class _SectionTile extends StatelessWidget {
  final IconData icon;
  final List<Color> iconGradient;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _SectionTile({
    required this.icon,
    required this.iconGradient,
    required this.title,
    required this.subtitle,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: AppColors.borderLight.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Gradient icon circle
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: iconGradient,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: iconGradient.first.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, size: 22, color: Colors.white),
              ),
              const SizedBox(width: 14),
              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.labelLarge.copyWith(
                        color: AppColors.primaryNavy,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              // Stat chip + chevron
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  STAT CHIP — compact badge next to section tiles
// ═══════════════════════════════════════════════════════════
class _StatChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  QUICK ACTION PILL — compact action button
// ═══════════════════════════════════════════════════════════
class _QuickActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.borderLight.withValues(alpha: 0.4)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.1),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryNavy,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  INSIGHTS BANNER
// ═══════════════════════════════════════════════════════════
class _InsightsBanner extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Compute a real insight from live data
    final products = ref.watch(inventoryProvider).value ?? [];
    final suppliers = ref.watch(suppliersProvider).value ?? [];
    final lowStockCount = products.where((p) => p.status.name == 'lowStock').length;
    final outOfStockCount = products.where((p) => p.status.name == 'outOfStock').length;
    final dueCount = suppliers.where((s) => s.hasDue).length;
    final totalProducts = products.length;

    String title;
    String subtitle;
    IconData icon;

    if (outOfStockCount > 0) {
      title = '$outOfStockCount Product${outOfStockCount > 1 ? 's' : ''} Out of Stock';
      subtitle = 'Reorder soon to avoid missed sales.';
      icon = Icons.error_outline_rounded;
    } else if (lowStockCount > 0) {
      title = '$lowStockCount Product${lowStockCount > 1 ? 's' : ''} Running Low';
      subtitle = 'Review stock levels and reorder before they run out.';
      icon = Icons.warning_amber_rounded;
    } else if (dueCount > 0) {
      title = '$dueCount Supplier Payment${dueCount > 1 ? 's' : ''} Due';
      subtitle = 'Check outstanding balances to stay on top of payables.';
      icon = Icons.payment_rounded;
    } else if (totalProducts > 0) {
      final avgValue = products.fold<double>(0, (s, p) => s + p.totalCostValue) / totalProducts;
      title = 'Inventory Healthy';
      subtitle = '$totalProducts products tracked, avg value ${avgValue.toStringAsFixed(0)} per item.';
      icon = Icons.check_circle_outline_rounded;
    } else {
      title = 'Get Started';
      subtitle = 'Add your first product to start tracking inventory.';
      icon = Icons.add_business_rounded;
    }

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
            color: AppColors.primaryNavy.withValues(alpha: 0.25),
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
                child: Icon(icon, size: 18, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: AppTypography.labelLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
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

// ═══════════════════════════════════════════════════════════
//  GRID SECTION DATA — simple data holder for grid cards
// ═══════════════════════════════════════════════════════════
class _GridSectionData {
  final IconData icon;
  final List<Color> gradient;
  final String title;
  final Widget? badge;
  final VoidCallback onTap;

  const _GridSectionData({
    required this.icon,
    required this.gradient,
    required this.title,
    required this.badge,
    required this.onTap,
  });
}

// ═══════════════════════════════════════════════════════════
//  SECTION GRID CARD — compact card for 2×2 grid layout
// ═══════════════════════════════════════════════════════════
class _SectionGridCard extends StatelessWidget {
  final IconData icon;
  final List<Color> iconGradient;
  final String title;
  final Widget? badge;
  final VoidCallback onTap;

  const _SectionGridCard({
    required this.icon,
    required this.iconGradient,
    required this.title,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: AppColors.borderLight.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: iconGradient,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: iconGradient.first.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, size: 20, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(height: 6),
                badge!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
