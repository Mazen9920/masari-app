import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/auth_repository.dart';
import '../repositories/transaction_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/product_repository.dart';
import '../repositories/supplier_repository.dart';
import '../repositories/purchase_repository.dart';
import '../repositories/payment_repository.dart';
import '../repositories/recurring_transaction_repository.dart';
import '../repositories/user_profile_repository.dart';
import '../repositories/sale_repository.dart';
import '../repositories/goods_receipt_repository.dart';
import '../repositories/balance_sheet_repository.dart';
import '../repositories/firestore/firestore_sale_repository.dart';
import '../repositories/firestore/firestore_goods_receipt_repository.dart';
import '../repositories/firestore/firestore_balance_sheet_repository.dart';
import '../repositories/firebase/firebase_auth_repository.dart';
import '../repositories/firestore/firestore_transaction_repository.dart';
import '../repositories/firestore/firestore_category_repository.dart';
import '../repositories/firestore/firestore_product_repository.dart';
import '../repositories/firestore/firestore_supplier_repository.dart';
import '../repositories/firestore/firestore_purchase_repository.dart';
import '../repositories/firestore/firestore_payment_repository.dart';
import '../repositories/firestore/firestore_recurring_transaction_repository.dart';
import '../repositories/firestore/firestore_user_profile_repository.dart';
import '../repositories/shopify_connection_repository.dart';
import '../repositories/shopify_product_mapping_repository.dart';
import '../repositories/shopify_sync_log_repository.dart';
import '../repositories/firestore/firestore_shopify_connection_repository.dart';
import '../repositories/firestore/firestore_shopify_product_mapping_repository.dart';
import '../repositories/firestore/firestore_shopify_sync_log_repository.dart';
import '../repositories/conversion_order_repository.dart';
import '../repositories/firestore/firestore_conversion_order_repository.dart';
import '../../shared/models/conversion_order_model.dart';

/// ─── Repository Providers ─────────────────────────────────
///
/// These providers expose repository instances to the rest of the app.
/// Using Firestore implementations for cloud persistence.

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository();
});

final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return FirestoreTransactionRepository();
});

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return FirestoreCategoryRepository();
});

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return FirestoreProductRepository();
});

final supplierRepositoryProvider = Provider<SupplierRepository>((ref) {
  return FirestoreSupplierRepository();
});

final purchaseRepositoryProvider = Provider<PurchaseRepository>((ref) {
  return FirestorePurchaseRepository();
});

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return FirestorePaymentRepository();
});

final recurringTransactionRepositoryProvider =
    Provider<RecurringTransactionRepository>((ref) {
  return FirestoreRecurringTransactionRepository();
});

final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  return FirestoreUserProfileRepository();
});

final saleRepositoryProvider = Provider<SaleRepository>((ref) {
  final saleRepo = FirestoreSaleRepository();
  // When sale mutations also write transaction docs (batch creates),
  // invalidate the txn range cache to prevent stale reads.
  saleRepo.onTransactionCacheInvalidated =
      () => ref.read(transactionRepositoryProvider).clearRangeCache();
  return saleRepo;
});

final goodsReceiptRepositoryProvider =
    Provider<GoodsReceiptRepository>((ref) {
  return FirestoreGoodsReceiptRepository();
});

final balanceSheetRepositoryProvider =
    Provider<BalanceSheetRepository>((ref) {
  return FirestoreBalanceSheetRepository();
});

// ─── Shopify Repositories ────────────────────────────────

final shopifyConnectionRepositoryProvider =
    Provider<ShopifyConnectionRepository>((ref) {
  return FirestoreShopifyConnectionRepository();
});

final shopifyProductMappingRepositoryProvider =
    Provider<ShopifyProductMappingRepository>((ref) {
  return FirestoreShopifyProductMappingRepository();
});

final shopifySyncLogRepositoryProvider =
    Provider<ShopifySyncLogRepository>((ref) {
  return FirestoreShopifySyncLogRepository();
});

// ─── Conversion Orders ─────────────────────────────────

final conversionOrderRepositoryProvider =
    Provider<ConversionOrderRepository>((ref) {
  return FirestoreConversionOrderRepository();
});

/// Fetches conversion orders for a specific product.
final conversionOrdersForProductProvider =
    FutureProvider.family<List<ConversionOrder>, String>((ref, productId) async {
  final repo = ref.read(conversionOrderRepositoryProvider);
  final result = await repo.getOrdersForProduct(productId);
  return result.data ?? [];
});
