import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/notifications_provider.dart';
import '../../l10n/app_localizations.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

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

  List<AppNotification> _filtered(List<AppNotification> all, NotificationType? type) {
    if (type == null) return all;
    return all.where((n) => n.type == type).toList();
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('dd MMM').format(dt);
  }

  void _onTap(AppNotification item) {
    HapticFeedback.lightImpact();
    // Mark as read
    ref.read(readNotificationIdsProvider.notifier).markRead(item.id);
    // Navigate if route is set
    if (item.routeName != null) {
      context.pushNamed(item.routeName!, extra: item.routeExtra);
    }
  }

  void _markAllRead(List<AppNotification> notifications) {
    HapticFeedback.lightImpact();
    ref
        .read(readNotificationIdsProvider.notifier)
        .markAllRead(notifications.map((n) => n.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(notificationsProvider);
    final readIds = ref.watch(readNotificationIdsProvider);
    final alerts = _filtered(notifications, NotificationType.alert);
    final updates = _filtered(notifications, NotificationType.update);
    final hasUnread = notifications.any((n) => !readIds.contains(n.id));

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primaryNavy),
        ),
        title: Text(AppLocalizations.of(context)!.notifications, style: AppTypography.h3.copyWith(color: AppColors.primaryNavy)),
        centerTitle: true,
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: () => _markAllRead(notifications),
              child: Text(
                AppLocalizations.of(context)!.readAll,
                style: TextStyle(
                  color: AppColors.secondaryBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
                Tab(text: 'All (${notifications.length})'),
                Tab(text: 'Alerts (${alerts.length})'),
                Tab(text: 'Updates (${updates.length})'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildNotificationList(notifications, readIds),
          _buildNotificationList(alerts, readIds),
          _buildNotificationList(updates, readIds),
        ],
      ),
    );
  }

  Widget _buildNotificationList(List<AppNotification> items, Set<String> readIds) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_off_outlined, size: 48, color: AppColors.textTertiary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(AppLocalizations.of(context)!.noNotifications, style: TextStyle(fontSize: 15, color: AppColors.textTertiary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(AppLocalizations.of(context)!.allCaughtUp, style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
          ],
        ),
      );
    }

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final today = items.where((n) => !n.createdAt.isBefore(todayStart)).toList();
    final earlier = items.where((n) => n.createdAt.isBefore(todayStart)).toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      physics: const BouncingScrollPhysics(),
      children: [
        if (today.isNotEmpty) ...[
          _groupTitle(AppLocalizations.of(context)!.todayLabel),
          const SizedBox(height: 8),
          ...today.asMap().entries.map((e) =>
            _buildNotificationTile(e.value, readIds.contains(e.value.id))
                .animate()
                .fadeIn(duration: 250.ms, delay: (e.key * 50).ms)
                .slideX(begin: 0.03),
          ),
        ],
        if (earlier.isNotEmpty) ...[
          const SizedBox(height: 20),
          _groupTitle(AppLocalizations.of(context)!.earlierLabel),
          const SizedBox(height: 8),
          ...earlier.asMap().entries.map((e) =>
            _buildNotificationTile(e.value, readIds.contains(e.value.id))
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

  Widget _buildNotificationTile(AppNotification item, bool isRead) {
    final isAlert = item.type == NotificationType.alert;
    return GestureDetector(
      onTap: () => _onTap(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isRead ? AppColors.backgroundLight : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isRead
                ? AppColors.borderLight.withValues(alpha: 0.4)
                : (isAlert ? AppColors.borderLight : AppColors.borderLight.withValues(alpha: 0.5)),
          ),
          boxShadow: (!isRead && isAlert)
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: isRead ? item.iconBg.withValues(alpha: 0.5) : item.iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, color: isRead ? item.iconColor.withValues(alpha: 0.5) : item.iconColor, size: 20),
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
                            item.localizedTitle(AppLocalizations.of(context)!),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isRead ? FontWeight.w500 : (isAlert ? FontWeight.w700 : FontWeight.w600),
                              color: isRead ? AppColors.textSecondary : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (!isRead && isAlert)
                          Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(
                              color: item.iconColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        if (!isRead && !isAlert)
                          Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(
                              color: AppColors.secondaryBlue,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.localizedSubtitle(AppLocalizations.of(context)!),
                      style: TextStyle(
                        fontSize: 12,
                        color: isRead ? AppColors.textTertiary : AppColors.textSecondary,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _timeAgo(item.createdAt),
                      style: TextStyle(fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.w500),
                    ),
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
