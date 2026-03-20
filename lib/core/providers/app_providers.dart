import 'dart:async';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../shared/models/transaction_model.dart';
import '../../shared/models/category_data.dart';
import '../../shared/models/product_model.dart';
import '../../shared/models/supplier_model.dart';
import '../../shared/models/purchase_model.dart';
import '../../shared/models/payment_model.dart';
import '../../shared/models/sale_model.dart';
import '../../shared/models/goods_receipt_model.dart';
import '../repositories/sale_repository.dart' show StockDeduction;
import '../services/result.dart';
import '../../shared/models/balance_sheet_entries.dart';
import '../../shared/models/conversion_order_model.dart';
import 'auth_provider.dart';
import 'app_settings_provider.dart';
import 'repository_providers.dart';
import '../../features/shopify/providers/shopify_connection_provider.dart';
import '../services/shopify_sync_service.dart';

// ═══════════════════════════════════════════════════════════
// USER STATE  (legacy bridge — will be replaced by AuthNotifier)
// ═══════════════════════════════════════════════════════════

class UserState {
  final String name;
  final String email;

  const UserState({
    required this.name,
    required this.email,
  });

  UserState copyWith({String? name, String? email}) {
    return UserState(
      name: name ?? this.name,
      email: email ?? this.email,
    );
  }
}

class UserNotifier extends Notifier<UserState> {
  @override
  UserState build() => const UserState(name: 'User', email: '');

  void setUser(String name, String email) {
    state = UserState(name: name, email: email);
  }

  void updateName(String name) {
    state = state.copyWith(name: name);
  }
}

final userProvider = NotifierProvider<UserNotifier, UserState>(() {
  return UserNotifier();
});

// ═══════════════════════════════════════════════════════════
// TRANSACTIONS  — AsyncNotifier with loading/error states
// ═══════════════════════════════════════════════════════════

class TransactionsNotifier extends AsyncNotifier<List<Transaction>> {
  String? _lastDocId;
  final int _limit = 20;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  Completer<void>? _loadAllCompleter;
  int _buildGeneration = 0;

  bool get hasMore => _hasMore;

  @override
  Future<List<Transaction>> build() async {
    _lastDocId = null;
    _hasMore = true;
    _buildGeneration++;
    final repo = ref.read(transactionRepositoryProvider);
    final result = await repo.getTransactions(limit: _limit);
    if (result.isSuccess && result.data != null) {
      final newItems = result.data!;
      _hasMore = newItems.length == _limit;
      if (newItems.isNotEmpty) _lastDocId = newItems.last.id;
      return newItems;
    }
    throw Exception(result.error ?? 'Failed to load transactions');
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    
    _isLoadingMore = true;
    final gen = _buildGeneration;
    try {
      final repo = ref.read(transactionRepositoryProvider);
      final result = await repo.getTransactions(
        limit: _limit,
        startAfterId: _lastDocId,
      );
      
      if (gen != _buildGeneration) return; // refresh() happened, discard
      if (result.isSuccess && result.data != null) {
        final newItems = result.data!;
        _hasMore = newItems.length == _limit;
        if (newItems.isNotEmpty) _lastDocId = newItems.last.id;
        
        final currentList = state.value ?? [];
        final existingIds = currentList.map((t) => t.id).toSet();
        final deduped = newItems.where((t) => !existingIds.contains(t.id)).toList();
        if (deduped.isNotEmpty) {
          state = AsyncValue.data([...currentList, ...deduped]);
        }
      }
    } catch (e) {
      // Don't throw here to avoid blowing away the main list state,
      // just let the UI know it failed (could show a snackbar)
    } finally {
      _isLoadingMore = false;
    }
  }

  /// Loads all remaining pages. Used by report screens that need complete data.
  Future<void> loadAll() async {
    if (_loadAllCompleter != null) return _loadAllCompleter!.future;
    _loadAllCompleter = Completer<void>();
    try {
      while (_hasMore) {
        await loadMore();
      }
      _loadAllCompleter!.complete();
    } catch (e) {
      _loadAllCompleter!.completeError(e);
    } finally {
      _loadAllCompleter = null;
    }
  }

  Future<void> addTransaction(Transaction transaction) async {
    // Optimistic: update state immediately so UI reflects the change
    final previous = state.value ?? [];
    state = AsyncValue.data([transaction, ...previous]);

    final repo = ref.read(transactionRepositoryProvider);
    final result = await repo.createTransaction(transaction);
    if (result.isSuccess && result.data != null) {
      // Replace optimistic entry with server-confirmed data
      final current = state.value ?? [];
      state = AsyncValue.data([
        for (final t in current)
          if (t.id == transaction.id) result.data! else t,
      ]);
    } else if (!result.isSuccess) {
      // Rollback on failure
      final current = state.value ?? [];
      state = AsyncValue.data(
        current.where((t) => t.id != transaction.id).toList(),
      );
    }
  }

  Future<void> removeTransaction(String id) async {
    // Optimistic: remove from state immediately
    final previous = state.value ?? [];
    state = AsyncValue.data(previous.where((t) => t.id != id).toList());

    final repo = ref.read(transactionRepositoryProvider);
    final result = await repo.deleteTransaction(id);
    if (!result.isSuccess) {
      // Rollback on failure
      state = AsyncValue.data(previous);
    }
  }

  Future<void> updateTransaction(Transaction transaction) async {
    // Optimistic: update state immediately
    final previous = state.value ?? [];
    state = AsyncValue.data([
      for (final t in previous)
        if (t.id == transaction.id) transaction else t,
    ]);

    final repo = ref.read(transactionRepositoryProvider);
    final result = await repo.updateTransaction(transaction);
    if (!result.isSuccess) {
      // Rollback on failure
      state = AsyncValue.data(previous);
    }
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => build());
  }

  /// Resets to page 1 then loads ALL remaining pages in one call.
  /// Use this instead of refresh() when a screen needs complete data.
  Future<void> refreshAll() async {
    state = await AsyncValue.guard(() => build());
    await loadAll();
  }
}

