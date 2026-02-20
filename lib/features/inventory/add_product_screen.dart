import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/models/product_model.dart';

class AddProductScreen extends ConsumerStatefulWidget {
  const AddProductScreen({super.key});

  @override
  ConsumerState<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends ConsumerState<AddProductScreen> {
  final _nameController = TextEditingController();
  final _skuController = TextEditingController();
  final _costController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  final _reorderController = TextEditingController(text: '10');
  final _wasteController = TextEditingController();

  bool _isPhysical = true;
  String _selectedCategory = '';
  String _selectedUom = 'Pieces';
  bool _isRawMaterial = false;
  String _baseMaterialType = '';
  bool _showOptional = false;

  static const _categories = [
    'Gym Gear',
    'Weights',
    'Yoga',
    'Supplements',
    'Accessories',
    'Clothing',
    'Electronics',
  ];

  static const _uomOptions = [
    'Pieces',
    'Kilograms (kg)',
    'Liters (l)',
    'Boxes',
  ];

  static const _materialTypes = [
    'Fabric',
    'Plastic',
    'Wood',
    'Metal',
  ];

  bool get _canSave => _nameController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _costController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _reorderController.dispose();
    _wasteController.dispose();
    super.dispose();
  }

  void _autoGenerateSku() {
    final name = _nameController.text.trim().toUpperCase();
    if (name.isEmpty) return;
    final parts = name.split(' ');
    final prefix =
        parts.length >= 2 ? '${parts[0].substring(0, 3)}-${parts[1].substring(0, parts[1].length.clamp(0, 3))}' : name.substring(0, name.length.clamp(0, 6));
    _skuController.text = prefix;
    HapticFeedback.lightImpact();
  }

