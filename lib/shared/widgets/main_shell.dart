import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/transactions/transactions_list_screen.dart';
import '../../features/manage/manage_screen.dart';
import '../../l10n/app_localizations.dart';

/// Main app shell with bottom navigation bar + center FAB.
/// Tabs: Home | Reports | (+) FAB | Cards | Profile
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  bool _isOffline = false;
  late final StreamSubscription<List<ConnectivityResult>> _connectivitySub;

  @override
  void initState() {
    super.initState();
    // Check initial state
    Connectivity().checkConnectivity().then((results) {
      if (mounted) {
        setState(() => _isOffline = results.every((r) => r == ConnectivityResult.none));
      }
    });
    // Listen for changes
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (mounted) {
        setState(() => _isOffline = results.every((r) => r == ConnectivityResult.none));
      }
    });
  }

  @override
  void dispose() {
    _connectivitySub.cancel();
    super.dispose();
  }

  final List<Widget> _screens = [
    const DashboardScreen(),
    const TransactionsListScreen(),
    const SizedBox(), // FAB placeholder (index 2)
    const ReportsScreen(),
    const ManageScreen(),
  ];

  void _onTabTap(int index) {
    if (index == 2) {
      _openAddTransaction();
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _currentIndex = index);
  }

  void _openAddTransaction() {
    HapticFeedback.mediumImpact();
    context.push(AppRoutes.addTransaction);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: Column(
        children: [
          if (_isOffline)
            MaterialBanner(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: const Icon(Icons.cloud_off_rounded, color: Colors.white, size: 20),
              content: Text(
                l10n.offlineBanner,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              backgroundColor: Colors.grey.shade700,
              actions: const [SizedBox.shrink()],
            ),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
          ),
        ],
      ),
      extendBody: true,
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.borderLight.withValues(alpha: 0.6)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _navItem(0, Icons.dashboard_rounded, l10n.home),
              _navItem(1, Icons.receipt_long_rounded, l10n.transactions),
              _buildFAB(),
              _navItem(3, Icons.bar_chart_rounded, l10n.reports),
              _navItem(4, Icons.grid_view_rounded, l10n.manage),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final isActive = _currentIndex == index;
    return Semantics(
      label: AppLocalizations.of(context)!.tabLabel(label),
      button: true,
      selected: isActive,
      child: GestureDetector(
        onTap: () => _onTabTap(index),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 56,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 24,
                color: isActive ? AppColors.accentOrange : AppColors.textTertiary,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive
                      ? AppColors.accentOrange
                      : AppColors.textTertiary,
                ),
                maxLines: 1,
                overflow: TextOverflow.visible,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFAB() {
    return Semantics(
      label: AppLocalizations.of(context)!.addTransaction,
      button: true,
      child: GestureDetector(
        onTap: _openAddTransaction,
        child: Container(
          width: 52,
          height: 52,
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: AppColors.accentOrange,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.accentOrange.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}