final transactionsProvider =
    AsyncNotifierProvider<TransactionsNotifier, List<Transaction>>(() {
  return TransactionsNotifier();
});

// ═══════════════════════════════════════════════════════════
// CATEGORIES  — AsyncNotifier with loading/error states
// ═══════════════════════════════════════════════════════════

class CategoriesNotifier extends AsyncNotifier<List<CategoryData>> {
  @override
  Future<List<CategoryData>> build() async {
    final repo = ref.read(categoryRepositoryProvider);
    final result = await repo.getCategories();
    if (result.isSuccess && result.data != null) {
      CategoryData.customCategories = result.data!;
      return result.data!;
    }
    throw Exception(result.error ?? 'Failed to load categories');
  }

  Future<void> addCategory(CategoryData category) async {
    final current = state.value ?? [];
    final newList = [...current, category];
    CategoryData.customCategories = newList;
    state = AsyncValue.data(newList);

    final repo = ref.read(categoryRepositoryProvider);
    final result = await repo.createCategory(category);
    if (result.isSuccess && result.data != null) {
      // Swap optimistic item with the one carrying the real Firestore ID
      final updatedList = <CategoryData>[
        for (final c in state.value ?? [])
          if (c.id == category.id) result.data! else c,
      ];
      CategoryData.customCategories = updatedList;
      state = AsyncValue.data(updatedList);
    } else if (!result.isSuccess) {
      CategoryData.customCategories = current;
      state = AsyncValue.data(current);
    }
  }

  Future<void> removeCategory(String id) async {
    final current = state.value ?? [];
    final newList = current.where((c) => c.id != id).toList();
    CategoryData.customCategories = newList;
    state = AsyncValue.data(newList);

    // Reassign ALL orphaned transactions to Uncategorized (server-side batch)
    final txRepo = ref.read(transactionRepositoryProvider);
    await txRepo.reassignCategory(id, 'cat_uncategorized');

    // Refresh loaded transactions to reflect the reassignment
    ref.read(transactionsProvider.notifier).refresh();

    final repo = ref.read(categoryRepositoryProvider);
    final result = await repo.deleteCategory(id);
    if (!result.isSuccess) {
      CategoryData.customCategories = current;
      state = AsyncValue.data(current);
    }
  }

  Future<void> updateCategory(CategoryData updated) async {
    final current = state.value ?? [];
    final newList = [
      for (final c in current)
        if (c.id == updated.id) updated else c,
    ];
    CategoryData.customCategories = newList;
    state = AsyncValue.data(newList);

    final repo = ref.read(categoryRepositoryProvider);
    final result = await repo.updateCategory(updated);
    if (!result.isSuccess) {
      CategoryData.customCategories = current;
      state = AsyncValue.data(current);
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => build());
  }
}

final categoriesProvider =
    AsyncNotifierProvider<CategoriesNotifier, List<CategoryData>>(() {
  return CategoriesNotifier();
});

// ═══════════════════════════════════════════════════════════
// INVENTORY  — AsyncNotifier with loading/error states
// ═══════════════════════════════════════════════════════════

class InventoryNotifier extends AsyncNotifier<List<Product>> {
  String? _lastDocId;
  final int _limit = 20;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  int _buildGeneration = 0;

  bool get hasMore => _hasMore;

  @override
  Future<List<Product>> build() async {
    _lastDocId = null;
    _hasMore = true;
    _buildGeneration++;
    final repo = ref.read(productRepositoryProvider);
    final result = await repo.getProducts(limit: _limit);
    if (result.isSuccess && result.data != null) {
      final newItems = result.data!;
      _hasMore = newItems.length == _limit;
      if (newItems.isNotEmpty) _lastDocId = newItems.last.id;
      return newItems;
    }
    throw Exception(result.error ?? 'Failed to load products');
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    
    _isLoadingMore = true;
    final gen = _buildGeneration;
    try {
      final repo = ref.read(productRepositoryProvider);
      final result = await repo.getProducts(
        limit: _limit,
        startAfterId: _lastDocId,
      );
      
      if (gen != _buildGeneration) return; // refresh() happened, discard
      if (result.isSuccess && result.data != null) {
        final newItems = result.data!;
        _hasMore = newItems.length == _limit;
        if (newItems.isNotEmpty) _lastDocId = newItems.last.id;
        
        final currentList = state.value ?? [];
        final existingIds = currentList.map((p) => p.id).toSet();
        final deduped = newItems.where((p) => !existingIds.contains(p.id)).toList();
        if (deduped.isNotEmpty) {
          state = AsyncValue.data([...currentList, ...deduped]);
        }
      }
    } catch (e) {
      // Silently fail pagination, let user try again or swipe to refresh
    } finally {
      _isLoadingMore = false;
    }
  }

  /// Loads all remaining pages. Used by report screens that need complete data.
  Completer<void>? _loadAllCompleter;
  Future<void> loadAll() async {
    if (_loadAllCompleter != null) return _loadAllCompleter!.future;
    _loadAllCompleter = Completer<void>();
    try {
      while (_hasMore) {
        await loadMore();
      }
      _loadAllCompleter!.complete();
    } catch (e) {
      _loadAllCompleter!.completeError(e);
    } finally {
      _loadAllCompleter = null;
    }
  }

  Future<Result<Product>> addProduct(Product product) async {
    // Optimistic: update state immediately
    final previous = state.value ?? [];
    state = AsyncValue.data([...previous, product]);

    final repo = ref.read(productRepositoryProvider);
    final result = await repo.createProduct(product);
    if (result.isSuccess && result.data != null) {
      final current = state.value ?? [];
      state = AsyncValue.data([
        for (final p in current)
          if (p.id == product.id) result.data! else p,
      ]);
      return result;
    } else if (!result.isSuccess) {
      state = AsyncValue.data(previous);
      return result;
    }
    return Result.failure('Failed to add product');
  }

