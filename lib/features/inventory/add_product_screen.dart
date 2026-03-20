import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/image_upload_service.dart';
import '../../shared/models/product_model.dart';
import '../../shared/widgets/image_source_picker.dart';

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
  String _selectedUom = 'pcs';
  String _selectedSupplier = '';
  bool _isRawMaterial = false;
  String _baseMaterialType = '';
  bool _showOptional = false;

  // Photo
  File? _pickedImage;
  bool _uploadingImage = false;
  bool _isSaving = false;

  // Variants
  final List<ProductOption> _options = [];
  List<_AddVariantRow> _variantRows = [];

  static const _uomOptions = [
    'pcs',
    'kg',
    'liters',
    'boxes',
  ];

  static const _materialTypes = [
    'Fabric',
    'Plastic',
    'Wood',
    'Metal',
  ];

  bool get _canSave => _nameController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(appSettingsProvider);
    _selectedUom = settings.defaultUnit;
    _reorderController.text = settings.alertThreshold.toString();
  }

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
    final parts = name
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
    final first = parts.isNotEmpty ? parts[0] : name;
    final second = parts.length >= 2 ? parts[1] : '';
    final firstPrefix = first.substring(0, first.length >= 3 ? 3 : first.length);
    final secondPrefix = second.isNotEmpty
      ? second.substring(0, second.length >= 3 ? 3 : second.length)
      : '';
    final prefix = secondPrefix.isNotEmpty
      ? '$firstPrefix-$secondPrefix'
      : name.substring(0, name.length >= 6 ? 6 : name.length);
    _skuController.text = prefix;
    HapticFeedback.lightImpact();
  }

  Future<void> _pickProductImage() async {
    final source = await showImageSourcePicker(context);
    if (source == null) return;
    final xFile = await ImageUploadService.pickImage(source: source);
    if (xFile == null) return;
    setState(() => _pickedImage = File(xFile.path));
  }

  void _regenerateVariantRows() {
    if (_options.isEmpty || _options.any((o) => o.values.isEmpty)) {
      _variantRows = [];
      return;
    }
    // Cartesian product of all option values
    List<Map<String, String>> combos = [{}];
    for (final opt in _options) {
      final expanded = <Map<String, String>>[];
      for (final combo in combos) {
        for (final val in opt.values) {
          expanded.add({...combo, opt.name: val});
        }
      }
      combos = expanded;
    }
    _variantRows = combos.map((combo) {
      final displayName = combo.values.join(' / ');
      // Try to reuse existing row if it matches
      final existing = _variantRows.cast<_AddVariantRow?>().firstWhere(
        (r) => r!.displayName == displayName,
        orElse: () => null,
      );
      return existing ?? _AddVariantRow(
        displayName: displayName,
        optionValues: combo,
        skuCtrl: TextEditingController(),
        costCtrl: TextEditingController(),
        priceCtrl: TextEditingController(),
        stockCtrl: TextEditingController(text: '0'),
        reorderCtrl: TextEditingController(
            text: ref.read(appSettingsProvider).alertThreshold.toString()),
      );
    }).toList();
  }

  void _save() async {
    if (_isSaving) return;
    if (!_canSave) {
      HapticFeedback.heavyImpact();
      return;
    }

    // Validate numeric inputs are non-negative
    if (_variantRows.isEmpty) {
      final cost = double.tryParse(_costController.text) ?? 0;
      final price = double.tryParse(_priceController.text) ?? 0;
      final stock = int.tryParse(_stockController.text) ?? 0;
      if (cost < 0 || price < 0 || stock < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cost, price, and stock must not be negative'),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }
    } else {
      for (final row in _variantRows) {
        final cost = double.tryParse(row.costCtrl.text) ?? 0;
        final price = double.tryParse(row.priceCtrl.text) ?? 0;
        final stock = int.tryParse(row.stockCtrl.text) ?? 0;
        if (cost < 0 || price < 0 || stock < 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${row.displayName}: cost, price, and stock must not be negative'),
              backgroundColor: AppColors.danger,
            ),
          );
          return;
        }
      }
    }

    // M2: Warn if cost exceeds selling price
    bool hasCostWarning = false;
    if (_variantRows.isEmpty) {
      final cost = double.tryParse(_costController.text) ?? 0;
      final price = double.tryParse(_priceController.text) ?? 0;
      if (cost > 0 && price > 0 && cost > price) hasCostWarning = true;
    } else {
      for (final row in _variantRows) {
        final cost = double.tryParse(row.costCtrl.text) ?? 0;
        final price = double.tryParse(row.priceCtrl.text) ?? 0;
        if (cost > 0 && price > 0 && cost > price) {
          hasCostWarning = true;
          break;
        }
      }
    }
    if (hasCostWarning) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cost exceeds selling price'),
          content: const Text(
            'One or more variants have a cost price higher than '
            'the selling price. This means you would sell at a loss. '
            'Continue anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              child: const Text('Save Anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
      if (!mounted) return;
    }

    // M3: Check SKU uniqueness against loaded products
    final skuToCheck = _skuController.text.trim();
    if (skuToCheck.isNotEmpty) {
      final existingProducts = ref.read(inventoryProvider).value ?? [];
      final skuExists = existingProducts.any((p) =>
        p.variants.any((v) => v.sku.toLowerCase() == skuToCheck.toLowerCase()),
      );
      if (skuExists) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Duplicate SKU'),
            content: Text('SKU "$skuToCheck" is already used by another product. Save anyway?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Save Anyway'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
        if (!mounted) return;
      }
    }

    setState(() => _isSaving = true);

    final sku = _skuController.text.trim().isEmpty
        ? 'SKU-${DateTime.now().millisecondsSinceEpoch % 100000}'
        : _skuController.text.trim();

    final productId = DateTime.now().millisecondsSinceEpoch.toString();

    // Upload image if picked
    String? imageUrl;
    if (_pickedImage != null) {
      setState(() => _uploadingImage = true);
      final uid = ref.read(authProvider).user?.id ?? '';
      imageUrl = await ImageUploadService.uploadFile(
        file: _pickedImage!,
        storagePath: 'products/$uid/$productId.jpg',
      );
      if (mounted) setState(() => _uploadingImage = false);
    }

    // Build variants
    List<ProductVariant> variants;
    List<ProductOption> options;

    if (_variantRows.isNotEmpty) {
      options = _options;
      variants = _variantRows.asMap().entries.map((entry) {
        final i = entry.key;
        final row = entry.value;
        final variantSku = row.skuCtrl.text.trim().isEmpty
            ? '$sku-v$i'
            : row.skuCtrl.text.trim();
        return ProductVariant(
          id: '${productId}_v$i',
          optionValues: row.optionValues,
          sku: variantSku,
          costPrice: double.tryParse(row.costCtrl.text) ?? 0,
          sellingPrice: double.tryParse(row.priceCtrl.text) ?? 0,
          currentStock: int.tryParse(row.stockCtrl.text) ?? 0,
          reorderPoint: int.tryParse(row.reorderCtrl.text) ?? 10,
        );
      }).toList();
    } else {
      options = const [];
      variants = [
        ProductVariant(
          id: '${productId}_v0',
          sku: sku,
          costPrice: double.tryParse(_costController.text) ?? 0,
          sellingPrice: double.tryParse(_priceController.text) ?? 0,
          currentStock: int.tryParse(_stockController.text) ?? 0,
          reorderPoint: int.tryParse(_reorderController.text) ?? 10,
        ),
      ];
    }

    final product = Product(
      id: productId,
      userId: '', // set by provider/repository
      name: _nameController.text.trim(),
      category: _selectedCategory.isEmpty ? 'Uncategorized' : _selectedCategory,
      supplier: _selectedSupplier,
      unitOfMeasure: _selectedUom,
      imageUrl: imageUrl,
      options: options,
      variants: variants,
    );

    final result = await ref.read(inventoryProvider.notifier).addProduct(product);
    if (!result.isSuccess) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Failed to save product'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
      return;
    }

    HapticFeedback.mediumImpact();
    if (mounted) {
      setState(() => _isSaving = false);
      Navigator.of(context).pop();
    }
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
          Opacity(
            opacity: _canSave ? 1.0 : 0.5,
            child: TextButton(
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

                  // Variants
                  _buildVariantsSection(),
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
    final hasImage = _pickedImage != null;
    return Column(
      children: [
        GestureDetector(
          onTap: _pickProductImage,
          child: Stack(
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
                child: hasImage
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.file(_pickedImage!, fit: BoxFit.cover, width: 120, height: 120),
                      )
                    : const Center(
                        child: Icon(
                          Icons.photo_camera_rounded,
                          size: 40,
                          color: AppColors.textTertiary,
                        ),
                      ),
              ),
              if (_uploadingImage)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.black.withValues(alpha: 0.4),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      ),
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
                  child: Icon(hasImage ? Icons.edit : Icons.add, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          hasImage ? 'Change Photo' : 'Upload Product Photo',
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
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primaryNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.primaryNavy.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  'Auto-generate',
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.primaryNavy,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
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
          child: Builder(
            builder: (_) {
              final categoriesAsync = ref.watch(categoriesProvider);
              final categoryNames = categoriesAsync.value
                      ?.map((c) => c.name)
                      .toList() ??
                  [];
              return _dropdown(
                value: _selectedCategory.isEmpty ? null : _selectedCategory,
                hint: 'Select a category',
                items: categoryNames,
                onChanged: (v) => setState(() => _selectedCategory = v ?? ''),
              );
            },
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
        GestureDetector(
          onTap: _showSupplierPicker,
          child: Container(
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
                    color: _selectedSupplier.isEmpty
                        ? const Color(0xFFE8E8E8)
                        : AppColors.primaryNavy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(Icons.store_rounded,
                      size: 20,
                      color: _selectedSupplier.isEmpty
                          ? AppColors.textTertiary
                          : AppColors.primaryNavy),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _selectedSupplier.isEmpty
                        ? 'Choose supplier'
                        : _selectedSupplier,
                    style: AppTypography.labelMedium.copyWith(
                      color: _selectedSupplier.isEmpty
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                      fontWeight: _selectedSupplier.isEmpty
                          ? FontWeight.w500
                          : FontWeight.w600,
                    ),
                  ),
                ),
                if (_selectedSupplier.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(() => _selectedSupplier = ''),
                    child: const Icon(Icons.close_rounded,
                        color: AppColors.textTertiary, size: 18),
                  )
                else
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showSupplierPicker() {
    final suppliersAsync = ref.read(suppliersProvider);
    final suppliers = suppliersAsync.value ?? [];
    if (suppliers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No suppliers found. Add one first.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Select Supplier',
                      style: AppTypography.h3.copyWith(
                        color: AppColors.primaryNavy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.textTertiary, size: 22),
                    ),
                  ],
                ),
              ),
              Divider(
                  height: 1,
                  color: AppColors.borderLight.withValues(alpha: 0.5)),
              ...suppliers.map((sup) {
                final selected = sup.name == _selectedSupplier;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      setState(() => _selectedSupplier = sup.name);
                      HapticFeedback.lightImpact();
                      Navigator.pop(ctx);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              sup.name,
                              style: AppTypography.labelMedium.copyWith(
                                color: selected
                                    ? AppColors.primaryNavy
                                    : AppColors.textPrimary,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (selected)
                            const Icon(Icons.check_rounded,
                                color: AppColors.accentOrange, size: 20),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  PRICING
  // ═══════════════════════════════════════════════════
  Widget _buildPricingSection() {
    final currency = ref.watch(currencyProvider);
    return _card(
      children: [
        Row(
          children: [
            Expanded(
              child: _inputField(
                controller: _costController,
                label: 'Cost (per unit)',
                hint: '0.00',
                prefix: currency,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _inputField(
                controller: _priceController,
                label: 'Selling Price',
                hint: '0.00',
                prefix: currency,
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
  //  VARIANTS
  // ═══════════════════════════════════════════════════
  Widget _buildVariantsSection() {
    final currency = ref.watch(currencyProvider);
    return _card(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('PRODUCT VARIANTS', style: _labelStyle),
            if (_options.length < 3)
              GestureDetector(
                onTap: _showAddOptionDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primaryNavy.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.primaryNavy.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, size: 14, color: AppColors.primaryNavy),
                      const SizedBox(width: 4),
                      Text(
                        'Add Option',
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.primaryNavy,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (_options.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Add options like Color, Size to create variants.',
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textTertiary,
              fontSize: 11,
            ),
          ),
        ],
        ..._options.asMap().entries.map((entry) {
          final idx = entry.key;
          final opt = entry.value;
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          opt.name,
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _options.removeAt(idx);
                            _regenerateVariantRows();
                          });
                        },
                        child: Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ...opt.values.map((val) => Chip(
                        label: Text(val, style: const TextStyle(fontSize: 12)),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        onDeleted: () {
                          setState(() {
                            final newValues = List<String>.from(opt.values)..remove(val);
                            _options[idx] = opt.copyWith(values: newValues);
                            _regenerateVariantRows();
                          });
                        },
                        backgroundColor: Colors.white,
                        side: BorderSide(color: AppColors.borderLight),
                        visualDensity: VisualDensity.compact,
                      )),
                      GestureDetector(
                        onTap: () => _showAddValueDialog(idx),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.4), style: BorderStyle.solid),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add, size: 14, color: AppColors.accentOrange),
                              const SizedBox(width: 4),
                              Text('Add', style: TextStyle(color: AppColors.accentOrange, fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        if (_variantRows.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.style_rounded, size: 16, color: AppColors.accentOrange),
              const SizedBox(width: 6),
              Text(
                '${_variantRows.length} variant${_variantRows.length == 1 ? '' : 's'} generated',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._variantRows.map((row) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.displayName, style: AppTypography.labelMedium.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _inputField(label: 'SKU', controller: row.skuCtrl),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _inputField(label: 'COST PRICE', controller: row.costCtrl, prefix: currency, keyboardType: TextInputType.number)),
                  const SizedBox(width: 10),
                  Expanded(child: _inputField(label: 'SELLING PRICE', controller: row.priceCtrl, prefix: currency, keyboardType: TextInputType.number)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _inputField(label: 'START STOCK', controller: row.stockCtrl, keyboardType: TextInputType.number)),
                  const SizedBox(width: 10),
                  Expanded(child: _inputField(label: 'REORDER POINT', controller: row.reorderCtrl, keyboardType: TextInputType.number)),
                ]),
              ],
            ),
          )),
        ],
      ],
    );
  }

  void _showAddOptionDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Add Option', style: AppTypography.h3),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'e.g. Color, Size, Material',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: AppColors.textTertiary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryNavy,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty && !_options.any((o) => o.name.toLowerCase() == name.toLowerCase())) {
                setState(() {
                  _options.add(ProductOption(name: name, values: []));
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAddValueDialog(int optionIndex) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Add ${_options[optionIndex].name} Value', style: AppTypography.h3),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'e.g. Red, Large, Cotton',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: AppColors.textTertiary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryNavy,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final val = ctrl.text.trim();
              if (val.isNotEmpty) {
                final opt = _options[optionIndex];
                if (!opt.values.contains(val)) {
                  setState(() {
                    _options[optionIndex] = opt.copyWith(values: [...opt.values, val]);
                    _regenerateVariantRows();
                  });
                }
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
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
            onChanged: (v) => setState(() => _selectedUom = v ?? 'pcs'),
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

class _AddVariantRow {
  final String displayName;
  final Map<String, String> optionValues;
  final TextEditingController skuCtrl;
  final TextEditingController costCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController stockCtrl;
  final TextEditingController reorderCtrl;

  _AddVariantRow({
    required this.displayName,
    required this.optionValues,
    required this.skuCtrl,
    required this.costCtrl,
    required this.priceCtrl,
    required this.stockCtrl,
    required this.reorderCtrl,
  });
}