  void _save() {
    if (!_canSave) {
      HapticFeedback.heavyImpact();
      return;
    }

    final product = Product(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      sku: _skuController.text.trim().isEmpty
          ? 'SKU-${DateTime.now().millisecondsSinceEpoch % 100000}'
          : _skuController.text.trim(),
      category: _selectedCategory.isEmpty ? 'Uncategorized' : _selectedCategory,
      supplier: '',
      costPrice: double.tryParse(_costController.text) ?? 0,
      sellingPrice: double.tryParse(_priceController.text) ?? 0,
      currentStock: int.tryParse(_stockController.text) ?? 0,
      reorderPoint: int.tryParse(_reorderController.text) ?? 10,
      unitOfMeasure: _selectedUom,
    );

    ref.read(inventoryProvider.notifier).addProduct(product);
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
        ),
        title: Text(
          'Add New Product',
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _canSave ? _save : null,
            child: Text(
              'Save',
              style: AppTypography.labelMedium.copyWith(
                color: _canSave
                    ? AppColors.primaryNavy
                    : AppColors.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              child: Column(
                children: [
                  // Subtitle
                  Text(
                    'Basics first — you can add details later.',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textTertiary),
                  ),
                  const SizedBox(height: 20),

                  // Photo upload
                  _buildPhotoUpload(),
                  const SizedBox(height: 20),

                  // Main details
                  _buildMainSection(),
                  const SizedBox(height: 12),

                  // Supplier
                  _buildSupplierSection(),
                  const SizedBox(height: 12),

                  // Pricing
                  _buildPricingSection(),
                  const SizedBox(height: 12),

                  // Stock & UOM
                  _buildStockSection(),
                  const SizedBox(height: 12),

                  // Raw materials
                  _buildRawMaterialSection(),
                  const SizedBox(height: 12),

                  // Optional details
                  _buildOptionalToggle(),
                ],
              ),
            ),
          ),
          _buildBottomActions(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  PHOTO UPLOAD
  // ═══════════════════════════════════════════════════
  Widget _buildPhotoUpload() {
    return Column(
      children: [
        Stack(
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.borderLight,
                  width: 2,
                  style: BorderStyle.solid,
                ),
                color: const Color(0xFFF8F9FA),
              ),
              child: const Center(
                child: Icon(
                  Icons.photo_camera_rounded,
                  size: 40,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.accentOrange,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accentOrange.withValues(alpha: 0.3),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Upload Product Photo',
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.primaryNavy,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms);
  }

  // ═══════════════════════════════════════════════════
  //  MAIN SECTION (type, name, sku, category)
  // ═══════════════════════════════════════════════════
  Widget _buildMainSection() {
    return _card(
      children: [
        // Physical / Service toggle
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F1F3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              _typeToggle('Physical', _isPhysical),
              _typeToggle('Service', !_isPhysical),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Product name
        _inputField(
          controller: _nameController,
          label: 'Product Name',
          hint: 'e.g. Figure-8 Straps',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),

        // SKU
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'SKU',
              style: _labelStyle,
            ),
            GestureDetector(
              onTap: _autoGenerateSku,
              child: Text(
                'Auto-generate',
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _textField(_skuController, 'SKU-123456'),
        const SizedBox(height: 14),

        // Category
        _inputField(
          label: 'Category',
          child: _dropdown(
            value: _selectedCategory.isEmpty ? null : _selectedCategory,
            hint: 'Select a category',
            items: _categories,
            onChanged: (v) => setState(() => _selectedCategory = v ?? ''),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  SUPPLIER
  // ═══════════════════════════════════════════════════
  Widget _buildSupplierSection() {
    return _card(
      children: [
        Text('SUPPLIER (OPTIONAL)', style: _labelStyle),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: AppColors.borderLight.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8E8E8),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.store_rounded,
                    size: 20, color: AppColors.textTertiary),
              ),
              const SizedBox(width: 10),
              Text(
                'Choose supplier',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textTertiary),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  PRICING
  // ═══════════════════════════════════════════════════
  Widget _buildPricingSection() {
    return _card(
      children: [
        Row(
          children: [
            Expanded(
              child: _inputField(
                controller: _costController,
                label: 'Cost (per unit)',
                hint: '0.00',
                prefix: 'EGP',
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _inputField(
                controller: _priceController,
                label: 'Selling Price',
                hint: '0.00',
                prefix: 'EGP',
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.info_outline_rounded,
                size: 12, color: AppColors.textTertiary),
            const SizedBox(width: 4),
            Text(
              'Profit margin will be calculated automatically.',
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.textTertiary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  STOCK
  // ═══════════════════════════════════════════════════
  Widget _buildStockSection() {
    return _card(
      children: [
        _inputField(
          label: 'Unit of Measure',
          child: _dropdown(
            value: _selectedUom,
            hint: 'Select',
            items: _uomOptions,
            onChanged: (v) => setState(() => _selectedUom = v ?? 'Pieces'),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _inputField(
                controller: _stockController,
                label: 'Starting Stock',
                hint: '0',
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _inputField(
                controller: _reorderController,
                label: 'Reorder Point',
                hint: '10',
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  RAW MATERIALS
  // ═══════════════════════════════════════════════════
  Widget _buildRawMaterialSection() {
    return _card(
      children: [
        Text('RAW MATERIALS (OPTIONAL)', style: _labelStyle),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'This is a raw material',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _isRawMaterial = !_isRawMaterial);
              },
              child: AnimatedContainer(
                duration: 200.ms,
                width: 44,
                height: 24,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(50),
                  color: _isRawMaterial
                      ? AppColors.accentOrange
                      : const Color(0xFFCCCCCC),
                ),
                child: AnimatedAlign(
                  duration: 200.ms,
                  alignment: _isRawMaterial
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        AnimatedCrossFade(
          duration: 300.ms,
          crossFadeState: _isRawMaterial
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(
              children: [
                Divider(
                    color: AppColors.borderLight.withValues(alpha: 0.5)),
                const SizedBox(height: 10),
                _inputField(
                  label: 'Select Base Material Type',
                  child: _dropdown(
                    value: _baseMaterialType.isEmpty
                        ? null
                        : _baseMaterialType,
                    hint: 'Select type...',
                    items: _materialTypes,
                    onChanged: (v) =>
                        setState(() => _baseMaterialType = v ?? ''),
                  ),
                ),
                const SizedBox(height: 14),
                _inputField(
                  controller: _wasteController,
                  label: 'Waste Percentage estimate',
                  hint: '0',
                  suffix: '%',
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          secondChild: const SizedBox.shrink(),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  OPTIONAL DETAILS TOGGLE
  // ═══════════════════════════════════════════════════
  Widget _buildOptionalToggle() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _showOptional = !_showOptional);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppColors.borderLight.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Optional details',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
            AnimatedRotation(
              turns: _showOptional ? 0.5 : 0,
              duration: 200.ms,
              child: const Icon(Icons.expand_more_rounded,
                  color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  BOTTOM ACTIONS
  // ═══════════════════════════════════════════════════
  Widget _buildBottomActions() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
              color: AppColors.borderLight.withValues(alpha: 0.5)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentOrange,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                shadowColor: AppColors.accentOrange.withValues(alpha: 0.3),
              ),
              child: Text(
                'Save Product',
                style: AppTypography.labelMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () {
              _save();
              // Optionally reset form for another
            },
            child: Text(
              'Save & Add Another',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.primaryNavy,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════
  TextStyle get _labelStyle => AppTypography.captionSmall.copyWith(
        color: AppColors.textTertiary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        fontSize: 10,
      );

  Widget _card({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _inputField({
    TextEditingController? controller,
    String? label,
    String? hint,
    String? prefix,
    String? suffix,
    TextInputType? keyboardType,
    Widget? child,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label.toUpperCase(), style: _labelStyle),
          const SizedBox(height: 6),
        ],
        child ??
            _textField(controller!, hint ?? '',
                prefix: prefix,
                suffix: suffix,
                keyboardType: keyboardType,
                onChanged: onChanged),
      ],
    );
  }

  Widget _textField(
    TextEditingController controller,
    String hint, {
    String? prefix,
    String? suffix,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            AppTypography.bodySmall.copyWith(color: AppColors.textTertiary),
        prefixIcon: prefix != null
            ? Padding(
                padding: const EdgeInsets.only(left: 12, right: 4),
                child: Text(
                  prefix,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textTertiary),
                ),
              )
            : null,
        prefixIconConstraints:
            const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: suffix != null
            ? Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  suffix,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textTertiary),
                ),
              )
            : null,
        suffixIconConstraints:
            const BoxConstraints(minWidth: 0, minHeight: 0),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: AppColors.borderLight.withValues(alpha: 0.7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: AppColors.primaryNavy, width: 1.5),
        ),
      ),
      style: AppTypography.bodySmall.copyWith(color: AppColors.textPrimary),
    );
  }

  Widget _dropdown({
    String? value,
    required String hint,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: AppColors.borderLight.withValues(alpha: 0.7)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(
            hint,
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textTertiary),
          ),
          icon: const Icon(Icons.expand_more_rounded,
              color: AppColors.textTertiary),
          isExpanded: true,
          items: items
              .map((e) => DropdownMenuItem(
                    value: e,
                    child: Text(
                      e,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textPrimary),
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _typeToggle(String label, bool isSelected) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() => _isPhysical = label == 'Physical');
        },
        child: AnimatedContainer(
          duration: 200.ms,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: isSelected
                    ? AppColors.primaryNavy
                    : AppColors.textTertiary,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