  Future<void> removeProduct(String id) async {
    // Optimistic: remove immediately
    final previous = state.value ?? [];
    state = AsyncValue.data(previous.where((p) => p.id != id).toList());

    final repo = ref.read(productRepositoryProvider);
    final result = await repo.deleteProduct(id);
    if (!result.isSuccess) {
      state = AsyncValue.data(previous);
    } else {
      // Clean up any Shopify product mappings for this product
      final mappingRepo = ref.read(shopifyProductMappingRepositoryProvider);
      mappingRepo.deleteMappingsByMasariProductId(id);
    }
  }

  Future<Result<Product>> updateProduct(String id, Product updated) async {
    // Optimistic: update state immediately
    final previous = state.value ?? [];
    state = AsyncValue.data([
      for (final p in previous)
        if (p.id == id) updated else p,
    ]);

    final repo = ref.read(productRepositoryProvider);
    final result = await repo.updateProduct(id, updated);
    if (result.isSuccess && result.data != null) {
      final current = state.value ?? [];
      state = AsyncValue.data([
        for (final p in current)
          if (p.id == id) result.data! else p,
      ]);
      // Auto-push product details to Shopify (fire-and-forget)
      _autoPushProductToShopify(id, result.data!);
      return result;
    } else {
      state = AsyncValue.data(previous);
      return result;
    }
  }

  Future<Result<Product>> adjustStock(String id, String variantId, int delta, String reason, {double? unitCost, String valuationMethod = 'fifo', String? supplierName, bool skipCostLayer = false, bool clearLegacyLayers = false}) async {
    final repo = ref.read(productRepositoryProvider);
    final result = await repo.adjustStock(id, variantId, delta, reason, unitCost: unitCost, valuationMethod: valuationMethod, supplierName: supplierName, skipCostLayer: skipCostLayer, clearLegacyLayers: clearLegacyLayers);
    if (result.isSuccess && result.data != null) {
      final current = state.value ?? [];
      state = AsyncValue.data([
        for (final p in current)
          if (p.id == id) result.data! else p,
      ]);

      // Auto-push to Shopify if always-on sync is active.
      // Fire-and-forget — errors are logged but don't block the UI.
      _autoPushToShopify(id, variantId, result.data!);
    }
    return result;
  }

  /// Pushes updated stock to Shopify when always-on inventory sync is active.
  void _autoPushToShopify(String productId, String variantId, Product updatedProduct) {
    // Read connection (may not exist if Shopify is not connected)
    final conn = ref.read(shopifyConnectionProvider).value;
    if (conn == null || !conn.isActive) return;
    if (conn.syncInventoryEnabled != true) return;
    if (conn.inventorySyncMode != 'always') return;

    // Find the updated variant's stock level
    final variant = updatedProduct.variants.where((v) => v.id == variantId).firstOrNull;
    if (variant == null) return;

    final syncService = ref.read(shopifySyncServiceProvider);
    syncService.syncInventoryToShopify(
      productId: productId,
      variantId: variantId,
      newStock: variant.currentStock,
    ).then((pushResult) {
      if (!pushResult.isSuccess) {
        developer.log(
          'Auto-push to Shopify failed: ${pushResult.error}',
          name: 'InventoryNotifier',
        );
      }
    }).catchError((Object e) {
      developer.log(
        'Auto-push to Shopify error: $e',
        name: 'InventoryNotifier',
      );
    });
  }

  /// Pushes product detail changes (title, prices, SKUs) to Shopify.
  void _autoPushProductToShopify(String productId, Product product) {
    final conn = ref.read(shopifyConnectionProvider).value;
    if (conn == null || !conn.isActive) return;
    if (conn.syncInventoryEnabled != true) return;
    if (conn.inventorySyncMode != 'always') return;

    // Only push if the product is actually mapped to Shopify
    if (product.shopifyProductId == null || product.shopifyProductId!.isEmpty) return;

    final syncService = ref.read(shopifySyncServiceProvider);
    syncService.syncProductToShopify(
      productId: productId,
      productName: product.name,
      variants: product.variants
          .map((v) => (variantId: v.id, sellingPrice: v.sellingPrice, sku: v.sku))
          .toList(),
    ).then((pushResult) {
      if (!pushResult.isSuccess) {
        developer.log(
          'Auto-push product to Shopify failed: ${pushResult.error}',
          name: 'InventoryNotifier',
        );
      }
    }).catchError((Object e) {
      developer.log(
        'Auto-push product to Shopify error: $e',
        name: 'InventoryNotifier',
      );
    });
  }

