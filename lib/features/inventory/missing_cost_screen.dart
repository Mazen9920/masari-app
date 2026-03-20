import 'package:cached_network_image/cached_network_image.dart';
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

/// A row representing one product (or its variants) that needs a cost price.
class _MissingCostEntry {
  final Product product;
  /// Per-variant controllers — one per variant that has cost == 0.
  final List<_VariantCostRow> variantRows;
  /// For multi-variant products: apply one cost to all variants at once.
  bool applyToAll;
  final TextEditingController bulkCostCtrl;

  _MissingCostEntry({
    required this.product,
    required this.variantRows,
    this.applyToAll = false, // ignore: unused_element_parameter
  }) : bulkCostCtrl = TextEditingController();

  void dispose() {
    bulkCostCtrl.dispose();
    for (final r in variantRows) {
      r.costCtrl.dispose();
    }
  }
}

class _VariantCostRow {
  final ProductVariant variant;
  final TextEditingController costCtrl;
  bool saved;

  _VariantCostRow({required this.variant})
      : costCtrl = TextEditingController(),
        saved = false;
}

class MissingCostScreen extends ConsumerStatefulWidget {
  const MissingCostScreen({super.key});

  @override
  ConsumerState<MissingCostScreen> createState() => _MissingCostScreenState();
}

