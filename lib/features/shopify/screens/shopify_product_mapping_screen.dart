import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/models/product_model.dart';
import '../../../shared/models/shopify_product_mapping_model.dart';
import '../providers/shopify_product_mappings_provider.dart';
import '../providers/shopify_products_provider.dart';
import '../../../shared/utils/safe_pop.dart';

/// Shopify-centric product mapping & import screen.
///
/// Shows ALL Shopify products with their mapping status:
/// - Green = already linked to a Revvo product
/// - Orange = unmapped — tap to import or link
///
/// Features:
/// - "Import All" — bulk-import all unmapped Shopify products into Revvo
/// - Tap unmapped → import single product or link to existing Revvo product
/// - Auto-Match by SKU
/// - Delete existing mappings
class ShopifyProductMappingScreen extends ConsumerStatefulWidget {
  const ShopifyProductMappingScreen({super.key});

  @override
  ConsumerState<ShopifyProductMappingScreen> createState() =>
      _ShopifyProductMappingScreenState();
}

class _ShopifyProductMappingScreenState
    extends ConsumerState<ShopifyProductMappingScreen> {
  bool _importing = false;
  bool _autoMatching = false;
  bool _didAutoRelink = false;

  /// Silently runs auto-match to re-create mappings for products
  /// already in Revvo that match Shopify products by SKU or
  /// shopifyProductId/shopifyVariantId.
  Future<void> _autoRelinkExistingProducts(
    List<Map<String, dynamic>> shopifyProds,
    List<ShopifyProductMapping> mappings,
  ) async {
    if (_didAutoRelink || _autoMatching) return;
    _didAutoRelink = true;

    // Refresh inventory to pick up any webhook-imported products
    // that exist in Firestore but aren't in local provider state yet.
    ref.read(inventoryProvider.notifier).refresh();

    // Only run if there are unmapped Shopify products
    final mappedIds = <String>{for (final m in mappings) m.shopifyProductId};
    final hasUnmapped = shopifyProds.any(
      (sp) => !mappedIds.contains(sp['id']?.toString()),
    );
    if (!hasUnmapped) return;

    // Run auto-match silently
    final result = await ref
        .read(shopifyMappingsProvider.notifier)
        .autoMatchBySku();

    if (!mounted) return;
    if (result.isSuccess && (result.data ?? 0) > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.shopifyAutoLinked(result.data!),
          ),
          backgroundColor: AppColors.primaryNavy,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncShopify = ref.watch(shopifyProductsProvider);
    final asyncMappings = ref.watch(shopifyMappingsProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: asyncShopify.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.primaryNavy),
                ),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_rounded,
                            size: 48, color: AppColors.danger),
                        const SizedBox(height: 16),
                        Text(
                          AppLocalizations.of(context)!.shopifyFailedLoadProducts,
                          style: AppTypography.h3.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$e',
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextButton.icon(
                          onPressed: () => ref
                              .read(shopifyProductsProvider.notifier)
                              .refresh(),
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(AppLocalizations.of(context)!.shopifyRetry),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (shopifyProducts) {
                  final mappings = asyncMappings.value ?? [];
                  return _buildBody(shopifyProducts, mappings);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
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
            AppLocalizations.of(context)!.shopifyProductsTitle,
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.primaryNavy,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  // ── Body ────────────────────────────────────────────────

  Widget _buildBody(
    List<Map<String, dynamic>> shopifyProducts,
    List<ShopifyProductMapping> mappings,
  ) {
    final l10n = AppLocalizations.of(context)!;
    // Auto-relink existing products on first load after reconnect
    if (!_didAutoRelink) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoRelinkExistingProducts(shopifyProducts, mappings);
      });
    }

    // Index mappings by shopifyProductId for quick lookup
    final mappingsByShopifyId = <String, List<ShopifyProductMapping>>{};
    for (final m in mappings) {
      mappingsByShopifyId
          .putIfAbsent(m.shopifyProductId, () => [])
          .add(m);
    }

    final mapped = shopifyProducts.where(
        (p) => mappingsByShopifyId.containsKey(p['id']?.toString()));
    final unmapped = shopifyProducts.where(
        (p) => !mappingsByShopifyId.containsKey(p['id']?.toString()));

    return Column(
      children: [
        // Stats bar + action buttons
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.white,
          child: Column(
            children: [
              Row(
                children: [
                  _MiniStat(
                    label: l10n.shopifyMapped,
                    count: mapped.length,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 16),
                  _MiniStat(
                    label: l10n.shopifyUnmapped,
                    count: unmapped.length,
                    color: AppColors.warning,
                  ),
                  const Spacer(),
                  _ActionChip(
                    label: l10n.shopifyAutoMatch,
                    icon: Icons.auto_fix_high_rounded,
                    loading: _autoMatching,
                    onTap: _autoMatching ? null : _onAutoMatch,
                  ),
                ],
              ),
              if (unmapped.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _importing ? null : () => _importAll(
                      unmapped.toList(),
                      mappingsByShopifyId,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            AppColors.primaryNavy,
                            Color(0xFF2E86C1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _importing
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.download_rounded,
                                    size: 18, color: Colors.white),
                                const SizedBox(width: 8),
                                Text(
                                  l10n.shopifyImportAllProducts(unmapped.length),
                                  style: AppTypography.labelSmall.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Divider(
            height: 1,
            color: AppColors.borderLight.withValues(alpha: 0.5)),

        // Shopify product list
        Expanded(
          child: shopifyProducts.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding:
                      const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  itemCount: shopifyProducts.length,
                  itemBuilder: (context, index) {
                    final sp = shopifyProducts[index];
                    final spId = sp['id']?.toString() ?? '';
                    final spMappings =
                        mappingsByShopifyId[spId] ?? [];
                    final isMapped = spMappings.isNotEmpty;

                    return _ShopifyProductTile(
                      shopifyProduct: sp,
                      mappings: spMappings,
                      isMapped: isMapped,
                      onImport: () => _importSingle(sp),
                      onLink: () => _showLinkPicker(sp),
                      onDeleteMapping: (m) => _deleteMapping(m),
                    ).animate().fadeIn(
                          duration: 200.ms,
                          delay: (index * 30).ms,
                        );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storefront_outlined,
              size: 56, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text(
            l10n.shopifyNoProducts,
            style: AppTypography.h3.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.shopifyNoProductsDesc,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Import single Shopify product into Revvo ───────────

  Future<void> _importSingle(Map<String, dynamic> shopifyProduct) async {
    final l10n = AppLocalizations.of(context)!;
    HapticFeedback.mediumImpact();
    setState(() => _importing = true);

    try {
      await _importShopifyProduct(shopifyProduct);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.shopifyImportedProduct(shopifyProduct['title'] ?? 'Product'),
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.shopifyImportFailedError('$e')),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  // ── Import ALL unmapped products ────────────────────────

  Future<void> _importAll(
    List<Map<String, dynamic>> unmapped,
    Map<String, List<ShopifyProductMapping>> existingMappings,
  ) async {
    HapticFeedback.mediumImpact();
    final l10n = AppLocalizations.of(context)!;

    // Confirm with the user
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          l10n.shopifyImportCountTitle(unmapped.length),
          style: AppTypography.h3.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          l10n.shopifyImportAllConfirmMessage(unmapped.length),
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryNavy,
            ),
            child: Text(l10n.shopifyImportAll),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _importing = true);
    int importedCount = 0;

    try {
      for (final sp in unmapped) {
        await _importShopifyProduct(sp);
        importedCount++;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.shopifyImportedCount(importedCount)),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.shopifyImportPartial(importedCount, unmapped.length, '$e'),
          ),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  // ── Core import logic ───────────────────────────────────

  /// Creates a Revvo Product from a Shopify product JSON, saves it,
  /// then creates variant-level mappings.
  ///
  /// **Dedup guard**: If a Revvo product already exists with the same
  /// `shopifyProductId` or matching SKUs, it will be re-linked instead
  /// of creating a duplicate.
  Future<void> _importShopifyProduct(
    Map<String, dynamic> shopifyProduct,
  ) async {
    final uid =
        ref.read(authProvider).user?.id ?? '';
    final uuid = const Uuid();

    final shopifyProductId = shopifyProduct['id']?.toString() ?? '';
    final title = shopifyProduct['title']?.toString() ?? 'Untitled';
    final shopifyVariants =
        (shopifyProduct['variants'] as List<dynamic>?) ?? [];
    final shopifyOptions =
        (shopifyProduct['options'] as List<dynamic>?) ?? [];
    final imageUrl = _extractImageUrl(shopifyProduct);

    // ── Check for existing Revvo product (dedup) ───────
    // Priority 1: Match by shopifyProductId stored on Revvo product
    // Priority 2: Match by SKU of the first variant
    final existingProducts = ref.read(inventoryProvider).value ?? [];
    Product? existingProduct;

    // Try shopifyProductId match
    if (shopifyProductId.isNotEmpty) {
      existingProduct = existingProducts.cast<Product?>().firstWhere(
        (p) => p!.shopifyProductId == shopifyProductId,
        orElse: () => null,
      );
    }

    // Try SKU match if no ID match
    if (existingProduct == null && shopifyVariants.isNotEmpty) {
      // Collect all Shopify SKUs for this product
      final shopifySkus = <String>{};
      for (final sv in shopifyVariants) {
        final v = Map<String, dynamic>.from(sv as Map);
        final sku = (v['sku']?.toString() ?? '').trim().toLowerCase();
        if (sku.isNotEmpty) shopifySkus.add(sku);
      }

      if (shopifySkus.isNotEmpty) {
        existingProduct = existingProducts.cast<Product?>().firstWhere(
          (p) => p!.variants.any(
            (v) => shopifySkus.contains(v.sku.trim().toLowerCase()),
          ),
          orElse: () => null,
        );
      }
    }

    // If product already exists, just create mappings (don't duplicate)
    if (existingProduct != null) {
      await _createMappingsForExistingProduct(
        existingProduct,
        shopifyProduct,
        title,
      );
      return;
    }

    // ── Build ProductOptions from Shopify options ────────
    final options = <ProductOption>[];
    for (final opt in shopifyOptions) {
      final o = Map<String, dynamic>.from(opt as Map);
      final name = o['name']?.toString() ?? '';
      final values = (o['values'] as List<dynamic>?)
              ?.map((v) => v.toString())
              .toList() ??
          [];
      // Skip the "Title" default option Shopify adds when no real options
      if (name.toLowerCase() == 'title' &&
          values.length == 1 &&
          values.first == 'Default Title') {
        continue;
      }
      if (name.isNotEmpty && values.isNotEmpty) {
        options.add(ProductOption(name: name, values: values));
      }
    }

    // ── Build ProductVariants from Shopify variants ──────
    final variants = <ProductVariant>[];
    for (final sv in shopifyVariants) {
      final v = Map<String, dynamic>.from(sv as Map);
      final variantId = uuid.v4();
      final shopifyVariantId = v['id']?.toString() ?? '';
      final shopifyInvItemId =
          v['inventory_item_id']?.toString() ?? '';
      final sku = v['sku']?.toString() ?? '';
      final price =
          double.tryParse(v['price']?.toString() ?? '0') ?? 0;
      final stock = (v['inventory_quantity'] as num?)?.toInt() ?? 0;

      // Build option values map from Shopify's option1/option2/option3
      final optionValues = <String, String>{};
      for (var i = 0; i < options.length && i < 3; i++) {
        final optVal =
            v['option${i + 1}']?.toString() ?? '';
        if (optVal.isNotEmpty) {
          optionValues[options[i].name] = optVal;
        }
      }

      variants.add(ProductVariant(
        id: variantId,
        optionValues: optionValues,
        sku: sku,
        costPrice: 0, // Shopify doesn't expose cost in products API
        sellingPrice: price,
        currentStock: stock > 0 ? stock : 0,
        reorderPoint: 10,
        shopifyVariantId: shopifyVariantId,
        shopifyInventoryItemId: shopifyInvItemId,
      ));
    }

    // If no variants from Shopify, create a default one
    if (variants.isEmpty) {
      variants.add(ProductVariant(
        id: uuid.v4(),
        sku: '',
        costPrice: 0,
        sellingPrice: 0,
        currentStock: 0,
      ));
    }

    // ── Create the Revvo Product ────────────────────────
    final productId = uuid.v4();
    final product = Product(
      id: productId,
      userId: uid,
      name: title,
      category: 'Shopify Import',
      supplier: '',
      unitOfMeasure: 'pcs',
      imageUrl: imageUrl,
      shopifyProductId: shopifyProductId,
      options: options,
      variants: variants,
    );

    await ref.read(inventoryProvider.notifier).addProduct(product);

    // ── Create mappings for each variant ────────────────
    for (final variant in variants) {
      final mapping = ShopifyProductMapping(
        id: '',
        userId: '',
        revvoProductId: productId,
        revvoVariantId: variant.id,
        shopifyProductId: shopifyProductId,
        shopifyVariantId: variant.shopifyVariantId ?? '',
        shopifyInventoryItemId: variant.shopifyInventoryItemId ?? '',
        shopifySku: variant.sku,
        shopifyTitle:
            '$title${variant.displayName != "Default" ? " — ${variant.displayName}" : ""}',
        autoImported: true,
        createdAt: DateTime.now(),
      );
      await ref
          .read(shopifyMappingsProvider.notifier)
          .createMapping(mapping);
    }
  }

  /// Links an existing Revvo product to its Shopify counterpart by
  /// matching variants via shopifyVariantId or SKU.
  /// Called when dedup detects the product already exists.
  Future<void> _createMappingsForExistingProduct(
    Product revvoProduct,
    Map<String, dynamic> shopifyProduct,
    String shopifyTitle,
  ) async {
    final shopifyProductId = shopifyProduct['id']?.toString() ?? '';
    final shopifyVariants =
        (shopifyProduct['variants'] as List<dynamic>?) ?? [];

    // Build a map of Revvo variants by shopifyVariantId and SKU
    final revvoByShopifyVarId = <String, ProductVariant>{};
    final revvoBySku = <String, ProductVariant>{};
    for (final v in revvoProduct.variants) {
      if (v.shopifyVariantId != null && v.shopifyVariantId!.isNotEmpty) {
        revvoByShopifyVarId[v.shopifyVariantId!] = v;
      }
      final sku = v.sku.trim().toLowerCase();
      if (sku.isNotEmpty) revvoBySku[sku] = v;
    }

    // Match Shopify variants → Revvo variants and create mappings
    final usedRevvoVariantIds = <String>{};
    for (final sv in shopifyVariants) {
      final v = Map<String, dynamic>.from(sv as Map);
      final shopifyVariantId = v['id']?.toString() ?? '';
      final shopifySku = (v['sku']?.toString() ?? '').trim().toLowerCase();
      final inventoryItemId = v['inventory_item_id']?.toString() ?? '';

      // Find matching Revvo variant — prefer shopifyVariantId, then SKU
      final revvoVariant = revvoByShopifyVarId[shopifyVariantId] ??
          (shopifySku.isNotEmpty ? revvoBySku[shopifySku] : null);

      if (revvoVariant == null) continue;
      if (usedRevvoVariantIds.contains(revvoVariant.id)) continue;
      usedRevvoVariantIds.add(revvoVariant.id);

      final mapping = ShopifyProductMapping(
        id: '',
        userId: '',
        revvoProductId: revvoProduct.id,
        revvoVariantId: revvoVariant.id,
        shopifyProductId: shopifyProductId,
        shopifyVariantId: shopifyVariantId,
        shopifyInventoryItemId: inventoryItemId,
        shopifySku: shopifySku,
        shopifyTitle:
            '$shopifyTitle${revvoVariant.displayName != "Default" ? " — ${revvoVariant.displayName}" : ""}',
        autoImported: true,
        createdAt: DateTime.now(),
      );
      await ref
          .read(shopifyMappingsProvider.notifier)
          .createMapping(mapping);
    }

    // Update the Revvo product's shopifyProductId if not already set
    if (revvoProduct.shopifyProductId != shopifyProductId) {
      await ref.read(inventoryProvider.notifier).updateProduct(
        revvoProduct.id,
        revvoProduct.copyWith(shopifyProductId: shopifyProductId),
      );
    }
  }

  /// Extracts the primary image URL from a Shopify product JSON.
  String? _extractImageUrl(Map<String, dynamic> sp) {
    // Try product.image.src first
    if (sp['image'] != null && sp['image'] is Map) {
      final src = (sp['image'] as Map)['src']?.toString();
      if (src != null && src.isNotEmpty) return src;
    }
    // Try images array
    final images = sp['images'] as List<dynamic>?;
    if (images != null && images.isNotEmpty) {
      final first = images.first;
      if (first is Map) {
        return first['src']?.toString();
      }
    }
    return null;
  }

  // ── Link to existing Revvo product ─────────────────────

  void _showLinkPicker(Map<String, dynamic> shopifyProduct) {
    final products = ref.read(inventoryProvider).value ?? [];
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.shopifyNoRevvoProducts,
          ),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RevvoProductPickerSheet(
        shopifyProduct: shopifyProduct,
        revvoProducts: products,
        onSelected: (product) => _linkToRevvoProduct(
          shopifyProduct,
          product,
        ),
      ),
    );
  }

  Future<void> _linkToRevvoProduct(
    Map<String, dynamic> shopifyProduct,
    Product revvoProduct,
  ) async {
    HapticFeedback.mediumImpact();
    final shopifyProductId = shopifyProduct['id']?.toString() ?? '';
    final title = shopifyProduct['title']?.toString() ?? '';
    final shopifyVariants =
        (shopifyProduct['variants'] as List<dynamic>?) ?? [];

    // Auto-link variant by variant (by index for simple cases)
    for (var i = 0; i < shopifyVariants.length; i++) {
      final sv = Map<String, dynamic>.from(shopifyVariants[i] as Map);
      final revvoVariant = i < revvoProduct.variants.length
          ? revvoProduct.variants[i]
          : revvoProduct.variants.last;

      final mapping = ShopifyProductMapping(
        id: '',
        userId: '',
        revvoProductId: revvoProduct.id,
        revvoVariantId: revvoVariant.id,
        shopifyProductId: shopifyProductId,
        shopifyVariantId: sv['id']?.toString() ?? '',
        shopifyInventoryItemId:
            sv['inventory_item_id']?.toString() ?? '',
        shopifySku: sv['sku']?.toString() ?? '',
        shopifyTitle:
            '$title — ${sv['title']?.toString() ?? 'Default'}',
        autoImported: false,
        createdAt: DateTime.now(),
      );
      await ref
          .read(shopifyMappingsProvider.notifier)
          .createMapping(mapping);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.shopifyLinked(title, revvoProduct.name)),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Auto-match ──────────────────────────────────────────

  Future<void> _onAutoMatch() async {
    setState(() => _autoMatching = true);
    HapticFeedback.mediumImpact();
    final l10n = AppLocalizations.of(context)!;

    final result = await ref
        .read(shopifyMappingsProvider.notifier)
        .autoMatchBySku();

    if (!mounted) return;
    setState(() => _autoMatching = false);

    if (result.isSuccess) {
      final count = result.data ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(count > 0
              ? l10n.shopifyMatchedBySku(count)
              : l10n.shopifyNoMatchesBySku),
          backgroundColor: AppColors.primaryNavy,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? l10n.shopifyAutoMatchFailed),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  // ── Delete mapping ──────────────────────────────────────

  Future<void> _deleteMapping(ShopifyProductMapping mapping) async {
    HapticFeedback.lightImpact();
    final result = await ref
        .read(shopifyMappingsProvider.notifier)
        .deleteMapping(mapping.id);

    if (!mounted) return;
    if (result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.shopifyMappingRemoved),
          backgroundColor: AppColors.primaryNavy,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════
//  PRIVATE WIDGETS
// ═══════════════════════════════════════════════════════════

class _MiniStat extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$count $label',
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback? onTap;

  const _ActionChip({
    required this.label,
    required this.icon,
    this.loading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.primaryNavy.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.primaryNavy.withValues(alpha: 0.2),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primaryNavy,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: AppColors.primaryNavy),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.primaryNavy,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Shopify Product Tile ──────────────────────────────────

class _ShopifyProductTile extends StatefulWidget {
  final Map<String, dynamic> shopifyProduct;
  final List<ShopifyProductMapping> mappings;
  final bool isMapped;
  final VoidCallback onImport;
  final VoidCallback onLink;
  final ValueChanged<ShopifyProductMapping> onDeleteMapping;

  const _ShopifyProductTile({
    required this.shopifyProduct,
    required this.mappings,
    required this.isMapped,
    required this.onImport,
    required this.onLink,
    required this.onDeleteMapping,
  });

  @override
  State<_ShopifyProductTile> createState() => _ShopifyProductTileState();
}

class _ShopifyProductTileState extends State<_ShopifyProductTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title =
        widget.shopifyProduct['title']?.toString() ?? 'Untitled';
    final variants =
        (widget.shopifyProduct['variants'] as List<dynamic>?) ?? [];
    final imageUrl = _extractImage(widget.shopifyProduct);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.isMapped
              ? AppColors.success.withValues(alpha: 0.3)
              : AppColors.warning.withValues(alpha: 0.3),
        ),
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
          // Main row
          InkWell(
            onTap: widget.isMapped
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Product image or icon
                  _ProductImage(imageUrl: imageUrl, isMapped: widget.isMapped),
                  const SizedBox(width: 12),

                  // Product info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.isMapped
                              ? l10n.shopifyVariantsLinked(widget.mappings.length)
                              : l10n.shopifyVariantsNotImported(variants.length),
                          style: AppTypography.bodySmall.copyWith(
                            color: widget.isMapped
                                ? AppColors.success
                                : AppColors.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                        if (variants.isNotEmpty && !widget.isMapped) ...[
                          const SizedBox(height: 2),
                          Text(
                            _variantSummary(variants),
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Action buttons for unmapped
                  if (!widget.isMapped) ...[
                    const SizedBox(width: 4),
                    _SmallButton(
                      label: l10n.shopifyImportButton,
                      icon: Icons.download_rounded,
                      color: AppColors.primaryNavy,
                      onTap: widget.onImport,
                    ),
                    const SizedBox(width: 6),
                    _SmallButton(
                      label: l10n.shopifyLinkButton,
                      icon: Icons.link_rounded,
                      color: AppColors.textTertiary,
                      onTap: widget.onLink,
                    ),
                  ] else ...[
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 22,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Expanded variant mappings
          if (_expanded && widget.mappings.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                color: AppColors.backgroundLight.withValues(alpha: 0.5),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(14),
                ),
              ),
              child: Column(
                children: [
                  Divider(
                    height: 1,
                    color: AppColors.borderLight.withValues(alpha: 0.5),
                  ),
                  for (final mapping in widget.mappings)
                    _VariantMappingRow(
                      mapping: mapping,
                      onDelete: () =>
                          widget.onDeleteMapping(mapping),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _variantSummary(List<dynamic> variants) {
    final first = variants.first;
    if (first is Map) {
      final sku = first['sku']?.toString() ?? '';
      final price = first['price']?.toString() ?? '';
      final parts = <String>[];
      if (sku.isNotEmpty) parts.add('SKU: $sku');
      if (price.isNotEmpty) parts.add('\$$price');
      return parts.join(' • ');
    }
    return '';
  }

  static String? _extractImage(Map<String, dynamic> sp) {
    if (sp['image'] != null && sp['image'] is Map) {
      final src = (sp['image'] as Map)['src']?.toString();
      if (src != null && src.isNotEmpty) return src;
    }
    final images = sp['images'] as List<dynamic>?;
    if (images != null && images.isNotEmpty) {
      final first = images.first;
      if (first is Map) return first['src']?.toString();
    }
    return null;
  }
}

// ── Small Action Button ───────────────────────────────────

class _SmallButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SmallButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Product Image ─────────────────────────────────────────

class _ProductImage extends StatelessWidget {
  final String? imageUrl;
  final bool isMapped;

  const _ProductImage({this.imageUrl, required this.isMapped});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isMapped
            ? AppColors.success.withValues(alpha: 0.08)
            : AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isMapped
              ? AppColors.success.withValues(alpha: 0.2)
              : AppColors.borderLight,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl != null
          ? Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, e, st) => Icon(
                Icons.storefront_rounded,
                size: 22,
                color: isMapped
                    ? AppColors.success
                    : AppColors.textTertiary,
              ),
            )
          : Icon(
              Icons.storefront_rounded,
              size: 22,
              color: isMapped
                  ? AppColors.success
                  : AppColors.textTertiary,
            ),
    );
  }
}

// ── Variant Mapping Row ───────────────────────────────────

class _VariantMappingRow extends StatelessWidget {
  final ShopifyProductMapping mapping;
  final VoidCallback onDelete;

  const _VariantMappingRow({
    required this.mapping,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          const SizedBox(width: 44 + 12), // align with product text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mapping.shopifyTitle.isEmpty
                      ? AppLocalizations.of(context)!.shopifyVariantLabel
                      : mapping.shopifyTitle,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (mapping.shopifySku.isNotEmpty)
                  Text(
                    'SKU: ${mapping.shopifySku}',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onDelete,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.link_off_rounded,
                size: 16,
                color: AppColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Revvo Product Picker (for "Link" flow) ───────────────

class _RevvoProductPickerSheet extends StatefulWidget {
  final Map<String, dynamic> shopifyProduct;
  final List<Product> revvoProducts;
  final ValueChanged<Product> onSelected;

  const _RevvoProductPickerSheet({
    required this.shopifyProduct,
    required this.revvoProducts,
    required this.onSelected,
  });

  @override
  State<_RevvoProductPickerSheet> createState() =>
      _RevvoProductPickerSheetState();
}

class _RevvoProductPickerSheetState
    extends State<_RevvoProductPickerSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final filtered = widget.revvoProducts.where((p) {
      if (_search.isEmpty) return true;
      final q = _search.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q);
    }).toList();

    final shopifyTitle =
        widget.shopifyProduct['title']?.toString() ?? 'Product';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.shopifyLinkToRevvo,
                  style: AppTypography.h3.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.shopifyLinkSubtitle(shopifyTitle),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: l10n.shopifySearchHint,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                filled: true,
                fillColor: AppColors.backgroundLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      l10n.shopifyNoMatchingProducts,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final p = filtered[i];
                      return ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.primaryNavy
                                .withValues(alpha: 0.08),
                            borderRadius:
                                BorderRadius.circular(8),
                          ),
                          child: Icon(p.icon,
                              size: 18,
                              color: AppColors.primaryNavy),
                        ),
                        title: Text(
                          p.name,
                          style: AppTypography.labelSmall.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          '${p.variants.length} variant(s) • SKU: ${p.sku}',
                          style: AppTypography.bodySmall.copyWith(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          widget.onSelected(p);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