  /// Performs a variant breakdown operation atomically.
  /// Returns an error string on failure, or null on success.
  Future<String?> breakdownProduct({
    required String productId,
    required String sourceVariantId,
    required int qty,
    required String valuationMethod,
  }) async {
    if (qty <= 0) return 'Quantity must be greater than 0';

    // Read fresh from Firestore to avoid stale cost layers in local cache
    final freshResult = await ref.read(productRepositoryProvider).getProductById(productId);
    if (!freshResult.isSuccess || freshResult.data == null) {
      return freshResult.error ?? 'Product not found';
    }
    final product = freshResult.data!;
    if (!product.hasBreakdown) return 'No breakdown recipe';

    final recipe = product.breakdownRecipe!;
    if (recipe.sourceVariantId != sourceVariantId) return 'Source variant mismatch';

    final sourceVariant = product.variantById(sourceVariantId);
    if (sourceVariant == null) return 'Source variant not found';
    if (sourceVariant.currentStock < qty) return 'Insufficient stock';

    // Calculate total cost consumed from source using selected valuation method
    final cogsPerUnit = sourceVariant.cogsPerUnit(qty, valuationMethod);
    final totalCost = cogsPerUnit * qty;

    // Allocate cost to outputs by selling price ratio.
    // Fallback: if all selling prices are zero, allocate by output quantity.
    final outputAllocations = <String, ({int quantity, double unitCost})>{};
    double totalSellingValue = 0;
    int totalOutputQty = 0;
    for (final output in recipe.outputs) {
      final variant = product.variantById(output.variantId);
      totalOutputQty += (output.quantityPerUnit * qty).round();
      if (variant != null) {
        totalSellingValue += output.quantityPerUnit * variant.sellingPrice;
      }
    }
    for (final output in recipe.outputs) {
      final variant = product.variantById(output.variantId);
      final outputQty = (output.quantityPerUnit * qty).round();
      if (outputQty <= 0) continue;

      double unitCost;
      if (variant != null && totalSellingValue > 0) {
        final outputSelling = output.quantityPerUnit * variant.sellingPrice;
        final allocatedTotal = totalCost * (outputSelling / totalSellingValue);
        unitCost = (allocatedTotal / outputQty * 100).roundToDouble() / 100;
      } else {
        unitCost = totalOutputQty > 0
            ? (totalCost / totalOutputQty * 100).roundToDouble() / 100
            : 0.0;
      }

      outputAllocations[output.variantId] = (
        quantity: outputQty,
        unitCost: unitCost,
      );
    }

    // 1. Perform atomic breakdown (source deduction + output additions in a single transaction)
    final result = await ref.read(productRepositoryProvider).breakdownStock(
      productId: productId,
      sourceVariantId: sourceVariantId,
      qty: qty,
      valuationMethod: valuationMethod,
      outputAllocations: outputAllocations,
    );
    if (!result.isSuccess || result.data == null) {
      return result.error ?? 'Breakdown failed';
    }

    // 2. Save conversion order for audit trail
    final outputLines = recipe.outputs.map((output) {
      final variant = product.variantById(output.variantId);
      final alloc = outputAllocations[output.variantId];
      final outputQty = alloc?.quantity ?? (output.quantityPerUnit * qty).round();
      final unitCost = alloc?.unitCost ?? 0.0;
      return ConversionOutputLine(
        variantId: output.variantId,
        variantName: variant?.displayName ?? output.variantId,
        quantity: outputQty.toDouble(),
        unitCost: unitCost,
        totalCost: unitCost * outputQty,
      );
    }).toList();

    final order = ConversionOrder(
      id: const Uuid().v4(),
      userId: ref.read(authProvider).user?.id ?? '',
      productId: productId,
      productName: product.name,
      sourceVariantId: sourceVariantId,
      sourceQuantity: qty.toDouble(),
      sourceTotalCost: totalCost,
      outputs: outputLines,
      date: DateTime.now(),
    );
    await ref.read(conversionOrderRepositoryProvider).createOrder(order);

    // 3. Update local state
    final updatedProduct = result.data!;
    final current = state.value ?? [];
    state = AsyncValue.data([
      for (final p in current)
        if (p.id == productId) updatedProduct else p,
    ]);
    return null; // success
  }

  /// Recalculate output variant costs from the breakdown recipe.
  /// Replaces cost layers for each output variant with a single layer
  /// at the correct breakdown-derived cost (source cost allocated by
  /// selling-price ratio). Fixes data from before cost-layer tracking.
  Future<String?> recalculateBreakdownCosts({
    required String productId,
    bool confirmed = false,
  }) async {
    final products = state.value ?? [];
    final product = products.cast<Product?>().firstWhere(
      (p) => p!.id == productId,
      orElse: () => null,
    );
    if (product == null) return 'Product not found';
    if (!product.hasBreakdown) return 'No breakdown recipe';

    final recipe = product.breakdownRecipe!;

    // Guard: if any output variant already has cost layers, require explicit
    // confirmation so the user is aware existing layer history will be replaced.
    if (!confirmed) {
      final hasExistingLayers = recipe.outputs.any((o) {
        final v = product.variantById(o.variantId);
        return v != null && v.costLayers.isNotEmpty;
      });
      if (hasExistingLayers) {
        return 'CONFIRM_REQUIRED';
      }
    }

    final sourceVariant = product.variantById(recipe.sourceVariantId);
    if (sourceVariant == null) return 'Source variant not found';

    final sourceCost = sourceVariant.costPrice;

    // Calculate selling-price-weighted cost allocation
    double totalSellingValue = 0;
    for (final output in recipe.outputs) {
      final v = product.variantById(output.variantId);
      if (v != null) {
        totalSellingValue += output.quantityPerUnit * v.sellingPrice;
      }
    }
    final totalOutputQtyPerUnit = recipe.outputs
      .map((o) => o.quantityPerUnit)
      .fold<double>(0.0, (s, q) => s + q);

    // Build corrected variants
    final updatedVariants = product.variants.map((v) {
      final output = recipe.outputs.where((o) => o.variantId == v.id);
      if (output.isEmpty) return v; // source or unrelated variant

      final outDef = output.first;
        final correctUnitCost = totalSellingValue > 0
          ? (((sourceCost *
                  ((outDef.quantityPerUnit * v.sellingPrice) /
                    totalSellingValue)) /
                outDef.quantityPerUnit) *
              100)
            .roundToDouble() /
            100
          : (totalOutputQtyPerUnit > 0
            ? (sourceCost / totalOutputQtyPerUnit * 100)
                .roundToDouble() /
              100
            : sourceCost);

      if (v.currentStock <= 0) {
        return v.copyWith(costPrice: correctUnitCost, costLayers: []);
      }
      return v.copyWith(
        costPrice: correctUnitCost,
        costLayers: [
          CostLayer(
            date: DateTime.now(),
            unitCost: correctUnitCost,
            remainingQty: v.currentStock,
          ),
        ],
      );
    }).toList();

    final updated = product.copyWith(
      variants: updatedVariants,
      updatedAt: DateTime.now(),
    );

    await ref.read(productRepositoryProvider).updateProduct(productId, updated);
    final current = state.value ?? [];
    state = AsyncValue.data([
      for (final p in current)
        if (p.id == productId) updated else p,
    ]);
    return null; // success
  }

  Future<void> refresh() async {
    _buildGeneration++;
    final gen = _buildGeneration;
    _lastDocId = null;
    _hasMore = false;
    _isLoadingMore = false;

    // Only show spinner on the very first load (no data yet)
    if (state is! AsyncData) {
      state = const AsyncValue.loading();
    }

    try {
      final repo = ref.read(productRepositoryProvider);
      // Load ALL products in one shot for a complete, consistent view.
      // Pagination is only used for the initial lazy load via build().
      final result = await repo.getProducts();
      if (gen != _buildGeneration) return;
      if (result.isSuccess && result.data != null) {
        final items = result.data!;
        _hasMore = false;
        if (items.isNotEmpty) _lastDocId = items.last.id;
        state = AsyncValue.data(items);
      } else {
        throw Exception(result.error ?? 'Failed to load products');
      }
    } catch (e, st) {
      if (gen != _buildGeneration) return;
      // If we had old data, keep it visible instead of showing error
      if (state is AsyncData) return;
      state = AsyncValue.error(e, st);
    }
  }

