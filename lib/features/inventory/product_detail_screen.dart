import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/providers/repository_providers.dart';
import '../../shared/models/product_model.dart';
import '../../shared/models/conversion_order_model.dart';
import '../shopify/providers/shopify_connection_provider.dart';
import '../shopify/widgets/shopify_badges.dart';
import '../../shared/utils/safe_pop.dart';
import '../../l10n/app_localizations.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final String productId;

  const ProductDetailScreen({super.key, required this.productId});

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  AppLocalizations get l10n => AppLocalizations.of(context)!;
  int _adjustQuantity = 0;
  String _adjustReason = 'Correction';
  bool _showAdjustment = false;
  String? _adjustVariantId;
  final _adjustQtyCtrl = TextEditingController(text: '0');

  @override
  void dispose() {
    _adjustQtyCtrl.dispose();
    super.dispose();
  }

  static const _reasons = [
    'Correction',
    'Damage',
    'Loss',
    'Return',
    'Restock',
  ];

  String _reasonLabel(String key) => {
    'Correction': l10n.correctionReason,
    'Damage': l10n.damageReason,
    'Loss': l10n.lossReason,
    'Return': l10n.returnReason,
    'Restock': l10n.restockReason2,
  }[key] ?? key;

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(inventoryProvider).value ?? [];
    if (products.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.backgroundLight,
        body: Center(child: Text(l10n.productNotFound)),
      );
    }
    final product = products.cast<Product?>().firstWhere(
      (p) => p!.id == widget.productId,
      orElse: () => null,
    );
    if (product == null) {
      return Scaffold(
        backgroundColor: AppColors.backgroundLight,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.productNotFound),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.safePop(),
                child: Text(l10n.goBack),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ProductHeader(product: product),
                    const SizedBox(height: 16),
                    _StockOverviewCard(product: product),
                    const SizedBox(height: 14),
                    _buildActionButtons(product),
                    const SizedBox(height: 14),
                    if (_showAdjustment)
                      _buildAdjustmentSection(product),
                    if (_showAdjustment) const SizedBox(height: 14),
                    if (product.shopifyProductId != null &&
                        product.shopifyProductId!.isNotEmpty) ...[                      Builder(builder: (context) {
                        final conn = ref.watch(shopifyConnectionProvider).value;
                        return ShopifyProductBadge(
                          shopifyProductId: product.shopifyProductId,
                          lastInventorySyncAt: conn?.lastInventorySyncAt,
                          shopDomain: conn?.shopDomain,
                        );
                      }),
                      const SizedBox(height: 14),
                    ],
                    _PricingCard(product: product),
                    const SizedBox(height: 14),
                    _CostOverviewCard(product: product),
                    const SizedBox(height: 14),
                    _SupplierCostCard(product: product),
                    const SizedBox(height: 14),
                    if (product.variants.length > 1 || product.hasVariants)
                      _VariantsSection(product: product),
                    if (product.variants.length > 1 || product.hasVariants)
                      const SizedBox(height: 14),
                    if (ref.watch(isGrowthProvider))
                      _MovementHistory(movements: product.movements),
                    if (product.hasBreakdown &&
                        ref.watch(appSettingsProvider).breakdownEnabled) ...[
                      const SizedBox(height: 14),
                      _ConversionHistorySection(productId: product.id),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
              color: AppColors.borderLight.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.safePop(),
            icon: const Icon(Icons.chevron_left_rounded, size: 28),
            color: AppColors.primaryNavy,
          ),
          const Spacer(),
          Text(
            l10n.productDetails,
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.primaryNavy,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              context.pushNamed('EditProductScreen', extra: {'productId': widget.productId});
            },
            child: Text(
              l10n.edit,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.accentOrange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(Product product) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  _showAddStockDialog();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.accentOrange, width: 2),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_rounded,
                          size: 20, color: AppColors.accentOrange),
                      const SizedBox(width: 6),
                      Text(
                        l10n.addStock,
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.accentOrange,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  setState(() => _showAdjustment = !_showAdjustment);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.accentOrange,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accentOrange.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.tune_rounded,
                          size: 20, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        l10n.adjustStock,
                        style: AppTypography.labelMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (product.hasBreakdown &&
            ref.watch(appSettingsProvider).breakdownEnabled) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              context.pushNamed('BreakdownScreen',
                  extra: {'productId': product.id});
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.primaryNavy,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryNavy.withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.call_split_rounded,
                      size: 20, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    l10n.breakDown,
                    style: AppTypography.labelMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              HapticFeedback.lightImpact();
              var error = await ref
                  .read(inventoryProvider.notifier)
                  .recalculateBreakdownCosts(productId: product.id);
              if (!context.mounted) return;

              // If existing layers would be overwritten, ask for confirmation
              if (error == 'CONFIRM_REQUIRED') {
                if (!mounted) return;
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(l10n.replaceCostLayers),
                    content: Text(
                      l10n.replaceCostLayersDesc,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: Text(l10n.cancel),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: Text(l10n.recalculateOutputCosts),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !context.mounted) return;
                error = await ref
                    .read(inventoryProvider.notifier)
                    .recalculateBreakdownCosts(
                      productId: product.id,
                      confirmed: true,
                    );
                if (!context.mounted) return;
              }
              if (!mounted) return;

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(error ?? l10n.outputCostsRecalculated),
                  backgroundColor:
                      error != null ? AppColors.danger : AppColors.success,
                ),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primaryNavy.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.refresh_rounded,
                      size: 18, color: AppColors.primaryNavy),
                  const SizedBox(width: 6),
                  Text(
                    l10n.recalculateOutputCosts,
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.primaryNavy,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 150.ms);
  }

  // ═══════════════════════════════════════════════════
  //  QUICK ADJUSTMENT SECTION
  // ═══════════════════════════════════════════════════
  Widget _buildAdjustmentSection(Product product) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.accentOrange.withValues(alpha: 0.2)),
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
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accentOrange,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.quickAdjustment,
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Text(
                l10n.manualCorrection,
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Variant picker (only for multi-variant products)
          if (product.variants.length > 1) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _adjustVariantId ?? product.defaultVariant.id,
                  icon: const Icon(Icons.expand_more_rounded,
                      color: AppColors.textTertiary, size: 20),
                  isExpanded: true,
                  items: product.variants
                      .map((v) => DropdownMenuItem(
                            value: v.id,
                            child: Text(
                              '${v.localizedDisplayName(l10n)}  (${v.currentStock})',
                              style: AppTypography.labelMedium.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _adjustVariantId = v),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              // Stepper
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundLight,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: AppColors.borderLight),
                  ),
                  child: Row(
                    children: [
                      _stepperButton(Icons.remove_rounded, () {
                        HapticFeedback.lightImpact();
                        setState(() {
                          _adjustQuantity--;
                          _adjustQtyCtrl.text = '$_adjustQuantity';
                        });
                      }),
                      Expanded(
                        child: TextField(
                          controller: _adjustQtyCtrl,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(signed: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[-\d]')),
                          ],
                          style: AppTypography.h3.copyWith(
                            color: _adjustQuantity < 0
                                ? AppColors.danger
                                : _adjustQuantity > 0
                                    ? AppColors.success
                                    : AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (val) {
                            final parsed = int.tryParse(val);
                            setState(() => _adjustQuantity = parsed ?? 0);
                          },
                        ),
                      ),
                      _stepperButton(Icons.add_rounded, () {
                        HapticFeedback.lightImpact();
                        setState(() {
                          _adjustQuantity++;
                          _adjustQtyCtrl.text = '$_adjustQuantity';
                        });
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Reason dropdown
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundLight,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: AppColors.borderLight),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _adjustReason,
                      icon: const Icon(Icons.expand_more_rounded,
                          color: AppColors.textTertiary, size: 20),
                      isExpanded: true,
                      items: _reasons
                          .map((r) => DropdownMenuItem(
                                value: r,
                                child: Text(
                                  _reasonLabel(r),
                                  style: AppTypography.labelMedium
                                      .copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _adjustReason = v ?? 'Correction'),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _adjustQuantity != 0
                  ? () async {
                      // Warn if adjustment would make stock negative
                      final variantId = _adjustVariantId ?? product.defaultVariant.id;
                      final variant = product.variantById(variantId);
                      if (variant != null && variant.currentStock + _adjustQuantity < 0) {
                        final proceed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(l10n.negativeStockTitle),
                            content: Text(
                              l10n.negativeStockWillBring(variant.currentStock + _adjustQuantity),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: Text(l10n.cancel),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: Text(l10n.continueAction),
                              ),
                            ],
                          ),
                        );
                        if (proceed != true || !mounted) return;
                      }
                      final result = await ref.read(inventoryProvider.notifier).adjustStock(
                            widget.productId,
                            variantId,
                            _adjustQuantity,
                            _adjustReason,
                            unitCost: _adjustQuantity > 0 && variant != null && variant.costPrice > 0
                                ? variant.costPrice
                                : null,
                            valuationMethod: ref.read(appSettingsProvider).valuationMethod,
                          );
                      if (!mounted) return;
                      if (!result.isSuccess) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(result.error ?? l10n.adjustmentFailed),
                            backgroundColor: AppColors.danger,
                          ),
                        );
                        return;
                      }
                      HapticFeedback.mediumImpact();
                      setState(() {
                        _adjustQuantity = 0;
                        _adjustQtyCtrl.text = '0';
                        _showAdjustment = false;
                      });
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.textPrimary,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    AppColors.textTertiary.withValues(alpha: 0.3),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                l10n.saveAdjustment,
                style: AppTypography.labelMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: -0.05, end: 0, duration: 300.ms);
  }

  Widget _stepperButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
            ),
          ],
        ),
        child: Icon(icon, size: 20, color: AppColors.textSecondary),
      ),
    );
  }

  void _showAddStockDialog() {
    final products = ref.read(inventoryProvider).value ?? [];
    final product = products.cast<Product?>().firstWhere(
      (p) => p!.id == widget.productId,
      orElse: () => null,
    );
    if (product == null) return;

    int quantity = 0;
    String? selectedVariantId = product.defaultVariant.id;
    final quantityCtrl = TextEditingController(text: '0');
    final unitCostCtrl = TextEditingController(
      text: product.defaultVariant.costPrice > 0
          ? product.defaultVariant.costPrice.toStringAsFixed(2)
          : '',
    );
    final notifier = ref.read(inventoryProvider.notifier);
    final valMethod = ref.read(appSettingsProvider).valuationMethod;
    final currency = ref.read(currencyProvider);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.success.withValues(alpha: 0.1),
                ),
                child: const Icon(Icons.add_rounded,
                    size: 20, color: AppColors.success),
              ),
              const SizedBox(width: 10),
              Text(
                l10n.addStock,
                style: AppTypography.h3.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Variant picker for multi-variant products
              if (product.variants.length > 1) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedVariantId,
                      icon: const Icon(Icons.expand_more_rounded,
                          color: AppColors.textTertiary, size: 20),
                      isExpanded: true,
                      items: product.variants
                          .map((v) => DropdownMenuItem(
                                value: v.id,
                                child: Text(
                                  '${v.localizedDisplayName(l10n)}  (${v.currentStock})',
                                  style: AppTypography.bodySmall.copyWith(
                                      color: AppColors.textPrimary),
                                ),
                              ))
                          .toList(),
                      onChanged: (v) => setDialogState(() {
                        selectedVariantId = v;
                        final selected = product.variantById(v ?? '') ??
                            product.defaultVariant;
                        unitCostCtrl.text = selected.costPrice > 0
                            ? selected.costPrice.toStringAsFixed(2)
                            : '';
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Text(
                l10n.howManyUnitsToRestock,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderLight),
                  color: AppColors.backgroundLight,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (quantity > 0) {
                          setDialogState(() {
                            quantity--;
                            quantityCtrl.text = '$quantity';
                          });
                          HapticFeedback.lightImpact();
                        }
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  Colors.black.withValues(alpha: 0.04),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.remove_rounded,
                            size: 22, color: AppColors.textSecondary),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: quantityCtrl,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(decimal: false),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'\d')),
                        ],
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: quantity > 0
                              ? AppColors.success
                              : AppColors.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (val) {
                          final parsed = int.tryParse(val);
                          setDialogState(() => quantity = (parsed ?? 0).abs());
                        },
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setDialogState(() {
                          quantity++;
                          quantityCtrl.text = '$quantity';
                        });
                        HapticFeedback.lightImpact();
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  Colors.black.withValues(alpha: 0.04),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.add_rounded,
                            size: 22, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: unitCostCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'\d*\.?\d*')),
                ],
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  labelText: l10n.unitCost,
                  prefixText: '$currency ',
                  filled: true,
                  fillColor: AppColors.backgroundLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.borderLight),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.borderLight),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: AppColors.primaryNavy, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                l10n.cancel,
                style: AppTypography.labelMedium
                    .copyWith(color: AppColors.textTertiary),
              ),
            ),
            ElevatedButton(
              onPressed: quantity > 0
                  ? () async {
                      final unitCost =
                          double.tryParse(unitCostCtrl.text.trim()) ?? 0;
                      if (unitCost <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.enterValidUnitCost),
                            backgroundColor: AppColors.danger,
                          ),
                        );
                        return;
                      }

                      final result = await notifier.adjustStock(
                            widget.productId,
                            selectedVariantId ?? product.defaultVariant.id,
                            quantity,
                            'Restock',
                            unitCost: unitCost,
                            valuationMethod: valMethod,
                          );
                      HapticFeedback.mediumImpact();
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (!result.isSuccess && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(result.error ?? l10n.restockFailed),
                            backgroundColor: AppColors.danger,
                          ),
                        );
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    AppColors.textTertiary.withValues(alpha: 0.2),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
              ),
              child: Text(
                l10n.restockPlus(quantity),
                style: AppTypography.labelMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ).then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        quantityCtrl.dispose();
        unitCostCtrl.dispose();
      });
    });
  }
}

