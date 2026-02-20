import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../auth/widgets/form_components.dart';

/// Shared layout shell for all 3 business setup steps.
/// Provides: back button, step indicator, segmented progress bar,
/// scrollable content area, and sticky bottom CTA.
class SetupShell extends StatelessWidget {
  final int currentStep; // 1, 2, or 3
  final int totalSteps;
  final String title;
  final String subtitle;
  final String buttonText;
  final IconData? buttonIcon;
  final VoidCallback onBack;
  final VoidCallback onContinue;
  final Widget? belowButton; // Optional text below button
  final Widget child;

  const SetupShell({
    super.key,
    required this.currentStep,
    this.totalSteps = 3,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    this.buttonIcon,
    required this.onBack,
    required this.onContinue,
    this.belowButton,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Top: back + step + progress ───
            _buildTopSection(),

            // ─── Scrollable content ───
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenHorizontal,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    Text(
                      title,
                      style: AppTypography.h1.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    child,
                    // Extra padding so content isn't hidden behind sticky button
                    const SizedBox(height: 120),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomCTA(),
    );
  }

  Widget _buildTopSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, AppSpacing.screenHorizontal, 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.chevron_left_rounded),
                iconSize: 28,
                color: AppColors.textPrimary,
              ),
              Text(
                'Step $currentStep of $totalSteps',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              // Invisible spacer to balance the row
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 12),
          // Segmented progress bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildProgressBar(),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Row(
      children: List.generate(totalSteps, (index) {
        final isCompleted = index < currentStep;
        return Expanded(
          child: Container(
            height: 5,
            margin: EdgeInsets.only(
              right: index < totalSteps - 1 ? 6 : 0,
            ),
            decoration: BoxDecoration(
              color: isCompleted
                  ? AppColors.accentOrange
                  : AppColors.borderLight,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildBottomCTA() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        16,
        AppSpacing.screenHorizontal,
        32,
      ),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        border: Border(
          top: BorderSide(
            color: AppColors.borderLight.withOpacity(0.5),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MasariPrimaryButton(
            text: buttonText,
            icon: buttonIcon ?? Icons.arrow_forward_rounded,
            onPressed: onContinue,
          ),
          if (belowButton != null) ...[
            const SizedBox(height: 12),
            belowButton!,
          ],
        ],
      ),
    );
  }
}