  /// Alias for [refresh] — loads all products.
  Future<void> refreshAll() async {
    await refresh();
  }
}

final inventoryProvider =
    AsyncNotifierProvider<InventoryNotifier, List<Product>>(() {
  return InventoryNotifier();
});

// ═══════════════════════════════════════════════════════════
// SUPPLIERS  — AsyncNotifier with loading/error states
// ═══════════════════════════════════════════════════════════

class SuppliersNotifier extends AsyncNotifier<List<Supplier>> {
  String? _lastDocId;
  final int _limit = 20;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  bool get hasMore => _hasMore;

  @override
  Future<List<Supplier>> build() async {
    _lastDocId = null;
    _hasMore = true;
    final repo = ref.read(supplierRepositoryProvider);
    final result = await repo.getSuppliers(limit: _limit);
    if (result.isSuccess && result.data != null) {
      final newItems = result.data!;
      _hasMore = newItems.length == _limit;
      if (newItems.isNotEmpty) _lastDocId = newItems.last.id;
      return newItems;
    }
    throw Exception(result.error ?? 'Failed to load suppliers');
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    
    _isLoadingMore = true;
    try {
      final repo = ref.read(supplierRepositoryProvider);
      final result = await repo.getSuppliers(
        limit: _limit,
        startAfterId: _lastDocId,
      );
      
      if (result.isSuccess && result.data != null) {
        final newItems = result.data!;
        _hasMore = newItems.length == _limit;
        if (newItems.isNotEmpty) _lastDocId = newItems.last.id;
        
        final currentList = state.value ?? [];
        final existingIds = currentList.map((s) => s.id).toSet();
        final deduped = newItems.where((s) => !existingIds.contains(s.id)).toList();
        if (deduped.isNotEmpty) {
          state = AsyncValue.data([...currentList, ...deduped]);
        }
      }
    } catch (e) {
      // Silently fail pagination, let user try again or swipe to refresh
    } finally {
      _isLoadingMore = false;
    }
  }

  /// Loads all remaining pages.
  Completer<void>? _loadAllCompleter;
  Future<void> loadAll() async {
    if (_loadAllCompleter != null) return _loadAllCompleter!.future;
    _loadAllCompleter = Completer<void>();
    try {
      while (_hasMore) {
        await loadMore();
      }
      _loadAllCompleter!.complete();
    } catch (e) {
      _loadAllCompleter!.completeError(e);
    } finally {
      _loadAllCompleter = null;
    }
  }

  Future<void> addSupplier(Supplier supplier) async {
    final repo = ref.read(supplierRepositoryProvider);
    final result = await repo.createSupplier(supplier);
    if (result.isSuccess && result.data != null) {
      final current = state.value ?? [];
      state = AsyncValue.data([...current, result.data!]);
    }
  }

  Future<void> removeSupplier(String id) async {
    final repo = ref.read(supplierRepositoryProvider);
    final result = await repo.deleteSupplier(id);
    if (result.isSuccess) {
      final current = state.value ?? [];
      state = AsyncValue.data(current.where((s) => s.id != id).toList());
    }
  }

  Future<void> updateSupplier(String id, Supplier updated) async {
    final repo = ref.read(supplierRepositoryProvider);
    final result = await repo.updateSupplier(id, updated);
    if (result.isSuccess && result.data != null) {
      final current = state.value ?? [];
      state = AsyncValue.data([
        for (final s in current)
          if (s.id == id) result.data! else s,
      ]);
    }
  }

  Future<void> recordPayment(String id, double amount) async {
    final repo = ref.read(supplierRepositoryProvider);
    final result = await repo.recordPayment(id, amount);
    if (result.isSuccess && result.data != null) {
      final current = state.value ?? [];
      state = AsyncValue.data([
        for (final s in current)
          if (s.id == id) result.data! else s,
      ]);
    }
  }

  Future<void> recordPurchase(String id, double amount, {DateTime? dueDate}) async {
    final repo = ref.read(supplierRepositoryProvider);
    final result = await repo.recordPurchase(id, amount, dueDate: dueDate);
    if (result.isSuccess && result.data != null) {
      final current = state.value ?? [];
      state = AsyncValue.data([
        for (final s in current)
          if (s.id == id) result.data! else s,
      ]);
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => build());
  }

  /// Resets to page 1 then loads ALL remaining pages in one call.
  Future<void> refreshAll() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => build());
    await loadAll();
  }
}

final suppliersProvider =
    AsyncNotifierProvider<SuppliersNotifier, List<Supplier>>(() {
  return SuppliersNotifier();
});

// ═══════════════════════════════════════════════════════════
// PURCHASES  — AsyncNotifier with optimistic updates
// ═══════════════════════════════════════════════════════════

class PurchasesNotifier extends AsyncNotifier<List<Purchase>> {
  @override
  Future<List<Purchase>> build() async {
    final repo = ref.read(purchaseRepositoryProvider);
    final result = await repo.getPurchases();
    if (result.isSuccess && result.data != null) {
      return result.data!;
    }
    throw Exception(result.error ?? 'Failed to load purchases');
  }

  void addPurchase(Purchase p) {
    final current = state.value ?? [];
    state = AsyncValue.data([...current, p]);
    _createPurchase(p);
  }

  Future<void> _createPurchase(Purchase p) async {
    final repo = ref.read(purchaseRepositoryProvider);
    final result = await repo.createPurchase(p);
    if (result.isSuccess && result.data != null) {
      final current = state.value ?? [];
      state = AsyncValue.data([for (final x in current) if (x.id == p.id) result.data! else x]);
    } else if (!result.isSuccess) {
      final current = state.value ?? [];
      state = AsyncValue.data(current.where((x) => x.id != p.id).toList());
    }
  }

