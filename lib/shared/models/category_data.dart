import 'package:flutter/material.dart';

/// Category data used across transactions list, filter, and add screens.
class CategoryData {
  final String name;
  final IconData icon;
  final Color color;
  final Color bgColor;

  const CategoryData({
    required this.name,
    required this.icon,
    required this.color,
    required this.bgColor,
  });

  /// Master list of all categories.
  static const List<CategoryData> all = [
    CategoryData(
      name: 'Groceries',
      icon: Icons.shopping_cart_rounded,
      color: Color(0xFFE67E22),
      bgColor: Color(0xFFFFF3E0),
    ),
    CategoryData(
      name: 'Income',
      icon: Icons.work_rounded,
      color: Color(0xFF27AE60),
      bgColor: Color(0xFFE8F5E9),
    ),
    CategoryData(
      name: 'Transport',
      icon: Icons.local_taxi_rounded,
      color: Color(0xFF2E86C1),
      bgColor: Color(0xFFE3F2FD),
    ),
    CategoryData(
      name: 'Entertainment',
      icon: Icons.movie_rounded,
      color: Color(0xFFE74C3C),
      bgColor: Color(0xFFFFEBEE),
    ),
    CategoryData(
      name: 'Health',
      icon: Icons.fitness_center_rounded,
      color: Color(0xFF8E44AD),
      bgColor: Color(0xFFF3E5F5),
    ),
    CategoryData(
      name: 'Food & Dining',
      icon: Icons.restaurant_rounded,
      color: Color(0xFFF39C12),
      bgColor: Color(0xFFFFF8E1),
    ),
    CategoryData(
      name: 'Shopping',
      icon: Icons.shopping_bag_rounded,
      color: Color(0xFF9B59B6),
      bgColor: Color(0xFFF3E5F5),
    ),
    CategoryData(
      name: 'Bills',
      icon: Icons.electric_bolt_rounded,
      color: Color(0xFF7F8C8D),
      bgColor: Color(0xFFECEFF1),
    ),
    CategoryData(
      name: 'Coffee',
      icon: Icons.coffee_rounded,
      color: Color(0xFFD4A017),
      bgColor: Color(0xFFFFF9C4),
    ),
    CategoryData(
      name: 'Utilities',
      icon: Icons.bolt_rounded,
      color: Color(0xFF546E7A),
      bgColor: Color(0xFFECEFF1),
    ),
    CategoryData(
      name: 'Rent',
      icon: Icons.home_rounded,
      color: Color(0xFF27AE60),
      bgColor: Color(0xFFE8F5E9),
    ),
    CategoryData(
      name: 'Education',
      icon: Icons.school_rounded,
      color: Color(0xFF3498DB),
      bgColor: Color(0xFFE3F2FD),
    ),
    CategoryData(
      name: 'Software',
      icon: Icons.dns_rounded,
      color: Color(0xFF1ABC9C),
      bgColor: Color(0xFFE0F2F1),
    ),
    CategoryData(
      name: 'Salaries',
      icon: Icons.people_rounded,
      color: Color(0xFF1B4F72),
      bgColor: Color(0xFFD6EAF8),
    ),
    CategoryData(
      name: 'Marketing',
      icon: Icons.campaign_rounded,
      color: Color(0xFF6366F1),
      bgColor: Color(0xFFEEF2FF),
    ),
    CategoryData(
      name: 'Office Supplies',
      icon: Icons.inventory_2_rounded,
      color: Color(0xFFF97316),
      bgColor: Color(0xFFFFF7ED),
    ),
    CategoryData(
      name: 'Travel',
      icon: Icons.flight_rounded,
      color: Color(0xFFF43F5E),
      bgColor: Color(0xFFFFF1F2),
    ),
  ];

  /// Find category by name (case insensitive).
  static CategoryData findByName(String name) {
    return all.firstWhere(
      (c) => c.name.toLowerCase() == name.toLowerCase(),
      orElse: () => all.first,
    );
  }
}
