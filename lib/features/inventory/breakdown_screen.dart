import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../shared/models/product_model.dart';
import '../../shared/utils/safe_pop.dart';
import '../../l10n/app_localizations.dart';

class BreakdownScreen extends ConsumerStatefulWidget {
  final String productId;

  const BreakdownScreen({super.key, required this.productId});

  @override
  ConsumerState<BreakdownScreen> createState() => _BreakdownScreenState();
}

class _BreakdownScreenState extends ConsumerState<BreakdownScreen> {
  AppLocalizations get l10n => AppLocalizations.of(context)!;
  final _qtyController = TextEditingController(text: '1');
  bool _isSaving = false;

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  int get _qty => int.tryParse(_qtyController.text) ?? 0;

  Future<void> _execute(Product product) async {
    if (_qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.enterValidQuantity)),
      );
      return;
    }

    final recipe = product.breakdownRecipe!;
    final sourceVariant = product.variantById(recipe.sourceVariantId);
    if (sourceVariant == null) return;

    if (sourceVariant.currentStock < _qty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              l10n.notEnoughStockAvailable(sourceVariant.currentStock)),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    HapticFeedback.lightImpact();

    final valuationMethod =
        ref.read(appSettingsProvider).valuationMethod;

    final error = await ref.read(inventoryProvider.notifier).breakdownProduct(
          productId: widget.productId,
          sourceVariantId: recipe.sourceVariantId,
          qty: _qty,
          valuationMethod: valuationMethod,
        );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.breakdownError(error)),
          backgroundColor: AppColors.danger,
        ),
      );
    } else {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
               l10n.breakdownComplete(_qty, sourceVariant.localizedDisplayName(l10n))),
          backgroundColor: AppColors.success,
        ),
      );
      if (mounted) context.safePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final products = ref.watch(inventoryProvider).value ?? [];
    final product = products.cast<Product?>().firstWhere(
      (p) => p!.id == widget.productId,
      orElse: () => null,
    );

    if (product == null || !product.hasBreakdown) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.breakdown)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.call_split_rounded, size: 64,
                  color: AppColors.textTertiary.withValues(alpha: 0.3)),
              const SizedBox(height: 16),
              Text(
                l10n.breakdownNotConfigured,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.breakdownNotConfiguredDesc,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
                textAlign: TextAlign.center,
              ),
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

    final recipe = product.breakdownRecipe!;
    final sourceVariant = product.variantById(recipe.sourceVariantId);
    if (sourceVariant == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.breakdown)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 64,
                  color: AppColors.textTertiary.withValues(alpha: 0.3)),
              const SizedBox(height: 16),
              Text(l10n.sourceVariantNotFound,
                  style: AppTypography.labelMedium.copyWith(color: AppColors.textTertiary)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.safePop(),
                child: Text(l10n.goBack),
              ),
            ],
          ),
        ),
      );
    }

    final currency = ref.watch(currencyProvider);
    final valuationMethod = ref.watch(appSettingsProvider).valuationMethod;
    final fmt = NumberFormat('#,##0.##');

    final qty = _qty;
    final cogsPerUnit =
        qty > 0 ? sourceVariant.cogsPerUnit(qty, valuationMethod) : 0.0;
    final totalCost = cogsPerUnit * qty;

    // Compute per-output allocations for preview
    double totalSellingValue = 0;
    int totalOutputQty = 0;
    for (final output in recipe.outputs) {
      final v = product.variantById(output.variantId);
      totalOutputQty += (output.quantityPerUnit * qty).round();
      if (v != null) {
        totalSellingValue += output.quantityPerUnit * v.sellingPrice;
      }
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_isSaving) return;
        context.safePop();
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundLight,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: TextButton(
            onPressed: _isSaving ? null : () => context.safePop(),
            child: Text(
               l10n.cancel,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          leadingWidth: 80,
          title: Text(
             l10n.breakDown,
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.primaryNavy,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          centerTitle: true,
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding:
                    const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product header
                    _card(
                      children: [
                        Text(
                          product.name,
                          style: AppTypography.h3.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.primaryNavy
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                 l10n.sourceLabel(sourceVariant.localizedDisplayName(l10n)),
                                style: AppTypography.captionSmall.copyWith(
                                  color: AppColors.primaryNavy,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.inStockCount(sourceVariant.currentStock),
                              style: AppTypography.captionSmall.copyWith(
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Quantity input
                    _card(
                      children: [
                        Text(
                          l10n.quantityToBreakDown,
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
                            _qtyButton(
                              icon: Icons.remove_rounded,
                              enabled: _qty > 1,
                              onTap: () {
                                final v = _qty;
                                if (v > 1) {
                                  setState(() =>
                                      _qtyController.text = '${v - 1}');
                                }
                              },
                            ),
                            Expanded(
                              child: TextField(
                                controller: _qtyController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                onChanged: (_) => setState(() {}),
                                style: AppTypography.h3.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          vertical: 14),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(
                                        color: AppColors.borderLight),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(
                                        color: AppColors.borderLight
                                            .withValues(alpha: 0.7)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: AppColors.primaryNavy,
                                        width: 1.5),
                                  ),
                                ),
                              ),
                            ),
                            _qtyButton(
                              icon: Icons.add_rounded,
                              enabled: _qty < sourceVariant.currentStock,
                              onTap: () {
                                final v = _qty;
                                if (v < sourceVariant.currentStock) {
                                  setState(() =>
                                      _qtyController.text = '${v + 1}');
                                }
                              },
                            ),
                          ],
                        ),
                        if (qty > sourceVariant.currentStock)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                               l10n.exceedsAvailableStock(sourceVariant.currentStock),
                              style: AppTypography.captionSmall
                                  .copyWith(color: AppColors.danger),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Cost preview
                    if (qty > 0)
                      _card(
                        children: [
                          Row(
                            children: [
                              Icon(Icons.calculate_rounded,
                                  size: 16,
                                  color: AppColors.primaryNavy),
                              const SizedBox(width: 6),
                              Text(
                                 l10n.costAllocationPreview,
                                style: AppTypography.labelMedium.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                             l10n.methodLabel(valuationMethod.toUpperCase()),
                            style: AppTypography.captionSmall.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                          const Divider(height: 20),
                          _costRow(
                            label:
                                 l10n.sourceCostLabel(qty, currency, fmt.format(cogsPerUnit)),
                            value: '$currency ${fmt.format(totalCost)}',
                            isTotal: false,
                          ),
                          const SizedBox(height: 12),
                          Text(
                             l10n.outputs.toUpperCase(),
                            style: AppTypography.captionSmall.copyWith(
                              color: AppColors.textTertiary,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...recipe.outputs.map((output) {
                            final v = product.variantById(output.variantId);
                            if (v == null) return const SizedBox.shrink();
                            final outputQty =
                                (output.quantityPerUnit * qty).round();
                            double allocatedUnitCost = 0;
                            if (totalSellingValue > 0) {
                              final outputSelling = output.quantityPerUnit *
                                  v.sellingPrice;
                              final allocatedTotal = totalCost *
                                  (outputSelling / totalSellingValue);
                              allocatedUnitCost = outputQty > 0
                                  ? (allocatedTotal / outputQty * 100)
                                          .roundToDouble() /
                                      100
                                  : 0;
                            } else {
                              allocatedUnitCost = totalOutputQty > 0
                                ? (totalCost / totalOutputQty * 100)
                                    .roundToDouble() /
                                  100
                                : 0;
                            }
                            return Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 10),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.backgroundLight,
                                  borderRadius:
                                      BorderRadius.circular(10),
                                  border: Border.all(
                                      color: AppColors.borderLight),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            v.localizedDisplayName(l10n),
                                            style: AppTypography
                                                .labelMedium
                                                .copyWith(
                                              color:
                                                  AppColors.textPrimary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            l10n.unitsCount(outputQty),
                                            style: AppTypography
                                                .captionSmall
                                                .copyWith(
                                              color: AppColors.textTertiary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          l10n.perUnitCost(currency, fmt.format(allocatedUnitCost)),
                                          style: AppTypography
                                              .labelMedium
                                              .copyWith(
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          l10n.totalCostValue(currency, fmt.format(allocatedUnitCost * outputQty)),
                                          style: AppTypography
                                              .captionSmall
                                              .copyWith(
                                            color: AppColors.textTertiary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                  ],
                ),
              ),
            ),

            // Bottom CTA
            Container(
              padding: EdgeInsets.fromLTRB(
                  16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
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
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: (_isSaving ||
                          qty <= 0 ||
                          qty > sourceVariant.currentStock)
                      ? null
                      : () => _execute(product),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryNavy,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.borderLight,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                           l10n.breakDownAction(qty, sourceVariant.localizedDisplayName(l10n)),
                          style: AppTypography.labelMedium.copyWith(
                            color: qty > 0 &&
                                    qty <= sourceVariant.currentStock
                                ? Colors.white
                                : AppColors.textTertiary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
        children: children,
      ),
    );
  }

  Widget _qtyButton(
      {required IconData icon,
      required bool enabled,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              onTap();
            }
          : null,
      child: Container(
        width: 44,
        height: 44,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.backgroundLight
              : AppColors.backgroundLight.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled
              ? AppColors.primaryNavy
              : AppColors.textTertiary,
        ),
      ),
    );
  }

  Widget _costRow(
      {required String label,
      required String value,
      required bool isTotal}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color:
                  isTotal ? AppColors.textPrimary : AppColors.textSecondary,
              fontWeight:
                  isTotal ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        Text(
          value,
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
