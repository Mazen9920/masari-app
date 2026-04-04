import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/notification_settings_provider.dart';
import '../../shared/utils/safe_pop.dart';
import '../../l10n/app_localizations.dart';

class NotificationPreferencesScreen extends ConsumerWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(notificationSettingsProvider);
    final notifier = ref.read(notificationSettingsProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.safePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primaryNavy),
        ),
        title: Text(l10n.notificationsTitle, style: AppTypography.h3.copyWith(color: AppColors.primaryNavy)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(l10n.notificationsSectionChannels),
            const SizedBox(height: 10),
            _buildCard([
              _buildToggleRow(
                icon: Icons.notifications_active_outlined,
                iconColor: const Color(0xFF3B82F6),
                title: l10n.notificationsPush,
                subtitle: l10n.notificationsPushSubtitle,
                value: settings.pushNotifications,
                onChanged: (v) => notifier.setPush(v),
              ),
              _divider(),
              _buildToggleRow(
                icon: Icons.mail_outline_rounded,
                iconColor: const Color(0xFF8B5CF6),
                title: l10n.notificationsEmail,
                subtitle: l10n.notificationsEmailSubtitle,
                value: settings.emailNotifications,
                onChanged: (v) => notifier.setEmail(v),
              ),
            ]),
            const SizedBox(height: 24),
            _sectionTitle(l10n.notificationsSectionAlerts),
            const SizedBox(height: 10),
            _buildCard([
              _buildToggleRow(
                icon: Icons.point_of_sale_rounded,
                iconColor: const Color(0xFF22C55E),
                title: l10n.notificationsSales,
                subtitle: l10n.notificationsSalesSubtitle,
                value: settings.salesNotifications,
                onChanged: (v) => notifier.setSales(v),
              ),
              _divider(),
              _buildToggleRow(
                icon: Icons.store_rounded,
                iconColor: const Color(0xFF8B5CF6),
                title: l10n.notificationsShopifyOrders,
                subtitle: l10n.notificationsShopifySubtitle,
                value: settings.shopifyOrderNotifications,
                onChanged: (v) => notifier.setShopifyOrders(v),
              ),
              _divider(),
              _buildToggleRow(
                icon: Icons.receipt_long_rounded,
                iconColor: const Color(0xFF0EA5E9),
                title: l10n.notificationsBilling,
                subtitle: l10n.notificationsBillingSubtitle,
                value: settings.billingNotifications,
                onChanged: (v) => notifier.setBilling(v),
              ),
              _divider(),
              _buildToggleRow(
                icon: Icons.inventory_2_outlined,
                iconColor: const Color(0xFFEF4444),
                title: l10n.notificationsLowStock,
                subtitle: l10n.notificationsLowStockSubtitle,
                value: settings.lowStockAlerts,
                onChanged: (v) => notifier.setLowStock(v),
              ),
              _divider(),
              _buildToggleRow(
                icon: Icons.payments_outlined,
                iconColor: const Color(0xFFF59E0B),
                title: l10n.notificationsPaymentReminders,
                subtitle: l10n.notificationsPaymentSubtitle,
                value: settings.paymentReminders,
                onChanged: (v) => notifier.setPaymentReminders(v),
              ),
            ]),
            const SizedBox(height: 24),
            _sectionTitle(l10n.notificationsSectionReports),
            const SizedBox(height: 10),
            _buildCard([
              _buildToggleRow(
                icon: Icons.summarize_outlined,
                iconColor: const Color(0xFF22C55E),
                title: l10n.notificationsWeeklyDigest,
                subtitle: l10n.notificationsWeeklySubtitle,
                value: settings.weeklyDigest,
                onChanged: (v) => notifier.setWeeklyDigest(v),
              ),
              _divider(),
              _buildToggleRow(
                icon: Icons.calendar_month_outlined,
                iconColor: const Color(0xFF0EA5E9),
                title: l10n.notificationsMonthlyReport,
                subtitle: l10n.notificationsMonthlySubtitle,
                value: settings.monthlyReport,
                onChanged: (v) => notifier.setMonthlyReport(v),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: AppTypography.captionSmall.copyWith(
          color: AppColors.textTertiary, fontWeight: FontWeight.w700, letterSpacing: 1.2, fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8)],
      ),
      child: Column(children: children),
    );
  }

  Widget _divider() => Divider(height: 1, color: AppColors.borderLight.withValues(alpha: 0.5), indent: 68);

  Widget _buildToggleRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: (v) { HapticFeedback.lightImpact(); onChanged(v); },
            activeThumbColor: AppColors.accentOrange,
            activeTrackColor: AppColors.accentOrange.withValues(alpha: 0.3),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFFCBD5E1),
          ),
        ],
      ),
    );
  }
}