// ═══════════════════════════════════════════════════════════
//  PRODUCT HEADER
// ═══════════════════════════════════════════════════════════
class _ProductHeader extends StatelessWidget {
  final Product product;

  const _ProductHeader({required this.product});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final statusLabel = switch (product.status) {
      StockStatus.inStock => l10n.inStock,
      StockStatus.lowStock => l10n.lowStock,
      StockStatus.outOfStock => l10n.outOfStock,
    };
    final statusColor = switch (product.status) {
      StockStatus.inStock => AppColors.success,
      StockStatus.lowStock => AppColors.warning,
      StockStatus.outOfStock => AppColors.danger,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Product icon / image
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: product.color.withValues(alpha: 0.1),
            border: Border.all(
                color: AppColors.borderLight.withValues(alpha: 0.5)),
          ),
          child: product.imageUrl != null && product.imageUrl!.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CachedNetworkImage(
                    imageUrl: product.imageUrl!,
                    fit: BoxFit.cover,
                    width: 80,
                    height: 80,
                    memCacheWidth: 160,
                    memCacheHeight: 160,
                    placeholder: (_, _) => Icon(product.icon, size: 36, color: product.color),
                    errorWidget: (_, _, _) => Icon(product.icon, size: 36, color: product.color),
                  ),
                )
              : Icon(product.icon, size: 36, color: product.color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                product.name,
                style: AppTypography.h3.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                l10n.skuLabel(product.sku),
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms);
  }
}

