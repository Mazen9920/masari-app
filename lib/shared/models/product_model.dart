import 'package:flutter/material.dart';

import '../utils/money_utils.dart';

/// Stock status of a product or variant
enum StockStatus { inStock, lowStock, outOfStock }

// ═══════════════════════════════════════════════════════════
//  COST LAYER — a batch of inventory received at a specific cost
// ═══════════════════════════════════════════════════════════

/// Represents a batch (lot) of inventory received at a particular cost.
/// Used by FIFO/LIFO costing to track which units to consume first.
class CostLayer {
  final DateTime date;
  final double unitCost;
  final int remainingQty;

  const CostLayer({
    required this.date,
    required this.unitCost,
    required this.remainingQty,
  });

  CostLayer copyWith({DateTime? date, double? unitCost, int? remainingQty}) {
    return CostLayer(
      date: date ?? this.date,
      unitCost: unitCost ?? this.unitCost,
      remainingQty: remainingQty ?? this.remainingQty,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'unit_cost': unitCost,
        'remaining_qty': remainingQty,
      };

  factory CostLayer.fromJson(Map<String, dynamic> json) {
    return CostLayer(
      date: DateTime.parse(json['date'] as String),
      unitCost: (json['unit_cost'] as num).toDouble(),
      remainingQty: (json['remaining_qty'] as num).toInt(),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  BREAKDOWN RECIPE — defines how a source variant breaks into outputs
// ═══════════════════════════════════════════════════════════

/// One output of a breakdown recipe, referencing a variant within the same product.
class BreakdownOutput {
  final String variantId;
  final double quantityPerUnit; // how many of this variant per 1 unit of source

  const BreakdownOutput({
    required this.variantId,
    required this.quantityPerUnit,
  });

  BreakdownOutput copyWith({String? variantId, double? quantityPerUnit}) {
    return BreakdownOutput(
      variantId: variantId ?? this.variantId,
      quantityPerUnit: quantityPerUnit ?? this.quantityPerUnit,
    );
  }

  Map<String, dynamic> toJson() => {
        'variant_id': variantId,
        'quantity_per_unit': quantityPerUnit,
      };

  factory BreakdownOutput.fromJson(Map<String, dynamic> json) {
    return BreakdownOutput(
      variantId: json['variant_id'] as String,
      quantityPerUnit: (json['quantity_per_unit'] as num).toDouble(),
    );
  }
}

/// Defines how a source variant is broken down into output variants.
/// E.g., 1 "Whole Chicken" → 2 "Breast" + 2 "Thighs" + 2 "Wings".
class BreakdownRecipe {
  final String sourceVariantId;
  final List<BreakdownOutput> outputs;

  const BreakdownRecipe({
    required this.sourceVariantId,
    required this.outputs,
  });

  BreakdownRecipe copyWith({
    String? sourceVariantId,
    List<BreakdownOutput>? outputs,
  }) {
    return BreakdownRecipe(
      sourceVariantId: sourceVariantId ?? this.sourceVariantId,
      outputs: outputs ?? this.outputs,
    );
  }

  Map<String, dynamic> toJson() => {
        'source_variant_id': sourceVariantId,
        'outputs': outputs.map((o) => o.toJson()).toList(),
      };

  factory BreakdownRecipe.fromJson(Map<String, dynamic> json) {
    return BreakdownRecipe(
      sourceVariantId: json['source_variant_id'] as String,
      outputs: (json['outputs'] as List<dynamic>)
          .map((o) => BreakdownOutput.fromJson(o as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  PRODUCT OPTION — e.g. "Color" with values ["Red", "Blue"]
// ═══════════════════════════════════════════════════════════

/// A user-defined option type for a product (up to 3 per product).
/// Example: ProductOption(name: 'Color', values: ['Red', 'Blue', 'Green'])
class ProductOption {
  final String name;
  final List<String> values;

  const ProductOption({required this.name, required this.values});

  ProductOption copyWith({String? name, List<String>? values}) {
    return ProductOption(
      name: name ?? this.name,
      values: values ?? this.values,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'values': values,
      };

  factory ProductOption.fromJson(Map<String, dynamic> json) {
    return ProductOption(
      name: json['name'] as String,
      values: (json['values'] as List<dynamic>).cast<String>(),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  PRODUCT VARIANT — a specific combination of option values
// ═══════════════════════════════════════════════════════════

/// A single variant of a product. Each variant has its own SKU, price,
/// cost, stock level, and movement history.
///
/// Example: Variant for "Red / M" of a T-Shirt product.
class ProductVariant {
  final String id;

  /// Maps option name → selected value, e.g. {"Color": "Red", "Size": "M"}.
  /// Empty map for the "Default" variant of a product with no options.
  final Map<String, String> optionValues;

  final String sku;
  final double costPrice;
  final double sellingPrice;
  final int currentStock;
  final int reorderPoint;
  final String? imageUrl;
  final String? barcode;
  final List<StockMovement> movements;

  /// Cost layers (lots) for FIFO/LIFO/Average costing.
  /// Each layer represents a batch received at a specific cost.
  final List<CostLayer> costLayers;

  // ── Shopify integration ─────────────────────────────────
  /// Shopify variant ID for two-way sync.
  final String? shopifyVariantId;
  /// Shopify inventory item ID for stock-level sync.
  final String? shopifyInventoryItemId;

  const ProductVariant({
    required this.id,
    this.optionValues = const {},
    required this.sku,
    required this.costPrice,
    required this.sellingPrice,
    required this.currentStock,
    this.reorderPoint = 10,
    this.imageUrl,
    this.barcode,
    this.movements = const [],
    this.costLayers = const [],
    this.shopifyVariantId,
    this.shopifyInventoryItemId,
  });

  // ── Computed ────────────────────────────────────────────

  StockStatus get status {
    if (currentStock <= 0) return StockStatus.outOfStock;
    if (currentStock <= reorderPoint) return StockStatus.lowStock;
    return StockStatus.inStock;
  }

  double get totalValue => roundMoney(currentStock * sellingPrice);
  double get totalCostValue => roundMoney(currentStock * costPrice);

  /// Human-readable name, e.g. "Red / M" or "Default".
  String get displayName {
    if (optionValues.isEmpty) return 'Default';
    return optionValues.values.join(' / ');
  }

  /// Whether this is the auto-created default variant (no options).
  bool get isDefault => optionValues.isEmpty;

  /// Returns the effective cost layers, auto-migrating from legacy data.
  /// If costLayers is empty but stock/cost exist, creates a single layer
  /// dated to epoch so it sorts as the oldest (FIFO consumes it first).
  List<CostLayer> get effectiveCostLayers {
    if (costLayers.isNotEmpty) return costLayers;
    if (currentStock > 0 && costPrice > 0) {
      return [CostLayer(date: DateTime(2000), unitCost: costPrice, remainingQty: currentStock)];
    }
    return [];
  }

  /// Calculate COGS per unit for [qty] units based on the costing method.
  /// Pure calculation — does not modify layers.
  /// [method]: 'fifo', 'lifo', or 'average'.
  double cogsPerUnit(int qty, String method) {
    if (qty <= 0) return costPrice;
    if (method == 'average' || effectiveCostLayers.isEmpty) return costPrice;

    final layers = List<CostLayer>.from(effectiveCostLayers);
    if (method == 'lifo') {
      layers.sort((a, b) => b.date.compareTo(a.date)); // newest first
    } else {
      layers.sort((a, b) => a.date.compareTo(b.date)); // oldest first (FIFO)
    }

    var remaining = qty;
    var totalCost = 0.0;
    for (final layer in layers) {
      if (remaining <= 0) break;
      final take = remaining < layer.remainingQty ? remaining : layer.remainingQty;
      totalCost += take * layer.unitCost;
      remaining -= take;
    }
    // If remaining > 0 (shouldn't happen with valid stock), use last known cost
    if (remaining > 0) totalCost += remaining * costPrice;

    return (totalCost / qty * 100).roundToDouble() / 100;
  }

  // ── Copy / Serialization ───────────────────────────────

  ProductVariant copyWith({
    String? id,
    Map<String, String>? optionValues,
    String? sku,
    double? costPrice,
    double? sellingPrice,
    int? currentStock,
    int? reorderPoint,
    String? imageUrl,
    String? barcode,
    List<StockMovement>? movements,
    List<CostLayer>? costLayers,
    String? shopifyVariantId,
    String? shopifyInventoryItemId,
  }) {
    return ProductVariant(
      id: id ?? this.id,
      optionValues: optionValues ?? this.optionValues,
      sku: sku ?? this.sku,
      costPrice: costPrice ?? this.costPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      currentStock: currentStock ?? this.currentStock,
      reorderPoint: reorderPoint ?? this.reorderPoint,
      imageUrl: imageUrl ?? this.imageUrl,
      barcode: barcode ?? this.barcode,
      movements: movements ?? this.movements,
      costLayers: costLayers ?? this.costLayers,
      shopifyVariantId: shopifyVariantId ?? this.shopifyVariantId,
      shopifyInventoryItemId: shopifyInventoryItemId ?? this.shopifyInventoryItemId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'option_values': optionValues,
        'sku': sku,
        'cost_price': costPrice,
        'selling_price': sellingPrice,
        'current_stock': currentStock,
        'reorder_point': reorderPoint,
        if (imageUrl != null) 'image_url': imageUrl,
        if (barcode != null) 'barcode': barcode,
        'movements': movements.map((m) => m.toJson()).toList(),
        'cost_layers': costLayers.map((l) => l.toJson()).toList(),
        if (shopifyVariantId != null) 'shopify_variant_id': shopifyVariantId,
        if (shopifyInventoryItemId != null) 'shopify_inventory_item_id': shopifyInventoryItemId,
      };

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    return ProductVariant(
      id: json['id'] as String,
      optionValues: (json['option_values'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          const {},
      sku: json['sku'] as String? ?? '',
      costPrice: (json['cost_price'] as num?)?.toDouble() ?? 0,
      sellingPrice: (json['selling_price'] as num?)?.toDouble() ?? 0,
      currentStock: (json['current_stock'] as num?)?.toInt() ?? 0,
      reorderPoint: (json['reorder_point'] as num?)?.toInt() ?? 10,
      imageUrl: json['image_url'] as String?,
      barcode: json['barcode'] as String?,
      movements: (json['movements'] as List<dynamic>?)
              ?.map((m) => StockMovement.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
      costLayers: (json['cost_layers'] as List<dynamic>?)
              ?.map((l) => CostLayer.fromJson(l as Map<String, dynamic>))
              .toList() ??
          [],
      shopifyVariantId: json['shopify_variant_id'] as String?,
      shopifyInventoryItemId: json['shopify_inventory_item_id'] as String?,
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  PRODUCT — the parent product, now with options + variants
// ═══════════════════════════════════════════════════════════

/// Product model for the inventory system.
///
/// Every product has at least one [ProductVariant]. Products without
/// user-defined options contain a single "Default" variant.
/// Stock, pricing, and movements live at the **variant** level.
class Product {
  final String id;
  final String userId;
  final String name;
  final String category;
  final String supplier;
  final String unitOfMeasure;
  final IconData icon;
  final Color color;
  final String? imageUrl;
  final bool isMaterial;
  final String? baseMaterialType;
  final double? scrapPercentage;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // ── Shopify integration ─────────────────────────────────
  /// Shopify product ID for two-way sync.
  final String? shopifyProductId;

  /// Up to 3 user-defined option types (e.g. Color, Size, Material).
  final List<ProductOption> options;

  /// All variants of this product. Always has at least one element.
  final List<ProductVariant> variants;

  /// Optional breakdown recipe: defines how a source variant is broken down
  /// into output variants within this product.
  final BreakdownRecipe? breakdownRecipe;

  const Product({
    required this.id,
    required this.userId,
    required this.name,
    required this.category,
    required this.supplier,
    this.unitOfMeasure = 'Pieces',
    this.icon = Icons.inventory_2_rounded,
    this.color = const Color(0xFF1B4F72),
    this.imageUrl,
    this.isMaterial = false,
    this.baseMaterialType,
    this.scrapPercentage,
    this.createdAt,
    this.updatedAt,
    this.shopifyProductId,
    this.options = const [],
    this.variants = const [],
    this.breakdownRecipe,
  });

  // ── Aggregate computed properties across all variants ───

  /// Primary SKU — first variant's SKU (for display in lists).
  String get sku => variants.isNotEmpty ? variants.first.sku : '';

  /// Aggregate stock across all variants.
  int get currentStock =>
      variants.fold(0, (sum, v) => sum + v.currentStock);

  /// Weighted-average cost price across variants (weighted by stock).
  double get costPrice {
    final total = currentStock;
    if (total <= 0) {
      return variants.isNotEmpty ? variants.first.costPrice : 0;
    }
    return roundMoney(
      variants.fold(0.0, (s, v) => s + v.currentStock * v.costPrice) / total,
    );
  }

  /// First variant's selling price (for display; actual price is per-variant).
  double get sellingPrice =>
      variants.isNotEmpty ? variants.first.sellingPrice : 0;

  /// Minimum reorder point across variants.
  int get reorderPoint =>
      variants.isNotEmpty
          ? variants.map((v) => v.reorderPoint).reduce((a, b) => a < b ? a : b)
          : 10;

  /// Aggregate total selling value.
  double get totalValue =>
      roundMoney(variants.fold(0.0, (s, v) => s + v.totalValue));

  /// Aggregate total cost value — used for balance sheet inventory valuation.
  double get totalCostValue =>
      roundMoney(variants.fold(0.0, (s, v) => s + v.totalCostValue));

  /// Profit margin of the first variant (for display).
  double get profitMargin {
    final sp = sellingPrice;
    final cp = costPrice;
    return sp > 0 ? roundMoney((sp - cp) / sp * 100) : 0;
  }

  /// Worst stock status across all variants.
  StockStatus get status {
    if (variants.isEmpty || variants.every((v) => v.currentStock <= 0)) {
      return StockStatus.outOfStock;
    }
    if (variants.any((v) => v.status == StockStatus.lowStock || v.status == StockStatus.outOfStock)) {
      return StockStatus.lowStock;
    }
    return StockStatus.inStock;
  }

  /// All movements across all variants, sorted newest first.
  List<StockMovement> get movements {
    final all = <StockMovement>[];
    for (final v in variants) {
      all.addAll(v.movements);
    }
    all.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return all;
  }

  /// Whether this product has user-defined variant options.
  bool get hasVariants => options.isNotEmpty;

  /// Total number of variants.
  int get variantCount => variants.length;

  /// Look up a specific variant by its ID.
  ProductVariant? variantById(String variantId) {
    for (final v in variants) {
      if (v.id == variantId) return v;
    }
    return null;
  }

  /// The default (first) variant.
  ProductVariant get defaultVariant => variants.first;

  /// Whether this product has a breakdown recipe defined.
  bool get hasBreakdown =>
      breakdownRecipe != null && breakdownRecipe!.outputs.isNotEmpty;

  // ── Copy / Serialization ───────────────────────────────

  Product copyWith({
    String? name,
    String? userId,
    String? category,
    String? supplier,
    String? unitOfMeasure,
    IconData? icon,
    Color? color,
    String? imageUrl,
    bool? isMaterial,
    String? baseMaterialType,
    double? scrapPercentage,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? shopifyProductId,
    List<ProductOption>? options,
    List<ProductVariant>? variants,
    BreakdownRecipe? breakdownRecipe,
  }) {
    return Product(
      id: id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      category: category ?? this.category,
      supplier: supplier ?? this.supplier,
      unitOfMeasure: unitOfMeasure ?? this.unitOfMeasure,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      imageUrl: imageUrl ?? this.imageUrl,
      isMaterial: isMaterial ?? this.isMaterial,
      baseMaterialType: baseMaterialType ?? this.baseMaterialType,
      scrapPercentage: scrapPercentage ?? this.scrapPercentage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      shopifyProductId: shopifyProductId ?? this.shopifyProductId,
      options: options ?? this.options,
      variants: variants ?? this.variants,
      breakdownRecipe: breakdownRecipe ?? this.breakdownRecipe,
    );
  }

  /// Serializes to JSON for backend communication.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'sku': sku, // keep top-level sku for backward compat / queries
      'category': category,
      'supplier': supplier,
      'unit_of_measure': unitOfMeasure,
      'icon_code': icon.codePoint,
      'color': color.toARGB32(),
      if (imageUrl != null) 'image_url': imageUrl,
      'is_material': isMaterial,
      if (baseMaterialType != null) 'base_material_type': baseMaterialType,
      if (scrapPercentage != null) 'scrap_percentage': scrapPercentage,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      if (shopifyProductId != null) 'shopify_product_id': shopifyProductId,
      'options': options.map((o) => o.toJson()).toList(),
      'variants': variants.map((v) => v.toJson()).toList(),
      if (breakdownRecipe != null)
        'breakdown_recipe': breakdownRecipe!.toJson(),
      // Aggregate fields kept for backward compat / Firestore queries
      'cost_price': costPrice,
      'selling_price': sellingPrice,
      'current_stock': currentStock,
      'reorder_point': reorderPoint,
    };
  }

  /// Deserializes from JSON. Backward-compatible: if `variants` key is missing,
  /// auto-creates a single "Default" variant from the flat product fields.
  factory Product.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;

    // Parse options
    final optionsList = (json['options'] as List<dynamic>?)
            ?.map((o) => ProductOption.fromJson(o as Map<String, dynamic>))
            .toList() ??
        [];

    // Parse variants — backward-compatible migration
    List<ProductVariant> variantsList;
    if (json['variants'] != null && (json['variants'] as List).isNotEmpty) {
      variantsList = (json['variants'] as List<dynamic>)
          .map((v) => ProductVariant.fromJson(v as Map<String, dynamic>))
          .toList();
    } else {
      // Legacy product without variants → create a Default variant
      variantsList = [
        ProductVariant(
          id: '${id}_v0',
          optionValues: const {},
          sku: json['sku'] as String? ?? '',
          costPrice: (json['cost_price'] as num?)?.toDouble() ?? 0,
          sellingPrice: (json['selling_price'] as num?)?.toDouble() ?? 0,
          currentStock: (json['current_stock'] as num?)?.toInt() ?? 0,
          reorderPoint: (json['reorder_point'] as num?)?.toInt() ?? 10,
          imageUrl: json['image_url'] as String?,
          movements: (json['movements'] as List<dynamic>?)
                  ?.map((m) =>
                      StockMovement.fromJson(m as Map<String, dynamic>))
                  .toList() ??
              [],
        ),
      ];
    }

    return Product(
      id: id,
      userId: json['user_id'] as String? ?? 'system',
      name: json['name'] as String,
      category: json['category'] as String,
      supplier: json['supplier'] as String,
      unitOfMeasure: json['unit_of_measure'] as String? ?? 'Pieces',
      icon: json['icon_code'] != null
          ? IconData(json['icon_code'] as int, fontFamily: 'MaterialIcons')
          : Icons.inventory_2_rounded,
      color: json['color'] != null
          ? Color(json['color'] as int)
          : const Color(0xFF1B4F72),
      imageUrl: json['image_url'] as String?,
      isMaterial: json['is_material'] as bool? ?? false,
      baseMaterialType: json['base_material_type'] as String?,
      scrapPercentage: (json['scrap_percentage'] as num?)?.toDouble(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      shopifyProductId: json['shopify_product_id'] as String?,
      options: optionsList,
      variants: variantsList,
      breakdownRecipe: json['breakdown_recipe'] != null
          ? BreakdownRecipe.fromJson(
              json['breakdown_recipe'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// A single stock movement event (restock, sale, adjustment, damage, breakdown).
class StockMovement {
  final String type; // Restock, Sale, Damage, Correction, Return, Breakdown
  final int quantity; // positive = in, negative = out
  final DateTime dateTime;
  final String? note;
  final String? variantId; // optional — links movement to specific variant
  final double? unitCost; // cost per unit at time of this movement
  final String? supplierName; // supplier who provided the stock (Restock only)

  const StockMovement({
    required this.type,
    required this.quantity,
    required this.dateTime,
    this.note,
    this.variantId,
    this.unitCost,
    this.supplierName,
  });

  IconData get icon {
    switch (type) {
      case 'Restock':
        return Icons.arrow_upward_rounded;
      case 'Sale':
        return Icons.shopping_cart_rounded;
      case 'Damage':
        return Icons.broken_image_rounded;
      case 'Return':
        return Icons.replay_rounded;
      case 'Breakdown':
        return Icons.call_split_rounded;
      default:
        return Icons.tune_rounded;
    }
  }

  Color get iconColor {
    switch (type) {
      case 'Restock':
        return const Color(0xFF10B981);
      case 'Sale':
        return const Color(0xFF3B82F6);
      case 'Damage':
        return const Color(0xFFEF4444);
      case 'Return':
        return const Color(0xFF8B5CF6);
      case 'Breakdown':
        return const Color(0xFFEC4899);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'quantity': quantity,
      'date_time': dateTime.toIso8601String(),
      if (note != null) 'note': note,
      if (variantId != null) 'variant_id': variantId,
      if (unitCost != null) 'unit_cost': unitCost,
      if (supplierName != null) 'supplier_name': supplierName,
    };
  }

  factory StockMovement.fromJson(Map<String, dynamic> json) {
    return StockMovement(
      type: json['type'] as String? ?? 'unknown',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      dateTime: json['date_time'] != null
          ? DateTime.parse(json['date_time'] as String)
          : DateTime.now(),
      note: json['note'] as String?,
      variantId: json['variant_id'] as String?,
      unitCost: (json['unit_cost'] as num?)?.toDouble(),
      supplierName: json['supplier_name'] as String?,
    );
  }
}

/// Empty initial state for products
final List<Product> sampleProducts = [];