  void updatePurchase(Purchase updated) {
    final old = state.value ?? [];
    state = AsyncValue.data([for (final p in old) if (p.id == updated.id) updated else p]);
    _updatePurchase(updated, old);
  }

  Future<void> _updatePurchase(Purchase updated, List<Purchase> rollback) async {
    final repo = ref.read(purchaseRepositoryProvider);
    final result = await repo.updatePurchase(updated.id, updated);
    if (!result.isSuccess) {
      state = AsyncValue.data(rollback);
    }
  }

  void removePurchase(String id) {
    final old = state.value ?? [];
    state = AsyncValue.data(old.where((p) => p.id != id).toList());
    _deletePurchase(id, old);
  }

  Future<void> _deletePurchase(String id, List<Purchase> rollback) async {
    final repo = ref.read(purchaseRepositoryProvider);
    final result = await repo.deletePurchase(id);
    if (!result.isSuccess) {
      state = AsyncValue.data(rollback);
    }
  }

  List<Purchase> forSupplier(String supplierId) =>
      (state.value ?? []).where((p) => p.supplierId == supplierId).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
}

final purchasesProvider = AsyncNotifierProvider<PurchasesNotifier, List<Purchase>>(() {
  return PurchasesNotifier();
});

// ═══════════════════════════════════════════════════════════
// PAYMENTS  — AsyncNotifier with optimistic updates
// ═══════════════════════════════════════════════════════════

class PaymentsNotifier extends AsyncNotifier<List<Payment>> {
  @override
  Future<List<Payment>> build() async {
    final repo = ref.read(paymentRepositoryProvider);
    final result = await repo.getPayments();
    if (result.isSuccess && result.data != null) {
      return result.data!;
    }
    throw Exception(result.error ?? 'Failed to load payments');
  }

  void addPayment(Payment p) {
    final current = state.value ?? [];
    state = AsyncValue.data([...current, p]);
    _createPayment(p);
  }

  Future<void> _createPayment(Payment p) async {
    final repo = ref.read(paymentRepositoryProvider);
    final result = await repo.createPayment(p);
    if (result.isSuccess && result.data != null) {
      final current = state.value ?? [];
      state = AsyncValue.data([for (final x in current) if (x.id == p.id) result.data! else x]);
    } else if (!result.isSuccess) {
      final current = state.value ?? [];
      state = AsyncValue.data(current.where((x) => x.id != p.id).toList());
    }
  }

  void updatePayment(Payment updated) {
    final old = state.value ?? [];
    state = AsyncValue.data([for (final p in old) if (p.id == updated.id) updated else p]);
    _updatePayment(updated, old);
  }

  Future<void> _updatePayment(Payment updated, List<Payment> rollback) async {
    final repo = ref.read(paymentRepositoryProvider);
    final result = await repo.updatePayment(updated.id, updated);
    if (!result.isSuccess) {
      state = AsyncValue.data(rollback);
    }
  }

  void removePayment(String id) {
    final old = state.value ?? [];
    state = AsyncValue.data(old.where((p) => p.id != id).toList());
    _deletePayment(id, old);
  }

  Future<void> _deletePayment(String id, List<Payment> rollback) async {
    final repo = ref.read(paymentRepositoryProvider);
    final result = await repo.deletePayment(id);
    if (!result.isSuccess) {
      state = AsyncValue.data(rollback);
    }
  }

  List<Payment> forSupplier(String supplierId) =>
      (state.value ?? []).where((p) => p.supplierId == supplierId).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
}

final paymentsProvider = AsyncNotifierProvider<PaymentsNotifier, List<Payment>>(() {
  return PaymentsNotifier();
});

// ═══════════════════════════════════════════════════════════
// SALES  — AsyncNotifier (Growth tier)
// ═══════════════════════════════════════════════════════════

class SalesNotifier extends AsyncNotifier<List<Sale>> {
  String? _lastDocId;
  final int _limit = 20;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  int _buildGeneration = 0;

  bool get hasMore => _hasMore;

  @override
  Future<List<Sale>> build() async {
    _lastDocId = null;
    _hasMore = true;
    _buildGeneration++;
    final repo = ref.read(saleRepositoryProvider);
    final result = await repo.getSales(limit: _limit);
    if (result.isSuccess && result.data != null) {
      final newItems = result.data!;
      _hasMore = newItems.length == _limit;
      if (newItems.isNotEmpty) _lastDocId = newItems.last.id;
      return newItems;
    }
    throw Exception(result.error ?? 'Failed to load sales');
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    _isLoadingMore = true;
    final gen = _buildGeneration;
    try {
      final repo = ref.read(saleRepositoryProvider);
      final result = await repo.getSales(
        limit: _limit,
        startAfterId: _lastDocId,
      );

      if (gen != _buildGeneration) return; // refresh() happened, discard
      if (result.isSuccess && result.data != null) {
        final newItems = result.data!;
        _hasMore = newItems.length == _limit;
        if (newItems.isNotEmpty) _lastDocId = newItems.last.id;

        final currentList = state.value ?? [];
        final existingIds = currentList.map((s) => s.id).toSet();
        final deduped = newItems.where((s) => !existingIds.contains(s.id)).toList();
        if (deduped.isNotEmpty) {
          state = AsyncValue.data([...currentList, ...deduped]);
        }
      }
    } catch (e) {
      // Silently fail pagination
    } finally {
      _isLoadingMore = false;
    }
  }

  /// Loads all remaining pages. Used by report screens that need complete data.
  Completer<void>? _loadAllCompleter;
  Future<void> loadAll() async {
    if (_loadAllCompleter != null) return _loadAllCompleter!.future;
    _loadAllCompleter = Completer<void>();
    try {
      while (_hasMore) {
        await loadMore();
      }
      _loadAllCompleter!.complete();
    } catch (e) {
      _loadAllCompleter!.completeError(e);
    } finally {
      _loadAllCompleter = null;
    }
  }

