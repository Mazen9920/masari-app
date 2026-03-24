import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../shared/models/product_model.dart';
import '../../shared/widgets/discard_changes_dialog.dart';
import '../../shared/utils/safe_pop.dart';
import '../../l10n/app_localizations.dart';

class AddMaterialScreen extends ConsumerStatefulWidget {
  const AddMaterialScreen({super.key});

  @override
  ConsumerState<AddMaterialScreen> createState() => _AddMaterialScreenState();
}

class _AddMaterialScreenState extends ConsumerState<AddMaterialScreen> {
  AppLocalizations get l10n => AppLocalizations.of(context)!;
  final _nameController = TextEditingController();
  final _skuController = TextEditingController();
  final _categoryController = TextEditingController();
  final _costController = TextEditingController();
  final _stockController = TextEditingController();
  final _reorderController = TextEditingController(text: '10');
  final _uomController = TextEditingController(text: 'kg');
  final _supplierCustomController = TextEditingController();
  final _wasteController = TextEditingController();
  final _notesController = TextEditingController();
  final _locationController = TextEditingController();

  String? _selectedSupplierId;
  bool _showSupplierCustom = false;
  String _baseMaterialType = '';
  bool _showOptional = false;

  static const _uomPresets = ['kg',
     'g',
     'liters',
     'meters',
     'pcs',
     'rolls',
     'sheets',
  ];

  static const _materialTypes = [
     'Fabric',
     'Plastic',
     'Wood',
     'Metal',
     'Liquid',
     'Paper',
     'Other',
  ];

  Map<String, String> get _materialTypeLabels => {
    'Fabric': l10n.materialFabric,
    'Plastic': l10n.materialPlastic,
    'Wood': l10n.materialWood,
    'Metal': l10n.materialMetal,
    'Liquid': l10n.materialLiquid,
    'Paper': l10n.materialPaper,
    'Other': l10n.materialOther,
  };

