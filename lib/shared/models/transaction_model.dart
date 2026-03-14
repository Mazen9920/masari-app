import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'category_data.dart';

/// Transaction model used across list, detail, and filter screens.
class Transaction {
  final String id;
  final String userId;
  final String title;
  final double amount;
  final DateTime dateTime;
  final String categoryId;
  final String? note;
  final String paymentMethod;
  final String? supplierId;
  final String? saleId;
  final bool excludeFromPL;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Transaction({
    required this.id,
    required this.userId,
    required this.title,
    required this.amount,
    required this.dateTime,
    required this.categoryId,
    this.note,
    this.paymentMethod = 'Cash',
    this.supplierId,
    this.saleId,
    this.excludeFromPL = false,
    this.createdAt,
    this.updatedAt,
  });

  Transaction copyWith({
    String? id,
    String? userId,
    String? title,
    double? amount,
    DateTime? dateTime,
    String? categoryId,
    String? note,
    String? paymentMethod,
    String? supplierId,
    String? saleId,
    bool? excludeFromPL,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Transaction(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      dateTime: dateTime ?? this.dateTime,
      categoryId: categoryId ?? this.categoryId,
      note: note ?? this.note,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      supplierId: supplierId ?? this.supplierId,
      saleId: saleId ?? this.saleId,
      excludeFromPL: excludeFromPL ?? this.excludeFromPL,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isIncome => amount > 0;

  static final _fmt = NumberFormat('#,##0.00', 'en');

  String get formattedAmount {
    final prefix = isIncome ? '+' : '-';
    return '$prefix${_fmt.format(amount.abs())}';
  }

  String formattedAmountWith(String currency) {
    final prefix = isIncome ? '+' : '-';
    return '$prefix$currency ${_fmt.format(amount.abs())}';
  }

  String get formattedTime {
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }

  /// Serializes to JSON for backend communication.
  /// Category is stored as its ID reference, not as an embedded object.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'amount': amount,
      'date_time': Timestamp.fromDate(dateTime),
      'category_id': categoryId,
      if (note != null) 'note': note,
      'payment_method': paymentMethod,
      if (supplierId != null) 'supplier_id': supplierId,
      if (saleId != null) 'sale_id': saleId,
      'exclude_from_pl': excludeFromPL,
      if (createdAt != null) 'created_at': Timestamp.fromDate(createdAt!),
      if (updatedAt != null) 'updated_at': Timestamp.fromDate(updatedAt!),
    };
  }

  /// Safely parse a dynamic Firestore field to [DateTime].
  static DateTime _parseDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.parse(value);
    if (value != null) {
      try {
        // ignore: avoid_dynamic_calls
        return (value as dynamic).toDate() as DateTime;
      } catch (_) {}
    }
    return DateTime.now();
  }

  static DateTime? _parseDateNullable(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.parse(value);
    try {
      // ignore: avoid_dynamic_calls
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }

  /// Deserializes from JSON. Resolves category by ID from the provided list
  /// (or falls back to static defaults).
  factory Transaction.fromJson(
    Map<String, dynamic> json, {
    List<CategoryData>? categories,
  }) {
    final categoryId = json['category_id']?.toString() ?? 'cat_other';
    final resolvedCategory = categories != null
        ? categories.firstWhere(
            (c) => c.id == categoryId,
            orElse: () => CategoryData.findById(categoryId),
          )
        : CategoryData.findById(categoryId);

    return Transaction(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? 'system',
      title: json['title']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      dateTime: _parseDate(json['date_time']),
      categoryId: resolvedCategory.id,
      note: json['note']?.toString(),
      paymentMethod: json['payment_method']?.toString() ?? 'Cash',
      supplierId: json['supplier_id']?.toString(),
      saleId: json['sale_id']?.toString(),
      excludeFromPL: json['exclude_from_pl'] as bool? ?? false,
      createdAt: _parseDateNullable(json['created_at']),
      updatedAt: _parseDateNullable(json['updated_at']),
    );
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
    this.amountRange = const RangeValues(0, double.infinity),
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
    if (amountRange != const RangeValues(0, double.infinity)) count++;
    if (selectedCategories.isNotEmpty) count++;
    if (onlySuppliers) count++;
    return count;
  }

  bool get isDefault =>
      type == TransactionType.all &&
      amountRange == const RangeValues(0, double.infinity) &&
      selectedCategories.isEmpty &&
      !onlySuppliers;

  static const TransactionFilter empty = TransactionFilter();
}

enum TransactionType { all, income, expense }

/// Empty initial state for transactions
class SampleTransactions {
  SampleTransactions._();

  static List<Transaction> get all => [];
}