  Future<void> addSale(Sale sale) async {
    final repo = ref.read(saleRepositoryProvider);
    final result = await repo.createSale(sale);
    if (result.isSuccess && result.data != null) {
      final current = state.value ?? [];
      state = AsyncValue.data([result.data!, ...current]);
    } else if (!result.isSuccess) {
      state = AsyncValue.error(
        result.error ?? 'Failed to add sale',
        StackTrace.current,
      );
    }
  }

  /// Creates sale + associated revenue/COGS transactions atomically.
  /// When [stockDeductions] is provided, stock adjustments are included in the
  /// same Firestore transaction so everything succeeds or fails together.
  /// Returns true on success. Transactions are also inserted into the
  /// TransactionsNotifier state so the UI is consistent.
  Future<bool> addSaleAtomic(Sale sale, List<Transaction> transactions,
      {List<StockDeduction> stockDeductions = const []}) async {
    // Optimistic: update state immediately
    final previousSales = state.value ?? [];
    state = AsyncValue.data([sale, ...previousSales]);

    final currentTxns = ref.read(transactionsProvider).value ?? [];
    final existingIds = currentTxns.map((t) => t.id).toSet();
    final newTxns = transactions.where((t) => !existingIds.contains(t.id)).toList();
    if (newTxns.isNotEmpty) {
      ref.read(transactionsProvider.notifier).state =
          AsyncValue.data([...newTxns, ...currentTxns]);
    }

    final repo = ref.read(saleRepositoryProvider);
    final Result<Sale> result;
    if (stockDeductions.isNotEmpty) {
      result = await repo.createSaleWithTransactionsAndStock(
          sale, transactions, stockDeductions);
    } else {
      result = await repo.createSaleWithTransactions(sale, transactions);
    }
    if (result.isSuccess && result.data != null) {
      // Replace optimistic entry with server-confirmed data
      final current = state.value ?? [];
      state = AsyncValue.data([
        for (final s in current)
          if (s.id == sale.id) result.data! else s,
      ]);
      // Refresh inventory state if stock was deducted atomically
      if (stockDeductions.isNotEmpty) {
        ref.invalidate(inventoryProvider);
      }
      return true;
    }
    // Rollback on failure
    state = AsyncValue.data(previousSales);
    if (newTxns.isNotEmpty) {
      ref.read(transactionsProvider.notifier).state =
          AsyncValue.data(currentTxns);
    }
    return false;
  }

  /// Permanently deletes a sale, its linked transactions, and restores stock.
  ///
  /// **Important:** For Shopify-linked sales (`externalSource == 'shopify'`),
  /// callers should show a warning that deletion is local-only and the order
  /// must be cancelled separately on Shopify. Prefer [updateSale] with
  /// `orderStatus: OrderStatus.cancelled` + reversal entries instead.
  Future<void> removeSale(String id) async {
    final current = state.value ?? [];
    final sale = current.where((s) => s.id == id).firstOrNull;

    // 1. Restore stock for each sale item first.
    // If this fails, we stop before deleting transactions/sale to avoid data loss.
    if (sale != null) {
      final invNotifier = ref.read(inventoryProvider.notifier);
      final valMethod = ref.read(appSettingsProvider).valuationMethod;
      for (final item in sale.items) {
        if (item.productId != null && item.quantity > 0) {
          final stockResult = await invNotifier.adjustStock(
            item.productId!,
            item.variantId ?? '${item.productId}_v0',
            item.quantity.round(), // positive delta restores stock
            'Sale deleted – stock restored',
            valuationMethod: valMethod,
          );
          if (!stockResult.isSuccess) {
            developer.log(
              'Failed to restore stock while deleting sale $id: ${stockResult.error}',
              name: 'SalesNotifier',
            );
            return;
          }
        }
      }
    }

    // 2. Delete linked revenue & COGS transactions
    final txns = ref.read(transactionsProvider).value ?? [];
    final linked = txns.where((t) => t.saleId == id).toList();
    final transNotifier = ref.read(transactionsProvider.notifier);
    for (final tx in linked) {
      await transNotifier.removeTransaction(tx.id);
    }

    // 3. Delete the sale itself — optimistic
    state = AsyncValue.data(current.where((s) => s.id != id).toList());

    final repo = ref.read(saleRepositoryProvider);
    final result = await repo.deleteSale(id);
    if (!result.isSuccess) {
      // Rollback on failure
      state = AsyncValue.data(current);
    }
  }

  Future<void> updateSale(Sale sale) async {
    // Optimistic: update state immediately
    final previous = state.value ?? [];
    state = AsyncValue.data([
      for (final s in previous)
        if (s.id == sale.id) sale else s,
    ]);

    final repo = ref.read(saleRepositoryProvider);
    final result = await repo.updateSale(sale.id, sale);
    if (!result.isSuccess) {
      // Rollback on failure
      state = AsyncValue.data(previous);
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => build());
  }

  /// Resets to page 1 then loads ALL remaining pages in one call.
  Future<void> refreshAll() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => build());
    await loadAll();
  }
}

final salesProvider =
    AsyncNotifierProvider<SalesNotifier, List<Sale>>(() {
  return SalesNotifier();
});

// ═══════════════════════════════════════════════════════════
// SALE ↔ TRANSACTION LINK MIGRATION
// Fixes orphaned saleId links from the era when Firestore auto-generated
// doc IDs, replacing the client-side UUIDs that transactions referenced.
// Safe to run every app launch — only updates docs that actually need it.
// ═══════════════════════════════════════════════════════════

