/// Sale model for the Growth-tier sales system.
/// Each sale records items sold, amounts, payment info, and optionally
/// links back to inventory products for COGS calculation and stock adjustment.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/money_utils.dart';

/// Payment status for a sale.
enum PaymentStatus {
  unpaid,     // 0 – nothing received yet
  partial,    // 1 – some amount received
  paid,       // 2 – fully paid
  refunded,   // 3 – fully refunded
}

/// Order lifecycle status.
enum OrderStatus {
  pending,    // 0 – just placed, not yet confirmed
  confirmed,  // 1 – confirmed by seller
  processing, // 2 – being prepared / packed
  completed,  // 3 – fulfilled / delivered
  cancelled,  // 4 – cancelled (stock restored, txns zeroed)
}

/// A single line-item within a sale.
class SaleItem {
  final String? productId;
  final String? variantId;
  final String? variantName;
  final String productName;
  final double quantity;
  final double unitPrice;
  final double costPrice;

  // ── Shopify integration ─────────────────────────────────
  /// Shopify line-item ID for per-line sync on order edits.
  final String? shopifyLineItemId;

  const SaleItem({
    this.productId,
    this.variantId,
    this.variantName,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.costPrice = 0,
    this.shopifyLineItemId,
  });

  double get lineTotal => roundMoney(quantity * unitPrice);
  double get lineCogs => roundMoney(quantity * costPrice);

  SaleItem copyWith({
    String? productId,
    String? variantId,
    String? variantName,
    String? productName,
    double? quantity,
    double? unitPrice,
    double? costPrice,
    String? shopifyLineItemId,
  }) {
    return SaleItem(
      productId: productId ?? this.productId,
      variantId: variantId ?? this.variantId,
      variantName: variantName ?? this.variantName,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      costPrice: costPrice ?? this.costPrice,
      shopifyLineItemId: shopifyLineItemId ?? this.shopifyLineItemId,
    );
  }

  Map<String, dynamic> toJson() => {
        if (productId != null) 'product_id': productId,
        if (variantId != null) 'variant_id': variantId,
        if (variantName != null) 'variant_name': variantName,
        'product_name': productName,
        'quantity': quantity,
        'unit_price': unitPrice,
        'cost_price': costPrice,
        if (shopifyLineItemId != null) 'shopify_line_item_id': shopifyLineItemId,
      };

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    return SaleItem(
      productId: json['product_id']?.toString(),
      variantId: json['variant_id']?.toString(),
      variantName: json['variant_name']?.toString(),
      productName: json['product_name']?.toString() ?? 'Unknown',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
      costPrice: (json['cost_price'] as num?)?.toDouble() ?? 0,
      shopifyLineItemId: json['shopify_line_item_id']?.toString(),
    );
  }
}

/// The main Sale record.
class Sale {
  final String id;
  final String userId;
  final String? customerName;
  final DateTime date;
  final List<SaleItem> items;
  final double taxAmount;
  final double discountAmount;
  final String paymentMethod;
  final PaymentStatus paymentStatus;
  final double amountPaid;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Order lifecycle
  final OrderStatus orderStatus;

  // Shopify-ready fields
  final String? externalOrderId;
  final String? externalSource;
  final String? shopifyOrderNumber;

  // Customer details
  final String? customerPhone;
  final String? customerEmail;

  // Shipping
  final String? shippingAddress;
  final double shippingCost;
  final String? shippingNotes;
  final String? shippingMethod;
  final String? trackingNumber;
  final String? deliveryStatus;

  const Sale({
    required this.id,
    required this.userId,
    this.customerName,
    required this.date,
    required this.items,
    this.taxAmount = 0,
    this.discountAmount = 0,
    this.paymentMethod = 'Cash',
    this.paymentStatus = PaymentStatus.paid,
    this.amountPaid = 0,
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.orderStatus = OrderStatus.confirmed,
    this.externalOrderId,
    this.externalSource,
    this.shopifyOrderNumber,
    this.customerPhone,
    this.customerEmail,
    this.shippingAddress,
    this.shippingCost = 0,
    this.shippingNotes,
    this.shippingMethod,
    this.trackingNumber,
    this.deliveryStatus,
  });

  // ── Computed fields ──────────────────────────────────────

  /// Sum of all line items before tax/discount.
  double get subtotal =>
      roundMoney(items.fold(0.0, (sum, item) => sum + item.lineTotal));

  /// Final total after tax, discount, and shipping.
  double get total =>
      roundMoney(subtotal + taxAmount - discountAmount + shippingCost);

  /// Net revenue = subtotal − discount. Excludes tax (which is a
  /// collected liability) and shipping cost, per GAAP/IFRS.
  double get netRevenue => roundMoney(subtotal - discountAmount);

  /// Total cost of goods sold for this sale.
  double get totalCogs =>
      roundMoney(items.fold(0.0, (sum, item) => sum + item.lineCogs));

  /// Gross profit = net revenue – COGS.
  double get grossProfit => roundMoney(netRevenue - totalCogs);

  /// Outstanding balance remaining (clamped to zero on overpayment).
  double get outstanding =>
      roundMoney((total - amountPaid).clamp(0.0, double.maxFinite));

  // ── copyWith ─────────────────────────────────────────────

