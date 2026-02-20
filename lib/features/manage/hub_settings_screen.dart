import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import 'pinned_actions_screen.dart';

/// Hub Settings — layout, dashboard customization, notifications for the Manage hub.
class HubSettingsScreen extends StatefulWidget {
  const HubSettingsScreen({super.key});

  @override
  State<HubSettingsScreen> createState() => _HubSettingsScreenState();
}

class _HubSettingsScreenState extends State<HubSettingsScreen> {
  // Layout
  int _layoutIndex = 1; // 0 = Grid, 1 = List
  bool _showQuickActions = true;
  bool _showInsightsBanner = true;

  // Default tab
  int _defaultTabIndex = 0; // 0=Hub Overview, 1=Inventory, 2=Suppliers
  final _tabOptions = const ['Hub Overview', 'Inventory', 'Suppliers'];

  // Notifications
  bool _lowStockAlerts = true;
  bool _paymentDueReminders = true;
  bool _showStatBadges = true;

  // Pinned actions (preview list)
  final _pinnedActions = const [
    {'icon': Icons.add_box_rounded, 'label': 'Add Product'},
    {'icon': Icons.local_shipping_rounded, 'label': 'New Supplier'},
    {'icon': Icons.receipt_long_rounded, 'label': 'Add Transaction'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Header ──
            _buildHeader(),
            // ── Content ──
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ═══  LAYOUT PREFERENCES  ═══
                    _sectionTitle('Layout Preferences')
                        .animate().fadeIn(duration: 250.ms),
                    const SizedBox(height: 10),
                    _buildLayoutSection()
                        .animate().fadeIn(duration: 250.ms, delay: 30.ms),

                    const SizedBox(height: 24),

                    // ═══  DASHBOARD CUSTOMIZATION  ═══
                    _sectionTitle('Dashboard Customization')
                        .animate().fadeIn(duration: 250.ms, delay: 60.ms),
                    const SizedBox(height: 10),
                    _buildDashboardSection()
                        .animate().fadeIn(duration: 250.ms, delay: 80.ms),

                    const SizedBox(height: 24),

                    // ═══  NOTIFICATIONS & BADGES  ═══
                    _sectionTitle('Notifications & Badges')
                        .animate().fadeIn(duration: 250.ms, delay: 100.ms),
                    const SizedBox(height: 10),
                    _buildNotificationsSection()
                        .animate().fadeIn(duration: 250.ms, delay: 120.ms),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  HEADER
  // ═══════════════════════════════════════════════════════
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 10),
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
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.primaryNavy,
          ),
          Expanded(
            child: Text(
              'Hub Settings',
              style: AppTypography.h2.copyWith(
                color: AppColors.primaryNavy,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  SECTION TITLE
  // ═══════════════════════════════════════════════════════
  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        text.toUpperCase(),
        style: AppTypography.captionSmall.copyWith(
          color: AppColors.textTertiary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          fontSize: 11,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  LAYOUT PREFERENCES
  // ═══════════════════════════════════════════════════════
  Widget _buildLayoutSection() {
    return _card(
      children: [
        // Layout picker
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hub Layout',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _layoutOption(0, 'Grid (2×2)')),
                  const SizedBox(width: 10),
                  Expanded(child: _layoutOption(1, 'List')),
                ],
              ),
            ],
          ),
        ),
        _divider(),
        _toggleRow(
          title: 'Show Quick Actions',
          subtitle: 'Shortcuts below main cards',
          value: _showQuickActions,
          onChanged: (v) => setState(() => _showQuickActions = v),
        ),
        _divider(),
        _toggleRow(
          title: 'Show Insights Banner',
          subtitle: 'Weekly summaries & tips',
          value: _showInsightsBanner,
          onChanged: (v) => setState(() => _showInsightsBanner = v),
        ),
      ],
    );
  }

  Widget _layoutOption(int index, String label) {
    final selected = _layoutIndex == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _layoutIndex = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFFF7ED)
              : const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? const Color(0xFFE67E22)
                : AppColors.borderLight,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            // Mini grid / list icon
            SizedBox(
              width: 28,
              height: 28,
              child: index == 0
                  ? _gridIcon(selected)
                  : _listIcon(selected),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? const Color(0xFFE67E22)
                    : AppColors.textTertiary,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (selected)
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFE67E22),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _gridIcon(bool active) {
    final color = active
        ? const Color(0xFFE67E22).withValues(alpha: 0.5)
        : AppColors.textTertiary.withValues(alpha: 0.4);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 3),
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 3),
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          ],
        ),
      ],
    );
  }

  Widget _listIcon(bool active) {
    final color = active
        ? const Color(0xFFE67E22)
        : AppColors.textTertiary.withValues(alpha: 0.4);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        3,
        (_) => Container(
          width: 24,
          height: 5,
          margin: const EdgeInsets.symmetric(vertical: 1.5),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  DASHBOARD CUSTOMIZATION
  // ═══════════════════════════════════════════════════════
  Widget _buildDashboardSection() {
    return _card(
      children: [
        // Default tab dropdown
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Default Manage Tab',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: DropdownButton<int>(
                  value: _defaultTabIndex,
                  isExpanded: true,
                  underline: const SizedBox(),
                  icon: const Icon(Icons.expand_more_rounded,
                      color: AppColors.textTertiary),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                  items: List.generate(
                    _tabOptions.length,
                    (i) => DropdownMenuItem(
                      value: i,
                      child: Text(_tabOptions[i]),
                    ),
                  ),
                  onChanged: (v) {
                    if (v != null) setState(() => _defaultTabIndex = v);
                  },
                ),
              ),
            ],
          ),
        ),
        _divider(),
        // Pinned Actions
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Pinned Actions',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.primaryNavy,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PinnedActionsScreen(),
                        ),
                      );
                    },
                    child: Text(
                      'Edit',
                      style: TextStyle(
                        color: const Color(0xFFE67E22),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Preview of pinned actions
              ...List.generate(_pinnedActions.length, (i) {
                final action = _pinnedActions[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.borderLight.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Icon(
                            action['icon'] as IconData,
                            size: 16,
                            color: AppColors.primaryNavy,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            action['label'] as String,
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const Icon(Icons.drag_handle_rounded,
                            size: 20, color: AppColors.borderLight),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  //  NOTIFICATIONS & BADGES
  // ═══════════════════════════════════════════════════════
  Widget _buildNotificationsSection() {
    return _card(
      children: [
        _toggleRow(
          title: 'Low Stock Alerts',
          subtitle: 'Notify when items hit minimum',
          value: _lowStockAlerts,
          onChanged: (v) => setState(() => _lowStockAlerts = v),
        ),
        _divider(),
        _toggleRow(
          title: 'Payment Due Reminders',
          subtitle: 'Alerts for upcoming vendor payments',
          value: _paymentDueReminders,
          onChanged: (v) => setState(() => _paymentDueReminders = v),
        ),
        _divider(),
        _toggleRow(
          title: 'Show Stat Badges on Cards',
          subtitle: 'Display mini-stats on hub cards',
          value: _showStatBadges,
          onChanged: (v) => setState(() => _showStatBadges = v),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  //  SHARED BUILDERS
  // ═══════════════════════════════════════════════════════
  Widget _card({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _divider() {
    return Divider(
      height: 1,
      thickness: 1,
      color: AppColors.borderLight.withValues(alpha: 0.5),
    );
  }

  Widget _toggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.primaryNavy,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            onChanged: (v) {
              HapticFeedback.lightImpact();
              onChanged(v);
            },
            activeColor: const Color(0xFFE67E22),
            activeTrackColor: const Color(0xFFE67E22).withValues(alpha: 0.3),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFFCBD5E1),
          ),
        ],
      ),
    );
  }
}