// ═══════════════════════════════════════════════════════════
//  STOCK OVERVIEW CARD
// ═══════════════════════════════════════════════════════════
class _StockOverviewCard extends ConsumerWidget {
  final Product product;

  const _StockOverviewCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative
          Positioned(
            top: -16,
            right: -16,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryNavy.withValues(alpha: 0.03),
              ),
            ),
          ),
          Column(
            children: [
              Text(
                l10n.currentInventory,
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  TweenAnimationBuilder<int>(
                    tween:
                        IntTween(begin: 0, end: product.currentStock),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (_, value, _) => Text(
                      '$value',
                      style: TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryNavy,
                        letterSpacing: -1,
                        height: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.unitsLabel,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.only(top: 14),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                        color: AppColors.borderLight.withValues(alpha: 0.5)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            l10n.totalValueLabel,
                            style: AppTypography.captionSmall.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${ref.watch(appSettingsProvider).currency} ${NumberFormat('#,##0.00').format(product.totalValue)}',
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 36,
                      color:
                          AppColors.borderLight.withValues(alpha: 0.5),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            l10n.reorderPoint,
                            style: AppTypography.captionSmall.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${product.reorderPoint}',
                            style: AppTypography.labelMedium.copyWith(
                              color: product.currentStock <=
                                      product.reorderPoint
                                  ? AppColors.accentOrange
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 50.ms);
  }
}

// ═══════════════════════════════════════════════════════════
//  PRICING CARD (additional enhancement)
// ═══════════════════════════════════════════════════════════
class _PricingCard extends ConsumerWidget {
  final Product product;

  const _PricingCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.pricing,
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _priceItem(l10n.cost, '${ref.watch(appSettingsProvider).currency} ${NumberFormat('#,##0.00').format(product.costPrice)}'),
              _priceItem(
                  l10n.selling, '${ref.watch(appSettingsProvider).currency} ${NumberFormat('#,##0.00').format(product.sellingPrice)}'),
              _priceItem(
                l10n.margin,
                '${product.profitMargin.toStringAsFixed(1)}%',
                color: product.profitMargin >= 0 ? AppColors.success : AppColors.danger,
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 200.ms);
  }

  Widget _priceItem(String label, String value, {Color? color}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textTertiary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.labelMedium.copyWith(
              color: color ?? AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  COST OVERVIEW
// ═══════════════════════════════════════════════════════════
class _CostOverviewCard extends ConsumerWidget {
  final Product product;
  const _CostOverviewCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final currency = ref.watch(appSettingsProvider).currency;
    final valMethod = ref.watch(appSettingsProvider).valuationMethod;
    final valLabel = {
      'fifo': l10n.fifoLabel,
      'lifo': l10n.lifoLabel,
      'average': l10n.averageLabel,
    }[valMethod] ?? l10n.fifoLabel;

    // Collect restock movements with unitCost across all variants
    final restocks = <StockMovement>[];
    for (final v in product.variants) {
      for (final m in v.movements) {
        if (m.type == 'Restock' && m.unitCost != null) {
          restocks.add(m);
        }
      }
    }
    restocks.sort((a, b) => b.dateTime.compareTo(a.dateTime));

    if (restocks.isEmpty) {
      return const SizedBox.shrink();
    }

    final lastCost = restocks.first.unitCost!;
    final lowestCost = restocks
        .map((m) => m.unitCost!)
        .reduce((a, b) => a < b ? a : b);
    final avgCost = product.costPrice;

    final fmt = NumberFormat('#,##0.00');
    final dateFmt = DateFormat('MMM d');

    final costUp = lastCost > avgCost;
    final costDown = lastCost < avgCost;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l10n.costOverview,
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  valLabel,
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.primaryNavy,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _costItem(l10n.avgCost, '$currency ${fmt.format(avgCost)}'),
              _costItem(
                l10n.lastCost,
                '$currency ${fmt.format(lastCost)}',
                trailing: costUp
                    ? const Icon(Icons.arrow_upward_rounded,
                        size: 12, color: Color(0xFFEF4444))
                    : costDown
                        ? const Icon(Icons.arrow_downward_rounded,
                            size: 12, color: Color(0xFF10B981))
                        : null,
              ),
              _costItem(l10n.lowestCost, '$currency ${fmt.format(lowestCost)}'),
            ],
          ),
          if (restocks.length > 1) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: AppColors.borderLight.withValues(alpha: 0.5)),
            const SizedBox(height: 10),
            Text(
              l10n.recentCostHistory,
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 8),
            ...restocks.take(5).map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 56,
                        child: Text(
                          dateFmt.format(m.dateTime),
                          style: AppTypography.captionSmall.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Text(
                        '$currency ${fmt.format(m.unitCost)}',
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        l10n.unitsCount(m.quantity),
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 250.ms);
  }

  Widget _costItem(String label, String value, {Widget? trailing}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textTertiary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 2), trailing],
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  VARIANTS SECTION
// ═══════════════════════════════════════════════════════════
class _VariantsSection extends ConsumerWidget {
  final Product product;

  const _VariantsSection({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final currency = ref.watch(currencyProvider);
    final fmt = NumberFormat('#,##0.00', 'en');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.style_rounded, size: 18, color: AppColors.primaryNavy),
              const SizedBox(width: 8),
              Text(
                l10n.variantsLabel,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${product.variantCount}',
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.primaryNavy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...product.variants.map((v) {
            final statusColor = v.status == StockStatus.inStock
                ? AppColors.success
                : v.status == StockStatus.lowStock
                    ? AppColors.accentOrange
                    : AppColors.danger;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.backgroundLight,
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
                          v.localizedDisplayName(l10n),
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.unitsCount(v.currentStock),
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (v.sku.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      l10n.skuLabel(v.sku),
                      style: AppTypography.captionSmall.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _priceChip(l10n.cost, '$currency ${fmt.format(v.costPrice)}'),
                      const SizedBox(width: 8),
                      _priceChip(
                          l10n.selling, '$currency ${fmt.format(v.sellingPrice)}'),
                      const SizedBox(width: 8),
                      _priceChip(l10n.valueLabel,
                          '$currency ${fmt.format(v.totalValue)}'),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 200.ms);
  }

  Widget _priceChip(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w600,
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  MOVEMENT HISTORY
// ═══════════════════════════════════════════════════════════
class _MovementHistory extends StatelessWidget {
  final List<StockMovement> movements;

  const _MovementHistory({required this.movements});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.recentMovements,
          style: AppTypography.captionSmall.copyWith(
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 12),
        if (movements.isEmpty)
          _buildEmpty(context)
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppColors.borderLight.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                for (int i = 0; i < movements.length; i++) ...[
                  _MovementTile(movement: movements[i], index: i),
                  if (i < movements.length - 1)
                    Divider(
                      height: 1,
                      color: AppColors.borderLight.withValues(alpha: 0.5),
                      indent: 16,
                      endIndent: 16,
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(32),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Icon(Icons.history_rounded,
              size: 32,
              color: AppColors.textTertiary.withValues(alpha: 0.4)),
          const SizedBox(height: 10),
          Text(
            l10n.noMovementsYet,
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _MovementTile extends StatelessWidget {
  final StockMovement movement;
  final int index;

  const _MovementTile({required this.movement, required this.index});

  String get _formattedDate {
    final d = movement.dateTime;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = d.hour > 12 ? d.hour - 12 : d.hour;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year} • ${hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final isPositive = movement.quantity > 0;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: movement.iconColor.withValues(alpha: 0.1),
            ),
            child: Icon(
              movement.icon,
              size: 20,
              color: movement.iconColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movement.note ?? movement.type,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formattedDate,
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isPositive ? '+' : ''}${movement.quantity}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isPositive ? AppColors.success : AppColors.textPrimary,
                ),
              ),
              Text(
                AppLocalizations.of(context)!.unitsLabel,
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(
            duration: 250.ms,
            delay: Duration(milliseconds: 40 * index))
        .slideX(begin: 0.02, end: 0);
  }
}

// ═══════════════════════════════════════════════════
//  SUPPLIER COST COMPARISON
// ═══════════════════════════════════════════════════
class _SupplierCostCard extends ConsumerWidget {
  final Product product;
  const _SupplierCostCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final l10n = AppLocalizations.of(context)!;
    final fmt = NumberFormat('#,##0.##');
    final restockMovements = product.movements
        .where((m) => m.type == 'Restock' && m.supplierName != null && m.unitCost != null)
        .toList();

    if (restockMovements.isEmpty) return const SizedBox.shrink();

    // Group by supplier name
    final Map<String, List<StockMovement>> bySupplier = {};
    for (final m in restockMovements) {
      bySupplier.putIfAbsent(m.supplierName!, () => []).add(m);
    }

    // Need at least one supplier with data to show the card
    if (bySupplier.isEmpty) return const SizedBox.shrink();

    // Sort suppliers by most recent restock date
    final entries = bySupplier.entries.toList()
      ..sort((a, b) {
        final aLast = a.value.map((m) => m.dateTime).reduce((x, y) => x.isAfter(y) ? x : y);
        final bLast = b.value.map((m) => m.dateTime).reduce((x, y) => x.isAfter(y) ? x : y);
        return bLast.compareTo(aLast);
      });

    // Find supplier with lowest average cost (highlighted as BEST)
    final bestEntry = entries.reduce((a, b) {
      final aAvg = a.value.map((m) => m.unitCost!).reduce((x, y) => x + y) / a.value.length;
      final bAvg = b.value.map((m) => m.unitCost!).reduce((x, y) => x + y) / b.value.length;
      return aAvg <= bAvg ? a : b;
    });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
        children: [
          Row(
            children: [
              Icon(Icons.store_rounded, size: 16, color: AppColors.primaryNavy),
              const SizedBox(width: 6),
              Text(
                l10n.costBySupplier,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Header row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(l10n.supplierHeader, style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary, fontWeight: FontWeight.w600,
                    letterSpacing: 0.6, fontSize: 9,
                  )),
                ),
                Expanded(
                  child: Text(l10n.avgHeader, style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary, fontWeight: FontWeight.w600,
                    letterSpacing: 0.6, fontSize: 9,
                  ), textAlign: TextAlign.center),
                ),
                Expanded(
                  child: Text(l10n.lastHeader, style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary, fontWeight: FontWeight.w600,
                    letterSpacing: 0.6, fontSize: 9,
                  ), textAlign: TextAlign.center),
                ),
                Expanded(
                  child: Text(l10n.ordersHeader, style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary, fontWeight: FontWeight.w600,
                    letterSpacing: 0.6, fontSize: 9,
                  ), textAlign: TextAlign.end),
                ),
              ],
            ),
          ),
          const Divider(height: 12),
          ...entries.map((entry) {
            final movs = entry.value;
            final avgCost = movs.map((m) => m.unitCost!).reduce((a, b) => a + b) / movs.length;
            final lastCost = movs
                .reduce((a, b) => a.dateTime.isAfter(b.dateTime) ? a : b)
                .unitCost!;
            final isBest = entry.key == bestEntry.key && entries.length > 1;
            final lastDate = movs
                .map((m) => m.dateTime)
                .reduce((a, b) => a.isAfter(b) ? a : b);

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isBest
                      ? AppColors.success.withValues(alpha: 0.06)
                      : AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isBest
                        ? AppColors.success.withValues(alpha: 0.25)
                        : AppColors.borderLight,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  entry.key,
                                  style: AppTypography.labelSmall.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isBest) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.success,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    l10n.bestLabel,
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            l10n.lastDateLabel(DateFormat('MMM d').format(lastDate)),
                            style: AppTypography.captionSmall.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Text(
                        fmt.format(avgCost),
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            fmt.format(lastCost),
                            style: AppTypography.labelSmall.copyWith(
                              color: lastCost > avgCost
                                  ? AppColors.danger
                                  : lastCost < avgCost
                                      ? AppColors.success
                                      : AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (lastCost != avgCost)
                            Text(
                              lastCost > avgCost ? '↑' : '↓',
                              style: TextStyle(
                                fontSize: 10,
                                color: lastCost > avgCost
                                    ? AppColors.danger
                                    : AppColors.success,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${movs.length}',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              l10n.avgLastCostIn(currency),
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.textTertiary,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}

// ═══════════════════════════════════════════════════
//  CONVERSION HISTORY
// ═══════════════════════════════════════════════════
class _ConversionHistorySection extends ConsumerWidget {
  final String productId;
  const _ConversionHistorySection({required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(conversionOrdersForProductProvider(productId));
    final currency = ref.watch(currencyProvider);
    final fmt = NumberFormat('#,##0.##');
    final l10n = AppLocalizations.of(context)!;

    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (orders) {
        if (orders.isEmpty) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: AppColors.borderLight.withValues(alpha: 0.5)),
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
            children: [
              Row(
                children: [
                  Icon(Icons.call_split_rounded,
                      size: 16, color: AppColors.primaryNavy),
                  const SizedBox(width: 6),
                  Text(
                    l10n.breakdownHistory,
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryNavy.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${orders.length}',
                      style: AppTypography.captionSmall.copyWith(
                        color: AppColors.primaryNavy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...orders.take(5).map((order) =>
                  _ConversionOrderTile(
                      order: order, currency: currency, fmt: fmt)),
              if (orders.length > 5)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n.moreCount(orders.length - 5),
                    style: AppTypography.captionSmall
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ),
            ],
          ),
        ).animate().fadeIn(duration: 300.ms);
      },
    );
  }
}

class _ConversionOrderTile extends StatelessWidget {
  final ConversionOrder order;
  final String currency;
  final NumberFormat fmt;

  const _ConversionOrderTile({
    required this.order,
    required this.currency,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final dateStr = DateFormat('MMM d, yyyy').format(order.date);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                dateStr,
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                l10n.conversionSummary(order.sourceQuantity.toInt(), order.outputs.length),
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                l10n.sourceCostValue(currency, fmt.format(order.sourceTotalCost)),
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: order.outputs.map((line) {
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: AppColors.borderLight),
                ),
                child: Text(
                  '${line.variantName}: ${line.quantity.toInt()} × $currency ${fmt.format(line.unitCost)}',
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
