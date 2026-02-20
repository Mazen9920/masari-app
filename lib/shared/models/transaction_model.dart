import 'package:flutter/material.dart';
import 'category_data.dart';

/// Transaction model used across list, detail, and filter screens.
class Transaction {
  final String id;
  final String title;
  final double amount;
  final DateTime dateTime;
  final CategoryData category;
  final String? note;
  final String paymentMethod;

  const Transaction({
    required this.id,
    required this.title,
    required this.amount,
    required this.dateTime,
    required this.category,
    this.note,
    this.paymentMethod = 'Cash',
    this.supplierId,
  });

  final String? supplierId;

  Transaction copyWith({
    String? id,
    String? title,
    double? amount,
    DateTime? dateTime,
    CategoryData? category,
    String? note,
    String? paymentMethod,
    String? supplierId,
  }) {
    return Transaction(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      dateTime: dateTime ?? this.dateTime,
      category: category ?? this.category,
      note: note ?? this.note,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      supplierId: supplierId ?? this.supplierId,
    );
  }

  bool get isIncome => amount > 0;

  String get formattedAmount {
    final prefix = isIncome ? '+' : '-';
    return '$prefix\$${amount.abs().toStringAsFixed(2)}';
  }

  String get formattedTime {
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }
}

/// Filter data class with copyWith for clean state management.
class TransactionFilter {
  final TransactionType type;
  final RangeValues amountRange;
  final Set<String> selectedCategories;
  final String? period;
  final bool onlySuppliers;

  const TransactionFilter({
    this.type = TransactionType.all,
    this.amountRange = const RangeValues(0, 10000),
    this.selectedCategories = const {},
    this.period,
    this.onlySuppliers = false,
  });

  TransactionFilter copyWith({
    TransactionType? type,
    RangeValues? amountRange,
    Set<String>? selectedCategories,
    String? period,
    bool? onlySuppliers,
  }) {
    return TransactionFilter(
      type: type ?? this.type,
      amountRange: amountRange ?? this.amountRange,
      selectedCategories: selectedCategories ?? this.selectedCategories,
      period: period ?? this.period,
      onlySuppliers: onlySuppliers ?? this.onlySuppliers,
    );
  }

  int get activeCount {
    int count = 0;
    if (type != TransactionType.all) count++;
    if (amountRange != const RangeValues(0, 10000)) count++;
    if (selectedCategories.isNotEmpty) count += selectedCategories.length;
    if (onlySuppliers) count++;
    return count;
  }

  bool get isDefault =>
      type == TransactionType.all &&
      amountRange == const RangeValues(0, 10000) &&
      amountRange == const RangeValues(0, 10000) &&
      selectedCategories.isEmpty &&
      !onlySuppliers;

  static const TransactionFilter empty = TransactionFilter();
}

enum TransactionType { all, income, expense }

/// Sample transactions for demo purposes.
class SampleTransactions {
  SampleTransactions._();

  static List<Transaction> get all {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final twoDaysAgo = today.subtract(const Duration(days: 3));

    return [
      // Today
      Transaction(
        id: 'tx_001',
        title: 'Whole Foods Market',
        amount: -124.50,
        dateTime: today.add(const Duration(hours: 14, minutes: 30)),
        category: CategoryData.findByName('Groceries'),
        paymentMethod: 'Card',
      ),
      Transaction(
        id: 'tx_002',
        title: 'Upwork Payment',
        amount: 850.00,
        dateTime: today.add(const Duration(hours: 10, minutes: 15)),
        category: CategoryData.findByName('Income'),
      ),
      Transaction(
        id: 'tx_003',
        title: 'Uber Ride',
        amount: -24.90,
        dateTime: today.add(const Duration(hours: 8, minutes: 45)),
        category: CategoryData.findByName('Transport'),
      ),
      // Supplier Transactions (Mock)
      Transaction(
        id: 'tx_sup_1',
        title: 'Al-Amal Distributors',
        amount: -5200.00,
        dateTime: today.add(const Duration(hours: 12)),
        category: CategoryData.findByName('Inventory'), // Assuming Inventory exists or mapping to nearest
        supplierId: '1',
        paymentMethod: 'Bank Transfer',
        note: 'Inv #9923',
      ),
      Transaction(
        id: 'tx_sup_2',
        title: 'Cairo Logistics',
        amount: -1500.00,
        dateTime: yesterday.add(const Duration(hours: 14)),
        category: CategoryData.findByName('Travel'),
        supplierId: '2',
        paymentMethod: 'Cash',
      ),
      // Yesterday
      Transaction(
        id: 'tx_004',
        title: 'Netflix Subscription',
        amount: -15.99,
        dateTime: yesterday.add(const Duration(hours: 9)),
        category: CategoryData.findByName('Entertainment'),
      ),
      Transaction(
        id: 'tx_005',
        title: 'Gym Membership',
        amount: -45.00,
        dateTime: yesterday.add(const Duration(hours: 7)),
        category: CategoryData.findByName('Health'),
      ),
      Transaction(
        id: 'tx_006',
        title: 'Starbucks',
        amount: -6.50,
        dateTime: yesterday.add(const Duration(hours: 8, minutes: 15)),
        category: CategoryData.findByName('Coffee'),
      ),
      // 3 days ago
      Transaction(
        id: 'tx_007',
        title: 'Utility Bill',
        amount: -95.20,
        dateTime: twoDaysAgo.add(const Duration(hours: 16, minutes: 45)),
        category: CategoryData.findByName('Bills'),
      ),
      Transaction(
        id: 'tx_008',
        title: 'Freelance Project',
        amount: 3400.00,
        dateTime: twoDaysAgo.add(const Duration(hours: 11, minutes: 30)),
        category: CategoryData.findByName('Income'),
      ),
    ];
  }
}
