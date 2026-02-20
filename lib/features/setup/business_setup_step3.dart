import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import 'widgets/setup_shell.dart';
import '../../shared/widgets/main_shell.dart';

class BusinessSetupStep3 extends StatefulWidget {
  const BusinessSetupStep3({super.key});

  @override
  State<BusinessSetupStep3> createState() => _BusinessSetupStep3State();
}

class _BusinessSetupStep3State extends State<BusinessSetupStep3> {
  // Only Launch Mode is selectable for now
  int _selectedIndex = 0;

  void _onLetsGo() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell()),
      (route) => false, // removes all previous routes (no back to setup)
    );
  }

  @override
  Widget build(BuildContext context) {
    return SetupShell(
      currentStep: 3,
      title: 'How comfortable are you with finance?',
      subtitle:
          "We'll tailor the Masari AI experience and terminology based on your expertise level.",
      buttonText: "Let's Go!",
      buttonIcon: Icons.auto_awesome_rounded,
      onBack: () => Navigator.of(context).pop(),
      onContinue: _onLetsGo,
      belowButton: Text(
        'You can change this setting anytime in your profile.',
        style: AppTypography.caption.copyWith(
          color: AppColors.textTertiary,
          fontSize: 12,
        ),
        textAlign: TextAlign.center,
      ),
      child: Column(
        children: [
          // ─── Launch Mode (Active / Selectable) ───
          _TierCard(
            emoji: '🌱',
            title: 'Launch Mode',
            subtitle:
                'I need guidance. Explain things simply and handle the complex math for me.',
            badge: 'Recommended',
            badgeColor: AppColors.accentOrange,
            isSelected: _selectedIndex == 0,
            isEnabled: true,
            onTap: () => setState(() => _selectedIndex = 0),
          ),

          const SizedBox(height: 14),

          // ─── Growth Mode (Coming Soon) ───
          _TierCard(
            emoji: '🚀',
            title: 'Growth Mode',
            subtitle:
                'I know the basics. Give me the raw data but highlight the anomalies.',
            badge: 'Coming Soon',
            badgeColor: AppColors.textTertiary,
            isSelected: false,
            isEnabled: false,
            onTap: null,
          ),

          const SizedBox(height: 14),

          // ─── Pro Mode (Coming Soon) ───
          _TierCard(
            emoji: '👑',
            title: 'Pro Mode',
            subtitle:
                "I'm an expert. I want full manual control over ledgers and forecasting.",
            badge: 'Coming Soon',
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
              ? AppColors.accentOrange.withOpacity(0.05)
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.accentOrange : AppColors.borderLight,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.accentOrange.withOpacity(0.1),
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
                          color: AppColors.accentOrange.withOpacity(0.2),
                        )
                      : Border.all(color: AppColors.borderLight),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
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
                                : badgeColor.withOpacity(0.15),
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
