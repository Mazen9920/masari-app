import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/navigation/app_router.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/providers/business_profile_provider.dart';
import '../../l10n/app_localizations.dart';
import 'widgets/setup_shell.dart';

class BusinessSetupStep3 extends ConsumerStatefulWidget {
  const BusinessSetupStep3({super.key});

  @override
  ConsumerState<BusinessSetupStep3> createState() => _BusinessSetupStep3State();
}

class _BusinessSetupStep3State extends ConsumerState<BusinessSetupStep3> {
  // 0 = Launch, 1 = Growth
  int _selectedIndex = 0;

  void _onLetsGo() {
    // Set the tier based on selection
    final tier = switch (_selectedIndex) {
      1 => SubscriptionTier.growth,
      _ => SubscriptionTier.launch,
    };
    ref.read(appSettingsProvider.notifier).setTier(tier);

    // Persist business name (entered in step 1) from local prefs → Firestore
    final settings = ref.read(appSettingsProvider);
    final bizName = settings.businessName;
    if (bizName.isNotEmpty) {
      ref.read(businessProfileProvider.notifier).update(
        businessName: bizName,
        businessType: settings.industry,
        address: '',
        taxId: '',
      );
    }
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SetupShell(
      currentStep: 3,
      title: l10n.chooseYourPlan,
      subtitle: l10n.setupStep3Subtitle,
      buttonText: l10n.letsGo,
      buttonIcon: Icons.auto_awesome_rounded,
      onBack: () => context.go(AppRoutes.setupStep2),
      onContinue: _onLetsGo,
      belowButton: Text(
        l10n.changePlanAnytime,
        style: AppTypography.caption.copyWith(
          color: AppColors.textTertiary,
          fontSize: 12,
        ),
        textAlign: TextAlign.center,
      ),
      child: Column(
        children: [
          // ─── Launch Mode ───
          _TierCard(
            emoji: '🌱',
            title: l10n.launchMode,
            subtitle: l10n.launchModeSubtitle,
            badge: l10n.freeBadge,
            badgeColor: AppColors.success,
            isSelected: _selectedIndex == 0,
            isEnabled: true,
            onTap: () => setState(() => _selectedIndex = 0),
          ),

          const SizedBox(height: 14),

          // ─── Growth Mode ───
          _TierCard(
            emoji: '🚀',
            title: l10n.growthMode,
            subtitle: l10n.growthModeSubtitle,
            badge: l10n.popularBadge,
            badgeColor: AppColors.accentOrange,
            isSelected: _selectedIndex == 1,
            isEnabled: true,
            onTap: () => setState(() => _selectedIndex = 1),
          ),

          const SizedBox(height: 14),

          // ─── Pro Mode (Coming Soon) ───
          _TierCard(
            emoji: '👑',
            title: l10n.proMode,
            subtitle: l10n.proModeSubtitle,
            badge: l10n.comingSoonBadge,
            badgeColor: AppColors.textTertiary,
            isSelected: false,
            isEnabled: false,
            onTap: null,
          ),
        ],
      ),
    );
  }
}

// ─── Tier selection card ───
class _TierCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final bool isSelected;
  final bool isEnabled;
  final VoidCallback? onTap;

  const _TierCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.isSelected,
    required this.isEnabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accentOrange.withValues(alpha: 0.05)
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.accentOrange : AppColors.borderLight,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.accentOrange.withValues(alpha: 0.1),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Opacity(
          opacity: isEnabled ? 1.0 : 0.55,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Emoji icon container
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.surfaceLight
                      : AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(14),
                  border: isSelected
                      ? Border.all(
                          color: AppColors.accentOrange.withValues(alpha: 0.2),
                        )
                      : Border.all(color: AppColors.borderLight),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(width: 14),

              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row with badge
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: AppTypography.labelLarge.copyWith(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? badgeColor
                                : badgeColor.withValues(alpha: 0.15),
                            borderRadius: AppRadius.pillRadius,
                          ),
                          child: Text(
                            badge.toUpperCase(),
                            style: AppTypography.captionSmall.copyWith(
                              color: isSelected ? Colors.white : badgeColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 9,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
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
