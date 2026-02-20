import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import 'profit_loss_screen.dart';
import 'balance_sheet_screen.dart';
import 'cash_flow_screen.dart';
import 'export_share_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        HapticFeedback.lightImpact();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: Text(
          'Reports',
          style: AppTypography.h2.copyWith(color: AppColors.primaryNavy),
        ),
        actions: [
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ExportShareScreen(),
                ),
              );
            },
            icon: const Icon(Icons.ios_share_rounded,
                color: AppColors.textTertiary),
          ),
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              showModalBottomSheet(
                context: context,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                builder: (_) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('About Reports', style: AppTypography.h3),
                      const SizedBox(height: 12),
                      const Text('View your Profit & Loss, Balance Sheet, and Cash Flow reports here. Use the tabs to switch between reports and the share icon to export. Data updates in real-time as you add transactions.'),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              );
            },
            icon: const Icon(Icons.info_outline_rounded,
                color: AppColors.textTertiary),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.backgroundLight,
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: false, // Make it fill width
              labelColor: Colors.white,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                fontFamily: 'Inter',
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                fontFamily: 'Inter',
              ),
              indicator: BoxDecoration(
                color: AppColors.primaryNavy,
                borderRadius: BorderRadius.circular(21),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryNavy.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              splashFactory: NoSplash.splashFactory,
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(child: Text('Profit & Loss', textAlign: TextAlign.center)),
                Tab(child: Text('Balance Sheet', textAlign: TextAlign.center)),
                Tab(child: Text('Cash Flow', textAlign: TextAlign.center)),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const BouncingScrollPhysics(),
        children: const [
          ProfitLossScreen(),
          BalanceSheetScreen(),
          CashFlowScreen(),
        ],
      ),
    );
  }
}
