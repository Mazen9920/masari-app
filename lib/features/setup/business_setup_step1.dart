import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../auth/widgets/form_components.dart';
import 'widgets/setup_shell.dart';
import 'business_setup_step2.dart';

class BusinessSetupStep1 extends StatefulWidget {
  const BusinessSetupStep1({super.key});

  @override
  State<BusinessSetupStep1> createState() => _BusinessSetupStep1State();
}

class _BusinessSetupStep1State extends State<BusinessSetupStep1> {
  final _businessNameController = TextEditingController();
  String? _selectedIndustry;
  int _selectedStageIndex = -1;

  final List<String> _industries = [
    'Food & Beverage',
    'Retail & Fashion',
    'Technology',
    'Professional Services',
    'E-Commerce',
    'Healthcare',
    'Education',
    'Real Estate',
    'Manufacturing',
    'Other',
  ];

  final List<String> _stages = [
    'Just an idea',
    'Less than 6 months',
    '1–3 years',
    '3+ years',
  ];

  @override
  void dispose() {
    _businessNameController.dispose();
    super.dispose();
  }

  void _onContinue() {
    // Basic validation
    if (_businessNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enter your business name',
            style: AppTypography.bodySmall.copyWith(color: Colors.white),
          ),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BusinessSetupStep2()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SetupShell(
      currentStep: 1,
      title: 'Tell us about your business',
      subtitle:
          'Help Masari tailor your financial experience to your specific needs.',
      buttonText: 'Continue',
      onBack: () => Navigator.of(context).pop(),
      onContinue: _onContinue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Business Name ───
          _buildSectionLabel('Business Name'),
          const SizedBox(height: 8),
          MasariTextField(
            label: 'Business Name',
            icon: Icons.storefront_outlined,
            controller: _businessNameController,
            hint: 'e.g. Cairo Coffee House',
          ),

          const SizedBox(height: 24),

          // ─── Industry ───
          _buildSectionLabel('Industry'),
          const SizedBox(height: 8),
          _buildIndustryDropdown(),

          const SizedBox(height: 24),

          // ─── Business Stage ───
          _buildSectionLabel('What stage is your business in?'),
          const SizedBox(height: 12),
          _buildStageChips(),

          const SizedBox(height: 28),

          // ─── Country & Currency (auto-filled, read-only) ───
          Row(
            children: [
              Expanded(child: _buildReadOnlyField('COUNTRY', 'Egypt', '🇪🇬')),
              const SizedBox(width: 16),
              Expanded(child: _buildReadOnlyField('CURRENCY', 'EGP', null, Icons.lock_outline)),
            ],
          ),
        ],
      ),
    );
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
            'Select Industry',
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
          items: _industries.map((industry) {
            return DropdownMenuItem(
              value: industry,
              child: Text(industry),
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
      children: List.generate(_stages.length, (index) {
        final isSelected = _selectedStageIndex == index;
        return GestureDetector(
          onTap: () => setState(() => _selectedStageIndex = index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.accentOrange.withOpacity(0.1)
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
              _stages[index],
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
            color: AppColors.textPrimary.withOpacity(0.04),
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
