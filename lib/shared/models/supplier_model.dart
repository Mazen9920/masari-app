import 'package:flutter/material.dart';

/// Represents a supplier entity.
class Supplier {
  final String id;
  final String name;
  final String category;
  final String phone;
  final String email;
  final bool whatsappAvailable;
  final String paymentTerms; // 'On Receipt', 'Net 15', 'Net 30', 'Net 60'
  final double balance; // Outstanding amount owed
  final String address;
  final String notes;
  final String supplierId; // Custom ID like SUP-001
  final DateTime lastTransaction;
  final DateTime? dueDate;
  final Color avatarBg;
  final Color avatarTextColor;

  const Supplier({
    required this.id,
    required this.name,
    required this.category,
    this.phone = '',
    this.email = '',
    this.whatsappAvailable = false,
    this.paymentTerms = 'On Receipt',
    this.balance = 0,
    this.address = '',
    this.notes = '',
    this.supplierId = '',
    required this.lastTransaction,
    this.dueDate,
    this.avatarBg = const Color(0xFFE0E7FF),
    this.avatarTextColor = const Color(0xFF1B5074),
  });

  /// Initials for avatar
  String get initials {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  /// Whether the supplier is overdue
  bool get isOverdue {
    if (dueDate == null || balance <= 0) return false;
    return DateTime.now().isAfter(dueDate!);
  }

  /// Days overdue (0 if not overdue)
  int get daysOverdue {
    if (!isOverdue) return 0;
    return DateTime.now().difference(dueDate!).inDays;
  }

  /// Whether there's a balance due
  bool get hasDue => balance > 0;

  /// Whether fully paid
  bool get isPaid => balance <= 0;

  Supplier copyWith({
    String? id,
    String? name,
    String? category,
    String? phone,
    String? email,
    bool? whatsappAvailable,
    String? paymentTerms,
    double? balance,
    String? address,
    String? notes,
    String? supplierId,
    DateTime? lastTransaction,
    DateTime? dueDate,
    Color? avatarBg,
    Color? avatarTextColor,
  }) {
    return Supplier(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      whatsappAvailable: whatsappAvailable ?? this.whatsappAvailable,
      paymentTerms: paymentTerms ?? this.paymentTerms,
      balance: balance ?? this.balance,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      supplierId: supplierId ?? this.supplierId,
      lastTransaction: lastTransaction ?? this.lastTransaction,
      dueDate: dueDate ?? this.dueDate,
      avatarBg: avatarBg ?? this.avatarBg,
      avatarTextColor: avatarTextColor ?? this.avatarTextColor,
    );
  }
}

/// Sample suppliers for development
final sampleSuppliers = <Supplier>[
  Supplier(
    id: '1',
    name: 'Nile Packaging',
    category: 'Packaging',
    phone: '01012345678',
    email: 'nile@pack.com',
    balance: 6200,
    paymentTerms: 'Net 30',
    lastTransaction: DateTime(2025, 10, 12),
    dueDate: DateTime.now().add(const Duration(days: 5)),
    avatarBg: const Color(0xFFDBEAFE),
    avatarTextColor: const Color(0xFF1B5074),
  ),
  Supplier(
    id: '2',
    name: 'Cairo Logistics',
    category: 'Logistics',
    phone: '01098765432',
    balance: 12400,
    paymentTerms: 'Net 60',
    lastTransaction: DateTime(2025, 11, 1),
    dueDate: DateTime.now().add(const Duration(days: 10)),
    avatarBg: const Color(0xFFFED7AA),
    avatarTextColor: const Color(0xFFEA580C),
  ),
  Supplier(
    id: '3',
    name: 'El Gouna Traders',
    category: 'Wholesale',
    phone: '01155556666',
    balance: 0,
    paymentTerms: 'On Receipt',
    lastTransaction: DateTime(2025, 11, 3),
    avatarBg: const Color(0xFFCCFBF1),
    avatarTextColor: const Color(0xFF0F766E),
  ),
  Supplier(
    id: '4',
    name: 'Al-Ahram Supplies',
    category: 'Stationery',
    phone: '01234567890',
    balance: 2000,
    paymentTerms: 'Net 15',
    lastTransaction: DateTime(2025, 10, 28),
    dueDate: DateTime.now().subtract(const Duration(days: 2)),
    avatarBg: const Color(0xFFE9D5FF),
    avatarTextColor: const Color(0xFF7C3AED),
  ),
  Supplier(
    id: '5',
    name: 'Smart Tech Solutions',
    category: 'IT Services',
    phone: '01111222333',
    email: 'info@smarttech.eg',
    balance: 4000,
    paymentTerms: 'Net 30',
    lastTransaction: DateTime(2025, 9, 15),
    dueDate: DateTime.now().subtract(const Duration(days: 15)),
    avatarBg: const Color(0xFFE0E7FF),
    avatarTextColor: const Color(0xFF4F46E5),
  ),
];
