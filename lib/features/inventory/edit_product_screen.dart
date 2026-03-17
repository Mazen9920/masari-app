import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/image_upload_service.dart';
import '../../shared/models/product_model.dart';
import '../../shared/widgets/feature_gate.dart';
import '../../shared/widgets/image_source_picker.dart';
import '../../shared/widgets/discard_changes_dialog.dart';
import '../../shared/utils/safe_pop.dart';

class EditProductScreen extends ConsumerStatefulWidget {
  final String productId;

  const EditProductScreen({super.key, required this.productId});

  @override
  ConsumerState<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends ConsumerState<EditProductScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _skuController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _costController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _reorderController = TextEditingController();
  final TextEditingController _unitController = TextEditingController();
  final TextEditingController _supplierCustomController =
      TextEditingController();

  String? _selectedSupplierId;
  bool _showSupplierCustom = false;
  String _storageLocation = '';
  bool _showAdvanced = false;
  bool _hasChanges = false;
  bool _isSaving = false;

  File? _pickedImage;
  String? _existingImageUrl;
  bool _uploadingImage = false;

  // ── Variant editing state ───────────────────────────────
  List<_EditVariantRow> _editVariantRows = [];

  // ── Breakdown recipe state ──────────────────────────────
  bool _hasBreakdownRecipe = false;
  String? _breakdownSourceVariantId;
  final Map<String, TextEditingController> _breakdownOutputQtys = {};

  // ── Manufacturing mode state ────────────────────────────
  bool _isManufactured = false;

  static const _storageOptions = [
    'Warehouse A - Shelf 3',
    'Warehouse A - Shelf 4',
    'Warehouse B',
    'Display Store',
  ];

