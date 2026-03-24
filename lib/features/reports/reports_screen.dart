import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../l10n/app_localizations.dart';
import 'profit_loss_screen.dart';
import 'balance_sheet_screen.dart';
import 'cash_flow_screen.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  bool _lastIsGrowth = false;

  void _initTabs(bool isGrowth) {
    _tabController?.dispose();
    _lastIsGrowth = isGrowth;
    _tabController = TabController(
      length: isGrowth ? 3 : 2,
      vsync: this,
    );
    _tabController!.addListener(() {
      if (_tabController!.indexIsChanging) {
        HapticFeedback.lightImpact();
      }
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isGrowth = ref.watch(isGrowthProvider);

    // Rebuild tab controller if tier changed
    if (_tabController == null || _lastIsGrowth != isGrowth) {
      _initTabs(isGrowth);
    }

    final l10n = AppLocalizations.of(context)!;
    final tabs = isGrowth
        ? [
            Tab(child: Text(l10n.profitAndLoss, textAlign: TextAlign.center)),
            Tab(child: Text(l10n.balanceSheet, textAlign: TextAlign.center)),
            Tab(child: Text(l10n.cashFlowTab, textAlign: TextAlign.center)),
          ]
        : [
            Tab(child: Text(l10n.performanceTab, textAlign: TextAlign.center)),
            Tab(child: Text(l10n.cashFlowTab, textAlign: TextAlign.center)),
          ];

    final tabViews = isGrowth
        ? const [
            ProfitLossScreen(),
            BalanceSheetScreen(),
            CashFlowScreen(),
          ]
        : const [
            ProfitLossScreen(),
            CashFlowScreen(),
          ];
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        title: Text(
          l10n.reportsTitle,
          style: AppTypography.h2.copyWith(color: AppColors.primaryNavy),
        ),
        actions: [
          Tooltip(
            message: isGrowth ? l10n.exportAndShare : l10n.upgradeToExport,
            child: IconButton(
              onPressed: isGrowth
                  ? () {
                      HapticFeedback.lightImpact();
                      context.pushNamed('ExportShareScreen');
                    }
                  : null,
              icon: Icon(Icons.ios_share_rounded,
                  color: isGrowth ? AppColors.textSecondary : AppColors.textTertiary.withValues(alpha: 0.4),
                  size: 22),
            ),
          ),
          IconButton(
            onPressed: () => _showAboutModal(context, isGrowth),
            icon: const Icon(Icons.info_outline_rounded,
                color: AppColors.textSecondary, size: 22),
            tooltip: l10n.aboutReports,
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: false,
              labelColor: Colors.white,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                fontFamily: 'Inter',
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 12,
                fontFamily: 'Inter',
              ),
              indicator: BoxDecoration(
                color: AppColors.primaryNavy,
                borderRadius: BorderRadius.circular(11),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryNavy.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              splashFactory: NoSplash.splashFactory,
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              dividerColor: Colors.transparent,
              tabs: tabs,
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const BouncingScrollPhysics(),
        children: tabViews,
      ),
    );
  }

  void _showAboutModal(BuildContext context, bool isGrowth) {
    final l10n = AppLocalizations.of(context)!;
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.aboutReports, style: AppTypography.h3),
                IconButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textTertiary),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFF1F5F9),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(32, 32),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isGrowth) ...[
              _aboutBullet(Icons.bar_chart_rounded, l10n.aboutPnl),
              _aboutBullet(Icons.account_balance_rounded, l10n.aboutBalanceSheet),
              _aboutBullet(Icons.waterfall_chart_rounded, l10n.aboutCashFlow),
              _aboutBullet(Icons.sync_rounded, l10n.aboutRealTime),
              _aboutBullet(Icons.ios_share_rounded, l10n.aboutExport),
            ] else ...[
              _aboutBullet(Icons.trending_up_rounded, l10n.aboutPerformance),
              _aboutBullet(Icons.sync_rounded, l10n.aboutAutoUpdate),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.chartOrangeLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.chartOrange.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.stars_rounded, color: AppColors.accentOrange, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n.upgradeForBalanceSheet,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.accentOrangeDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _aboutBullet(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primaryNavy),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary, height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
