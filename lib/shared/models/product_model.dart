import 'package:flutter/material.dart';

/// Stock status of a product
enum StockStatus { inStock, lowStock, outOfStock }

/// Product model for the inventory system.
class Product {
  final String id;
  final String name;
  final String sku;
  final String category;
  final String supplier;
  final double costPrice;
  final double sellingPrice;
  final int currentStock;
  final int reorderPoint;
  final String unitOfMeasure;
  final IconData icon;
  final Color color;
  final bool isMaterial;
  final List<StockMovement> movements;

  const Product({
    required this.id,
    required this.name,
    required this.sku,
    required this.category,
    required this.supplier,
    required this.costPrice,
    required this.sellingPrice,
    required this.currentStock,
    this.reorderPoint = 10,
    this.unitOfMeasure = 'Pieces',
    this.icon = Icons.inventory_2_rounded,
    this.color = const Color(0xFF1B4F72),
    this.isMaterial = false,
    this.movements = const [],
  });

  StockStatus get status {
    if (currentStock <= 0) return StockStatus.outOfStock;
    if (currentStock <= reorderPoint) return StockStatus.lowStock;
    return StockStatus.inStock;
  }

  double get totalValue => currentStock * sellingPrice;
  double get profitMargin =>
      sellingPrice > 0 ? ((sellingPrice - costPrice) / sellingPrice * 100) : 0;

  Product copyWith({
    String? name,
    String? sku,
    String? category,
    String? supplier,
    double? costPrice,
    double? sellingPrice,
    int? currentStock,
    int? reorderPoint,
    String? unitOfMeasure,
    IconData? icon,
    Color? color,
    bool? isMaterial,
    List<StockMovement>? movements,
  }) {
    return Product(
      id: id,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      category: category ?? this.category,
      supplier: supplier ?? this.supplier,
      costPrice: costPrice ?? this.costPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      currentStock: currentStock ?? this.currentStock,
      reorderPoint: reorderPoint ?? this.reorderPoint,
      unitOfMeasure: unitOfMeasure ?? this.unitOfMeasure,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      isMaterial: isMaterial ?? this.isMaterial,
      movements: movements ?? this.movements,
    );
  }
}

/// A single stock movement event (restock, sale, adjustment, damage).
class StockMovement {
  final String type; // Restock, Sale, Damage, Correction, Return
  final int quantity; // positive = in, negative = out
  final DateTime dateTime;
  final String? note;

  const StockMovement({
    required this.type,
    required this.quantity,
    required this.dateTime,
    this.note,
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
      default:
        return const Color(0xFFF59E0B);
    }
  }
}

/// Sample inventory data
final List<Product> sampleProducts = [
  Product(
    id: '1',
    name: 'RPE Figure-8 Straps V2',
    sku: 'RPE-008',
    category: 'Gym Gear',
    supplier: 'IronFit',
    costPrice: 280,
    sellingPrice: 450,
    currentStock: 32,
    reorderPoint: 10,
    icon: Icons.fitness_center_rounded,
    color: const Color(0xFF10B981),
    movements: [
      StockMovement(type: 'Restock', quantity: 10, dateTime: DateTime(2026, 2, 12, 10, 30)),
      StockMovement(type: 'Sale', quantity: -2, dateTime: DateTime(2026, 2, 10, 14, 15), note: 'Sale #1024'),
      StockMovement(type: 'Damage', quantity: -1, dateTime: DateTime(2026, 2, 8, 9, 0)),
    ],
  ),
  Product(
    id: '2',
    name: 'Hex Dumbbell Set 10kg',
    sku: 'HEX-10K',
    category: 'Weights',
    supplier: 'HeavyLift',
    costPrice: 800,
    sellingPrice: 1200,
    currentStock: 5,
    reorderPoint: 8,
    icon: Icons.sports_martial_arts_rounded,
    color: const Color(0xFFF59E0B),
    movements: [
      StockMovement(type: 'Sale', quantity: -3, dateTime: DateTime(2026, 2, 14, 11, 0)),
      StockMovement(type: 'Restock', quantity: 15, dateTime: DateTime(2026, 1, 28, 9, 0)),
    ],
  ),
  Product(
    id: '3',
    name: 'Pro Yoga Mat 6mm',
    sku: 'YOG-PRO',
    category: 'Yoga',
    supplier: 'ZenLife',
    costPrice: 380,
    sellingPrice: 650,
    currentStock: 0,
    reorderPoint: 5,
    icon: Icons.self_improvement_rounded,
    color: const Color(0xFFEF4444),
    movements: [
      StockMovement(type: 'Sale', quantity: -4, dateTime: DateTime(2026, 2, 11, 16, 0)),
      StockMovement(type: 'Damage', quantity: -1, dateTime: DateTime(2026, 2, 5, 8, 30)),
    ],
  ),
  Product(
    id: '4',
    name: 'Premium Shaker 700ml',
    sku: 'SHK-700',
    category: 'Accessories',
    supplier: 'GymSupps',
    costPrice: 65,
    sellingPrice: 120,
    currentStock: 85,
    reorderPoint: 15,
    icon: Icons.local_drink_rounded,
    color: const Color(0xFF3B82F6),
    movements: [
      StockMovement(type: 'Restock', quantity: 50, dateTime: DateTime(2026, 2, 1, 10, 0)),
      StockMovement(type: 'Sale', quantity: -12, dateTime: DateTime(2026, 2, 13, 13, 30)),
    ],
  ),
  Product(
    id: '5',
    name: 'Resistance Bands Set',
    sku: 'RES-SET',
    category: 'Gym Gear',
    supplier: 'IronFit',
    costPrice: 150,
    sellingPrice: 280,
    currentStock: 18,
    reorderPoint: 10,
    icon: Icons.straighten_rounded,
    color: const Color(0xFF8B5CF6),
    movements: [
      StockMovement(type: 'Sale', quantity: -5, dateTime: DateTime(2026, 2, 12, 15, 0)),
    ],
  ),
  Product(
    id: '6',
    name: 'Whey Protein 2kg',
    sku: 'WHY-2KG',
    category: 'Supplements',
    supplier: 'GymSupps',
    costPrice: 550,
    sellingPrice: 899,
    currentStock: 3,
    reorderPoint: 5,
    icon: Icons.science_rounded,
    color: const Color(0xFFF59E0B),
    movements: [
      StockMovement(type: 'Sale', quantity: -7, dateTime: DateTime(2026, 2, 14, 10, 0)),
    ],
  ),
  // Raw Materials
  Product(
    id: '7',
    name: 'Cotton Fabric Roll',
    sku: 'MAT-COT-01',
    category: 'Fabrics',
    supplier: 'Nile Textiles',
    costPrice: 1200,
    sellingPrice: 0, // Not for sale directly
    currentStock: 45, // meters
    reorderPoint: 20,
    unitOfMeasure: 'Meters',
    icon: Icons.texture_rounded,
    color: Color(0xFF795548),
    isMaterial: true,
  ),
  Product(
    id: '8',
    name: 'Packaging Boxes (Small)',
    sku: 'PKG-BOX-S',
    category: 'Packaging',
    supplier: 'Cairo Pack',
    costPrice: 5.5,
    sellingPrice: 0,
    currentStock: 500,
    reorderPoint: 100,
    unitOfMeasure: 'Pieces',
    icon: Icons.inventory_2_rounded,
    color: Color(0xFF607D8B),
    isMaterial: true,
  ),
];