final saleTxnMigrationProvider = FutureProvider<void>((ref) async {
  // Ensure ALL pages are loaded before migrating, not just page 1.
  await ref.read(salesProvider.notifier).loadAll();
  await ref.read(transactionsProvider.notifier).loadAll();
  final sales = ref.read(salesProvider).value ?? [];
  final txns = ref.read(transactionsProvider).value ?? [];
  if (sales.isEmpty || txns.isEmpty) return;

  final saleIdSet = sales.map((s) => s.id).toSet();

  // Transactions whose saleId doesn't point to any known sale
  final orphaned = txns.where(
    (t) =>
        t.saleId != null &&
        !saleIdSet.contains(t.saleId) &&
        (t.categoryId == 'cat_sales_revenue' || t.categoryId == 'cat_cogs'),
  );

  for (final tx in orphaned) {
    Sale? match;
    if (tx.categoryId == 'cat_sales_revenue') {
      match = sales
          .where((s) =>
              s.total == tx.amount &&
              s.date.year == tx.dateTime.year &&
              s.date.month == tx.dateTime.month &&
              s.date.day == tx.dateTime.day)
          .firstOrNull;
    } else {
      match = sales
          .where((s) =>
              -s.totalCogs == tx.amount &&
              s.date.year == tx.dateTime.year &&
              s.date.month == tx.dateTime.month &&
              s.date.day == tx.dateTime.day)
          .firstOrNull;
    }
    if (match != null) {
      ref.read(transactionsProvider.notifier).updateTransaction(
            tx.copyWith(saleId: match.id),
          );
    }
  }
});

// ═══════════════════════════════════════════════════════════
// PRODUCT VARIANT MIGRATION
// Rewrites product docs that lack a `variants` array with the new
// variant-based structure.  Product.fromJson already auto-creates
// a Default variant on read; this provider persists that back to
// Firestore so subsequent reads don't hit the compat path.
// Safe to run every launch — only writes docs that still need it.
// ═══════════════════════════════════════════════════════════

final variantMigrationProvider = FutureProvider<void>((ref) async {
  final uid = ref.read(authProvider).user?.id;
  if (uid == null) return;

  final firestore = FirebaseFirestore.instance;
  final col = firestore.collection('products');
  final snap = await col.where('user_id', isEqualTo: uid).get();

  int migrated = 0;
  final batch = firestore.batch();

  for (final doc in snap.docs) {
    final data = doc.data();
    if (data.containsKey('variants')) continue; // already migrated

    // Parse through fromJson (auto-creates Default variant) then serialise back
    final json = {...data, 'id': doc.id};
    final product = Product.fromJson(json);
    final updatedJson = product.toJson();
    updatedJson.remove('id');
    updatedJson['updated_at'] = DateTime.now().toIso8601String();

    batch.update(doc.reference, updatedJson);
    migrated++;
  }

  if (migrated > 0) {
    await batch.commit();
    developer.log('[VariantMigration] Migrated $migrated products to variant schema');
    // Refresh inventory to pick up migrated data
    ref.invalidate(inventoryProvider);
  }
});

// ═══════════════════════════════════════════════════════════
// GOODS RECEIPTS  — Firestore-backed with optimistic updates
// ═══════════════════════════════════════════════════════════

class GoodsReceiptsNotifier extends Notifier<List<GoodsReceipt>> {
  @override
  List<GoodsReceipt> build() {
    _load();
    return [];
  }

  Future<void> _load() async {
    developer.log('[GoodsReceipts] _load() started');
    final repo = ref.read(goodsReceiptRepositoryProvider);
    final result = await repo.getReceipts();
    if (result.isSuccess && result.data != null) {
      developer.log('[GoodsReceipts] loaded ${result.data!.length} receipts');
      state = result.data!;
    } else {
      developer.log('[GoodsReceipts] _load FAILED: ${result.error}');
    }
  }

  Future<Result<GoodsReceipt>> addReceipt(GoodsReceipt receipt) async {
    state = [receipt, ...state];
    return _createReceipt(receipt);
  }

  Future<Result<GoodsReceipt>> _createReceipt(GoodsReceipt receipt) async {
    final repo = ref.read(goodsReceiptRepositoryProvider);
    final result = await repo.createReceipt(receipt);
    if (result.isSuccess && result.data != null) {
      state = [
        for (final r in state)
          if (r.id == receipt.id) result.data! else r,
      ];
      return result;
    } else if (!result.isSuccess) {
      state = state.where((r) => r.id != receipt.id).toList();
      return result;
    }
    return Result.failure('Failed to create receipt');
  }

  void removeReceipt(String id) {
    final old = state;
    state = state.where((r) => r.id != id).toList();
    _deleteReceipt(id, old);
  }

  Future<void> _deleteReceipt(String id, List<GoodsReceipt> rollback) async {
    final repo = ref.read(goodsReceiptRepositoryProvider);
    final result = await repo.deleteReceipt(id);
    if (!result.isSuccess) {
      state = rollback;
    }
  }

  void updateReceipt(GoodsReceipt receipt) {
    final old = state;
    state = [
      for (final r in state)
        if (r.id == receipt.id) receipt else r,
    ];
    _updateReceipt(receipt, old);
  }

  Future<void> _updateReceipt(
      GoodsReceipt receipt, List<GoodsReceipt> rollback) async {
    final repo = ref.read(goodsReceiptRepositoryProvider);
    final result = await repo.updateReceipt(receipt.id, receipt);
    if (!result.isSuccess) {
      state = rollback;
    }
  }

  Future<void> refresh() async {
    await _load();
  }
}

final goodsReceiptsProvider =
    NotifierProvider<GoodsReceiptsNotifier, List<GoodsReceipt>>(() {
  return GoodsReceiptsNotifier();
});

// ═══════════════════════════════════════════════════════════
// BALANCE SHEET ENTRIES  — Firestore-persisted manual entries
// ═══════════════════════════════════════════════════════════

class BalanceSheetEntriesNotifier extends Notifier<BalanceSheetEntries> {
  @override
  BalanceSheetEntries build() {
    _load();
    return const BalanceSheetEntries();
  }

  Future<void> _load() async {
    final repo = ref.read(balanceSheetRepositoryProvider);
    final result = await repo.getEntries();
    if (result.isSuccess && result.data != null) {
      state = result.data!;
    }
  }

  void update(BalanceSheetEntries entries) {
    state = entries;
    _save(entries);
  }

  Future<void> _save(BalanceSheetEntries entries) async {
    final repo = ref.read(balanceSheetRepositoryProvider);
    await repo.saveEntries(entries);
  }
}

final balanceSheetEntriesProvider =
    NotifierProvider<BalanceSheetEntriesNotifier, BalanceSheetEntries>(() {
  return BalanceSheetEntriesNotifier();
});
