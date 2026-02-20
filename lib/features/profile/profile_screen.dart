import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import 'edit_profile_screen.dart';
import 'business_info_screen.dart';
import 'currency_language_screen.dart';
import 'notification_preferences_screen.dart';
import 'security_screen.dart';
import 'data_backup_screen.dart';
import 'help_center_screen.dart';
import 'about_screen.dart';
import 'manage_subscription_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Header ──
            SliverToBoxAdapter(child: _buildHeader(context)),
            // ── Profile Card ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: _buildProfileCard(context, user.name)
                    .animate()
                    .fadeIn(duration: 300.ms)
                    .slideY(begin: 0.05),
              ),
            ),
            // ── Account Section ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                child: _buildSection(
                  context,
                  'ACCOUNT',
                  [
                    _SettingItem(
                      icon: Icons.person_outline_rounded,
                      iconBg: const Color(0xFFEFF6FF),
                      iconColor: const Color(0xFF3B82F6),
                      title: 'Edit Profile',
                      subtitle: 'Name, email, phone',
                      onTap: () => _navigate(context, const EditProfileScreen()),
                    ),
                    _SettingItem(
                      icon: Icons.business_rounded,
                      iconBg: const Color(0xFFF0FDF4),
                      iconColor: const Color(0xFF22C55E),
                      title: 'Business Info',
                      subtitle: 'Company details & tax ID',
                      onTap: () => _navigate(context, const BusinessInfoScreen()),
                    ),
                    _SettingItem(
                      icon: Icons.language_rounded,
                      iconBg: const Color(0xFFFFF7ED),
                      iconColor: AppColors.accentOrange,
                      title: 'Currency & Language',
                      subtitle: 'EGP · English',
                      onTap: () => _navigate(context, const CurrencyLanguageScreen()),
                    ),
                    _SettingItem(
                      icon: Icons.workspace_premium_outlined,
                      iconBg: const Color(0xFFFEF2F2),
                      iconColor: const Color(0xFFEF4444),
                      title: 'Manage Subscription',
                      subtitle: 'Current plan: Launch Mode',
                      onTap: () => _navigate(context, const ManageSubscriptionScreen()),
                    ),
                  ],
                ).animate().fadeIn(duration: 300.ms, delay: 100.ms),
              ),
            ),
            // ── App Section ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: _buildSection(
                  context,
                  'APP',
                  [
                    _SettingItem(
                      icon: Icons.notifications_outlined,
                      iconBg: const Color(0xFFFEF2F2),
                      iconColor: const Color(0xFFEF4444),
                      title: 'Notification Preferences',
                      subtitle: 'Push, email & alerts',
                      onTap: () => _navigate(context, const NotificationPreferencesScreen()),
                    ),
                    _SettingItem(
                      icon: Icons.lock_outline_rounded,
                      iconBg: const Color(0xFFF5F3FF),
                      iconColor: const Color(0xFF8B5CF6),
                      title: 'Security & PIN',
                      subtitle: 'Biometrics, password',
                      onTap: () => _navigate(context, const SecurityScreen()),
                    ),
                    _SettingItem(
                      icon: Icons.cloud_upload_outlined,
                      iconBg: const Color(0xFFF0F9FF),
                      iconColor: const Color(0xFF0EA5E9),
                      title: 'Data & Backup',
                      subtitle: 'Export, restore, auto-backup',
                      onTap: () => _navigate(context, const DataBackupScreen()),
                    ),
                  ],
                ).animate().fadeIn(duration: 300.ms, delay: 200.ms),
              ),
            ),
            // ── Support Section ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: _buildSection(
                  context,
                  'SUPPORT',
                  [
                    _SettingItem(
                      icon: Icons.help_outline_rounded,
                      iconBg: const Color(0xFFFFFBEB),
                      iconColor: const Color(0xFFF59E0B),
                      title: 'Help Center',
                      subtitle: 'FAQ & contact support',
                      onTap: () => _navigate(context, const HelpCenterScreen()),
                    ),
                    _SettingItem(
                      icon: Icons.info_outline_rounded,
                      iconBg: const Color(0xFFF1F5F9),
                      iconColor: const Color(0xFF64748B),
                      title: 'About Masari',
                      subtitle: 'Version 1.0.0',
                      onTap: () => _navigate(context, const AboutScreen()),
                    ),
                  ],
                ).animate().fadeIn(duration: 300.ms, delay: 300.ms),
              ),
            ),
            // ── Sign Out ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 120),
                child: _buildSignOutButton(context)
                    .animate()
                    .fadeIn(duration: 300.ms, delay: 400.ms),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigate(BuildContext context, Widget screen) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            color: AppColors.primaryNavy,
          ),
          Expanded(
            child: Text(
              'Profile',
              style: AppTypography.h2.copyWith(
                color: AppColors.primaryNavy,
                fontWeight: FontWeight.w800,
                fontSize: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context, String userName) {
    final initials = userName.isNotEmpty ? userName[0].toUpperCase() : 'U';
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryNavy,
            AppColors.primaryNavy.withValues(alpha: 0.85),
            AppColors.secondaryBlue,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryNavy.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.2),
              border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'TechStyle Egypt',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accentOrange.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Pro Plan',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Edit
          IconButton(
            onPressed: () => _navigate(context, const EditProfileScreen()),
            icon: Icon(
              Icons.edit_rounded,
              color: Colors.white.withValues(alpha: 0.7),
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, List<_SettingItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title,
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              fontSize: 11,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                _buildSettingRow(items[i]),
                if (i < items.length - 1)
                  Divider(height: 1, color: AppColors.borderLight.withValues(alpha: 0.5), indent: 68),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingRow(_SettingItem item) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
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
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignOutButton(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () {
        HapticFeedback.mediumImpact();
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Sign Out', style: AppTypography.h3),
            content: const Text('Are you sure you want to sign out?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                child: const Text('Sign Out'),
              ),
            ],
          ),
        );
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.danger,
        side: BorderSide(color: AppColors.danger.withValues(alpha: 0.3)),
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: const Icon(Icons.logout_rounded, size: 20),
      label: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
    );
  }
}

class _SettingItem {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  _SettingItem({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}