  bool get _canSave => _nameController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _categoryController.dispose();
    _costController.dispose();
    _stockController.dispose();
    _reorderController.dispose();
    _uomController.dispose();
    _supplierCustomController.dispose();
    _wasteController.dispose();
    _notesController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _autoGenerateSku() {
    final name = _nameController.text.trim().toUpperCase();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.enterMaterialNameFirst)),
      );
      return;
    }
    final parts = name
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    final timestamp = DateTime.now().millisecondsSinceEpoch % 10000;
    String prefix;
    if (parts.length >= 2) {
      final first = parts[0];
      final second = parts[1];
      final firstPrefix = first.substring(0, first.length >= 3 ? 3 : first.length);
      final secondPrefix = second.substring(0, second.length >= 3 ? 3 : second.length);
      prefix = '$firstPrefix-$secondPrefix';
    } else {
      prefix = name.substring(0, name.length >= 6 ? 6 : name.length);
    }
    setState(() {
      _skuController.text = 'MAT-$prefix-$timestamp';
    });
    HapticFeedback.lightImpact();
  }

  String get _resolvedUom => _uomController.text.trim().isNotEmpty
      ? _uomController.text.trim()
      :  'kg';

  String get _resolvedSupplier {
    if (_showSupplierCustom) return _supplierCustomController.text.trim();
    if (_selectedSupplierId != null) {
      final suppliers = ref.read(suppliersProvider).value ?? [];
      if (suppliers.isNotEmpty) {
        return suppliers
            .firstWhere((s) => s.id == _selectedSupplierId,
                orElse: () => suppliers.first)
            .name;
      }
    }
    return '';
  }

  Future<void> _save() async {
    if (!_canSave) {
      HapticFeedback.heavyImpact();
      return;
    }

    final productId = DateTime.now().millisecondsSinceEpoch.toString();
    final sku = _skuController.text.trim().isEmpty
        ? 'MAT-${DateTime.now().millisecondsSinceEpoch % 100000}'
        : _skuController.text.trim();

    final defaultVariant = ProductVariant(
      id: '${productId}_v0',
      optionValues: const {},
      sku: sku,
      costPrice: double.tryParse(_costController.text) ?? 0,
      sellingPrice: 0,
      currentStock: int.tryParse(_stockController.text) ?? 0,
      reorderPoint: int.tryParse(_reorderController.text) ?? 10,
    );

    final product = Product(
      id: productId,
      userId: ref.read(authProvider).user?.id ?? '',
      name: _nameController.text.trim(),
      category: _categoryController.text.trim().isEmpty
          ? l10n.rawMaterial
          : _categoryController.text.trim(),
      supplier: _resolvedSupplier,
      unitOfMeasure: _resolvedUom,
      isMaterial: true,
      baseMaterialType: _baseMaterialType.isEmpty ? null : _baseMaterialType,
      scrapPercentage: (double.tryParse(_wasteController.text) ?? 0).clamp(0, 100).toDouble(),
      variants: [defaultVariant],
    );

    final result = await ref.read(inventoryProvider.notifier).addProduct(product);
    if (!result.isSuccess) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? l10n.somethingWentWrong),
            backgroundColor: AppColors.danger,
          ),
        );
      }
      return;
    }

    HapticFeedback.mediumImpact();
    if (!mounted) return;
    context.safePop();
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
        leading: IconButton(
          onPressed: () => context.safePop(),
          icon:
              const Icon(Icons.close_rounded, color: AppColors.textSecondary),
        ),
        title: Text(
           l10n.addRawMaterial,
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
               l10n.save,
              style: AppTypography.labelMedium.copyWith(
                color:
                    _canSave ? AppColors.primaryNavy : AppColors.textTertiary,
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
                  Text(
                     l10n.addMaterialDesc,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textTertiary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  _buildMainSection(),
                  const SizedBox(height: 12),

                  _buildSupplierSection(),
                  const SizedBox(height: 12),

                  _buildCostSection(),
                  const SizedBox(height: 12),

                  _buildStockSection(),
                  const SizedBox(height: 12),

                  _buildPropertiesSection(),
                  const SizedBox(height: 12),

                  _buildOptionalToggle(),
                ],
              ),
            ),
          ),
          _buildBottomActions(),
        ],
      ),
    ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  MAIN SECTION
  // ═══════════════════════════════════════════════════
  Widget _buildMainSection() {
    return _card(
      children: [
        // Material name
        _inputField(
          controller: _nameController,
          label: l10n.materialName,
          hint: l10n.egCottonFabric,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),

        // SKU with auto-generate
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l10n.skuRefCode, style: _labelStyle),
            GestureDetector(
              onTap: _autoGenerateSku,
              child: Text(
                l10n.autoGenerate,
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
        _textField(_skuController, l10n.egMatCot),
        const SizedBox(height: 14),

        // Category — free-text
        _inputField(
          controller: _categoryController,
          label: l10n.categoryOptional,
          hint: l10n.egFabricChemicals,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  SUPPLIER
  // ═══════════════════════════════════════════════════
  Widget _buildSupplierSection() {
    final suppliers = ref.watch(suppliersProvider).value ?? [];

    return _card(
      children: [
        Text(l10n.supplierOptional, style: _labelStyle),
        const SizedBox(height: 10),

        Row(
          children: [
            _pillToggle(l10n.fromList, !_showSupplierCustom, () {
              setState(() => _showSupplierCustom = false);
            }),
            SizedBox(width: 8),
            _pillToggle(l10n.custom, _showSupplierCustom, () {
              setState(() => _showSupplierCustom = true);
            }),
          ],
        ),
        const SizedBox(height: 10),

        if (_showSupplierCustom)
          _textField(_supplierCustomController, l10n.typeSupplierName)
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.borderLight.withValues(alpha: 0.5)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedSupplierId,
                hint: Text(
                  suppliers.isEmpty ? l10n.noSuppliersYet : l10n.chooseSupplier,
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
                            style: AppTypography.bodySmall
                                .copyWith(color: AppColors.textPrimary),
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedSupplierId = v),
              ),
            ),
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  COST
  // ═══════════════════════════════════════════════════
  Widget _buildCostSection() {
    return _card(
      children: [
        _inputField(
          controller: _costController,
          label: l10n.costPricePerUnit,
          hint: '0.00',
          prefix: ref.watch(appSettingsProvider).currency,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.info_outline_rounded,
                size: 12, color: AppColors.textTertiary),
            const SizedBox(width: 4),
            Text(
               l10n.costPriceInfo,
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
  //  STOCK & UOM
  // ═══════════════════════════════════════════════════
  Widget _buildStockSection() {
    return _card(
      children: [
        Text(l10n.unitOfMeasure, style: _labelStyle),
        const SizedBox(height: 8),
        _textField(_uomController, l10n.egKilogramsLiters),
        const SizedBox(height: 8),

        // Preset chips
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _uomPresets.map((uom) {
            final isSelected = _uomController.text == uom;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _uomController.text = uom);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF795548)
                      : AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF795548)
                        : AppColors.borderLight,
                  ),
                ),
                child: Text(
                  uom,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _inputField(
                controller: _stockController,
                label: l10n.startingStock,
                hint: '0',
                keyboardType: TextInputType.number,
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: _inputField(
                controller: _reorderController,
                label: l10n.reorderPoint,
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
  //  MATERIAL PROPERTIES
  // ═══════════════════════════════════════════════════
  Widget _buildPropertiesSection() {
    return _card(
      children: [
        Text(l10n.materialProperties, style: _labelStyle),
        const SizedBox(height: 10),

        // Material type dropdown
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.baseType, style: _labelStyle),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.borderLight.withValues(alpha: 0.5)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _baseMaterialType.isEmpty ? null : _baseMaterialType,
                  hint: Text(
                     l10n.selectMaterialType,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textTertiary),
                  ),
                  icon: const Icon(Icons.expand_more_rounded,
                      color: AppColors.textTertiary),
                  isExpanded: true,
                  items: _materialTypes
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(
                              _materialTypeLabels[t] ?? t,
                              style: AppTypography.bodySmall
                                  .copyWith(color: AppColors.textPrimary),
                            ),
                          ))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _baseMaterialType = v ?? ''),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        _inputField(
          controller: _wasteController,
          label: l10n.wasteScrapPercentage,
          hint: '0',
          suffix: '%',
          keyboardType: TextInputType.number,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  OPTIONAL DETAILS
  // ═══════════════════════════════════════════════════
  Widget _buildOptionalToggle() {
    return Column(
      children: [
        GestureDetector(
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
                Row(
                  children: [
                    Icon(Icons.tune_rounded,
                        size: 18, color: const Color(0xFF795548)),
                    const SizedBox(width: 10),
                    Text(
                       l10n.optionalDetails,
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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
        ),
        AnimatedCrossFade(
          duration: 300.ms,
          crossFadeState:
              _showOptional ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: Padding(
            padding: EdgeInsets.only(top: 12),
            child: _card(
              children: [
                _inputField(
                  controller: _locationController,
                  label: l10n.storageLocation,
                  hint: l10n.egWarehouseShelf,
                ),
                SizedBox(height: 14),
                _inputField(
                  controller: _notesController,
                  label: l10n.notes,
                  hint: l10n.anyExtraNotes,
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
              onPressed: _canSave ? _save : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF795548),
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.borderLight,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                 l10n.saveMaterial,
                style: AppTypography.labelMedium.copyWith(
                  color: _canSave ? Colors.white : AppColors.textTertiary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _canSave ? _save : null,
            child: Text(
               l10n.saveAndAddAnother,
              style: AppTypography.labelMedium.copyWith(
                color: _canSave ? const Color(0xFF795548) : AppColors.textTertiary,
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
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
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
        duration: 150.ms,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF795548)
              : AppColors.backgroundLight,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF795548)
                : AppColors.borderLight,
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
            _textField(
              controller!,
              hint ?? '',
              prefix: prefix,
              suffix: suffix,
              keyboardType: keyboardType,
              onChanged: onChanged,
            ),
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
      onChanged: onChanged ?? (_) => setState(() {}),
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
          borderSide:
              BorderSide(color: AppColors.borderLight.withValues(alpha: 0.7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: Color(0xFF795548), width: 1.5),
        ),
      ),
      style: AppTypography.bodySmall.copyWith(color: AppColors.textPrimary),
    );
  }
}
