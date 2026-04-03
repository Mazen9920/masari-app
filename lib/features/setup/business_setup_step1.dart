import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/navigation/app_router.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../l10n/app_localizations.dart';
import '../auth/widgets/form_components.dart';
import 'widgets/setup_shell.dart';

class BusinessSetupStep1 extends ConsumerStatefulWidget {
  const BusinessSetupStep1({super.key});

  @override
  ConsumerState<BusinessSetupStep1> createState() => _BusinessSetupStep1State();
}

class _BusinessSetupStep1State extends ConsumerState<BusinessSetupStep1> {
  final _businessNameController = TextEditingController();
  String? _selectedIndustry;
  int _selectedStageIndex = -1;

  final List<String> _industryKeys = [
    'industryFoodBeverage',
    'industryRetailFashion',
    'industryTechnology',
    'industryProfessionalServices',
    'industryEcommerce',
    'industryHealthcare',
    'industryEducation',
    'industryRealEstate',
    'industryManufacturing',
    'industryOther',
  ];

  final List<String> _stageKeys = [
    'stageJustAnIdea',
    'stageLessThan6Months',
    'stage1To3Years',
    'stage3PlusYears',
  ];

  @override
  void dispose() {
    _businessNameController.dispose();
    super.dispose();
  }

  void _onContinue() async {
    // Basic validation
    if (_businessNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.pleaseEnterBusinessName,
            style: AppTypography.bodySmall.copyWith(color: Colors.white),
          ),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
        ),
      );
      return;
    }

    // Save all step 1 data to appSettingsProvider
    final settings = ref.read(appSettingsProvider.notifier);
    await settings.setBusinessName(_businessNameController.text.trim());
    if (_selectedIndustry != null) {
      await settings.setIndustry(_selectedIndustry!);
    }
    if (_selectedStageIndex >= 0) {
      await settings.setBusinessStage(_stageKeys[_selectedStageIndex]);
    }

    if (!mounted) return;
    context.push(AppRoutes.setupStep2);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SetupShell(
      currentStep: 1,
      title: l10n.tellUsAboutBusiness,
      subtitle: l10n.setupStep1Subtitle,
      buttonText: l10n.continueButton,
      onBack: () => context.pop(),
      onContinue: _onContinue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Business Name ───
          _buildSectionLabel(l10n.businessName),
          const SizedBox(height: 8),
          RevvoTextField(
            label: l10n.businessName,
            icon: Icons.storefront_outlined,
            controller: _businessNameController,
            hint: l10n.egCairoCoffeeHouse,
          ),

          const SizedBox(height: 24),

          // ─── Industry ───
          _buildSectionLabel(l10n.industry),
          const SizedBox(height: 8),
          _buildIndustryDropdown(),

          const SizedBox(height: 24),

          // ─── Business Stage ───
          _buildSectionLabel(l10n.businessStageQuestion),
          const SizedBox(height: 12),
          _buildStageChips(),

          const SizedBox(height: 28),

          // ─── Country & Currency (auto-filled, read-only) ───
          Row(
            children: [
              Expanded(child: _buildReadOnlyField(l10n.country.toUpperCase(), 'Egypt', '🇪🇬')),
              const SizedBox(width: 16),
              Expanded(child: _buildReadOnlyField(l10n.currency.toUpperCase(), 'EGP', null, Icons.lock_outline)),
            ],
          ),
        ],
      ),
    );
  }

  String _localizedIndustry(String key, AppLocalizations l10n) {
    return switch (key) {
      'industryFoodBeverage' => l10n.industryFoodBeverage,
      'industryRetailFashion' => l10n.industryRetailFashion,
      'industryTechnology' => l10n.industryTechnology,
      'industryProfessionalServices' => l10n.industryProfessionalServices,
      'industryEcommerce' => l10n.industryEcommerce,
      'industryHealthcare' => l10n.industryHealthcare,
      'industryEducation' => l10n.industryEducation,
      'industryRealEstate' => l10n.industryRealEstate,
      'industryManufacturing' => l10n.industryManufacturing,
      'industryOther' => l10n.industryOther,
      _ => key,
    };
  }

  String _localizedStage(String key, AppLocalizations l10n) {
    return switch (key) {
      'stageJustAnIdea' => l10n.stageJustAnIdea,
      'stageLessThan6Months' => l10n.stageLessThan6Months,
      'stage1To3Years' => l10n.stage1To3Years,
      'stage3PlusYears' => l10n.stage3PlusYears,
      _ => key,
    };
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: AppTypography.labelMedium.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildIndustryDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.borderLight),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedIndustry,
          isExpanded: true,
          hint: Text(
            AppLocalizations.of(context)!.selectIndustry,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          icon: Icon(
            Icons.expand_more,
            color: AppColors.textTertiary,
          ),
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textPrimary,
          ),
          dropdownColor: AppColors.surfaceLight,
          borderRadius: AppRadius.cardRadius,
          items: _industryKeys.map((key) {
            return DropdownMenuItem(
              value: key,
              child: Text(_localizedIndustry(key, AppLocalizations.of(context)!)),
            );
          }).toList(),
          onChanged: (value) {
            setState(() => _selectedIndustry = value);
          },
        ),
      ),
    );
  }

  Widget _buildStageChips() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: List.generate(_stageKeys.length, (index) {
        final isSelected = _selectedStageIndex == index;
        return GestureDetector(
          onTap: () => setState(() => _selectedStageIndex = index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.accentOrange.withValues(alpha: 0.1)
                  : AppColors.surfaceLight,
              borderRadius: AppRadius.pillRadius,
              border: Border.all(
                color: isSelected
                    ? AppColors.accentOrange
                    : AppColors.borderLight,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Text(
              _localizedStage(_stageKeys[index], AppLocalizations.of(context)!),
              style: AppTypography.labelMedium.copyWith(
                color: isSelected
                    ? AppColors.accentOrange
                    : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildReadOnlyField(
    String label,
    String value,
    String? emoji, [
    IconData? trailingIcon,
  ]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.captionSmall.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.textPrimary.withValues(alpha: 0.04),
            borderRadius: AppRadius.cardRadius,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                value,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              if (emoji != null)
                Text(emoji, style: const TextStyle(fontSize: 18)),
              if (trailingIcon != null)
                Icon(trailingIcon, size: 16, color: AppColors.textTertiary),
            ],
          ),
        ),
      ],
    );
  }
}
