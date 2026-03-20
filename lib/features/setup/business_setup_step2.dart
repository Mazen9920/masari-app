import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_settings_provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/app_router.dart';
import 'widgets/setup_shell.dart';
import '../../l10n/app_localizations.dart';

class BusinessSetupStep2 extends ConsumerStatefulWidget {
  const BusinessSetupStep2({super.key});

  @override
  ConsumerState<BusinessSetupStep2> createState() => _BusinessSetupStep2State();
}

class _BusinessSetupStep2State extends ConsumerState<BusinessSetupStep2> {
  AppLocalizations get l10n => AppLocalizations.of(context)!;
  int _selectedGoalIndex = 0; // Default: first one selected

  List<_GoalOption> get _goals => [
    _GoalOption(
      icon: Icons.trending_up_rounded,
      title: l10n.trackProfitability,
      subtitle: 'Monitor margins and net profit in real-time.',
    ),
    _GoalOption(
      icon: Icons.account_balance_wallet_outlined,
      title: l10n.controlCashFlow,
      subtitle: 'Manage incoming and outgoing payments.',
    ),
    _GoalOption(
      icon: Icons.rocket_launch_rounded,
      title: l10n.growMyBusiness,
      subtitle: 'Secure funding and plan for expansion.',
    ),
    _GoalOption(
      icon: Icons.description_outlined,
      title: l10n.createFinancialReports,
      subtitle: 'Automate P&L and balance sheet generation.',
    ),
  ];

  void _onContinue() {
    // Save selected goal, then navigate to step 3
    ref.read(appSettingsProvider.notifier).setMainGoal(
      _goals[_selectedGoalIndex].title,
    );
    context.go(AppRoutes.setupStep3);
  }

  @override
  Widget build(BuildContext context) {
    return SetupShell(
      currentStep: 2,
      title: "What's Your Main Goal?",
      subtitle:
          "Select the one that matters most right now. We'll customize your dashboard based on this.",
      buttonText: 'Continue',
      onBack: () => context.go(AppRoutes.setupStep1),
      onContinue: _onContinue,
      child: Column(
        children: List.generate(_goals.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _GoalCard(
              goal: _goals[index],
              isSelected: _selectedGoalIndex == index,
              onTap: () => setState(() => _selectedGoalIndex = index),
            ),
          );
        }),
      ),
    );
  }
}

// ─── Data model ───
class _GoalOption {
  final IconData icon;
  final String title;
  final String subtitle;

  const _GoalOption({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}

// ─── Goal selection card ───
class _GoalCard extends StatelessWidget {
  final _GoalOption goal;
  final bool isSelected;
  final VoidCallback onTap;

  const _GoalCard({
    required this.goal,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accentOrange.withValues(alpha: 0.06)
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.accentOrange
                : AppColors.borderLight,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.accentOrange.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon container
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.surfaceLight
                    : AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(12),
                border: isSelected
                    ? Border.all(
                        color: AppColors.accentOrange.withValues(alpha: 0.2),
                      )
                    : null,
              ),
              child: Icon(
                goal.icon,
                color: isSelected
                    ? AppColors.accentOrange
                    : AppColors.textSecondary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),

            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    goal.title,
                    style: AppTypography.labelLarge.copyWith(
                      color: isSelected
                          ? AppColors.textPrimary
                          : AppColors.textPrimary,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    goal.subtitle,
                    style: AppTypography.bodySmall.copyWith(
                      color: isSelected
                          ? AppColors.textSecondary
                          : AppColors.textTertiary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            // Checkmark
            if (isSelected)
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accentOrange,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