class _MissingCostScreenState extends ConsumerState<MissingCostScreen> {
  AppLocalizations get l10n => AppLocalizations.of(context)!;
  List<_MissingCostEntry> _entries = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _buildEntries());
  }

  void _buildEntries() {
    final products = ref.read(inventoryProvider).value ?? [];
    final missing = <_MissingCostEntry>[];
    for (final p in products) {
      final zeroVariants =
          p.variants.where((v) => v.costPrice <= 0).toList();
      if (zeroVariants.isEmpty) continue;
      missing.add(_MissingCostEntry(
        product: p,
        variantRows:
            zeroVariants.map((v) => _VariantCostRow(variant: v)).toList(),
      ));
    }
    if (mounted) setState(() => _entries = missing);
  }

  @override
  void dispose() {
    for (final e in _entries) {
      e.dispose();
    }
    super.dispose();
  }

  Future<void> _saveAll() async {
    setState(() => _saving = true);
    final notifier = ref.read(inventoryProvider.notifier);
    int savedCount = 0;

    for (final entry in _entries) {
      final product = entry.product;
      List<ProductVariant> updatedVariants = List.of(product.variants);

      if (entry.applyToAll && entry.variantRows.length > 1) {
        // Bulk cost for all zero-cost variants
        final bulkCost = double.tryParse(entry.bulkCostCtrl.text.trim()) ?? 0;
        if (bulkCost <= 0) continue;
        updatedVariants = updatedVariants.map((v) {
          if (v.costPrice <= 0) return v.copyWith(costPrice: bulkCost);
          return v;
        }).toList();
        savedCount++;
      } else {
        // Per-variant costs
        bool anyUpdated = false;
        for (final row in entry.variantRows) {
          final cost = double.tryParse(row.costCtrl.text.trim()) ?? 0;
          if (cost <= 0) continue;
          updatedVariants = updatedVariants.map((v) {
            if (v.id == row.variant.id) return v.copyWith(costPrice: cost);
            return v;
          }).toList();
          anyUpdated = true;
        }
        if (!anyUpdated) continue;
        savedCount++;
      }

      final updated = product.copyWith(variants: updatedVariants);
      await notifier.updateProduct(product.id, updated);
    }

    if (mounted) {
      setState(() => _saving = false);
      _buildEntries(); // Refresh list
      if (savedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text( 'Updated $savedCount product${savedCount > 1 ? 's' : ''}'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(appSettingsProvider).currency;

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _entries.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                      itemCount: _entries.length,
                      itemBuilder: (context, i) =>
                          _buildProductCard(_entries[i], currency),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: _entries.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _saving ? null : _saveAll,
              backgroundColor: AppColors.primaryNavy,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_rounded, color: Colors.white),
              label: Text(
                 'Save All',
                style: AppTypography.labelMedium
                    .copyWith(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            )
          : null,
    );
  }

  // ── Header ───────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom:
              BorderSide(color: AppColors.borderLight.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.safePop(),
            icon: const Icon(Icons.arrow_back_rounded),
            iconSize: 24,
            color: AppColors.textSecondary,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                   'Missing Costs',
                  style: AppTypography.h2.copyWith(
                    color: AppColors.primaryNavy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${_entries.length} product${_entries.length == 1 ? '' : 's'} need pricing',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty state ──────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded,
                size: 40, color: AppColors.success),
          ),
          const SizedBox(height: 16),
          Text(
             'All products have costs!',
            style: AppTypography.h3.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
             'Every product and variant has a recorded cost price.',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Product card ─────────────────────────────────────────

  Widget _buildProductCard(_MissingCostEntry entry, String currency) {
    final product = entry.product;
    final isMultiVariant = entry.variantRows.length > 1;
    final fmt = NumberFormat('#,##0.00', 'en');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                _productThumbnail(product.imageUrl, 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        product.hasVariants
                            ? '${entry.variantRows.length} variant${entry.variantRows.length == 1 ? '' : 's'} missing cost'
                            : l10n.noCostRecorded,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (product.sellingPrice > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                       'Price: $currency ${fmt.format(product.sellingPrice)}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Apply-to-all toggle (multi-variant only)
          if (isMultiVariant) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: GestureDetector(
                onTap: () =>
                    setState(() => entry.applyToAll = !entry.applyToAll),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: entry.applyToAll
                        ? AppColors.primaryNavy.withValues(alpha: 0.06)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: entry.applyToAll
                          ? AppColors.primaryNavy.withValues(alpha: 0.3)
                          : AppColors.borderLight.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        entry.applyToAll
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded,
                        size: 20,
                        color: entry.applyToAll
                            ? AppColors.primaryNavy
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                         'Same cost for all variants',
                        style: AppTypography.labelSmall.copyWith(
                          color: entry.applyToAll
                              ? AppColors.primaryNavy
                              : AppColors.textSecondary,
                          fontWeight: entry.applyToAll
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Bulk cost field (if apply-to-all)
          if (isMultiVariant && entry.applyToAll)
            Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: _costField(
                controller: entry.bulkCostCtrl,
                label: l10n.costForAllVariants,
                currency: currency,
              ),
            )
          else
            // Per-variant cost fields
            ...entry.variantRows.map((row) => Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: _costField(
                    controller: row.costCtrl,
                    label: isMultiVariant
                        ? row.variant.displayName
                        :  'Cost Price',
                    currency: currency,
                  ),
                )),

          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _productThumbnail(String? imageUrl, double size) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: imageUrl != null && imageUrl.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: imageUrl,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(
                width: size,
                height: size,
                color: const Color(0xFFF1F5F9),
                child: Icon(Icons.inventory_2_rounded,
                    size: size * 0.5, color: AppColors.textTertiary),
              ),
              errorWidget: (_, _, _) => Container(
                width: size,
                height: size,
                color: const Color(0xFFF1F5F9),
                child: Icon(Icons.inventory_2_rounded,
                    size: size * 0.5, color: AppColors.textTertiary),
              ),
            )
          : Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.inventory_2_rounded,
                  size: size * 0.5, color: AppColors.textTertiary),
            ),
    );
  }

  Widget _costField({
    required TextEditingController controller,
    required String label,
    required String currency,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
      ],
      style: AppTypography.bodySmall.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTypography.caption.copyWith(
          color: AppColors.textSecondary,
        ),
        prefixText: '$currency ',
        prefixStyle: AppTypography.caption.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              BorderSide(color: AppColors.borderLight.withValues(alpha: 0.6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              BorderSide(color: AppColors.borderLight.withValues(alpha: 0.6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primaryNavy, width: 1.5),
        ),
        isDense: true,
      ),
    );
  }
}
