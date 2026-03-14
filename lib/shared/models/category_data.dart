import 'package:flutter/material.dart';

/// Category data used across transactions list, filter, and add screens.
class CategoryData {
  final String id;
  final String userId;
  final String name;
  final String iconName;
  final int colorValue;
  final int bgColorValue;
  final bool isExpense;
  final double? budgetLimit;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CategoryData({
    required this.id,
    required this.userId,
    required this.name,
    required this.iconName,
    required this.colorValue,
    required this.bgColorValue,
    this.isExpense = true,
    this.budgetLimit,
    this.createdAt,
    this.updatedAt,
  });

  CategoryData copyWith({
    String? id,
    String? userId,
    String? name,
    String? iconName,
    int? colorValue,
    int? bgColorValue,
    bool? isExpense,
    double? budgetLimit,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CategoryData(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      iconName: iconName ?? this.iconName,
      colorValue: colorValue ?? this.colorValue,
      bgColorValue: bgColorValue ?? this.bgColorValue,
      isExpense: isExpense ?? this.isExpense,
      budgetLimit: budgetLimit ?? this.budgetLimit,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Serializes to JSON for backend communication.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'icon_name': iconName,
      'color_value': colorValue,
      'bg_color_value': bgColorValue,
      'is_expense': isExpense,
      'budget_limit': budgetLimit,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  factory CategoryData.fromJson(Map<String, dynamic> json) {
    return CategoryData(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? 'system',
      name: json['name'] as String,
      iconName: json['icon_name'] as String? ?? 'grid_view',
      colorValue: json['color_value'] as int? ?? 0xFF9E9E9E,
      bgColorValue: json['bg_color_value'] as int? ?? 0xFFF5F5F5,
      isExpense: json['is_expense'] as bool? ?? (json['id'] != 'cat_income' && json['id'] != 'cat_investments'),
      budgetLimit: (json['budget_limit'] as num?)?.toDouble(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  /// Master list of all default categories.
  static const List<CategoryData> all = [
    CategoryData(
      id: 'cat_groceries',
      userId: 'system',
      name: 'Groceries',
      iconName: 'shopping_cart',
      colorValue: 0xFFE67E22,
      bgColorValue: 0xFFFFF3E0
    ),
    CategoryData(
      id: 'cat_income',
      userId: 'system',
      name: 'Income',
      iconName: 'work',
      colorValue: 0xFF27AE60,
      bgColorValue: 0xFFE8F5E9,
      isExpense: false,
    ),
    CategoryData(
      id: 'cat_transport',
      userId: 'system',
      name: 'Transport',
      iconName: 'local_taxi',
      colorValue: 0xFF2E86C1,
      bgColorValue: 0xFFE3F2FD
    ),
    CategoryData(
      id: 'cat_entertainment',
      userId: 'system',
      name: 'Entertainment',
      iconName: 'movie',
      colorValue: 0xFFE74C3C,
      bgColorValue: 0xFFFFEBEE
    ),
    CategoryData(
      id: 'cat_bills',
      userId: 'system',
      name: 'Bills',
      iconName: 'receipt',
      colorValue: 0xFF8E44AD,
      bgColorValue: 0xFFF3E5F5
    ),
    CategoryData(
      id: 'cat_health',
      userId: 'system',
      name: 'Health',
      iconName: 'favorite',
      colorValue: 0xFFE91E63,
      bgColorValue: 0xFFFCE4EC
    ),
    CategoryData(
      id: 'cat_education',
      userId: 'system',
      name: 'Education',
      iconName: 'school',
      colorValue: 0xFF3F51B5,
      bgColorValue: 0xFFE8EAF6
    ),
    CategoryData(
      id: 'cat_shopping',
      userId: 'system',
      name: 'Shopping',
      iconName: 'local_mall',
      colorValue: 0xFF00BCD4,
      bgColorValue: 0xFFE0F7FA
    ),
    CategoryData(
      id: 'cat_food',
      userId: 'system',
      name: 'Food & Dining',
      iconName: 'restaurant',
      colorValue: 0xFFFF9800,
      bgColorValue: 0xFFFFF3E0
    ),
    CategoryData(
      id: 'cat_gifts',
      userId: 'system',
      name: 'Gifts',
      iconName: 'card_giftcard',
      colorValue: 0xFF9C27B0,
      bgColorValue: 0xFFF3E5F5
    ),
    CategoryData(
      id: 'cat_travel',
      userId: 'system',
      name: 'Travel',
      iconName: 'flight',
      colorValue: 0xFF009688,
      bgColorValue: 0xFFE0F2F1
    ),
    CategoryData(
      id: 'cat_family',
      userId: 'system',
      name: 'Family',
      iconName: 'family_restroom',
      colorValue: 0xFF795548,
      bgColorValue: 0xFFEFEBE9
    ),
    CategoryData(
      id: 'cat_pet',
      userId: 'system',
      name: 'Pets',
      iconName: 'pets',
      colorValue: 0xFFFF5722,
      bgColorValue: 0xFFFBE9E7
    ),
    CategoryData(
      id: 'cat_investments',
      userId: 'system',
      name: 'Investments',
      iconName: 'trending_up',
      colorValue: 0xFF4CAF50,
      bgColorValue: 0xFFE8F5E9,
      isExpense: false,
    ),
    CategoryData(
      id: 'cat_utilities',
      userId: 'system',
      name: 'Utilities',
      iconName: 'electrical_services',
      colorValue: 0xFF607D8B,
      bgColorValue: 0xFFECEFF1
    ),
    CategoryData(
      id: 'cat_insurance',
      userId: 'system',
      name: 'Insurance',
      iconName: 'shield',
      colorValue: 0xFF3F51B5,
      bgColorValue: 0xFFE8EAF6
    ),
    CategoryData(
      id: 'cat_subscriptions',
      userId: 'system',
      name: 'Subscriptions',
      iconName: 'subscriptions',
      colorValue: 0xFFE91E63,
      bgColorValue: 0xFFFCE4EC
    ),
    CategoryData(
      id: 'cat_donations',
      userId: 'system',
      name: 'Donations',
      iconName: 'volunteer_activism',
      colorValue: 0xFF00BCD4,
      bgColorValue: 0xFFE0F7FA
    ),
    CategoryData(
      id: 'cat_personal_care',
      userId: 'system',
      name: 'Personal Care',
      iconName: 'spa',
      colorValue: 0xFF8BC34A,
      bgColorValue: 0xFFF1F8E9
    ),
    CategoryData(
      id: 'cat_supplier_payment',
      userId: 'system',
      name: 'Supplier Payment',
      iconName: 'store',
      colorValue: 0xFF1565C0,
      bgColorValue: 0xFFE3F2FD,
    ),
    CategoryData(
      id: 'cat_sales_revenue',
      userId: 'system',
      name: 'Sales Revenue',
      iconName: 'shopping_bag',
      colorValue: 0xFF10B981,
      bgColorValue: 0xFFECFDF5,
      isExpense: false,
    ),
    CategoryData(
      id: 'cat_cogs',
      userId: 'system',
      name: 'Cost of Goods Sold',
      iconName: 'inventory_2',
      colorValue: 0xFFDC2626,
      bgColorValue: 0xFFFEF2F2,
    ),
    CategoryData(
      id: 'cat_shipping',
      userId: 'system',
      name: 'Shipping Fees',
      iconName: 'local_shipping',
      colorValue: 0xFF6366F1,
      bgColorValue: 0xFFEEF2FF,
    ),
  ];

  static List<CategoryData> customCategories = [];

  /// Find category by name (case insensitive). Falls back to first category.
  static CategoryData findByName(String name) {
    for (final c in customCategories) {
      if (c.name.toLowerCase() == name.toLowerCase()) return c;
    }
    return all.firstWhere(
      (c) => c.name.toLowerCase() == name.toLowerCase(),
      orElse: () => all.first,
    );
  }

  /// Find category by ID. Falls back to Uncategorized category.
  static CategoryData findById(String id) {
    for (final c in customCategories) {
      if (c.id == id) return c;
    }
    return all.firstWhere(
      (c) => c.id == id,
      orElse: () => CategoryData(
        id: id,
        userId: 'system',
        name: 'Uncategorized',
        iconName: 'help_outline',
        colorValue: 0xFFE67E22,
        bgColorValue: 0xFFFFF3E0,
      ),
    );
  }
}

/// Extension to map normalized data to UI classes
extension CategoryDataUIExt on CategoryData {
  Color get displayColor => Color(colorValue);
  Color get displayBgColor => Color(bgColorValue);
  
  IconData get iconData {
    switch (iconName) {
      case 'shopping_cart': return Icons.shopping_cart_rounded;
      case 'work': return Icons.work_rounded;
      case 'local_taxi': return Icons.local_taxi_rounded;
      case 'movie': return Icons.movie_rounded;
      case 'receipt': return Icons.receipt_rounded;
      case 'favorite': return Icons.favorite_rounded;
      case 'school': return Icons.school_rounded;
      case 'local_mall': return Icons.local_mall_rounded;
      case 'restaurant': return Icons.restaurant_rounded;
      case 'card_giftcard': return Icons.card_giftcard_rounded;
      case 'flight': return Icons.flight_rounded;
      case 'family_restroom': return Icons.family_restroom_rounded;
      case 'pets': return Icons.pets_rounded;
      case 'trending_up': return Icons.trending_up_rounded;
      case 'electrical_services': return Icons.electrical_services_rounded;
      case 'shield': return Icons.shield_rounded;
      case 'subscriptions': return Icons.subscriptions_rounded;
      case 'volunteer_activism': return Icons.volunteer_activism_rounded;
      case 'spa': return Icons.spa_rounded;
      case 'directions_bus': return Icons.directions_bus_rounded;
      case 'shopping_bag': return Icons.shopping_bag_rounded;
      case 'home': return Icons.home_rounded;
      case 'medical_services': return Icons.medical_services_rounded;
      case 'directions_car': return Icons.directions_car_rounded;
      case 'campaign': return Icons.campaign_rounded;
      case 'fitness_center': return Icons.fitness_center_rounded;
      case 'more_horiz': return Icons.more_horiz_rounded;
      case 'store': return Icons.store_rounded;
      case 'inventory_2': return Icons.inventory_2_rounded;
      case 'grid_view':
      default:
        return Icons.grid_view_rounded;
    }
  }

  static String iconNameFromData(IconData icon) {
    if (icon == Icons.shopping_cart_rounded) return 'shopping_cart';
    if (icon == Icons.work_rounded) return 'work';
    if (icon == Icons.local_taxi_rounded) return 'local_taxi';
    if (icon == Icons.movie_rounded) return 'movie';
    if (icon == Icons.receipt_rounded) return 'receipt';
    if (icon == Icons.favorite_rounded) return 'favorite';
    if (icon == Icons.school_rounded) return 'school';
    if (icon == Icons.local_mall_rounded) return 'local_mall';
    if (icon == Icons.restaurant_rounded) return 'restaurant';
    if (icon == Icons.card_giftcard_rounded) return 'card_giftcard';
    if (icon == Icons.flight_rounded) return 'flight';
    if (icon == Icons.family_restroom_rounded) return 'family_restroom';
    if (icon == Icons.pets_rounded) return 'pets';
    if (icon == Icons.trending_up_rounded) return 'trending_up';
    if (icon == Icons.electrical_services_rounded) return 'electrical_services';
    if (icon == Icons.shield_rounded) return 'shield';
    if (icon == Icons.subscriptions_rounded) return 'subscriptions';
    if (icon == Icons.volunteer_activism_rounded) return 'volunteer_activism';
    if (icon == Icons.spa_rounded) return 'spa';
    if (icon == Icons.directions_bus_rounded) return 'directions_bus';
    if (icon == Icons.shopping_bag_rounded) return 'shopping_bag';
    if (icon == Icons.home_rounded) return 'home';
    if (icon == Icons.medical_services_rounded) return 'medical_services';
    if (icon == Icons.directions_car_rounded) return 'directions_car';
    if (icon == Icons.campaign_rounded) return 'campaign';
    if (icon == Icons.fitness_center_rounded) return 'fitness_center';
    if (icon == Icons.more_horiz_rounded) return 'more_horiz';
    if (icon == Icons.store_rounded) return 'store';
    if (icon == Icons.inventory_2_rounded) return 'inventory_2';
    return 'grid_view';
  }
}
