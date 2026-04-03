/// A single payment log entry returned by the getPaymentHistory CF.
class PaymentHistoryEntry {
  final String id;
  final String? plan;
  final bool success;
  final int amountCents;
  final String currency;
  final bool isRenewal;
  final String? paymobTransactionId;
  final DateTime? createdAt;

  const PaymentHistoryEntry({
    required this.id,
    this.plan,
    this.success = false,
    this.amountCents = 0,
    this.currency = 'EGP',
    this.isRenewal = false,
    this.paymobTransactionId,
    this.createdAt,
  });

  double get amount => amountCents / 100;

  factory PaymentHistoryEntry.fromJson(Map<String, dynamic> json) {
    final createdAtMs = json['created_at'] as int?;
    return PaymentHistoryEntry(
      id: json['id'] as String? ?? '',
      plan: json['plan'] as String?,
      success: json['success'] as bool? ?? false,
      amountCents: json['amount_cents'] as int? ?? 0,
      currency: json['currency'] as String? ?? 'EGP',
      isRenewal: json['is_renewal'] as bool? ?? false,
      paymobTransactionId: json['paymob_transaction_id'] as String?,
      createdAt: createdAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(createdAtMs)
          : null,
    );
  }
}
