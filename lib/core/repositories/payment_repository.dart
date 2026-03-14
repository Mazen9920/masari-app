import '../../shared/models/payment_model.dart';
import '../services/result.dart';

/// Contract for payment data operations.
abstract class PaymentRepository {
  /// Fetches payments, optionally filtered by supplier and paginated.
  Future<Result<List<Payment>>> getPayments({
    String? supplierId,
    int? limit,
    String? startAfterId,
  });

  /// Fetches a single payment by ID.
  Future<Result<Payment>> getPaymentById(String id);

  /// Creates a new payment.
  Future<Result<Payment>> createPayment(Payment payment);

  /// Updates an existing payment.
  Future<Result<Payment>> updatePayment(String id, Payment updated);

  /// Deletes a payment by ID.
  Future<Result<void>> deletePayment(String id);
}
