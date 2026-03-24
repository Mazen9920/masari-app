// Purchase model — one recorded purchase from a supplier.

import '../../l10n/app_localizations.dart';
import '../utils/money_utils.dart';

class Purchase {
  final String id;
  final String userId;
  final String supplierId;
  final String supplierName;
  final DateTime date;
  final String referenceNo;
  final List<PurchaseItem> items;
  final double tax;
  final int paymentStatus; // 0=Unpaid, 1=Partial, 2=Fully Paid
  final double amountPaid;
  final DateTime? dueDate;
  final DateTime createdAt;

  const Purchase({
    required this.id,
    this.userId = '',
    required this.supplierId,
    required this.supplierName,
    required this.date,
    this.referenceNo = '',
    this.items = const [],
    this.tax = 0,
    this.paymentStatus = 0,
    this.amountPaid = 0,
    this.dueDate,
    required this.createdAt,
  });

  double get subtotal =>
      roundMoney(items.fold<double>(0, (s, item) => s + item.total));

  double get total => roundMoney(subtotal + tax);

  double get outstanding {
    if (paymentStatus == 2) return 0;
    if (paymentStatus == 1) return roundMoney((total - amountPaid).clamp(0, double.maxFinite));
    return total;
  }

  /// Whether every item has been fully received via goods receipts.
  bool get isFullyReceived =>
      items.isNotEmpty && items.every((i) => i.receivedQty >= i.qty);

  /// Value of goods received so far (receivedQty * unitPrice per item).
  double get totalReceivedValue =>
      roundMoney(items.fold<double>(0, (s, i) => s + (i.receivedQty * i.unitPrice)));

  String get statusLabel {
    switch (paymentStatus) {
      case 0:
        return 'Unpaid';
      case 1:
        return 'Partial';
      case 2:
        return 'Paid';
      default:
        return 'Unknown';
    }
  }

  String localizedStatusLabel(AppLocalizations l10n) {
    switch (paymentStatus) {
      case 0:
        return l10n.unpaid;
      case 1:
        return l10n.partial;
      case 2:
        return l10n.paid;
      default:
        return l10n.unknownStatus;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'date': date.toIso8601String(),
      'reference_no': referenceNo,
      'items': items.map((i) => i.toJson()).toList(),
      'tax': tax,
      'payment_status': paymentStatus,
      'amount_paid': amountPaid,
      if (dueDate != null) 'due_date': dueDate!.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Purchase.fromJson(Map<String, dynamic> json) {
    return Purchase(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? '',
      supplierId: json['supplier_id'] as String,
      supplierName: json['supplier_name'] as String,
      date: DateTime.parse(json['date'] as String),
      referenceNo: json['reference_no'] as String? ?? '',
      items: (json['items'] as List<dynamic>?)
              ?.map((i) => PurchaseItem.fromJson(i as Map<String, dynamic>))
              .toList() ??
          [],
      tax: (json['tax'] as num?)?.toDouble() ?? 0,
      paymentStatus: json['payment_status'] as int? ?? 0,
      amountPaid: (json['amount_paid'] as num?)?.toDouble() ?? 0,
      dueDate: json['due_date'] != null ? DateTime.parse(json['due_date'] as String) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Purchase copyWith({
    String? id,
    String? userId,
    String? supplierId,
    String? supplierName,
    DateTime? date,
    String? referenceNo,
    List<PurchaseItem>? items,
    double? tax,
    int? paymentStatus,
    double? amountPaid,
    Object? dueDate = const _Sentinel(),
    DateTime? createdAt,
  }) {
    return Purchase(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      date: date ?? this.date,
      referenceNo: referenceNo ?? this.referenceNo,
      items: items ?? this.items,
      tax: tax ?? this.tax,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      amountPaid: amountPaid ?? this.amountPaid,
      dueDate: dueDate is _Sentinel ? this.dueDate : dueDate as DateTime?,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// Sentinel value used by [Purchase.copyWith] to distinguish
/// "not provided" from an explicit null (to clear dueDate).
class _Sentinel {
  const _Sentinel();
}

/// One line-item inside a purchase.
class PurchaseItem {
  final String name;
  final String category;
  final int qty;
  final double unitPrice;
  final int receivedQty;
  final String? productId;
  final String? variantId;
  final String? variantName;

  const PurchaseItem({
    required this.name,
    required this.category,
    required this.qty,
    required this.unitPrice,
    this.receivedQty = 0,
    this.productId,
    this.variantId,
    this.variantName,
  });

  double get total => roundMoney(qty * unitPrice);

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'category': category,
      'qty': qty,
      'unit_price': unitPrice,
      'received_qty': receivedQty,
      if (productId != null) 'product_id': productId,
      if (variantId != null) 'variant_id': variantId,
      if (variantName != null) 'variant_name': variantName,
    };
  }

  factory PurchaseItem.fromJson(Map<String, dynamic> json) {
    return PurchaseItem(
      name: json['name'] as String,
      category: json['category'] as String? ?? '',
      qty: json['qty'] as int? ?? 0,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
      receivedQty: json['received_qty'] as int? ?? 0,
      productId: json['product_id'] as String?,
      variantId: json['variant_id'] as String?,
      variantName: json['variant_name'] as String?,
    );
  }

  PurchaseItem copyWith({
    String? name,
    String? category,
    int? qty,
    double? unitPrice,
    int? receivedQty,
    String? productId,
    String? variantId,
    String? variantName,
  }) {
    return PurchaseItem(
      name: name ?? this.name,
      category: category ?? this.category,
      qty: qty ?? this.qty,
      unitPrice: unitPrice ?? this.unitPrice,
      receivedQty: receivedQty ?? this.receivedQty,
      productId: productId ?? this.productId,
      variantId: variantId ?? this.variantId,
      variantName: variantName ?? this.variantName,
    );
  }
}
