import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() => _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState extends State<NotificationPreferencesScreen> {
  bool _pushNotifications = true;
  bool _emailNotifications = false;
  bool _lowStockAlerts = true;
  bool _paymentReminders = true;
  bool _weeklyDigest = true;
  bool _monthlyReport = false;

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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('CHANNELS'),
            const SizedBox(height: 10),
            _buildCard([
              _buildToggleRow(
                icon: Icons.notifications_active_outlined,
                iconColor: const Color(0xFF3B82F6),
                title: 'Push Notifications',
                subtitle: 'Get instant alerts on your device',
                value: _pushNotifications,
                onChanged: (v) => setState(() => _pushNotifications = v),
              ),
              _divider(),
              _buildToggleRow(
                icon: Icons.mail_outline_rounded,
                iconColor: const Color(0xFF8B5CF6),
                title: 'Email Notifications',
                subtitle: 'Receive updates via email',
                value: _emailNotifications,
                onChanged: (v) => setState(() => _emailNotifications = v),
              ),
            ]),
            const SizedBox(height: 24),
            _sectionTitle('ALERTS'),
            const SizedBox(height: 10),
            _buildCard([
              _buildToggleRow(
                icon: Icons.inventory_2_outlined,
                iconColor: const Color(0xFFEF4444),
                title: 'Low Stock Alerts',
                subtitle: 'When items hit minimum quantity',
                value: _lowStockAlerts,
                onChanged: (v) => setState(() => _lowStockAlerts = v),
              ),
              _divider(),
              _buildToggleRow(
                icon: Icons.payments_outlined,
                iconColor: const Color(0xFFF59E0B),
                title: 'Payment Reminders',
                subtitle: 'Upcoming vendor payments',
                value: _paymentReminders,
                onChanged: (v) => setState(() => _paymentReminders = v),
              ),
            ]),
            const SizedBox(height: 24),
            _sectionTitle('REPORTS'),
            const SizedBox(height: 10),
            _buildCard([
              _buildToggleRow(
                icon: Icons.summarize_outlined,
                iconColor: const Color(0xFF22C55E),
                title: 'Weekly Digest',
                subtitle: 'Summary every Monday morning',
                value: _weeklyDigest,
                onChanged: (v) => setState(() => _weeklyDigest = v),
              ),
              _divider(),
              _buildToggleRow(
                icon: Icons.calendar_month_outlined,
                iconColor: const Color(0xFF0EA5E9),
                title: 'Monthly Report',
                subtitle: 'Detailed report on the 1st',
                value: _monthlyReport,
                onChanged: (v) => setState(() => _monthlyReport = v),
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
            activeColor: AppColors.accentOrange,
            activeTrackColor: AppColors.accentOrange.withValues(alpha: 0.3),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFFCBD5E1),
          ),
        ],
      ),
    );
  }
}
