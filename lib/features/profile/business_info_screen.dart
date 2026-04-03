import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/business_profile_provider.dart';
import '../../shared/utils/safe_pop.dart';
import '../../l10n/app_localizations.dart';

class BusinessInfoScreen extends ConsumerStatefulWidget {
  const BusinessInfoScreen({super.key});

  @override
  ConsumerState<BusinessInfoScreen> createState() => _BusinessInfoScreenState();
}

class _BusinessInfoScreenState extends ConsumerState<BusinessInfoScreen> {
  late final TextEditingController _businessNameController;
  late final TextEditingController _businessTypeController;
  late final TextEditingController _addressController;
  late final TextEditingController _taxIdController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final bp = ref.read(businessProfileProvider);
    _businessNameController = TextEditingController(text: bp.businessName);
    _businessTypeController = TextEditingController(text: bp.businessType);
    _addressController      = TextEditingController(text: bp.address);
    _taxIdController        = TextEditingController(text: bp.taxId);
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _businessTypeController.dispose();
    _addressController.dispose();
    _taxIdController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    await ref.read(businessProfileProvider.notifier).update(
      businessName: _businessNameController.text.trim(),
      businessType: _businessTypeController.text.trim(),
      address:      _addressController.text.trim(),
      taxId:        _taxIdController.text.trim(),
    );
    if (mounted) {
      setState(() => _saving = false);
      context.safePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.safePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primaryNavy),
        ),
        title: Text(l10n.businessInfoTitle, style: AppTypography.h3.copyWith(color: AppColors.primaryNavy)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(
                    l10n.save,
                    style: TextStyle(color: AppColors.accentOrange, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            // Business Logo
            Center(
              child: Stack(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: AppColors.primaryNavy.withValues(alpha: 0.1),
                      border: Border.all(color: AppColors.primaryNavy.withValues(alpha: 0.2), width: 2),
                    ),
                    child: const Center(
                      child: Icon(Icons.business_rounded, size: 36, color: AppColors.primaryNavy),
                    ),
                  ),
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.accentOrange,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.edit_rounded, color: Colors.white, size: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(l10n.businessInfoUploadLogo, style: TextStyle(fontSize: 12, color: AppColors.accentOrange, fontWeight: FontWeight.w600)),
            const SizedBox(height: 28),
            _buildField(l10n.businessInfoName, _businessNameController, Icons.storefront_rounded),
            const SizedBox(height: 16),
            _buildField(l10n.businessInfoType, _businessTypeController, Icons.category_rounded),
            const SizedBox(height: 16),
            _buildField(l10n.businessInfoAddress, _addressController, Icons.location_on_outlined),
            const SizedBox(height: 16),
            _buildField(l10n.businessInfoTaxId, _taxIdController, Icons.receipt_long_rounded),
            const SizedBox(height: 32),
            // Tax Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.accentOrange, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.businessInfoTaxNote,
                      style: TextStyle(fontSize: 12, color: AppColors.accentOrangeDark, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2)),
            ],
          ),
          child: TextField(
            controller: controller,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: AppColors.textTertiary, size: 20),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}