  Sale copyWith({
    String? id,
    String? userId,
    String? customerName,
    DateTime? date,
    List<SaleItem>? items,
    double? taxAmount,
    double? discountAmount,
    String? paymentMethod,
    PaymentStatus? paymentStatus,
    double? amountPaid,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    OrderStatus? orderStatus,
    String? externalOrderId,
    String? externalSource,
    String? shopifyOrderNumber,
    String? customerPhone,
    String? customerEmail,
    String? shippingAddress,
    double? shippingCost,
    String? shippingNotes,
    String? shippingMethod,
    String? trackingNumber,
    String? deliveryStatus,
  }) {
    return Sale(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      customerName: customerName ?? this.customerName,
      date: date ?? this.date,
      items: items ?? this.items,
      taxAmount: taxAmount ?? this.taxAmount,
      discountAmount: discountAmount ?? this.discountAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      amountPaid: amountPaid ?? this.amountPaid,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      orderStatus: orderStatus ?? this.orderStatus,
      externalOrderId: externalOrderId ?? this.externalOrderId,
      externalSource: externalSource ?? this.externalSource,
      shopifyOrderNumber: shopifyOrderNumber ?? this.shopifyOrderNumber,
      customerPhone: customerPhone ?? this.customerPhone,
      customerEmail: customerEmail ?? this.customerEmail,
      shippingAddress: shippingAddress ?? this.shippingAddress,
      shippingCost: shippingCost ?? this.shippingCost,
      shippingNotes: shippingNotes ?? this.shippingNotes,
      shippingMethod: shippingMethod ?? this.shippingMethod,
      trackingNumber: trackingNumber ?? this.trackingNumber,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
    );
  }

  // ── Serialization ────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        if (customerName != null) 'customer_name': customerName,
        'date': Timestamp.fromDate(date),
        'items': items.map((i) => i.toJson()).toList(),
        'tax_amount': taxAmount,
        'discount_amount': discountAmount,
        'payment_method': paymentMethod,
        'payment_status': paymentStatus.index,
        'amount_paid': amountPaid,
        if (notes != null) 'notes': notes,
        if (createdAt != null) 'created_at': Timestamp.fromDate(createdAt!),
        if (updatedAt != null) 'updated_at': Timestamp.fromDate(updatedAt!),
        'order_status': orderStatus.index,
        if (externalOrderId != null) 'external_order_id': externalOrderId,
        if (externalSource != null) 'external_source': externalSource,
        if (shopifyOrderNumber != null) 'shopify_order_number': shopifyOrderNumber,
        if (customerPhone != null) 'customer_phone': customerPhone,
        if (customerEmail != null) 'customer_email': customerEmail,
        if (shippingAddress != null) 'shipping_address': shippingAddress,
        if (shippingCost > 0) 'shipping_cost': shippingCost,
        if (shippingNotes != null) 'shipping_notes': shippingNotes,
        if (shippingMethod != null) 'shipping_method': shippingMethod,
        if (trackingNumber != null) 'tracking_number': trackingNumber,
        if (deliveryStatus != null) 'delivery_status': deliveryStatus,
      };

  /// Safely parse a dynamic Firestore field to [DateTime].
  /// Handles ISO-8601 strings, Firestore Timestamps, and nulls.
  static DateTime _parseDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.parse(value);
    // Firestore Timestamp duck-typing
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

  factory Sale.fromJson(Map<String, dynamic> json) {
    // Safely read payment_status — guard against out-of-range index
    final rawPayment = (json['payment_status'] as num?)?.toInt();
    final paymentIdx = (rawPayment != null &&
            rawPayment >= 0 &&
            rawPayment < PaymentStatus.values.length)
        ? rawPayment
        : 0; // default unpaid — safer than defaulting to "paid"

    final rawOrder = (json['order_status'] as num?)?.toInt();
    final orderIdx = (rawOrder != null &&
            rawOrder >= 0 &&
            rawOrder < OrderStatus.values.length)
        ? rawOrder
        : 1; // default confirmed

    return Sale(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? 'system',
      customerName: json['customer_name']?.toString(),
      date: _parseDate(json['date']),
      items: (json['items'] as List<dynamic>?)
              ?.map((i) => SaleItem.fromJson(
                  Map<String, dynamic>.from(i as Map)))
              .toList() ??
          [],
      taxAmount: (json['tax_amount'] as num?)?.toDouble() ?? 0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0,
      paymentMethod: json['payment_method']?.toString() ?? 'Cash',
      paymentStatus: PaymentStatus.values[paymentIdx],
      amountPaid: (json['amount_paid'] as num?)?.toDouble() ?? 0,
      notes: json['notes']?.toString(),
      createdAt: _parseDateNullable(json['created_at']),
      updatedAt: _parseDateNullable(json['updated_at']),
      orderStatus: OrderStatus.values[orderIdx],
      externalOrderId: json['external_order_id']?.toString(),
      externalSource: json['external_source']?.toString(),
      shopifyOrderNumber: json['shopify_order_number']?.toString(),
      customerPhone: json['customer_phone']?.toString(),
      customerEmail: json['customer_email']?.toString(),
      shippingAddress: json['shipping_address']?.toString(),
      shippingCost: (json['shipping_cost'] as num?)?.toDouble() ?? 0,
      shippingNotes: json['shipping_notes']?.toString(),
      shippingMethod: json['shipping_method']?.toString(),
      trackingNumber: json['tracking_number']?.toString(),
      deliveryStatus: json['delivery_status']?.toString(),
    );
  }
}
