import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';

class OnboardingPageData {
  final String title;
  final String highlightWord;
  final String subtitle;
  final Widget illustration;

  const OnboardingPageData({
    required this.title,
    required this.highlightWord,
    required this.subtitle,
    required this.illustration,
  });
}

class OnboardingPage extends StatelessWidget {
  final OnboardingPageData data;

  const OnboardingPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ─── Illustration area (flexible, takes available space) ───
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(child: data.illustration),
          ),
        ),

        // ─── Text content area ───
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenHorizontal,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(height: 8),

                // Title with highlighted word
                _buildTitle(context),

                const SizedBox(height: 14),

                // Subtitle
                Text(
                  data.subtitle,
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTitle(BuildContext context) {
    // Split the title to insert the highlighted word with accent color
    final parts = data.title.split(data.highlightWord);

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: AppTypography.h1.copyWith(
          color: AppColors.textPrimary,
          fontSize: 30,
          height: 1.25,
        ),
        children: [
          if (parts.isNotEmpty) TextSpan(text: parts[0]),
          TextSpan(
            text: data.highlightWord,
            style: AppTypography.h1.copyWith(
              color: AppColors.accentOrange,
              fontSize: 30,
              height: 1.25,
            ),
          ),
          if (parts.length > 1) TextSpan(text: parts[1]),
        ],
      ),
    );
  }
}
