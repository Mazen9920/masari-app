import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<_NotificationItem> _notifications = [
    _NotificationItem(
      icon: Icons.trending_down_rounded,
      iconColor: const Color(0xFFEF4444),
      iconBg: const Color(0xFFFEF2F2),
      title: 'Revenue decreased by 8%',
      subtitle: 'Your February revenue is trending lower than January. Tap to view details.',
      time: '2 min ago',
      isUnread: true,
      type: 'alert',
    ),
    _NotificationItem(
      icon: Icons.inventory_2_outlined,
      iconColor: const Color(0xFFF59E0B),
      iconBg: const Color(0xFFFFFBEB),
      title: '3 items low in stock',
      subtitle: 'Cotton T-Shirt, Denim Jacket, and Leather Belt need restocking.',
      time: '15 min ago',
      isUnread: true,
      type: 'alert',
    ),
    _NotificationItem(
      icon: Icons.payments_outlined,
      iconColor: const Color(0xFF3B82F6),
      iconBg: const Color(0xFFEFF6FF),
      title: 'Payment due tomorrow',
      subtitle: 'EGP 5,200 due to Cairo Textiles supplier.',
      time: '1 hour ago',
      isUnread: true,
      type: 'alert',
    ),
    _NotificationItem(
      icon: Icons.auto_awesome_rounded,
      iconColor: const Color(0xFF8B5CF6),
      iconBg: const Color(0xFFF5F3FF),
      title: 'AI Insight available',
      subtitle: 'Your cash flow pattern suggests optimizing payment timing. View analysis.',
      time: '3 hours ago',
      isUnread: false,
      type: 'update',
    ),
    _NotificationItem(
      icon: Icons.receipt_long_rounded,
      iconColor: const Color(0xFF22C55E),
      iconBg: const Color(0xFFF0FDF4),
      title: 'Monthly report ready',
      subtitle: 'Your January 2026 financial report has been generated.',
      time: 'Yesterday',
      isUnread: false,
      type: 'update',
    ),
    _NotificationItem(
      icon: Icons.system_update_outlined,
      iconColor: const Color(0xFF0EA5E9),
      iconBg: const Color(0xFFF0F9FF),
      title: 'App updated to v1.0.1',
      subtitle: 'New features: Export to Excel, improved AI forecasting.',
      time: '2 days ago',
      isUnread: false,
      type: 'update',
    ),
    _NotificationItem(
      icon: Icons.celebration_outlined,
      iconColor: AppColors.accentOrange,
      iconBg: const Color(0xFFFFF7ED),
      title: 'Welcome to Masari!',
      subtitle: 'Start tracking your finances with our smart tools.',
      time: '1 week ago',
      isUnread: false,
      type: 'update',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<_NotificationItem> _filtered(String type) {
    if (type == 'all') return _notifications;
    return _notifications.where((n) => n.type == type).toList();
  }

  void _markAllRead() {
    HapticFeedback.lightImpact();
    setState(() {
      for (var n in _notifications) {
        n.isUnread = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primaryNavy),
        ),
        title: Text('Notifications', style: AppTypography.h3.copyWith(color: AppColors.primaryNavy)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _markAllRead,
            child: Text('Mark all read', style: TextStyle(color: AppColors.accentOrange, fontWeight: FontWeight.w600, fontSize: 12)),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.backgroundLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: AppColors.primaryNavy,
              unselectedLabelColor: AppColors.textTertiary,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              tabs: [
                Tab(text: 'All (${_notifications.length})'),
                Tab(text: 'Alerts (${_filtered('alert').length})'),
                Tab(text: 'Updates (${_filtered('update').length})'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildNotificationList(_filtered('all')),
          _buildNotificationList(_filtered('alert')),
          _buildNotificationList(_filtered('update')),
        ],
      ),
    );
  }

  Widget _buildNotificationList(List<_NotificationItem> items) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_off_outlined, size: 48, color: AppColors.textTertiary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text('No notifications', style: TextStyle(fontSize: 15, color: AppColors.textTertiary, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    // Group by today / earlier
    final today = items.where((n) => n.time.contains('min') || n.time.contains('hour')).toList();
    final earlier = items.where((n) => !n.time.contains('min') && !n.time.contains('hour')).toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      physics: const BouncingScrollPhysics(),
      children: [
        if (today.isNotEmpty) ...[
          _groupTitle('TODAY'),
          const SizedBox(height: 8),
          ...today.asMap().entries.map((e) =>
            _buildNotificationTile(e.value)
                .animate()
                .fadeIn(duration: 250.ms, delay: (e.key * 50).ms)
                .slideX(begin: 0.03),
          ),
        ],
        if (earlier.isNotEmpty) ...[
          const SizedBox(height: 20),
          _groupTitle('EARLIER'),
          const SizedBox(height: 8),
          ...earlier.asMap().entries.map((e) =>
            _buildNotificationTile(e.value)
                .animate()
                .fadeIn(duration: 250.ms, delay: ((today.length + e.key) * 50).ms)
                .slideX(begin: 0.03),
          ),
        ],
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _groupTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(text, style: AppTypography.captionSmall.copyWith(
        color: AppColors.textTertiary, fontWeight: FontWeight.w700, letterSpacing: 1.2, fontSize: 11,
      )),
    );
  }

  Widget _buildNotificationTile(_NotificationItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: item.isUnread ? Colors.white : Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: item.isUnread ? AppColors.borderLight : AppColors.borderLight.withValues(alpha: 0.5)),
        boxShadow: item.isUnread
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => item.isUnread = false);
          },
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: item.iconBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(item.icon, color: item.iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: item.isUnread ? FontWeight.w700 : FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (item.isUnread)
                            Container(
                              width: 8, height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.accentOrange,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.subtitle,
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.time,
                        style: TextStyle(fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.w500),
                      ),
                    ],
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

class _NotificationItem {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final String time;
  bool isUnread;
  final String type;

  _NotificationItem({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.isUnread,
    required this.type,
  });
}
