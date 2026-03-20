import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/navigation/app_router.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/notifications_provider.dart';
import '../../core/providers/user_profile_provider.dart';
import '../../l10n/app_localizations.dart';
import 'providers/dashboard_state_provider.dart';
import 'providers/dashboard_config_provider.dart';
import 'widgets/ai_insight_card.dart';
import 'widgets/quick_stats_row.dart';
import 'widgets/analytics_chart.dart';
import 'widgets/profit_margins_card.dart';
import 'widgets/top_products_card.dart';
import 'widgets/inventory_valuation_card.dart';
import 'widgets/low_stock_alerts_card.dart';
import 'widgets/accounts_summary_card.dart';
import 'widgets/custom_date_range_picker.dart';
import 'widgets/recent_transactions.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  static String _greeting(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hour = DateTime.now().hour;
    if (hour < 12) return l10n.greetingMorning;
    if (hour < 17) return l10n.greetingAfternoon;
    return l10n.greetingEvening;
  }

  @override
  void initState() {
    super.initState();
    // Dashboard needs ALL data for accurate stats, not just page 1.
    Future.microtask(() {
      ref.read(transactionsProvider.notifier).loadAll();
      ref.read(salesProvider.notifier).loadAll();
      ref.read(inventoryProvider.notifier).loadAll();
      // purchasesProvider auto-loads on build (sync Notifier)
    });
  }

  Future<void> _refreshDashboard() async {
    // Recompute date range (e.g. if the day rolled over since last visit)
    final ds = ref.read(dashboardStateProvider);
    if (ds.period != DashboardPeriod.custom) {
      ref.read(dashboardStateProvider.notifier).setPeriod(ds.period);
    }

    await Future.wait([
      ref.read(transactionsProvider.notifier).refreshAll(),
      ref.read(salesProvider.notifier).refreshAll(),
      ref.read(inventoryProvider.notifier).refreshAll(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    // Trigger one-time sale↔transaction link migration for old data
    ref.watch(saleTxnMigrationProvider);
    // Trigger one-time product variant schema migration
    ref.watch(variantMigrationProvider);

    final profile = ref.watch(userProfileProvider);
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refreshDashboard,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            slivers: [
              // ─── Header: greeting + notification + avatar ───
              SliverToBoxAdapter(child: _buildHeader(profile.name)),

              // ─── AI Insight Card (dynamic) ───
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: AIInsightCard(),
                ),
              ),

              // ─── Period Selector (above stats) ───
              SliverToBoxAdapter(child: _buildPeriodSelector()),

              // ─── Quick Stats (horizontal scroll) ───
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: QuickStatsRow(),
                ),
              ),

              // ─── Analytics Chart (Shopify-style) ───
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: AnalyticsChart(),
                ),
              ),

              // ─── Dynamic sections (user-configurable) ───
              ..._buildConfigurableSections(),

              // ─── Bottom padding for nav bar ───
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String userName) {
    return Builder(
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Greeting
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting(context),
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  userName,
                  style: AppTypography.h1.copyWith(color: AppColors.textPrimary),
                ),
              ],
            ),
            // Notification + Avatar
            Row(
              children: [
                // Bell with red dot
                Semantics(
                  label: 'Notifications',
                  button: true,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      context.push(AppRoutes.notifications);
                    },
                    child: Builder(builder: (ctx) {
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
                ),
                const SizedBox(width: 10),
                // Avatar
                Semantics(
                  label: 'Profile',
                  button: true,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      context.push(AppRoutes.profile);
                    },
                    child: Builder(
                    builder: (ctx) {
                      final profile = ref.watch(userProfileProvider);
                      final avatarUrl = profile.avatarUrl;
                      final initials = profile.initials;
                      return Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primaryNavy.withValues(alpha: 0.12),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: (avatarUrl != null && avatarUrl.isNotEmpty)
                              ? CachedNetworkImage(
                                  imageUrl: avatarUrl,
                                  fit: BoxFit.cover,
                                  width: 42,
                                  height: 42,
                                  placeholder: (_, _) => Center(
                                    child: Text(initials, style: AppTypography.labelLarge.copyWith(color: AppColors.primaryNavy, fontSize: 17)),
                                  ),
                                  errorWidget: (_, _, _) => Center(
                                    child: Text(initials, style: AppTypography.labelLarge.copyWith(color: AppColors.primaryNavy, fontSize: 17)),
                                  ),
                                )
                              : Center(
                                  child: Text(
                                    initials,
                                    style: AppTypography.labelLarge.copyWith(
                                      color: AppColors.primaryNavy,
                                      fontSize: 17,
                                    ),
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    final ds = ref.watch(dashboardStateProvider);
    final period = ds.period;

    // Display label: period name or custom range
    final String displayLabel;
    if (period == DashboardPeriod.custom) {
      displayLabel = ds.range.formattedRange;
    } else {
      displayLabel = period.shortLabel;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: GestureDetector(
        onTap: () => _showDateRangeSheet(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.backgroundLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayLabel,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 18, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDateRangeSheet(BuildContext context) async {
    final ds = ref.read(dashboardStateProvider);
    final result = await showDateRangeSheet(
      context,
      currentPeriod: ds.period,
      currentRange: ds.range,
    );
    if (result == null) return;

    if (result.period != null) {
      ref.read(dashboardStateProvider.notifier).setPeriod(result.period!);
    } else if (result.customRange != null) {
      ref.read(dashboardStateProvider.notifier).setCustomRange(
            result.customRange!.start,
            result.customRange!.end,
          );
    }
  }

  List<Widget> _buildConfigurableSections() {
    final config = ref.watch(dashboardConfigProvider);
    final slivers = <Widget>[];

    for (final section in config.sections) {
      if (!section.visible) continue;
      final widget = _sectionWidget(section.id);
      if (widget != null) {
        slivers.add(SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: widget,
          ),
        ));
      }
    }

    // Edit button at the end
    slivers.add(SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Center(
          child: TextButton.icon(
            onPressed: () => _showEditDashboardSheet(context),
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: Text(AppLocalizations.of(context)!.customizeDashboard),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textTertiary,
              textStyle: AppTypography.labelMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    ));

    return slivers;
  }

  Widget? _sectionWidget(String id) {
    switch (id) {
      case 'profit_margins':
        return const ProfitMarginsCard();
      case 'top_products':
        return const TopProductsCard();
      case 'inventory_valuation':
        return const InventoryValuationCard();
      case 'low_stock':
        return const LowStockAlertsCard();
      case 'accounts':
        return const AccountsSummaryCard();
      case 'recent_transactions':
        return const RecentTransactions();
      default:
        return null;
    }
  }

  void _showEditDashboardSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _DashboardEditSheet(),
    );
  }
}

// ─── Dashboard Edit Bottom Sheet ───
class _DashboardEditSheet extends ConsumerStatefulWidget {
  const _DashboardEditSheet();

  @override
  ConsumerState<_DashboardEditSheet> createState() =>
      _DashboardEditSheetState();
}

class _DashboardEditSheetState extends ConsumerState<_DashboardEditSheet> {
  late List<DashboardSectionConfig> _sections;

  @override
  void initState() {
    super.initState();
    _sections =
        ref.read(dashboardConfigProvider).sections.map((s) => s.copy()).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: AppColors.borderLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppLocalizations.of(context)!.customizeDashboard,
                  style: AppTypography.h3.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    ref
                        .read(dashboardConfigProvider.notifier)
                        .updateSections(_sections);
                    Navigator.pop(context);
                  },
                  child: Text(
                    AppLocalizations.of(context)!.done,
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.accentOrange,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              AppLocalizations.of(context)!.toggleSectionsHint,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Reorderable list
          Flexible(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              padding: EdgeInsets.fromLTRB(
                20, 0, 20, 20 + MediaQuery.of(context).padding.bottom),
              itemCount: _sections.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = _sections.removeAt(oldIndex);
                  _sections.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final section = _sections[index];
                return Container(
                  key: ValueKey(section.id),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: section.visible
                        ? Colors.white
                        : AppColors.backgroundLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: ListTile(
                    leading: Icon(
                      section.icon,
                      color: section.visible
                          ? AppColors.primaryNavy
                          : AppColors.textTertiary,
                      size: 22,
                    ),
                    title: Text(
                      section.label,
                      style: AppTypography.bodyMedium.copyWith(
                        color: section.visible
                            ? AppColors.textPrimary
                            : AppColors.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch.adaptive(
                          value: section.visible,
                          activeTrackColor: AppColors.primaryNavy,
                          onChanged: (val) {
                            setState(() => section.visible = val);
                          },
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_handle_rounded,
                              color: AppColors.textTertiary, size: 20),
                        ),
                      ],
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
