import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';

class EditProductScreen extends ConsumerStatefulWidget {
  final String productId;

  const EditProductScreen({super.key, required this.productId});

  @override
  ConsumerState<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends ConsumerState<EditProductScreen> {
  late TextEditingController _nameController;
  late TextEditingController _skuController;
  late TextEditingController _costController;
  late TextEditingController _priceController;
  late TextEditingController _reorderController;
  late TextEditingController _unitController;

  String _selectedCategory = '';
  String _storageLocation = 'Warehouse A - Shelf 3';
  bool _isRawMaterial = false;
  String _selectedSupplier = '';
  bool _showAdvanced = false;
  bool _hasChanges = false;

  static const _categories = [
    'Gym Gear',
    'Weights',
    'Yoga',
    'Supplements',
    'Accessories',
    'Clothing',
    'Electronics',
  ];

  static const _storageOptions = [
    'Warehouse A - Shelf 3',
    'Warehouse A - Shelf 4',
    'Warehouse B',
    'Display Store',
  ];

  static const _supplierOptions = [
    'IronFit',
    'HeavyLift',
    'ZenLife',
    'GymSupps',
  ];

  @override
  void initState() {
    super.initState();
    final products = ref.read(inventoryProvider);
    final product = products.firstWhere(
      (p) => p.id == widget.productId,
      orElse: () => products.first,
    );

    _nameController = TextEditingController(text: product.name);
    _skuController = TextEditingController(text: product.sku);
    _costController =
        TextEditingController(text: product.costPrice.toStringAsFixed(2));
    _priceController =
        TextEditingController(text: product.sellingPrice.toStringAsFixed(2));
    _reorderController =
        TextEditingController(text: product.reorderPoint.toString());
    _unitController = TextEditingController(text: product.unitOfMeasure);

    _selectedCategory = product.category;
    _selectedSupplier = product.supplier;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _costController.dispose();
    _priceController.dispose();
    _reorderController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  void _markChanged() {
    if (!_hasChanges) setState(() => _hasChanges = true);
  }

  void _save() {
    final products = ref.read(inventoryProvider);
    final original = products.firstWhere(
      (p) => p.id == widget.productId,
      orElse: () => products.first,
    );

    final updated = original.copyWith(
      name: _nameController.text.trim(),
      sku: _skuController.text.trim(),
      category: _selectedCategory,
      supplier: _selectedSupplier,
      costPrice: double.tryParse(_costController.text) ?? original.costPrice,
      sellingPrice:
          double.tryParse(_priceController.text) ?? original.sellingPrice,
      reorderPoint:
          int.tryParse(_reorderController.text) ?? original.reorderPoint,
      unitOfMeasure: _unitController.text.trim(),
    );

    ref.read(inventoryProvider.notifier).updateProduct(widget.productId, updated);
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop();
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Product?',
          style: AppTypography.h3.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'This action cannot be undone. The product and its movement history will be permanently removed.',
          style: AppTypography.bodySmall
              .copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: AppTypography.labelMedium
                  .copyWith(color: AppColors.textTertiary),
            ),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(inventoryProvider.notifier)
                  .removeProduct(widget.productId);
              HapticFeedback.mediumImpact();
              Navigator.pop(ctx); // close dialog
              Navigator.pop(context); // close edit
              Navigator.pop(context); // close detail
            },
            child: Text(
              'Delete',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        leadingWidth: 80,
        title: Text(
          'Edit Product',
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.primaryNavy,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              'Save',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.accentOrange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        child: Column(
          children: [
            // ── Product Media ──────────────────────────
            _buildMediaSection(),
            const SizedBox(height: 16),

            // ── Basic Information ──────────────────────
            _buildBasicInfoSection(),
            const SizedBox(height: 16),

            // ── Pricing Strategy ──────────────────────
            _buildPricingSection(),
            const SizedBox(height: 16),

            // ── Stock Configuration ───────────────────
            _buildStockSection(),
            const SizedBox(height: 16),

            // ── Advanced Settings ─────────────────────
            _buildAdvancedSection(),
            const SizedBox(height: 24),

            // ── Delete ────────────────────────────────
            _buildDeleteButton(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  PRODUCT MEDIA
  // ═══════════════════════════════════════════════════
  Widget _buildMediaSection() {
    return _card(
      children: [
        Text(
          'Product Media',
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          height: 180,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: const Color(0xFFF0F1F3),
            border: Border.all(
                color: AppColors.borderLight.withValues(alpha: 0.5)),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image_rounded,
                        size: 48,
                        color: AppColors.textTertiary.withValues(alpha: 0.4)),
                    const SizedBox(height: 8),
                    Text(
                      'Product Image',
                      style: AppTypography.captionSmall.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Edit overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.black.withValues(alpha: 0.25),
                  ),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.photo_camera_rounded,
                              size: 16, color: AppColors.textPrimary),
                          const SizedBox(width: 6),
                          Text(
                            'Edit Photo',
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms);
  }

  // ═══════════════════════════════════════════════════
  //  BASIC INFORMATION
  // ═══════════════════════════════════════════════════
  Widget _buildBasicInfoSection() {
    return _card(
      children: [
        Text(
          'Basic Information',
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        _inputField(
          label: 'PRODUCT NAME',
          controller: _nameController,
          onChanged: (_) => _markChanged(),
        ),
        const SizedBox(height: 14),
        _inputField(
          label: 'SKU',
          controller: _skuController,
          onChanged: (_) => _markChanged(),
        ),
        const SizedBox(height: 14),
        _dropdownField(
          label: 'CATEGORY',
          value: _selectedCategory.isEmpty ? null : _selectedCategory,
          hint: 'Select category',
          items: _categories,
          onChanged: (v) {
            setState(() => _selectedCategory = v ?? '');
            _markChanged();
          },
        ),
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 50.ms);
  }

  // ═══════════════════════════════════════════════════
  //  PRICING
  // ═══════════════════════════════════════════════════
  Widget _buildPricingSection() {
    return _card(
      children: [
        Text(
          'Pricing Strategy',
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _inputField(
                label: 'COST PRICE',
                controller: _costController,
                prefix: 'EGP',
                keyboardType: TextInputType.number,
                onChanged: (_) => _markChanged(),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _inputField(
                label: 'SELLING PRICE',
                controller: _priceController,
                prefix: 'EGP',
                keyboardType: TextInputType.number,
                onChanged: (_) => _markChanged(),
              ),
            ),
          ],
        ),
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 100.ms);
  }

  // ═══════════════════════════════════════════════════
  //  STOCK CONFIG
  // ═══════════════════════════════════════════════════
  Widget _buildStockSection() {
    return _card(
      children: [
        Text(
          'Stock Configuration',
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _inputField(
                label: 'UNIT',
                controller: _unitController,
                onChanged: (_) => _markChanged(),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _inputField(
                label: 'REORDER POINT',
                controller: _reorderController,
                keyboardType: TextInputType.number,
                onChanged: (_) => _markChanged(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _dropdownField(
          label: 'STORAGE LOCATION',
          value: _storageLocation,
          hint: 'Select location',
          items: _storageOptions,
          onChanged: (v) {
            setState(() => _storageLocation = v ?? _storageLocation);
            _markChanged();
          },
        ),
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 150.ms);
  }

  // ═══════════════════════════════════════════════════
  //  ADVANCED SETTINGS
  // ═══════════════════════════════════════════════════
  Widget _buildAdvancedSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
        children: [
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _showAdvanced = !_showAdvanced);
            },
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Advanced Settings',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  AnimatedRotation(
                    turns: _showAdvanced ? 0.5 : 0,
                    duration: 200.ms,
                    child: const Icon(Icons.expand_more_rounded,
                        color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: 300.ms,
            crossFadeState: _showAdvanced
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Container(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                      color: AppColors.borderLight.withValues(alpha: 0.5)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 14),
                  // Raw material toggle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Raw Material',
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Track as component for manufacturing',
                            style: AppTypography.captionSmall.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() => _isRawMaterial = !_isRawMaterial);
                          _markChanged();
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
                  const SizedBox(height: 16),
                  _dropdownField(
                    label: 'SUPPLIER',
                    value: _selectedSupplier.isEmpty
                        ? null
                        : _selectedSupplier,
                    hint: 'Select Supplier...',
                    items: _supplierOptions,
                    onChanged: (v) {
                      setState(() => _selectedSupplier = v ?? '');
                      _markChanged();
                    },
                  ),
                ],
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 200.ms);
  }

  // ═══════════════════════════════════════════════════
  //  DELETE BUTTON
  // ═══════════════════════════════════════════════════
  Widget _buildDeleteButton() {
    return GestureDetector(
      onTap: _confirmDelete,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_outline_rounded,
                size: 18, color: AppColors.danger),
            const SizedBox(width: 6),
            Text(
              'Delete Product',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  REUSABLE HELPERS
  // ═══════════════════════════════════════════════════
  Widget _card({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
    required String label,
    required TextEditingController controller,
    String? prefix,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.captionSmall.copyWith(
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          onChanged: onChanged,
          decoration: InputDecoration(
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
            filled: true,
            fillColor: const Color(0xFFF8F9FA),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: AppColors.borderLight.withValues(alpha: 0.5)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: AppColors.borderLight.withValues(alpha: 0.5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.accentOrange, width: 1.5),
            ),
          ),
          style: AppTypography.bodySmall
              .copyWith(color: AppColors.textPrimary),
        ),
      ],
    );
  }

  Widget _dropdownField({
    required String label,
    String? value,
    required String hint,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.captionSmall.copyWith(
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.borderLight.withValues(alpha: 0.5)),
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
        ),
      ],
    );
  }
}
