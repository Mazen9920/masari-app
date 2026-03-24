import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/security_settings_provider.dart';
import '../../shared/utils/safe_pop.dart';
import '../../l10n/app_localizations.dart';

class SecurityScreen extends ConsumerWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(securitySettingsProvider);
    final notifier = ref.read(securitySettingsProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.safePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primaryNavy),
        ),
        title: Text(l10n.securityTitle, style: AppTypography.h3.copyWith(color: AppColors.primaryNavy)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Security Status Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                    const Color(0xFF8B5CF6).withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.shield_outlined, color: Color(0xFF8B5CF6), size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.securityStatus, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 8, height: 8,
                              decoration: BoxDecoration(
                                color: settings.appLock ? AppColors.success : AppColors.warning,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              settings.appLock ? l10n.securityProtected : l10n.securityBasic,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: settings.appLock ? AppColors.success : AppColors.warning,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _sectionTitle(l10n.securitySectionAuth),
            const SizedBox(height: 10),
            _buildCard([
              _buildToggleRow(
                icon: Icons.pin_outlined,
                iconColor: const Color(0xFF3B82F6),
                title: l10n.securityAppLock,
                subtitle: l10n.securityAppLockSubtitle,
                value: settings.appLock,
                onChanged: (v) {
                  HapticFeedback.lightImpact();
                  notifier.setAppLock(v);
                },
              ),
              _divider(),
              _buildToggleRow(
                icon: Icons.fingerprint_rounded,
                iconColor: const Color(0xFF22C55E),
                title: l10n.securityBiometric,
                subtitle: l10n.securityBiometricSubtitle,
                value: settings.biometrics,
                onChanged: (v) {
                  HapticFeedback.lightImpact();
                  notifier.setBiometrics(v);
                },
              ),
            ]),
            const SizedBox(height: 24),
            _sectionTitle(l10n.securitySectionPassword),
            const SizedBox(height: 10),
            _buildCard([
              _buildActionRow(
                icon: Icons.key_rounded,
                iconColor: const Color(0xFFF59E0B),
                title: l10n.securityChangePassword,
                subtitle: l10n.securityPasswordLastChanged,
                onTap: () {
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.securityPasswordComingSoon)),
                  );
                },
              ),
            ]),
            const SizedBox(height: 24),
            _sectionTitle(l10n.securitySectionSessions),
            const SizedBox(height: 10),
            _buildCard([
              _buildActionRow(
                icon: Icons.devices_rounded,
                iconColor: const Color(0xFF0EA5E9),
                title: l10n.securityActiveSessions,
                subtitle: l10n.securityActiveDevices,
                onTap: () {
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.securityOneActiveSession)));
                },
              ),
              _divider(),
              _buildActionRow(
                icon: Icons.logout_rounded,
                iconColor: AppColors.danger,
                title: l10n.securitySignOutAll,
                subtitle: l10n.securitySignOutAllSubtitle,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: Text(l10n.securitySignOutAllTitle, style: AppTypography.h3),
                      content: Text(l10n.securitySignOutAllMessage),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
                        FilledButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.securityAllSessionsEnded)));
                          },
                          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                          child: Text(l10n.securitySignOutAllButton),
                        ),
                      ],
                    ),
                  );
                },
                isDestructive: true,
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
      child: Text(text, style: AppTypography.captionSmall.copyWith(
        color: AppColors.textTertiary, fontWeight: FontWeight.w700, letterSpacing: 1.2, fontSize: 11,
      )),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8)],
      ),
      child: Column(children: children),
    );
  }

  Widget _divider() => Divider(height: 1, color: AppColors.borderLight.withValues(alpha: 0.5), indent: 68);

  Widget _buildToggleRow({
    required IconData icon, required Color iconColor,
    required String title, required String subtitle,
    required bool value, required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
          ])),
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

  Widget _buildActionRow({
    required IconData icon, required Color iconColor,
    required String title, required String subtitle,
    required VoidCallback onTap, bool isDestructive = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isDestructive ? AppColors.danger : AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
              ])),
              Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
