import '../utils/money_utils.dart';

/// A recorded supplier payment.
class Payment {
  final String id;
  final String userId;
  final String supplierId;
  final String supplierName;
  final double amount;
  final DateTime date;
  final String method; // 'Cash' | 'Bank Transfer' | 'InstaPay' | 'Vodafone Cash'
  final String notes;
  final List<String> appliedToPurchaseIds;
  final String? receiptUrl;
  final String? transactionId;
  final DateTime createdAt;

  const Payment({
    required this.id,
    this.userId = '',
    required this.supplierId,
    required this.supplierName,
    required this.amount,
    required this.date,
    this.method = 'Cash',
    this.notes = '',
    this.appliedToPurchaseIds = const [],
    this.receiptUrl,
    this.transactionId,
    required this.createdAt,
  });

  Payment copyWith({
    String? id,
    String? userId,
    String? supplierId,
    String? supplierName,
    double? amount,
    DateTime? date,
    String? method,
    String? notes,
    List<String>? appliedToPurchaseIds,
    String? receiptUrl,
    String? transactionId,
    DateTime? createdAt,
  }) {
    return Payment(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      method: method ?? this.method,
      notes: notes ?? this.notes,
      appliedToPurchaseIds: appliedToPurchaseIds ?? this.appliedToPurchaseIds,
      receiptUrl: receiptUrl ?? this.receiptUrl,
      transactionId: transactionId ?? this.transactionId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'amount': roundMoney(amount),
      'date': date.toIso8601String(),
      'method': method,
      'notes': notes,
      'applied_to_purchase_ids': appliedToPurchaseIds,
      if (receiptUrl != null) 'receipt_url': receiptUrl,
      if (transactionId != null) 'transaction_id': transactionId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? '',
      supplierId: json['supplier_id'] as String,
      supplierName: json['supplier_name'] as String,
      amount: roundMoney((json['amount'] as num).toDouble()),
      date: DateTime.parse(json['date'] as String),
      method: json['method'] as String? ?? 'Cash',
      notes: json['notes'] as String? ?? '',
      appliedToPurchaseIds: (json['applied_to_purchase_ids'] as List<dynamic>?)?.cast<String>() ?? [],
      receiptUrl: json['receipt_url'] as String?,
      transactionId: json['transaction_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
