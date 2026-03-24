import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_styles.dart';
import '../../../../shared/models/product_model.dart';
import '../../../l10n/app_localizations.dart';
import 'package:intl/intl.dart';

class ItemSelectionResult {
  final Product? product;
  final ProductVariant? variant;
  final String? customName;

  ItemSelectionResult({this.product, this.variant, this.customName});
}

class ItemSelectionSheet extends StatefulWidget {
  final List<Product> inventory;
  final String currency;

  const ItemSelectionSheet({
    super.key,
    required this.inventory,
    this.currency = 'EGP',
  });

  @override
  State<ItemSelectionSheet> createState() => _ItemSelectionSheetState();
}

class _ItemSelectionSheetState extends State<ItemSelectionSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Product> _filteredInventory = [];

  @override
  void initState() {
    super.initState();
    _filteredInventory = widget.inventory;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filter(String query) {
    if (query.isEmpty) {
      setState(() => _filteredInventory = widget.inventory);
      return;
    }
    final lowerQuery = query.toLowerCase();
    setState(() {
      _filteredInventory = widget.inventory.where((p) {
        return p.name.toLowerCase().contains(lowerQuery) ||
               p.category.toLowerCase().contains(lowerQuery);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final fmt = NumberFormat('#,##0', 'en');

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 24,
        left: 20,
        right: 20,
        bottom: bottomInset > 0 ? bottomInset + 20 : 32,
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.selectItemTitle, style: AppTypography.h3),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
                color: AppColors.textTertiary,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Search Bar
          TextField(
            controller: _searchCtrl,
            onChanged: _filter,
            decoration: InputDecoration(
              hintText: l10n.searchInventoryHint,
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.grey),
              filled: true,
              fillColor: AppColors.backgroundLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
            ),
          ),
          const SizedBox(height: 16),
          // List
          Flexible(
            child: _filteredInventory.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        l10n.noMatchingItems,
                        style: TextStyle(color: AppColors.textTertiary),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _filteredInventory.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: AppColors.borderLight.withValues(alpha: 0.3),
                    ),
                    itemBuilder: (context, index) {
                      final product = _filteredInventory[index];
                      return ListTile(
                        onTap: () {
                          if (product.hasVariants && product.variants.length > 1) {
                            _showVariantPicker(context, product);
                          } else {
                            final variant = product.variants.isNotEmpty ? product.variants.first : null;
                            Navigator.pop(context, ItemSelectionResult(product: product, variant: variant));
                          }
                        },
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: product.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: CachedNetworkImage(
                                    imageUrl: product.imageUrl!,
                                    fit: BoxFit.cover,
                                    width: 40,
                                    height: 40,
                                    placeholder: (_, _) => Icon(product.icon, color: product.color, size: 20),
                                    errorWidget: (_, _, _) => Icon(product.icon, color: product.color, size: 20),
                                  ),
                                )
                              : Icon(product.icon, color: product.color, size: 20),
                        ),
                        title: Text(
                          product.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: Text(
                          '${product.isMaterial ? l10n.rawMaterial : l10n.productLabel} • ${l10n.stockLabel(product.currentStock)}'
                          '${product.hasVariants && product.variants.length > 1 ? ' • ${l10n.variantCount(product.variants.length)}' : ''}',
                          style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                        ),
                        trailing: Text(
                          '${widget.currency} ${fmt.format(product.costPrice)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          // Custom Item Button
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: GestureDetector(
              onTap: () async {
                if (_searchCtrl.text.isNotEmpty) {
                  Navigator.pop(context, ItemSelectionResult(customName: _searchCtrl.text));
                } else {
                  final name = await _showCustomNameDialog(context);
                  if (name != null && name.trim().isNotEmpty) {
                    if (context.mounted) {
                      Navigator.pop(context, ItemSelectionResult(customName: name.trim()));
                    }
                  }
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.primaryNavy.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primaryNavy.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _searchCtrl.text.isNotEmpty ? Icons.add_rounded : Icons.edit_rounded,
                      color: AppColors.primaryNavy, size: 20
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _searchCtrl.text.isNotEmpty 
                          ? l10n.addAsCustomItem(_searchCtrl.text)
                          : l10n.writeCustomItem,
                      style: TextStyle(
                        color: AppColors.primaryNavy,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showVariantPicker(BuildContext ctx, Product product) {
    final l10n = AppLocalizations.of(ctx)!;
    final fmt = NumberFormat('#,##0', 'en');
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetCtx).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    l10n.selectVariantTitle(product.name),
                    style: AppTypography.h3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(sheetCtx),
                  icon: const Icon(Icons.close_rounded),
                  color: AppColors.textTertiary,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                itemCount: product.variants.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: AppColors.borderLight.withValues(alpha: 0.3),
                ),
                itemBuilder: (_, i) {
                  final v = product.variants[i];
                  return ListTile(
                    onTap: () {
                      Navigator.pop(sheetCtx); // close variant picker
                      Navigator.pop(ctx, ItemSelectionResult(product: product, variant: v));
                    },
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    leading: Builder(
                      builder: (_) {
                        final imgUrl = v.imageUrl ?? product.imageUrl;
                        return Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.primaryNavy.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: imgUrl != null && imgUrl.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CachedNetworkImage(
                                    imageUrl: imgUrl,
                                    fit: BoxFit.cover,
                                    width: 36,
                                    height: 36,
                                    placeholder: (_, _) => const Icon(Icons.style_rounded, color: AppColors.primaryNavy, size: 18),
                                    errorWidget: (_, _, _) => const Icon(Icons.style_rounded, color: AppColors.primaryNavy, size: 18),
                                  ),
                                )
                              : const Icon(Icons.style_rounded, color: AppColors.primaryNavy, size: 18),
                        );
                      },
                    ),
                    title: Text(
                      v.localizedDisplayName(l10n),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: Text(
                      '${l10n.skuLabel(v.sku.isNotEmpty ? v.sku : '—')} • ${l10n.stockLabel(v.currentStock)}',
                      style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                    ),
                    trailing: Text(
                      '${widget.currency} ${fmt.format(v.costPrice)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showCustomNameDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final TextEditingController nameCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.customItemTitle, style: AppTypography.h3),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l10n.enterItemNameHint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel, style: TextStyle(color: AppColors.textTertiary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryNavy,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, nameCtrl.text),
            child: Text(l10n.addAction, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