  @override
  void initState() {
    super.initState();
    final products = ref.read(inventoryProvider).value ?? [];
    if (products.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.safePop();
      });
      return;
    }
    final product = products.cast<Product?>().firstWhere(
      (p) => p!.id == widget.productId,
      orElse: () => null,
    );
    if (product == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Product not found')),
          );
          context.safePop();
        }
      });
      return;
    }

    // Populate with actual product data
    _nameController.text = product.name;
    _skuController.text = product.sku;
    _categoryController.text = product.category;
    _costController.text = product.costPrice.toStringAsFixed(2);
    _priceController.text = product.sellingPrice.toStringAsFixed(2);
    _reorderController.text = product.reorderPoint.toString();
    _unitController.text = product.unitOfMeasure;
    _storageLocation = _storageOptions.first;
    _existingImageUrl = product.imageUrl;

    // Try to match supplier to the list; if not found, use custom entry
    final suppliers = ref.read(suppliersProvider).value ?? [];
    final matched = suppliers.where((s) => s.name == product.supplier);
    if (matched.isNotEmpty) {
      _selectedSupplierId = matched.first.id;
      _supplierCustomController.clear();
    } else if (product.supplier.isNotEmpty) {
      _showSupplierCustom = true;
      _supplierCustomController.text = product.supplier;
    } else {
      _supplierCustomController.clear();
    }

    // Initialize variant rows
    if (product.variants.length > 1 || product.hasVariants) {
      _editVariantRows = product.variants.map((v) => _EditVariantRow(
        variantId: v.id,
        displayName: v.displayName,
        skuCtrl: TextEditingController(text: v.sku),
        costCtrl: TextEditingController(text: v.costPrice.toStringAsFixed(2)),
        priceCtrl: TextEditingController(text: v.sellingPrice.toStringAsFixed(2)),
        reorderCtrl: TextEditingController(text: v.reorderPoint.toString()),
        currentStock: v.currentStock,
        optionValues: v.optionValues,
      )).toList();
    }

    // Initialize breakdown recipe if exists
    if (product.hasBreakdown) {
      _hasBreakdownRecipe = true;
      _breakdownSourceVariantId = product.breakdownRecipe!.sourceVariantId;
      for (final output in product.breakdownRecipe!.outputs) {
        _breakdownOutputQtys[output.variantId] =
            TextEditingController(text: output.quantityPerUnit.toString());
      }
    }

    // Initialize manufacturing mode
    _isManufactured = product.isManufactured;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _categoryController.dispose();
    _costController.dispose();
    _priceController.dispose();
    _reorderController.dispose();
    _unitController.dispose();
    _supplierCustomController.dispose();
    for (final v in _editVariantRows) {
      v.skuCtrl.dispose();
      v.costCtrl.dispose();
      v.priceCtrl.dispose();
      v.reorderCtrl.dispose();
    }
    for (final c in _breakdownOutputQtys.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _markChanged() {
    if (!_hasChanges) setState(() => _hasChanges = true);
  }

  void _showApplyCostToAllDialog() {
    final ctrl = TextEditingController();
    final currency = ref.read(currencyProvider);
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Set Cost for All Variants',
          style: AppTypography.h3.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
          ],
          decoration: InputDecoration(
            labelText: 'Cost Price',
            prefixText: '$currency ',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, ctrl.text.trim());
            },
            child: Text('Apply',
                style: TextStyle(
                    color: AppColors.primaryNavy,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ).then((cost) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
      if (cost != null && cost.isNotEmpty) {
        for (final row in _editVariantRows) {
          row.costCtrl.text = cost;
        }
        _markChanged();
      }
    });
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      await _doSave();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _doSave() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Product name is required'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }
    final products = ref.read(inventoryProvider).value ?? [];
    if (products.isEmpty) return;
    final original = products.cast<Product?>().firstWhere(
      (p) => p!.id == widget.productId,
      orElse: () => null,
    );
    if (original == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product not found')),
        );
        context.safePop();
      }
      return;
    }

    // Upload new image if picked
    String? imageUrl = _existingImageUrl;
    if (_pickedImage != null) {
      setState(() => _uploadingImage = true);
      final uid = ref.read(authProvider).user?.id ?? '';
      final uploadedUrl = await ImageUploadService.uploadFile(
        file: _pickedImage!,
        storagePath: 'products/$uid/${widget.productId}.jpg',
      );
      // Preserve existing image if upload fails.
      if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
        imageUrl = uploadedUrl;
      }
      if (mounted) setState(() => _uploadingImage = false);
    }

    // Build updated variants
    List<ProductVariant> updatedVariants;

    if (_editVariantRows.isNotEmpty) {
      // Multi-variant: update each variant from its row controllers
      updatedVariants = [];
      for (final row in _editVariantRows) {
        final origVariant = original.variantById(row.variantId);
        if (origVariant != null) {
          // Output variants of a breakdown recipe: preserve WAC from cost layers
          final isOutput = _hasBreakdownRecipe &&
              _breakdownSourceVariantId != null &&
              row.variantId != _breakdownSourceVariantId;
          updatedVariants.add(origVariant.copyWith(
            sku: row.skuCtrl.text.trim(),
            costPrice: isOutput
                ? origVariant.costPrice
                : (double.tryParse(row.costCtrl.text) ?? origVariant.costPrice),
            sellingPrice: double.tryParse(row.priceCtrl.text) ?? origVariant.sellingPrice,
            reorderPoint: int.tryParse(row.reorderCtrl.text) ?? origVariant.reorderPoint,
          ));
        }
      }
      // If no rows matched (shouldn't happen), keep original
      if (updatedVariants.isEmpty) updatedVariants = original.variants;
    } else {
      // Single default variant: update from the main form fields
      final existingVariant = original.variants.isNotEmpty
          ? original.variants.first
          : ProductVariant(
              id: '${widget.productId}_v0',
              optionValues: const {},
              sku: '',
              costPrice: 0,
              sellingPrice: 0,
              currentStock: 0,
            );
      final updatedVariant = existingVariant.copyWith(
        sku: _skuController.text.trim(),
        costPrice: double.tryParse(_costController.text) ?? existingVariant.costPrice,
        sellingPrice: double.tryParse(_priceController.text) ?? existingVariant.sellingPrice,
        reorderPoint: int.tryParse(_reorderController.text) ?? existingVariant.reorderPoint,
      );
      updatedVariants = [updatedVariant, ...original.variants.skip(1)];
    }

    // Build breakdown recipe
    BreakdownRecipe? breakdownRecipe;
    if (_hasBreakdownRecipe && _breakdownSourceVariantId != null) {
      // Validate source variant still exists
      final sourceExists = updatedVariants.any((v) => v.id == _breakdownSourceVariantId);
      if (!sourceExists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Breakdown source variant no longer exists'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
        return;
      }

      final outputs = <BreakdownOutput>[];
      for (final row in _editVariantRows) {
        if (row.variantId == _breakdownSourceVariantId) continue;
        final ctrl = _breakdownOutputQtys[row.variantId];
        final qty = double.tryParse(ctrl?.text ?? '') ?? 0;
        if (qty > 0) {
          outputs.add(BreakdownOutput(
            variantId: row.variantId,
            quantityPerUnit: qty,
          ));
        }
      }
      if (outputs.isNotEmpty) {
        breakdownRecipe = BreakdownRecipe(
          sourceVariantId: _breakdownSourceVariantId!,
          outputs: outputs,
        );
      }
    }

    final updated = original.copyWith(
      name: _nameController.text.trim(),
      category: _categoryController.text.trim().isEmpty
          ? original.category
          : _categoryController.text.trim(),
      breakdownRecipe: breakdownRecipe,
      supplier: _showSupplierCustom
          ? _supplierCustomController.text.trim()
          : (_selectedSupplierId != null
              ? ((ref.read(suppliersProvider).value ?? [])
                      .where((s) => s.id == _selectedSupplierId)
                      .map((s) => s.name)
                      .firstOrNull ?? original.supplier)
              : original.supplier),
      unitOfMeasure: _unitController.text.trim(),
      imageUrl: imageUrl,
      variants: updatedVariants,
      isManufactured: _isManufactured,
    );

    final result = await ref
        .read(inventoryProvider.notifier)
        .updateProduct(widget.productId, updated);
    if (!result.isSuccess) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Failed to update product'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      return;
    }

    HapticFeedback.mediumImpact();
    if (mounted) context.safePop();
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
              // Navigate safely back to inventory list after dialog animation
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) context.go(AppRoutes.inventory);
              });
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await showDiscardChangesDialog(context);
        if (shouldPop && context.mounted) context.safePop();
      },
      child: Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: TextButton(
          onPressed: () => context.safePop(),
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
            if (_editVariantRows.isEmpty) ...[
              _buildPricingSection(),
              const SizedBox(height: 16),
            ],

            // ── Variant Pricing ───────────────────────
            if (_editVariantRows.isNotEmpty) ...[
              _buildVariantPricingSection(),
              const SizedBox(height: 16),
            ],

            // ── Breakdown Recipe ────────────────────────
            if (_editVariantRows.length >= 2 &&
                ref.watch(appSettingsProvider).breakdownEnabled) ...[
              _buildBreakdownRecipeSection(),
              const SizedBox(height: 16),
            ],

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
      ),    ),    );
  }

  // ═══════════════════════════════════════════════════
  //  PRODUCT MEDIA
  // ═══════════════════════════════════════════════════
  Widget _buildMediaSection() {
    final hasLocalImage = _pickedImage != null;
    final hasRemoteImage = _existingImageUrl != null && _existingImageUrl!.isNotEmpty;
    final hasImage = hasLocalImage || hasRemoteImage;

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
        GestureDetector(
          onTap: _pickProductImage,
          child: Container(
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
                // Image or placeholder
                if (hasLocalImage)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(_pickedImage!, fit: BoxFit.cover, width: double.infinity, height: 180),
                  )
                else if (hasRemoteImage)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: CachedNetworkImage(
                      imageUrl: _existingImageUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 180,
                      placeholder: (_, __) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      errorWidget: (_, __, ___) => const Center(child: Icon(Icons.broken_image_rounded, size: 48, color: AppColors.textTertiary)),
                    ),
                  )
                else
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
                // Upload spinner
                if (_uploadingImage)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.black.withValues(alpha: 0.4),
                      ),
                      child: const Center(
                        child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                      ),
                    ),
                  ),
                // Edit overlay
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: hasImage ? Colors.black.withValues(alpha: 0.25) : Colors.transparent,
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
                              hasImage ? 'Change Photo' : 'Add Photo',
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
        ),
      ],
    ).animate().fadeIn(duration: 300.ms);
  }

  Future<void> _pickProductImage() async {
    final source = await showImageSourcePicker(context);
    if (source == null) return;
    final xFile = await ImageUploadService.pickImage(source: source);
    if (xFile == null) return;
    setState(() {
      _pickedImage = File(xFile.path);
      _markChanged();
    });
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
        _inputField(
          label: 'CATEGORY',
          controller: _categoryController,
          hint: 'e.g. Gym Gear, Supplements...',
          onChanged: (_) => _markChanged(),
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
                prefix: ref.watch(appSettingsProvider).currency,
                keyboardType: TextInputType.number,
                onChanged: (_) => _markChanged(),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _inputField(
                label: 'SELLING PRICE',
                controller: _priceController,
                prefix: ref.watch(appSettingsProvider).currency,
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
  //  VARIANT PRICING (multi-variant products)
  // ═══════════════════════════════════════════════════
  Widget _buildVariantPricingSection() {
    final currency = ref.watch(currencyProvider);
    return _card(
      children: [
        Row(
          children: [
            Icon(Icons.style_rounded, size: 18, color: AppColors.accentOrange),
            const SizedBox(width: 8),
            Text(
              'Variant Pricing',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              '${_editVariantRows.length} variant${_editVariantRows.length == 1 ? '' : 's'}',
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // "Apply cost to all" button for multi-variant products
        if (_editVariantRows.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: _showApplyCostToAllDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primaryNavy.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primaryNavy.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.copy_all_rounded, size: 18, color: AppColors.primaryNavy),
                    const SizedBox(width: 8),
                    Text(
                      'Apply cost to all variants',
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.primaryNavy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.arrow_forward_ios_rounded,
                        size: 12, color: AppColors.primaryNavy.withValues(alpha: 0.5)),
                  ],
                ),
              ),
            ),
          ),
        ..._editVariantRows.map((row) {
          final isOutput = _hasBreakdownRecipe &&
              _breakdownSourceVariantId != null &&
              row.variantId != _breakdownSourceVariantId;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.displayName,
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primaryNavy.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${row.currentStock} in stock',
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.primaryNavy,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _inputField(
                  label: 'SKU',
                  controller: row.skuCtrl,
                  onChanged: (_) => _markChanged(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _inputField(
                        label: isOutput ? 'COST PRICE (from breakdown)' : 'COST PRICE',
                        controller: row.costCtrl,
                        prefix: currency,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => _markChanged(),
                        readOnly: isOutput,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _inputField(
                        label: 'SELLING PRICE',
                        controller: row.priceCtrl,
                        prefix: currency,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => _markChanged(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _inputField(
                  label: 'REORDER POINT',
                  controller: row.reorderCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _markChanged(),
                ),
              ],
            ),
          );
        }),
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
  //  BREAKDOWN RECIPE
  // ═══════════════════════════════════════════════════
  Widget _buildBreakdownRecipeSection() {
    return _card(
      children: [
        Row(
          children: [
            Icon(
              Icons.call_split_rounded,
              size: 18,
              color: _hasBreakdownRecipe
                  ? AppColors.primaryNavy
                  : AppColors.textTertiary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Breakdown Recipe',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Switch.adaptive(
              value: _hasBreakdownRecipe,
              activeColor: AppColors.primaryNavy,
              onChanged: (val) {
                setState(() {
                  _hasBreakdownRecipe = val;
                  if (!val) {
                    _breakdownSourceVariantId = null;
                    // Do not dispose controllers here — they may still be
                    // referenced by the widget tree during the ongoing
                    // flutter_animate fade. dispose() will clean them up.
                  }
                  _markChanged();
                });
              },
            ),
          ],
        ),
        if (!_hasBreakdownRecipe)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Define how one variant breaks down into others',
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ),
        if (_hasBreakdownRecipe) ...[
          const SizedBox(height: 12),
          Text(
            'SOURCE VARIANT',
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.borderLight.withValues(alpha: 0.5)),
              color: const Color(0xFFF8F9FA),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _breakdownSourceVariantId,
                isExpanded: true,
                hint: Text(
                  'Select source variant',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textTertiary),
                ),
                items: _editVariantRows.map((row) {
                  return DropdownMenuItem<String>(
                    value: row.variantId,
                    child: Text(row.displayName,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textPrimary)),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() => _breakdownSourceVariantId = val);
                  _markChanged();
                },
              ),
            ),
          ),
          if (_breakdownSourceVariantId != null) ...[
            const SizedBox(height: 16),
            Text(
              'OUTPUT VARIANTS (qty per 1 source unit)',
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 8),
            ..._editVariantRows
                .where((row) => row.variantId != _breakdownSourceVariantId)
                .map((row) {
              _breakdownOutputQtys.putIfAbsent(
                  row.variantId, () => TextEditingController());
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        row.displayName,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _inputField(
                        label: '',
                        controller: _breakdownOutputQtys[row.variantId]!,
                        hint: 'Qty',
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => _markChanged(),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 120.ms);
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
                  // Supplier — live list + custom toggle
                  Text(
                    'SUPPLIER',
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _pillToggle('From List', !_showSupplierCustom, () {
                        setState(() => _showSupplierCustom = false);
                      }),
                      const SizedBox(width: 8),
                      _pillToggle('Custom', _showSupplierCustom, () {
                        setState(() => _showSupplierCustom = true);
                      }),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Builder(builder: (context) {
                    final suppliers = ref.watch(suppliersProvider).value ?? [];
                    if (_showSupplierCustom) {
                      return TextField(
                        controller: _supplierCustomController,
                        onChanged: (_) => _markChanged(),
                        decoration: InputDecoration(
                          hintText: 'Type supplier name...',
                          hintStyle: AppTypography.bodySmall
                              .copyWith(color: AppColors.textTertiary),
                          filled: true,
                          fillColor: const Color(0xFFF8F9FA),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: AppColors.borderLight
                                    .withValues(alpha: 0.5)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: AppColors.borderLight
                                    .withValues(alpha: 0.5)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: AppColors.accentOrange, width: 1.5),
                          ),
                        ),
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textPrimary),
                      );
                    }
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color:
                                AppColors.borderLight.withValues(alpha: 0.5)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedSupplierId,
                          hint: Text(
                            suppliers.isEmpty
                                ? 'No suppliers yet'
                                : 'Choose supplier',
                            style: AppTypography.bodySmall
                                .copyWith(color: AppColors.textTertiary),
                          ),
                          icon: const Icon(Icons.expand_more_rounded,
                              color: AppColors.textTertiary),
                          isExpanded: true,
                          items: suppliers
                              .map((s) => DropdownMenuItem(
                                    value: s.id,
                                    child: Text(
                                      s.name,
                                      style: AppTypography.bodySmall.copyWith(
                                          color: AppColors.textPrimary),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            setState(() => _selectedSupplierId = v);
                            _markChanged();
                          },
                        ),
                      ),
                    );
                  }),

                  // ── Manufacturing mode (Pro) ──
                  const SizedBox(height: 18),
                  FeatureGate(
                    feature: GrowthFeature.manufacturingMode,
                    requiredTier: SubscriptionTier.pro,
                    inline: true,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.borderLight.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.precision_manufacturing_rounded,
                                color: Color(0xFF8B5CF6), size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Manufactured Product',
                                  style: AppTypography.labelMedium.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Goods receipts adjust stock only — cost is managed separately',
                                  style: TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch.adaptive(
                            value: _isManufactured,
                            activeColor: const Color(0xFF8B5CF6),
                            onChanged: (val) {
                              setState(() => _isManufactured = val);
                              _markChanged();
                            },
                          ),
                        ],
                      ),
                    ),
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

  Widget _pillToggle(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryNavy : AppColors.backgroundLight,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: isSelected ? AppColors.primaryNavy : AppColors.borderLight,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _inputField({
    required String label,
    required TextEditingController controller,
    String? hint,
    String? prefix,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
    bool readOnly = false,
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
          readOnly: readOnly,
          enabled: !readOnly,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: hint != null
                ? AppTypography.bodySmall.copyWith(color: AppColors.textTertiary)
                : null,
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

/// Helper for variant editing rows in the edit product screen.
class _EditVariantRow {
  final String variantId;
  final String displayName;
  final TextEditingController skuCtrl;
  final TextEditingController costCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController reorderCtrl;
  final int currentStock;
  final Map<String, String> optionValues;

  _EditVariantRow({
    required this.variantId,
    required this.displayName,
    required this.skuCtrl,
    required this.costCtrl,
    required this.priceCtrl,
    required this.reorderCtrl,
    required this.currentStock,
    required this.optionValues,
  });
}
