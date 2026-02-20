import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_styles.dart';
import '../../../../shared/models/product_model.dart';
import 'package:intl/intl.dart';

class ItemSelectionResult {
  final Product? product;
  final String? customName;

  ItemSelectionResult({this.product, this.customName});
}

class ItemSelectionSheet extends StatefulWidget {
  final List<Product> inventory;

  const ItemSelectionSheet({super.key, required this.inventory});

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
              Text('Select Item', style: AppTypography.h3),
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
              hintText: 'Search inventory...',
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
                        'No matching items found.',
                        style: TextStyle(color: AppColors.textTertiary),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _filteredInventory.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: AppColors.borderLight.withValues(alpha: 0.3),
                    ),
                    itemBuilder: (context, index) {
                      final product = _filteredInventory[index];
                      return ListTile(
                        onTap: () {
                          Navigator.pop(context, ItemSelectionResult(product: product));
                        },
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: product.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(product.icon, color: product.color, size: 20),
                        ),
                        title: Text(
                          product.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: Text(
                          '${product.isMaterial ? 'Raw Material' : 'Product'} • Stock: ${product.currentStock}',
                          style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                        ),
                        trailing: Text(
                          'EGP ${fmt.format(product.costPrice)}',
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
                          ? 'Add "${_searchCtrl.text}" as custom item'
                          : 'Write a custom item',
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

  Future<String?> _showCustomNameDialog(BuildContext context) {
    final TextEditingController nameCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Custom Item', style: AppTypography.h3),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter item name...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
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
            onPressed: () => Navigator.pop(ctx, nameCtrl.text),
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
