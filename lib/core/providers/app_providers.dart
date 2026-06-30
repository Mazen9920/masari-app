import 'dart:async';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import '../utils/connectivity_helper.dart';
import '../../shared/utils/money_utils.dart';
import '../../shared/utils/fixed_asset_acquisition.dart';
import '../../shared/models/balance_sheet_entries.dart';
import '../../shared/models/conversion_order_model.dart';
import '../../shared/models/production_order_model.dart';
import '../../shared/models/fixed_asset_model.dart';
import '../../shared/models/loan_model.dart';
import '../../shared/models/salary_model.dart';
import '../../shared/models/gateway_receivable_model.dart';
import '../../shared/models/accrued_expense_model.dart';
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
  final int _limit = 50;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  Completer<void>? _loadAllCompleter;
  int _buildGeneration = 0;

  /// Active date bounds for server-side filtering.
  DateTime? _startDate;
  DateTime? _endDate;

  /// Last pagination error (cleared on successful load).
  Object? _paginationError;

  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
  Object? get paginationError => _paginationError;

  /// Clears the repo-level range cache so the next fetch hits Firestore.
  void _invalidateCaches() {
    ref.read(transactionRepositoryProvider).clearRangeCache();
  }

  @override
  Future<List<Transaction>> build() async {
    // Keep data alive across tab switches so returning is instant.
    ref.keepAlive();

    // Default to "This Month" so the first fetch is date-bounded.
    if (_startDate == null && _endDate == null) {
      final now = DateTime.now();
      _startDate = DateTime(now.year, now.month, 1);
      _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    }

    _lastDocId = null;
    _hasMore = false;
    _buildGeneration++;
    final repo = ref.read(transactionRepositoryProvider);

    // Always use a single range query — no pagination needed.
    final queryStart = _startDate ?? DateTime(2020);
    final now = DateTime.now();
    final queryEnd = _endDate ?? DateTime(now.year, now.month, now.day, 23, 59, 59);
    final result = await repo.getTransactionsInRange(
      start: queryStart,
      end: queryEnd,
    );
    if (result.isSuccess && result.data != null) {
      return result.data!;
    }
    throw Exception(result.error ?? 'Failed to load transactions');
  }

  /// Sets the active date bounds and re-fetches from server.
  /// Pass null for both to clear the bounds (fetch all).
  Future<void> setPeriod(DateTime? start, DateTime? end) async {
    // Same period and already fully loaded — instant return.
    if (_sameDay(_startDate, start) && _sameDay(_endDate, end) &&
        state.hasValue && !_hasMore) {
      return;
    }

    _startDate = start;
    _endDate = end;
    _loadAllCompleter = null;
    _buildGeneration++;
    final gen = _buildGeneration;

    // For unbounded "All" — use a wide date range so we get a single
    // Firestore query that returns everything (no pagination needed).
    final queryStart = start ?? DateTime(2020);
    final now = DateTime.now();
    final queryEnd = end ?? DateTime(now.year, now.month, now.day, 23, 59, 59);

    final repo = ref.read(transactionRepositoryProvider);
    try {
      final result = await repo.getTransactionsInRange(
        start: queryStart,
        end: queryEnd,
      );
      if (gen != _buildGeneration) return;
      if (result.isSuccess && result.data != null) {
        _hasMore = false;
        _lastDocId = null;
        state = AsyncData(result.data!);
        return;
      }
    } catch (_) {
      if (!state.hasValue) rethrow;
    }
  }

  static bool _sameDay(DateTime? a, DateTime? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    
    _isLoadingMore = true;
    _paginationError = null;
    final gen = _buildGeneration;

    const maxRetries = 2;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final repo = ref.read(transactionRepositoryProvider);
        final result = await repo.getTransactions(
          limit: _limit,
          startAfterId: _lastDocId,
          startDate: _startDate,
          endDate: _endDate,
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
          _paginationError = null;
          break; // Success — exit retry loop
        }
        // Non-success result — treat as error for retry
        if (attempt == maxRetries) {
          _paginationError = result.error ?? 'Failed to load more';
        }
      } catch (e) {
        if (gen != _buildGeneration) return;
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt + 1));
          continue;
        }
        _paginationError = e;
      }
    }
    _isLoadingMore = false;
  }

  /// Loads all remaining pages. Used by report screens that need complete data.
  /// Accumulates pages privately and emits a single state update at the end
  /// to avoid incremental UI rebuilds (e.g. revenue cards flickering).
  Future<void> loadAll() async {
    final existing = _loadAllCompleter;
    if (existing != null) return existing.future;
    final completer = Completer<void>();
    _loadAllCompleter = completer;
    final gen = _buildGeneration;
    try {
      final accumulated = <Transaction>[...state.value ?? []];
      final seenIds = accumulated.map((t) => t.id).toSet();
      final repo = ref.read(transactionRepositoryProvider);
      var consecutiveFailures = 0;
      while (_hasMore) {
        if (gen != _buildGeneration) break;
        try {
          final result = await repo.getTransactions(
            limit: _limit,
            startAfterId: _lastDocId,
            startDate: _startDate,
            endDate: _endDate,
          );
          if (gen != _buildGeneration) break;
          if (result.isSuccess && result.data != null) {
            consecutiveFailures = 0;
            final newItems = result.data!;
            _hasMore = newItems.length == _limit;
            if (newItems.isNotEmpty) _lastDocId = newItems.last.id;
            for (final item in newItems) {
              if (seenIds.add(item.id)) accumulated.add(item);
            }
          } else {
            consecutiveFailures++;
            if (consecutiveFailures > 2) break;
            await Future.delayed(Duration(seconds: consecutiveFailures));
          }
        } catch (_) {
          consecutiveFailures++;
          if (consecutiveFailures > 2) break;
          await Future.delayed(Duration(seconds: consecutiveFailures));
        }
      }
      if (gen == _buildGeneration) {
        // Merge any optimistic entries added while we were paginating.
        final optimistic = state.value ?? [];
        final accIds = accumulated.map((t) => t.id).toSet();
        for (final t in optimistic) {
          if (!accIds.contains(t.id)) accumulated.insert(0, t);
        }
        state = AsyncValue.data(accumulated);
      }
      completer.complete();
    } catch (e) {
      completer.completeError(e);
    } finally {
      if (_loadAllCompleter == completer) _loadAllCompleter = null;
    }
  }

  /// Whether [dateTime] falls within the active date bounds.
  bool _isWithinBounds(DateTime dateTime) {
    if (_startDate != null && dateTime.isBefore(_startDate!)) return false;
    if (_endDate != null && dateTime.isAfter(_endDate!)) return false;
    return true;
  }

  Future<void> addTransaction(Transaction transaction) async {
    _invalidateCaches();
    // Optimistic: only insert into state if it falls within the active
    // date window, otherwise it would appear and then vanish on next refresh.
    final inBounds = _isWithinBounds(transaction.dateTime);
    final previous = state.value ?? [];
    if (inBounds) {
      state = AsyncValue.data([transaction, ...previous]);
    }

    final repo = ref.read(transactionRepositoryProvider);
    final result = await repo.createTransaction(transaction);
    if (result.isSuccess && result.data != null) {
      if (inBounds) {
        // Replace optimistic entry with server-confirmed data
        final current = state.value ?? [];
        state = AsyncValue.data([
          for (final t in current)
            if (t.id == transaction.id) result.data! else t,
        ]);
      }
    } else if (!result.isSuccess) {
      if (inBounds) {
        // Rollback on failure
        final current = state.value ?? [];
        state = AsyncValue.data(
          current.where((t) => t.id != transaction.id).toList(),
        );
      }
    }
  }

  /// Batch-insert transactions into state (single rebuild).
  /// Only items within the active date bounds are added to the visible list.
  /// Does NOT write to the server — callers handle persistence separately.
  void insertTransactionsLocally(List<Transaction> transactions) {
    if (transactions.isEmpty) return;
    _invalidateCaches();
    final current = state.value ?? [];
    final existingIds = current.map((t) => t.id).toSet();
    final toAdd = transactions
        .where((t) => !existingIds.contains(t.id) && _isWithinBounds(t.dateTime))
        .toList();
    if (toAdd.isNotEmpty) {
      state = AsyncValue.data([...toAdd, ...current]);
    }
  }

  /// Batch-remove transactions from state by IDs (single rebuild).
  /// Does NOT delete from the server — callers handle persistence separately.
  void removeTransactionsLocally(List<String> ids) {
    if (ids.isEmpty) return;
    _invalidateCaches();
    final idSet = ids.toSet();
    final current = state.value ?? [];
    state = AsyncValue.data(
      current.where((t) => !idSet.contains(t.id)).toList(),
    );
  }

  Future<void> removeTransaction(String id) async {
    _invalidateCaches();
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
    _invalidateCaches();
    // Optimistic: update state immediately.
    // If the edited transaction's date is now outside the active window,
    // remove it from state instead of leaving a stale entry.
    final previous = state.value ?? [];
    final inBounds = _isWithinBounds(transaction.dateTime);
    if (inBounds) {
      state = AsyncValue.data([
        for (final t in previous)
          if (t.id == transaction.id) transaction else t,
      ]);
    } else {
      state = AsyncValue.data(
        previous.where((t) => t.id != transaction.id).toList(),
      );
    }

    final repo = ref.read(transactionRepositoryProvider);
    final result = await repo.updateTransaction(transaction);
    if (!result.isSuccess) {
      // Rollback on failure
      state = AsyncValue.data(previous);
    }
  }

  /// Refresh without flashing a loading spinner.
  /// Old data stays visible while the new fetch runs.
  Future<void> refresh() async {
    _lastDocId = null;
    _hasMore = false;
    _buildGeneration++;
    _loadAllCompleter = null;
    _invalidateCaches();
    final gen = _buildGeneration;
    final repo = ref.read(transactionRepositoryProvider);

    // Always use a single range query — no pagination needed.
    final queryStart = _startDate ?? DateTime(2020);
    final now = DateTime.now();
    final queryEnd = _endDate ?? DateTime(now.year, now.month, now.day, 23, 59, 59);
    try {
      final result = await repo.getTransactionsInRange(
        start: queryStart,
        end: queryEnd,
      );
      if (gen != _buildGeneration) return;
      if (result.isSuccess && result.data != null) {
        state = AsyncData(result.data!);
      }
    } catch (_) {
      // On error keep previous data visible.
      if (!state.hasValue) rethrow;
    }
  }

  /// Resets to page 1 then loads ALL remaining pages in one call.
  /// Use this instead of refresh() when a screen needs complete data.
  Future<void> refreshAll() async {
    await refresh();
    await loadAll();
  }

  /// Clears date bounds and loads the entire dataset.
  /// Used by report screens that need all-time data regardless of what
  /// period the transactions list screen may have set.
  Future<void> loadAllUnbounded() async {
    await setPeriod(null, null);
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
  /// IDs deleted during this session — survives provider rebuilds because
  /// the notifier instance is retained by Riverpod.
  final Set<String> _deletedIds = {};

  @override
  Future<List<CategoryData>> build() async {
    final repo = ref.read(categoryRepositoryProvider);
    final result = await repo.getCategories();
    if (result.isSuccess && result.data != null) {
      // Filter out any categories the user deleted this session
      final filtered = result.data!
          .where((c) => !_deletedIds.contains(c.id))
          .toList();
      CategoryData.customCategories = filtered;
      return filtered;
    }
    throw Exception(result.error ?? 'Failed to load categories');
  }

  Future<void> addCategory(CategoryData category) async {
    _deletedIds.remove(category.id); // un-delete if re-added
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
    _deletedIds.add(id);
    final current = state.value ?? [];
    final newList = current.where((c) => c.id != id).toList();
    CategoryData.customCategories = newList;
    state = AsyncValue.data(newList);

    final repo = ref.read(categoryRepositoryProvider);
    final result = await repo.deleteCategory(id);
    if (!result.isSuccess) {
      _deletedIds.remove(id);
      CategoryData.customCategories = current;
      state = AsyncValue.data(current);
      return;
    }

    // Only reassign transactions after successful delete
    final txRepo = ref.read(transactionRepositoryProvider);
    await txRepo.reassignCategory(id, 'cat_uncategorized');

    // Refresh loaded transactions to reflect the reassignment
    ref.read(transactionsProvider.notifier).refresh();
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
  /// Accumulates pages privately and emits a single state update at the end.
  /// Returns the full product list so callers can use it without touching `ref`
  /// after the await (important for dispose-safe async flows).
  Completer<void>? _loadAllCompleter;
  Future<List<Product>> loadAll() async {
    final existing = _loadAllCompleter;
    if (existing != null) {
      await existing.future;
      return state.value ?? const [];
    }
    final completer = Completer<void>();
    _loadAllCompleter = completer;
    final gen = _buildGeneration;
    try {
      final accumulated = <Product>[...state.value ?? []];
      final seenIds = accumulated.map((p) => p.id).toSet();
      final repo = ref.read(productRepositoryProvider);
      while (_hasMore) {
        if (gen != _buildGeneration) break;
        final result = await repo.getProducts(
          limit: _limit,
          startAfterId: _lastDocId,
        );
        if (gen != _buildGeneration) break;
        if (result.isSuccess && result.data != null) {
          final newItems = result.data!;
          _hasMore = newItems.length == _limit;
          if (newItems.isNotEmpty) _lastDocId = newItems.last.id;
          for (final item in newItems) {
            if (seenIds.add(item.id)) accumulated.add(item);
          }
        } else {
          break;
        }
      }
      if (gen == _buildGeneration) {
        state = AsyncValue.data(accumulated);
      }
      completer.complete();
    } catch (e) {
      completer.completeError(e);
    } finally {
      if (_loadAllCompleter == completer) _loadAllCompleter = null;
    }
    return state.value ?? const [];
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
      mappingRepo.deleteMappingsByRevvoProductId(id);
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

  Future<Result<Product>> adjustStock(String id, String variantId, double delta, String reason, {double? unitCost, String valuationMethod = 'fifo', String? supplierName, bool skipCostLayer = false, bool clearLegacyLayers = false}) async {
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
      newStock: variant.currentStock.round(),
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

/// Returns true if the product looks like a Shopify bundle.
bool isShopifyBundle(Product p) {
  final type = p.shopifyProductType?.toLowerCase() ?? '';
  if (type.contains('bundle')) return true;
  final tags = p.shopifyTags?.toLowerCase() ?? '';
  if (tags.contains('bundle')) return true;
  return false;
}

/// Derived provider that filters out hidden draft / bundle products
/// based on user settings. Use this for display, calculations, alerts,
/// and reports.  Use the raw [inventoryProvider] only for mutations
/// (add / update / delete / stock-adjust) and Shopify sync.
final filteredInventoryProvider = Provider<AsyncValue<List<Product>>>((ref) {
  final asyncProducts = ref.watch(inventoryProvider);
  final settings = ref.watch(appSettingsProvider);
  return asyncProducts.whenData((products) {
    return products.where((p) {
      if (settings.hideShopifyDrafts && p.shopifyStatus == 'draft') return false;
      if (settings.hideShopifyBundles && isShopifyBundle(p)) return false;
      return true;
    }).toList();
  });
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
    final existing = _loadAllCompleter;
    if (existing != null) return existing.future;
    final completer = Completer<void>();
    _loadAllCompleter = completer;
    try {
      while (_hasMore) {
        await loadMore();
      }
      completer.complete();
    } catch (e) {
      completer.completeError(e);
    } finally {
      if (_loadAllCompleter == completer) _loadAllCompleter = null;
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

  Future<Result<Supplier>> recordPayment(String id, double amount) async {
    final repo = ref.read(supplierRepositoryProvider);
    final result = await repo.recordPayment(id, amount);
    if (result.isSuccess && result.data != null) {
      final current = state.value ?? [];
      state = AsyncValue.data([
        for (final s in current)
          if (s.id == id) result.data! else s,
      ]);
    }
    return result;
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

  /// Persists a payment. Returns the [Result] so callers can surface failures
  /// (instead of silently dropping the record) and keep the supplier balance
  /// consistent. Optimistically adds, then reconciles with the repo outcome.
  Future<Result<Payment>> addPayment(Payment p) async {
    final current = state.value ?? [];
    state = AsyncValue.data([...current, p]);
    final repo = ref.read(paymentRepositoryProvider);
    final result = await repo.createPayment(p);
    if (result.isSuccess && result.data != null) {
      final cur = state.value ?? [];
      state = AsyncValue.data(
          [for (final x in cur) if (x.id == p.id) result.data! else x]);
    } else {
      // Roll back the optimistic insert on failure.
      final cur = state.value ?? [];
      state = AsyncValue.data(cur.where((x) => x.id != p.id).toList());
    }
    return result;
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

/// Accurate amount owed to a supplier, computed live from the source records
/// (not the drift-prone stored `supplier.balance`):
///   Σ(purchase.outstanding)  −  Σ(general/unapplied payments)
/// Payments applied to a purchase are already reflected in that purchase's
/// amountPaid, so only unapplied payments are subtracted (avoids double-count).
/// A negative result means the supplier holds a credit/advance for us.
/// Accrual-basis position for one supplier — mirrors the balance sheet's
/// supplier payable / prepayment math (received vs paid, per purchase).
typedef SupplierAccrual = ({
  double payable, // owed for goods received but unpaid
  double prepaid, // deposits paid ahead of receipt (asset)
  double onOrder, // billed but not yet received (commitment)
  double billed, // total of all bills
  double received, // value of goods received
  double paid, // cash paid
});

final supplierAccrualProvider =
    Provider.family<SupplierAccrual, String>((ref, supplierId) {
  final purchases = (ref.watch(purchasesProvider).value ?? const [])
      .where((p) => p.supplierId == supplierId);
  double payable = 0, prepaid = 0, onOrder = 0, billed = 0, received = 0, paid = 0;
  for (final p in purchases) {
    payable += p.accruedPayable;
    prepaid += p.supplierPrepayment;
    onOrder += p.notYetReceivedValue;
    billed += p.total;
    received += p.totalReceivedValue;
    paid += p.amountPaid;
  }
  return (
    payable: roundMoney(payable),
    prepaid: roundMoney(prepaid),
    onOrder: roundMoney(onOrder),
    billed: roundMoney(billed),
    received: roundMoney(received),
    paid: roundMoney(paid),
  );
});

final supplierAmountDueProvider = Provider.family<double, String>((ref, supplierId) {
  final purchases = ref.watch(purchasesProvider).value ?? const [];
  final payments = ref.watch(paymentsProvider).value ?? const [];
  final owed = purchases
      .where((p) => p.supplierId == supplierId)
      .fold<double>(0.0, (s, p) => s + p.outstanding);
  final credits = payments
      .where((p) =>
          p.supplierId == supplierId && p.appliedToPurchaseIds.isEmpty)
      .fold<double>(0.0, (s, p) => s + p.amount);
  return roundMoney(owed - credits);
});

// ═══════════════════════════════════════════════════════════
// SALES  — AsyncNotifier (Growth tier)
// ═══════════════════════════════════════════════════════════

class SalesNotifier extends AsyncNotifier<List<Sale>> {
  String? _lastDocId;
  final int _limit = 50;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  int _buildGeneration = 0;

  /// Real-time Firestore listener for the current date-bounded view.
  /// Automatically picks up Shopify webhook-created sales without manual refresh.
  StreamSubscription<List<Sale>>? _realtimeSub;

  /// Active date bounds for server-side filtering.
  DateTime? _startDate;
  DateTime? _endDate;

  /// In-memory cache of previously fetched period results.
  final Map<String, List<Sale>> _periodCache = {};

  static String _periodKey(DateTime? s, DateTime? e) =>
      '${s?.year}-${s?.month}-${s?.day}_${e?.year}-${e?.month}-${e?.day}';

  /// Last pagination error (cleared on successful load).
  Object? _paginationError;

  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
  Object? get paginationError => _paginationError;

  @override
  Future<List<Sale>> build() async {
    // Keep data alive across tab switches so returning is instant.
    ref.keepAlive();

    // Cancel any previous real-time listener before re-building.
    _cancelRealtimeListener();
    ref.onDispose(_cancelRealtimeListener);

    // Default to "This Month" so the first fetch is date-bounded and
    // subsequent setPeriod("This Month") calls return instantly.
    if (_startDate == null && _endDate == null) {
      final now = DateTime.now();
      _startDate = DateTime(now.year, now.month, 1);
      _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    }

    _lastDocId = null;
    _hasMore = false;
    _buildGeneration++;
    final repo = ref.read(saleRepositoryProvider);

    // Date-bounded: single range query returns everything — no pagination.
    if (_startDate != null && _endDate != null) {
      final result = await repo.getSalesInRange(
        start: _startDate!,
        end: _endDate!,
      );
      if (result.isSuccess && result.data != null) {
        _periodCache[_periodKey(_startDate, _endDate)] = result.data!;
        // Start real-time listener so Shopify webhook-created sales
        // (and any other server-side changes) appear instantly.
        _startRealtimeListener(_startDate!, _endDate!);
        return result.data!;
      }
      throw Exception(result.error ?? 'Failed to load sales');
    }

    // Unbounded: paginate.
    _hasMore = true;
    final result = await repo.getSales(limit: _limit);
    if (result.isSuccess && result.data != null) {
      final newItems = result.data!;
      _hasMore = newItems.length == _limit;
      if (newItems.isNotEmpty) _lastDocId = newItems.last.id;
      return newItems;
    }
    throw Exception(result.error ?? 'Failed to load sales');
  }

  /// Subscribes to real-time Firestore snapshots for the given date range.
  /// When [skipFirst] is true (default after initial fetch), skips the first
  /// event since we already have that data. When false (after refresh), the
  /// first server event is accepted immediately.
  void _startRealtimeListener(DateTime start, DateTime end, {bool skipFirst = true}) {
    _cancelRealtimeListener();
    final gen = _buildGeneration;
    final repo = ref.read(saleRepositoryProvider);
    bool shouldSkip = skipFirst;
    _realtimeSub = repo
        .watchSalesInRange(start: start, end: end)
        .listen((sales) {
      if (shouldSkip) {
        shouldSkip = false;
        return;
      }
      // Guard against stale listeners after setPeriod / refresh.
      if (gen != _buildGeneration) {
        _cancelRealtimeListener();
        return;
      }
      _periodCache[_periodKey(start, end)] = sales;
      state = AsyncData(sales);
    }, onError: (e) {
      // Don't overwrite valid data with an error — just log it.
      developer.log('Sales real-time listener error: $e',
          name: 'SalesNotifier');
    });
  }

  void _cancelRealtimeListener() {
    _realtimeSub?.cancel();
    _realtimeSub = null;
  }

  /// Sets the active date bounds and re-fetches from server.
  /// Pass null for both to clear the bounds (fetch all).
  Future<void> setPeriod(DateTime? start, DateTime? end) async {
    // Same period and already fully loaded — instant return.
    if (_sameDay(_startDate, start) && _sameDay(_endDate, end) &&
        state.hasValue && !_hasMore) {
      return;
    }

    _startDate = start;
    _endDate = end;
    _loadAllCompleter = null;
    _buildGeneration++;
    _cancelRealtimeListener();
    final gen = _buildGeneration;

    // Check in-memory cache — instant period switching.
    final key = _periodKey(start, end);
    final cached = _periodCache[key];
    if (cached != null) {
      _hasMore = false;
      _lastDocId = null;
      state = AsyncData(cached);
      // Re-attach listener for the cached period so new data still streams in.
      if (start != null && end != null) {
        _startRealtimeListener(start, end);
      }
      return;
    }

    final repo = ref.read(saleRepositoryProvider);

    // Date-bounded: single range query — all data in one call.
    if (start != null && end != null) {
      try {
        final result = await repo.getSalesInRange(
          start: start,
          end: end,
        );
        if (gen != _buildGeneration) return;
        if (result.isSuccess && result.data != null) {
          _hasMore = false;
          _lastDocId = null;
          _periodCache[key] = result.data!;
          state = AsyncData(result.data!);
          _startRealtimeListener(start, end);
          return;
        }
      } catch (_) {
        if (!state.hasValue) rethrow;
      }
      return;
    }

    // Unbounded: paginated refresh + load all.
    await refresh();
    await loadAll();
  }

  static bool _sameDay(DateTime? a, DateTime? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    _isLoadingMore = true;
    _paginationError = null;
    final gen = _buildGeneration;

    const maxRetries = 2;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final repo = ref.read(saleRepositoryProvider);
        final result = await repo.getSales(
          limit: _limit,
          startAfterId: _lastDocId,
          startDate: _startDate,
          endDate: _endDate,
        );

        if (gen != _buildGeneration) return;
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
          _paginationError = null;
          break;
        }
        if (attempt == maxRetries) {
          _paginationError = result.error ?? 'Failed to load more';
        }
      } catch (e) {
        if (gen != _buildGeneration) return;
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt + 1));
          continue;
        }
        _paginationError = e;
      }
    }
    _isLoadingMore = false;
  }

  /// Loads all remaining pages. Used by report screens that need complete data.
  /// Accumulates pages privately and emits a single state update at the end.
  Completer<void>? _loadAllCompleter;
  Future<void> loadAll() async {
    final existing = _loadAllCompleter;
    if (existing != null) return existing.future;
    final completer = Completer<void>();
    _loadAllCompleter = completer;
    final gen = _buildGeneration;
    try {
      final accumulated = <Sale>[...state.value ?? []];
      final seenIds = accumulated.map((s) => s.id).toSet();
      final repo = ref.read(saleRepositoryProvider);
      var consecutiveFailures = 0;
      while (_hasMore) {
        if (gen != _buildGeneration) break;
        try {
          final result = await repo.getSales(
            limit: _limit,
            startAfterId: _lastDocId,
            startDate: _startDate,
            endDate: _endDate,
          );
          if (gen != _buildGeneration) break;
          if (result.isSuccess && result.data != null) {
            consecutiveFailures = 0;
            final newItems = result.data!;
            _hasMore = newItems.length == _limit;
            if (newItems.isNotEmpty) _lastDocId = newItems.last.id;
            for (final item in newItems) {
              if (seenIds.add(item.id)) accumulated.add(item);
            }
          } else {
            consecutiveFailures++;
            if (consecutiveFailures > 2) break;
            await Future.delayed(Duration(seconds: consecutiveFailures));
          }
        } catch (_) {
          consecutiveFailures++;
          if (consecutiveFailures > 2) break;
          await Future.delayed(Duration(seconds: consecutiveFailures));
        }
      }
      if (gen == _buildGeneration) {
        state = AsyncValue.data(accumulated);
      }
      completer.complete();
    } catch (e) {
      completer.completeError(e);
    } finally {
      if (_loadAllCompleter == completer) _loadAllCompleter = null;
    }
  }

  Future<void> addSale(Sale sale) async {
    _periodCache.clear();
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
    _periodCache.clear();
    // Optimistic: update state immediately
    final previousSales = state.value ?? [];
    state = AsyncValue.data([sale, ...previousSales]);

    // Insert linked transactions via the notifier's batch method so
    // date-bounds are respected and only one state rebuild fires.
    final transNotifier = ref.read(transactionsProvider.notifier);
    transNotifier.insertTransactionsLocally(transactions);

    final repo = ref.read(saleRepositoryProvider);
    final Result<Sale> result;
    if (stockDeductions.isNotEmpty) {
      final online = await hasConnectivity();
      if (online) {
        // Prefer atomic transaction when online; fall back to batch on timeout.
        result = await repo
            .createSaleWithTransactionsAndStock(
                sale, transactions, stockDeductions)
            .timeout(
          const Duration(seconds: 15),
          onTimeout: () => repo.createSaleWithTransactionsAndStockBatch(
              sale, transactions, stockDeductions),
        );
      } else {
        result = await repo.createSaleWithTransactionsAndStockBatch(
            sale, transactions, stockDeductions);
      }
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
    transNotifier.removeTransactionsLocally(
      transactions.map((t) => t.id).toList(),
    );
    return false;
  }

  /// Permanently deletes a sale, its linked transactions, and restores stock.
  ///
  /// **Important:** For Shopify-linked sales (`externalSource == 'shopify'`),
  /// callers should show a warning that deletion is local-only and the order
  /// must be cancelled separately on Shopify. Prefer [updateSale] with
  /// `orderStatus: OrderStatus.cancelled` + reversal entries instead.
  Future<void> removeSale(String id) async {
    _periodCache.clear();
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
            item.quantity.toDouble(), // positive delta restores stock
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

    // 2. Delete linked revenue & COGS transactions in a single state update.
    final txns = ref.read(transactionsProvider).value ?? [];
    final linkedIds = txns.where((t) => t.saleId == id).map((t) => t.id).toList();
    final transNotifier = ref.read(transactionsProvider.notifier);
    // Remove from local state in one shot (no N sequential rebuilds).
    transNotifier.removeTransactionsLocally(linkedIds);
    // Fire-and-forget server deletes (individual docs).
    final txRepo = ref.read(transactionRepositoryProvider);
    for (final txId in linkedIds) {
      await txRepo.deleteTransaction(txId);
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
    _periodCache.clear();
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

  /// Refresh without flashing a loading spinner.
  /// Old data stays visible while the new fetch runs.
  Future<void> refresh() async {
    _lastDocId = null;
    _hasMore = false;
    _buildGeneration++;
    _loadAllCompleter = null;
    _cancelRealtimeListener();
    _periodCache.clear();
    final gen = _buildGeneration;
    final repo = ref.read(saleRepositoryProvider);
    final key = _periodKey(_startDate, _endDate);
    try {
      // Date-bounded: single range query.
      if (_startDate != null && _endDate != null) {
        final result = await repo.getSalesInRange(
          start: _startDate!,
          end: _endDate!,
          forceServer: true,
        );
        if (gen != _buildGeneration) return;
        if (result.isSuccess && result.data != null) {
          _periodCache[key] = result.data!;
          state = AsyncData(result.data!);
          _startRealtimeListener(_startDate!, _endDate!);
        }
        return;
      }
      // Unbounded: paginated first page.
      _hasMore = true;
      final result = await repo.getSales(
        limit: _limit,
        startDate: _startDate,
        endDate: _endDate,
      );
      if (gen != _buildGeneration) return;
      if (result.isSuccess && result.data != null) {
        final newItems = result.data!;
        _hasMore = newItems.length == _limit;
        if (newItems.isNotEmpty) _lastDocId = newItems.last.id;
        state = AsyncData(newItems);
      }
    } catch (_) {
      // On error keep previous data visible.
      if (!state.hasValue) rethrow;
    }
  }

  /// Resets to page 1 then loads ALL remaining pages in one call.
  Future<void> refreshAll() async {
    await refresh();
    await loadAll();
  }

  /// Clears date bounds and loads the entire dataset.
  /// Used by report screens that need all-time data.
  Future<void> loadAllUnbounded() async {
    if (_startDate != null || _endDate != null) {
      _startDate = null;
      _endDate = null;
      _loadAllCompleter = null;
      await refresh();
    }
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
  // Only run this migration once per device.
  const key = 'saleTxnMigrationDone';
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(key) == true) return;

  // Ensure ALL pages are loaded before migrating, not just page 1.
  await ref.read(salesProvider.notifier).loadAllUnbounded();
  await ref.read(transactionsProvider.notifier).loadAllUnbounded();
  final sales = ref.read(salesProvider).value ?? [];
  final txns = ref.read(transactionsProvider).value ?? [];
  if (sales.isEmpty || txns.isEmpty) {
    await prefs.setBool(key, true);
    return;
  }

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

  await prefs.setBool(key, true);
});

// ═══════════════════════════════════════════════════════════
// BALANCE SHEET PREFETCH
// Warms the repository range cache with all-history transactions &
// sales so the Balance Sheet screen opens instantly on first visit.
// Runs once per app launch, in the background, after dashboard has
// loaded its own data. No awaits — fire-and-forget.
// ═══════════════════════════════════════════════════════════

final balanceSheetPrefetchProvider = FutureProvider<void>((ref) async {
  final uid = ref.read(authProvider).user?.id;
  if (uid == null) return;

  // Use the same range the Balance Sheet screen uses (year 2000 → now).
  final now = DateTime.now();
  final asOf = DateTime(now.year, now.month, now.day, 23, 59, 59);
  final start = DateTime(2000);

  final txnRepo = ref.read(transactionRepositoryProvider);
  final saleRepo = ref.read(saleRepositoryProvider);

  // Fire both in parallel, ignore errors — it's just a cache warm-up.
  await Future.wait([
    txnRepo.getTransactionsInRange(start: start, end: asOf).catchError(
          (_) => Result<List<Transaction>>.failure('prefetch'),
        ),
    saleRepo.getSalesInRange(start: start, end: asOf).catchError(
          (_) => Result<List<Sale>>.failure('prefetch'),
        ),
  ]);
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

// ═══════════════════════════════════════════════════════════
// FIXED ASSETS  — Firestore-persisted fixed-asset records
// ═══════════════════════════════════════════════════════════

class FixedAssetsNotifier extends Notifier<List<FixedAsset>> {
  @override
  List<FixedAsset> build() {
    _load();
    return [];
  }

  Future<void> _load() async {
    final repo = ref.read(fixedAssetRepositoryProvider);
    final result = await repo.getAll();
    if (result.isSuccess && result.data != null) {
      state = result.data!;
    }
  }

  Future<void> refresh() async => _load();

  /// Adds an asset. When [postCashOutflow] is true and the asset has a positive
  /// purchase price, also posts a linked, P&L-excluded cash-outflow transaction
  /// so buying the asset is a clean cash→asset swap (cash ↓, fixed assets ↑).
  /// Pass false for a non-cash contribution (e.g. an owner-contributed asset).
  Future<bool> add(FixedAsset asset, {bool postCashOutflow = false}) async {
    final repo = ref.read(fixedAssetRepositoryProvider);

    String? txnId;
    var toCreate = asset;
    if (postCashOutflow && asset.purchasePrice > 0) {
      txnId = const Uuid().v4();
      final event = buildAssetAcquisitionEvent(
        eventId: DateTime.now().millisecondsSinceEpoch.toString(),
        txnId: txnId,
        purchasePrice: asset.purchasePrice,
        purchaseDate: asset.purchaseDate,
      );
      toCreate = asset.copyWith(events: [...asset.events, event]);
    }

    final result = await repo.create(toCreate);
    if (result.isSuccess && result.data != null) {
      state = [result.data!, ...state];
      if (txnId != null) {
        final txn = buildAssetAcquisitionTxn(
          txnId: txnId,
          userId: ref.read(authProvider).user?.id ?? '',
          assetName: asset.name,
          purchasePrice: asset.purchasePrice,
          purchaseDate: asset.purchaseDate,
        );
        await ref.read(transactionsProvider.notifier).addTransaction(txn);
      }
      return true;
    }
    return false;
  }

  Future<bool> updateAsset(FixedAsset asset) async {
    final repo = ref.read(fixedAssetRepositoryProvider);
    final result = await repo.update(asset);
    if (result.isSuccess && result.data != null) {
      state = [
        for (final a in state)
          if (a.id == asset.id) result.data! else a,
      ];
      return true;
    }
    return false;
  }

  Future<bool> remove(String id) async {
    final asset = state.firstWhere((a) => a.id == id, orElse: () => state.first);
    final repo = ref.read(fixedAssetRepositoryProvider);
    final result = await repo.delete(id);
    if (result.isSuccess) {
      // Clean up linked transactions
      final txnNotifier = ref.read(transactionsProvider.notifier);
      for (final evt in asset.events) {
        if (evt.transactionId != null) {
          await txnNotifier.removeTransaction(evt.transactionId!);
        }
      }
      state = state.where((a) => a.id != id).toList();
      return true;
    }
    return false;
  }
  Future<bool> sellAsset(
      String assetId, double salePrice, DateTime saleDate, String? note) async {
    final asset = state.firstWhere((a) => a.id == assetId);
    final txnId = const Uuid().v4();
    final event = AssetEvent(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: AssetEventType.sale,
      amount: salePrice,
      date: saleDate,
      note: note,
      transactionId: txnId,
    );
    final updated = asset.copyWith(
      status: FixedAssetStatus.sold,
      disposalDate: saleDate,
      disposalPrice: salePrice,
      events: [...asset.events, event],
    );
    final ok = await updateAsset(updated);
    if (ok) {
      final txn = Transaction(
        id: txnId,
        userId: ref.read(authProvider).user?.id ?? '',
        title: 'Asset Sale – ${asset.name}',
        amount: salePrice,
        dateTime: saleDate,
        categoryId: 'cat_asset_sale',
        note: note,
        excludeFromPL: true,
      );
      await ref.read(transactionsProvider.notifier).addTransaction(txn);
    }
    return ok;
  }

  /// Dispose / write off an asset (fully damaged, scrapped, etc.).
  Future<bool> disposeAsset(
      String assetId, DateTime disposalDate, String? note) async {
    final asset = state.firstWhere((a) => a.id == assetId);
    final nbv = asset.netBookValue;
    final txnId = const Uuid().v4();
    final event = AssetEvent(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: AssetEventType.disposal,
      amount: nbv,
      date: disposalDate,
      note: note,
      transactionId: nbv > 0 ? txnId : null,
    );
    final updated = asset.copyWith(
      status: FixedAssetStatus.disposed,
      disposalDate: disposalDate,
      disposalPrice: 0,
      events: [...asset.events, event],
    );
    final ok = await updateAsset(updated);
    if (ok && nbv > 0) {
      final txn = Transaction(
        id: txnId,
        userId: ref.read(authProvider).user?.id ?? '',
        title: 'Asset Disposal – ${asset.name}',
        amount: -nbv,
        dateTime: disposalDate,
        categoryId: 'cat_asset_disposal',
        note: note,
      );
      await ref.read(transactionsProvider.notifier).addTransaction(txn);
    }
    return ok;
  }

  /// Record impairment / partial damage on an asset.
  Future<bool> recordImpairment(
      String assetId, double lossAmount, DateTime date, String? note) async {
    final asset = state.firstWhere((a) => a.id == assetId);
    final txnId = const Uuid().v4();
    final event = AssetEvent(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: AssetEventType.partialDamage,
      amount: lossAmount,
      date: date,
      note: note,
      transactionId: txnId,
    );
    final updated = asset.copyWith(
      impairmentLoss: asset.impairmentLoss + lossAmount,
      status: FixedAssetStatus.impaired,
      events: [...asset.events, event],
    );
    final ok = await updateAsset(updated);
    if (ok) {
      final txn = Transaction(
        id: txnId,
        userId: ref.read(authProvider).user?.id ?? '',
        title: 'Impairment Loss – ${asset.name}',
        amount: -lossAmount,
        dateTime: date,
        categoryId: 'cat_impairment_loss',
        note: note,
      );
      await ref.read(transactionsProvider.notifier).addTransaction(txn);
    }
    return ok;
  }
}

final fixedAssetsProvider =
    NotifierProvider<FixedAssetsNotifier, List<FixedAsset>>(() {
  return FixedAssetsNotifier();
});

// ═══════════════════════════════════════════════════════════
// LOANS  — Firestore-persisted loan records
// ═══════════════════════════════════════════════════════════

class LoansNotifier extends Notifier<List<Loan>> {
  @override
  List<Loan> build() {
    _load();
    return [];
  }

  Future<void> _load() async {
    final repo = ref.read(loanRepositoryProvider);
    final result = await repo.getAll();
    if (result.isSuccess && result.data != null) {
      state = result.data!;
    }
  }

  Future<void> refresh() async => _load();

  Future<bool> add(Loan loan) async {
    final repo = ref.read(loanRepositoryProvider);
    final result = await repo.create(loan);
    if (result.isSuccess && result.data != null) {
      state = [result.data!, ...state];
      return true;
    }
    return false;
  }

  Future<bool> updateLoan(Loan loan) async {
    final repo = ref.read(loanRepositoryProvider);
    final result = await repo.update(loan);
    if (result.isSuccess && result.data != null) {
      state = [
        for (final l in state)
          if (l.id == loan.id) result.data! else l,
      ];
      return true;
    }
    return false;
  }

  Future<bool> remove(String id) async {
    final loan = state.firstWhere((l) => l.id == id, orElse: () => state.first);
    final repo = ref.read(loanRepositoryProvider);
    final result = await repo.delete(id);
    if (result.isSuccess) {
      // Clean up linked transactions
      final txnNotifier = ref.read(transactionsProvider.notifier);
      for (final p in loan.payments) {
        if (p.transactionId != null) {
          await txnNotifier.removeTransaction(p.transactionId!);
        }
      }
      for (final d in loan.disbursements) {
        if (d.transactionId != null) {
          await txnNotifier.removeTransaction(d.transactionId!);
        }
      }
      state = state.where((l) => l.id != id).toList();
      return true;
    }
    return false;
  }
  Future<bool> recordPayment(String loanId, LoanPayment payment) async {
    final loan = state.firstWhere((l) => l.id == loanId);
    final txnId = const Uuid().v4();
    final linkedPayment = payment.copyWith(transactionId: txnId);
    final updated = loan.copyWith(
      totalPaid: loan.totalPaid + payment.amount,
      payments: [...loan.payments, linkedPayment],
      status: (loan.totalPaid + payment.amount) >= loan.totalAmountDue
          ? LoanStatus.paidOff
          : loan.status,
    );
    final ok = await updateLoan(updated);
    if (ok) {
      final txn = Transaction(
        id: txnId,
        userId: ref.read(authProvider).user?.id ?? '',
        title: 'Loan Payment – ${loan.name}',
        amount: -payment.amount,
        dateTime: payment.date,
        categoryId: 'cat_loan_repayment',
        note: payment.note,
        excludeFromPL: true,
      );
      await ref.read(transactionsProvider.notifier).addTransaction(txn);
    }
    return ok;
  }

  /// Record a loan disbursement (money received from lender).
  Future<bool> recordDisbursement(
      String loanId, LoanDisbursement disbursement) async {
    final loan = state.firstWhere((l) => l.id == loanId);
    final txnId = const Uuid().v4();
    final linkedDisb = disbursement.copyWith(transactionId: txnId);
    final updated = loan.copyWith(
      totalDisbursed: loan.totalDisbursed + disbursement.amount,
      disbursements: [...loan.disbursements, linkedDisb],
    );
    final ok = await updateLoan(updated);
    if (ok) {
      final txn = Transaction(
        id: txnId,
        userId: ref.read(authProvider).user?.id ?? '',
        title: 'Loan Received – ${loan.name}',
        amount: disbursement.amount,
        dateTime: disbursement.date,
        categoryId: 'cat_loan_received',
        note: disbursement.note,
        excludeFromPL: true,
      );
      await ref.read(transactionsProvider.notifier).addTransaction(txn);
    }
    return ok;
  }
}

final loansProvider =
    NotifierProvider<LoansNotifier, List<Loan>>(() {
  return LoansNotifier();
});

// ─── Payment-gateway receivables ───────────────────────

class GatewayReceivablesNotifier extends Notifier<List<GatewayReceivable>> {
  @override
  List<GatewayReceivable> build() {
    _load();
    return [];
  }

  Future<void> _load() async {
    final repo = ref.read(gatewayReceivableRepositoryProvider);
    final result = await repo.getAll();
    if (result.isSuccess && result.data != null) {
      state = result.data!;
    }
  }

  Future<void> refresh() async => _load();

  Future<bool> add(GatewayReceivable receivable) async {
    final repo = ref.read(gatewayReceivableRepositoryProvider);
    final result = await repo.create(receivable);
    if (result.isSuccess && result.data != null) {
      state = [result.data!, ...state];
      return true;
    }
    return false;
  }

  Future<bool> updateReceivable(GatewayReceivable receivable) async {
    final repo = ref.read(gatewayReceivableRepositoryProvider);
    final result = await repo.update(receivable);
    if (result.isSuccess && result.data != null) {
      state = [
        for (final r in state)
          if (r.id == receivable.id) result.data! else r,
      ];
      return true;
    }
    return false;
  }

  Future<bool> remove(String id) async {
    final receivable =
        state.firstWhere((r) => r.id == id, orElse: () => state.first);
    final repo = ref.read(gatewayReceivableRepositoryProvider);
    final result = await repo.delete(id);
    if (result.isSuccess) {
      // Clean up linked settlement transactions.
      final txnNotifier = ref.read(transactionsProvider.notifier);
      for (final s in receivable.settlements) {
        if (s.transactionId != null) {
          await txnNotifier.removeTransaction(s.transactionId!);
        }
      }
      state = state.where((r) => r.id != id).toList();
      return true;
    }
    return false;
  }

  /// Record a settlement (gateway deposits to the bank): always reduces the
  /// receivable. When [postCash] is true it also posts a matching cash inflow
  /// (excluded from P&L — the revenue was already recognized at the sale; this
  /// is just the receivable → cash swap). Pass false to only reduce the
  /// receivable (e.g. if the cash is logged separately).
  Future<bool> recordSettlement(
      String receivableId, GatewaySettlement settlement,
      {bool postCash = true}) async {
    final receivable = state.firstWhere((r) => r.id == receivableId);
    final txnId = postCash ? const Uuid().v4() : null;
    final linked =
        txnId != null ? settlement.copyWith(transactionId: txnId) : settlement;
    final newBalance = (receivable.pendingBalance - settlement.amount)
        .clamp(0.0, double.maxFinite);
    final updated = receivable.copyWith(
      pendingBalance: newBalance,
      settlements: [...receivable.settlements, linked],
    );
    final ok = await updateReceivable(updated);
    if (ok && txnId != null) {
      final txn = Transaction(
        id: txnId,
        userId: ref.read(authProvider).user?.id ?? '',
        title: 'Gateway settlement – ${receivable.gatewayName}',
        amount: settlement.amount, // positive = cash in
        dateTime: settlement.date,
        categoryId: 'cat_gateway_settlement',
        note: settlement.note,
        excludeFromPL: true,
      );
      await ref.read(transactionsProvider.notifier).addTransaction(txn);
    }
    return ok;
  }
}

final gatewayReceivablesProvider =
    NotifierProvider<GatewayReceivablesNotifier, List<GatewayReceivable>>(() {
  return GatewayReceivablesNotifier();
});

// ─── Accrued expenses (liability) ──────────────────────

class AccruedExpensesNotifier extends Notifier<List<AccruedExpense>> {
  @override
  List<AccruedExpense> build() {
    _load();
    return [];
  }

  Future<void> _load() async {
    final repo = ref.read(accruedExpenseRepositoryProvider);
    final result = await repo.getAll();
    if (result.isSuccess && result.data != null) {
      state = result.data!;
    }
  }

  Future<void> refresh() async => _load();

  /// Adds an accrual. When [postExpense] is true (default) it also posts a P&L
  /// expense recognizing the cost now (Dr expense, Cr the new liability) so the
  /// balance sheet balances. Pass false if the expense was already booked
  /// elsewhere — then only the liability is created.
  Future<bool> add(AccruedExpense expense, {bool postExpense = true}) async {
    final repo = ref.read(accruedExpenseRepositoryProvider);

    String? expenseTxnId;
    var toCreate = expense;
    if (postExpense && expense.amount > 0) {
      expenseTxnId = const Uuid().v4();
      toCreate = expense.copyWith(expenseTransactionId: expenseTxnId);
    }

    final result = await repo.create(toCreate);
    if (result.isSuccess && result.data != null) {
      state = [result.data!, ...state];
      if (expenseTxnId != null) {
        final txn = Transaction(
          id: expenseTxnId,
          userId: ref.read(authProvider).user?.id ?? '',
          title: 'Accrued: ${expense.name}',
          amount: -expense.amount, // expense reduces profit
          dateTime: DateTime.now(),
          categoryId: 'cat_accrued_expense',
          note: expense.notes,
          // In the P&L, NOT a cash movement (cf_engine excludes cat_accrued_expense).
        );
        await ref.read(transactionsProvider.notifier).addTransaction(txn);
      }
      return true;
    }
    return false;
  }

  Future<bool> updateExpense(AccruedExpense expense) async {
    final repo = ref.read(accruedExpenseRepositoryProvider);
    final result = await repo.update(expense);
    if (result.isSuccess && result.data != null) {
      state = [
        for (final e in state)
          if (e.id == expense.id) result.data! else e,
      ];
      return true;
    }
    return false;
  }

  Future<bool> remove(String id) async {
    final expense =
        state.firstWhere((e) => e.id == id, orElse: () => state.first);
    final repo = ref.read(accruedExpenseRepositoryProvider);
    final result = await repo.delete(id);
    if (result.isSuccess) {
      final txnNotifier = ref.read(transactionsProvider.notifier);
      if (expense.expenseTransactionId != null) {
        await txnNotifier.removeTransaction(expense.expenseTransactionId!);
      }
      for (final p in expense.payments) {
        if (p.transactionId != null) {
          await txnNotifier.removeTransaction(p.transactionId!);
        }
      }
      state = state.where((e) => e.id != id).toList();
      return true;
    }
    return false;
  }

  /// Record a payment against the accrual: always reduces the outstanding
  /// amount. When [postCash] is true (default) it also posts a cash outflow
  /// (excluded from P&L — the cost was already expensed when accrued).
  Future<bool> recordPayment(
      String expenseId, AccruedExpensePayment payment,
      {bool postCash = true}) async {
    final expense = state.firstWhere((e) => e.id == expenseId);
    final txnId = postCash ? const Uuid().v4() : null;
    final linked =
        txnId != null ? payment.copyWith(transactionId: txnId) : payment;
    final newAmount =
        (expense.amount - payment.amount).clamp(0.0, double.maxFinite);
    final updated = expense.copyWith(
      amount: newAmount,
      status: newAmount <= 0.01
          ? AccruedExpenseStatus.settled
          : expense.status,
      payments: [...expense.payments, linked],
    );
    final ok = await updateExpense(updated);
    if (ok && txnId != null) {
      final txn = Transaction(
        id: txnId,
        userId: ref.read(authProvider).user?.id ?? '',
        title: 'Accrued payment – ${expense.name}',
        amount: -payment.amount, // cash out
        dateTime: payment.date,
        categoryId: 'cat_accrued_payment',
        note: payment.note,
        excludeFromPL: true,
      );
      await ref.read(transactionsProvider.notifier).addTransaction(txn);
    }
    return ok;
  }
}

final accruedExpensesProvider =
    NotifierProvider<AccruedExpensesNotifier, List<AccruedExpense>>(() {
  return AccruedExpensesNotifier();
});

// ═══════════════════════════════════════════════════════════

class SalariesNotifier extends Notifier<List<Salary>> {
  @override
  List<Salary> build() {
    _load();
    return [];
  }

  Future<void> _load() async {
    final repo = ref.read(salaryRepositoryProvider);
    final result = await repo.getAll();
    if (result.isSuccess && result.data != null) {
      state = result.data!;
    }
  }

  Future<void> refresh() async => _load();

  Future<bool> add(Salary salary) async {
    final repo = ref.read(salaryRepositoryProvider);
    final result = await repo.create(salary);
    if (result.isSuccess && result.data != null) {
      state = [result.data!, ...state];
      return true;
    }
    return false;
  }

  Future<bool> updateSalary(Salary salary) async {
    final repo = ref.read(salaryRepositoryProvider);
    final result = await repo.update(salary);
    if (result.isSuccess && result.data != null) {
      state = [
        for (final s in state)
          if (s.id == salary.id) result.data! else s,
      ];
      return true;
    }
    return false;
  }

  Future<bool> remove(String id) async {
    final salary = state.firstWhere((s) => s.id == id, orElse: () => state.first);
    final repo = ref.read(salaryRepositoryProvider);
    final result = await repo.delete(id);
    if (result.isSuccess) {
      // Clean up linked transactions
      final txnNotifier = ref.read(transactionsProvider.notifier);
      for (final p in salary.payments) {
        if (p.transactionId != null) {
          await txnNotifier.removeTransaction(p.transactionId!);
        }
      }
      for (final a in salary.accruals) {
        if (a.transactionId != null) {
          await txnNotifier.removeTransaction(a.transactionId!);
        }
      }
      state = state.where((s) => s.id != id).toList();
      return true;
    }
    return false;
  }

  /// Record a payment for an employee.
  Future<bool> recordPayment(String salaryId, SalaryPayment payment) async {
    final salary = state.firstWhere((s) => s.id == salaryId);
    final txnId = const Uuid().v4();
    final linkedPayment = payment.copyWith(transactionId: txnId);
    final updated = salary.copyWith(
      totalPaid: salary.totalPaid + payment.amount,
      payments: [...salary.payments, linkedPayment],
    );
    final ok = await updateSalary(updated);
    if (ok) {
      final txn = Transaction(
        id: txnId,
        userId: ref.read(authProvider).user?.id ?? '',
        title: 'Salary Payment – ${salary.employeeName}',
        amount: -payment.amount,
        dateTime: payment.date,
        categoryId: 'cat_salary_payment',
        note: payment.note,
        excludeFromPL: true,
      );
      await ref.read(transactionsProvider.notifier).addTransaction(txn);
    }
    return ok;
  }

  /// Record a salary accrual (salary payable entry).
  Future<bool> recordAccrual(
      String salaryId, SalaryAccrual accrual) async {
    final salary = state.firstWhere((s) => s.id == salaryId);
    final txnId = const Uuid().v4();
    final linkedAccrual = accrual.copyWith(transactionId: txnId);
    final updated = salary.copyWith(
      manualAccrued: salary.manualAccrued + accrual.amount,
      accruals: [...salary.accruals, linkedAccrual],
    );
    final ok = await updateSalary(updated);
    if (ok) {
      final txn = Transaction(
        id: txnId,
        userId: ref.read(authProvider).user?.id ?? '',
        title: 'Salary Expense – ${salary.employeeName}',
        amount: -accrual.amount,
        dateTime: accrual.date,
        categoryId: 'cat_salary_expense',
        note: accrual.note,
      );
      await ref.read(transactionsProvider.notifier).addTransaction(txn);
    }
    return ok;
  }
}

final salariesProvider =
    NotifierProvider<SalariesNotifier, List<Salary>>(() {
  return SalariesNotifier();
});

// ═══════════════════════════════════════════════════════════
// PRODUCTION ORDERS — BOM-driven manufacturing runs.
//
// Two-phase: START consumes raw materials into a WIP order; COMPLETE turns
// WIP into finished-goods stock. Materials + labor are CAPITALIZED into the
// finished good's cost layer (they hit P&L as COGS only at sale). The labor
// cash payment recorded at completion is `excludeFromPL: true` so it never
// double-counts against the eventual COGS (see project gotcha #3).
// ═══════════════════════════════════════════════════════════

class ProductionOrdersNotifier extends AsyncNotifier<List<ProductionOrder>> {
  @override
  Future<List<ProductionOrder>> build() async {
    ref.keepAlive();
    final repo = ref.read(productionOrderRepositoryProvider);
    final result = await repo.getOrders();
    if (result.isSuccess && result.data != null) return result.data!;
    throw Exception(result.error ?? 'Failed to load production orders');
  }

  /// In-progress orders represent work-in-progress; their [materialsCost] sum
  /// is the WIP inventory value.
  List<ProductionOrder> get inProgressOrders =>
      (state.value ?? []).where((o) => o.isInProgress).toList();

  double get workInProgressValue =>
      roundMoney(inProgressOrders.fold(0.0, (s, o) => s + o.wipValue));

  /// Pure planning calculation — no writes. Returns null if the product has no
  /// BOM or the finished variant can't be found.
  ProductionPlan? planProduction(
      String productId, String variantId, int quantity) {
    final products = ref.read(inventoryProvider).value ?? [];
    final product = products.where((p) => p.id == productId).firstOrNull;
    if (product == null || !product.hasBom) return null;
    final finishedVariant = product.variantById(variantId);
    if (finishedVariant == null) return null;
    final bom = product.manufacturingBom!;

    final valMethod = ref.read(appSettingsProvider).valuationMethod;
    final productsById = {for (final p in products) p.id: p};
    final lines = <ProductionPlanLine>[];
    double materialsCost = 0;
    for (final c in bom.components) {
      // Resolve effective material product+variant (honours per-colour map).
      final resolved =
          Product.resolveComponentMaterial(c, finishedVariant, productsById);
      final matProduct = productsById[resolved.productId];
      if (matProduct == null) {
        lines.add(ProductionPlanLine(
          materialProductId: c.materialProductId,
          materialVariantId: c.materialVariantId ?? '',
          materialName: 'Unknown material',
          supplierName: '',
          unit: c.unit,
          requiredQty: roundMoney(c.quantityPerUnit * quantity),
          availableQty: 0,
          shortfallQty: roundMoney(c.quantityPerUnit * quantity),
          unitCost: 0,
          lineCost: 0,
          unresolved: true,
        ));
        continue;
      }
      final matVar = resolved.variantId != null
          ? matProduct.variantById(resolved.variantId!)
          : null;

      var perUnit = c.quantityPerUnit;
      final scrap = matProduct.scrapPercentage ?? 0;
      if (c.applyScrap && scrap > 0) {
        perUnit = perUnit * (1 + scrap / 100);
      }
      final required = roundMoney(perUnit * quantity);
      final available = matVar?.currentStock ?? 0;
      final shortfall = required > available ? roundMoney(required - available) : 0.0;
      // FIFO-accurate: cost of the next [required] units actually consumed
      // (blends across cost layers), not the smoothed weighted-average.
      final unitCost =
          matVar?.cogsPerUnit(required.ceil(), valMethod) ?? 0;
      final lineCost = roundMoney(required * unitCost);
      materialsCost += lineCost;

      lines.add(ProductionPlanLine(
        materialProductId: matProduct.id,
        materialVariantId: matVar?.id ?? '',
        materialName: matVar != null && !matVar.isDefault
            ? '${matProduct.name} (${matVar.displayName})'
            : matProduct.name,
        supplierName: matProduct.supplier,
        unit: c.unit,
        requiredQty: required,
        availableQty: available,
        shortfallQty: shortfall,
        unitCost: unitCost,
        lineCost: lineCost,
        unresolved: matVar == null,
        madeToOrder: c.madeToOrder,
      ));
    }

    final laborCost = roundMoney(bom.laborCostPerUnit * quantity);
    final totalCost = roundMoney(materialsCost + laborCost);
    final unitCost = quantity > 0 ? roundMoney(totalCost / quantity) : 0.0;

    return ProductionPlan(
      productId: product.id,
      productName: product.name,
      variantId: finishedVariant.id,
      variantName:
          finishedVariant.isDefault ? product.name : finishedVariant.displayName,
      quantity: quantity,
      lines: lines,
      materialsCost: roundMoney(materialsCost),
      laborCost: laborCost,
      laborSupplierId: bom.laborSupplierId,
      laborSupplierName: bom.laborSupplierName,
      totalCost: totalCost,
      unitCost: unitCost,
    );
  }

  /// Starts a production run: consumes raw materials atomically and creates an
  /// in-progress (WIP) order. Returns null on success, or an error message.
  Future<String?> startProduction({
    required String productId,
    required String variantId,
    required int quantity,
    String? notes,
  }) async {
    if (quantity <= 0) return 'Quantity must be greater than 0';
    final plan = planProduction(productId, variantId, quantity);
    if (plan == null) return 'No bill of materials for this product';
    if (plan.hasUnresolved) {
      return 'Some materials could not be resolved — check the BOM';
    }
    if (plan.hasShortfall) {
      return 'Not enough raw materials in stock for this run';
    }

    final valMethod = ref.read(appSettingsProvider).valuationMethod;
    // Only stocked materials are consumed from inventory. Made-to-order
    // components (produced with the run) are NOT pulled from stock — their
    // cost is added separately below.
    final materials = <({String productId, String variantId, String name, double quantity})>[];
    for (final l in plan.lines) {
      if (l.madeToOrder) continue;
      if (l.requiredQty <= 0) continue;
      materials.add((
        productId: l.materialProductId,
        variantId: l.materialVariantId,
        name: l.materialName,
        quantity: l.requiredQty,
      ));
    }

    final repo = ref.read(productionOrderRepositoryProvider);
    final consumeResult =
        await ref.read(productRepositoryProvider).consumeMaterialsForProduction(
              materials: materials,
              valuationMethod: valMethod,
            );
    if (!consumeResult.isSuccess || consumeResult.data == null) {
      return consumeResult.error ?? 'Failed to consume materials';
    }

    final inputs = consumeResult.data!
        .map((c) => ProductionInputLine(
              materialProductId: c.productId,
              materialVariantId: c.variantId,
              materialName: c.name,
              quantity: c.quantity.toDouble(),
              unitCost: c.unitCost,
              totalCost: c.totalCost,
            ))
        .toList();

    // Add made-to-order components as input lines (cost capitalized, no stock
    // movement) so the finished unit cost still includes them.
    for (final l in plan.lines) {
      if (!l.madeToOrder || l.requiredQty <= 0) continue;
      inputs.add(ProductionInputLine(
        materialProductId: l.materialProductId,
        materialVariantId: l.materialVariantId,
        materialName: l.materialName,
        quantity: l.requiredQty,
        unitCost: l.unitCost,
        totalCost: l.lineCost,
        madeToOrder: true,
      ));
    }

    // Materials drawn from stock drive WIP; made-to-order materials are billed
    // by the supplier at completion (with labor), so keep them separate.
    final materialsCost = roundMoney(inputs
        .where((i) => !i.madeToOrder)
        .fold(0.0, (s, i) => s + i.totalCost));
    final madeToOrderCost = roundMoney(inputs
        .where((i) => i.madeToOrder)
        .fold(0.0, (s, i) => s + i.totalCost));
    final laborCost = plan.laborCost;
    final totalCost = roundMoney(materialsCost + madeToOrderCost + laborCost);
    final unitCost = quantity > 0 ? roundMoney(totalCost / quantity) : 0.0;

    final order = ProductionOrder(
      id: const Uuid().v4(),
      userId: ref.read(authProvider).user?.id ?? '',
      productId: plan.productId,
      productName: plan.productName,
      variantId: plan.variantId,
      variantName: plan.variantName,
      quantity: quantity,
      status: ProductionStatus.inProgress,
      inputs: inputs,
      materialsCost: materialsCost,
      madeToOrderCost: madeToOrderCost,
      laborCost: laborCost,
      totalCost: totalCost,
      unitCost: unitCost,
      laborSupplierId: plan.laborSupplierId,
      startedAt: DateTime.now(),
      notes: notes,
    );

    // Optimistic state update.
    state = AsyncValue.data([order, ...(state.value ?? [])]);
    final createResult = await repo.createOrder(order);
    if (!createResult.isSuccess) {
      // Roll back local state; materials were consumed but order failed to
      // persist — surface the error so the user can retry/inspect.
      state = AsyncValue.data(
          (state.value ?? []).where((o) => o.id != order.id).toList());
      return createResult.error ?? 'Failed to save production order';
    }

    // Refresh inventory so consumed material stock is reflected in the UI.
    await ref.read(inventoryProvider.notifier).refresh();
    return null;
  }

  /// Receives part (or all) of an in-progress run: adds [qty] finished units to
  /// stock at the captured unit cost and records the labor cost for that batch.
  /// The order stays in-progress until all units are received, then flips to
  /// completed. [qty] defaults to all remaining units.
  ///
  /// [payNow] true → record an immediate cash outflow (`excludeFromPL: true`).
  /// false → add the labor cost to the finishing supplier's payable (settled
  /// later via the normal supplier-payment flow).
  Future<String?> completeProduction(String orderId,
      {bool payNow = true, int? qty}) async {
    final orders = state.value ?? [];
    final order = orders.where((o) => o.id == orderId).firstOrNull;
    if (order == null) return 'Production order not found';
    if (!order.isInProgress) return 'Order is not in progress';

    final remaining = order.remainingQty;
    if (remaining <= 0) return 'Nothing left to receive';
    final batchQty = (qty ?? remaining).clamp(1, remaining);

    // 1. Add the received finished goods at the capitalized unit cost.
    final output = await ref.read(productRepositoryProvider).addProductionOutput(
          productId: order.productId,
          variantId: order.variantId,
          qty: batchQty.toDouble(),
          unitCost: order.unitCost,
        );
    if (!output.isSuccess) {
      return output.error ?? 'Failed to add finished goods';
    }

    final uid = ref.read(authProvider).user?.id ?? '';
    final now = DateTime.now();
    final suppliers = ref.read(suppliersProvider).value ?? const [];
    final laborSup = order.laborSupplierId != null
        ? suppliers.where((s) => s.id == order.laborSupplierId).firstOrNull
        : null;
    final supName = laborSup?.name ?? 'Production';

    // 2. Record this received batch as a production goods receipt (a record
    //    only — stock was already added in step 1, so this does NOT re-adjust
    //    inventory). Lets production show in the Received Goods section.
    final receipt = GoodsReceipt(
      id: 'prodrcpt_${order.id}_${now.millisecondsSinceEpoch}',
      userId: uid,
      supplierId: order.laborSupplierId ?? '',
      supplierName: supName,
      date: now,
      items: [
        ReceiptItem(
          productId: order.productId,
          variantId: order.variantId,
          productName: '${order.productName} – ${order.variantName}',
          orderedQty: order.quantity.toDouble(),
          receivedQty: batchQty.toDouble(),
          unitCost: order.unitCost,
          notes: 'Production',
        ),
      ],
      status: ReceiptStatus.confirmed,
      notes: 'Production run',
    );
    await ref.read(goodsReceiptsProvider.notifier).addReceipt(receipt);

    // 3. Invoice the finishing supplier for THIS batch (proportional,
    //    capitalized — not P&L). The manufacturing invoice = finishing labor
    //    PLUS any made-to-order components the supplier produces (e.g. the
    //    mini bag made with the straps).
    final laborPerUnit =
        order.quantity > 0 ? order.laborCost / order.quantity : 0.0;
    final mtoPerUnit =
        order.quantity > 0 ? order.madeToOrderCost / order.quantity : 0.0;
    final batchCharge = roundMoney((laborPerUnit + mtoPerUnit) * batchQty);
    String? laborTxnId = order.laborTransactionId;
    if (batchCharge > 0) {
      if (payNow || order.laborSupplierId == null) {
        laborTxnId = const Uuid().v4();
        final txn = Transaction(
          id: laborTxnId,
          userId: uid,
          title: 'Manufacturing – ${order.productName}',
          amount: -batchCharge,
          dateTime: now,
          categoryId: 'cat_manufacturing_cost',
          note: 'Finishing + made-to-order for $batchQty × ${order.variantName}',
          supplierId: order.laborSupplierId,
          // Capitalized into finished-goods cost → excluded from P&L; flows to
          // COGS when the finished good is sold.
          excludeFromPL: true,
        );
        await ref.read(transactionsProvider.notifier).addTransaction(txn);
      } else {
        // Create a real supplier bill (linked to this order via referenceNo)
        // AND bump the payable — so it shows as a settleable line item.
        final items = <PurchaseItem>[
          if (laborPerUnit > 0)
            PurchaseItem(
              name: 'Finishing – ${order.productName}',
              category: 'Manufacturing',
              qty: batchQty,
              unitPrice: roundMoney(laborPerUnit),
            ),
          if (mtoPerUnit > 0)
            PurchaseItem(
              name: 'Made-to-order – ${order.productName}',
              category: 'Manufacturing',
              qty: batchQty,
              unitPrice: roundMoney(mtoPerUnit),
            ),
        ];
        final bill = Purchase(
          id: 'prodbill_${order.id}_${now.millisecondsSinceEpoch}',
          userId: uid,
          supplierId: order.laborSupplierId!,
          supplierName: supName,
          date: now,
          referenceNo: order.id,
          items: items,
          createdAt: now,
        );
        ref.read(purchasesProvider.notifier).addPurchase(bill);
        await ref
            .read(suppliersProvider.notifier)
            .recordPurchase(order.laborSupplierId!, bill.subtotal);
      }
    }

    // 3. Advance completedQty; mark completed only when fully received.
    final newCompleted = order.completedQty + batchQty;
    final done = newCompleted >= order.quantity;
    final updated = order.copyWith(
      completedQty: newCompleted,
      status: done ? ProductionStatus.completed : ProductionStatus.inProgress,
      completedAt: done ? DateTime.now() : order.completedAt,
      laborTransactionId: laborTxnId,
    );
    state = AsyncValue.data(
        orders.map((o) => o.id == orderId ? updated : o).toList());
    final repo = ref.read(productionOrderRepositoryProvider);
    final res = await repo.updateOrder(updated);
    if (!res.isSuccess) {
      state = AsyncValue.data(orders);
      return res.error ?? 'Failed to update production order';
    }

    await ref.read(inventoryProvider.notifier).refresh();
    return null;
  }

  /// Cancels an in-progress run: restocks the consumed raw materials at their
  /// consumed cost and marks the order cancelled.
  Future<String?> cancelProduction(String orderId) async {
    final orders = state.value ?? [];
    final order = orders.where((o) => o.id == orderId).firstOrNull;
    if (order == null) return 'Production order not found';
    if (!order.isInProgress) return 'Only in-progress orders can be cancelled';
    if (order.completedQty > 0) {
      return 'Cannot cancel — some units have already been received';
    }

    final inventory = ref.read(inventoryProvider.notifier);
    for (final input in order.inputs) {
      // Made-to-order inputs were never drawn from stock — don't restock them.
      if (input.madeToOrder) continue;
      if (input.quantity <= 0) continue;
      await inventory.adjustStock(
        input.materialProductId,
        input.materialVariantId,
        input.quantity,
        'Production cancelled',
        unitCost: input.unitCost,
      );
    }

    final updated = order.copyWith(
      status: ProductionStatus.cancelled,
      completedAt: DateTime.now(),
    );
    state = AsyncValue.data(
        orders.map((o) => o.id == orderId ? updated : o).toList());
    final repo = ref.read(productionOrderRepositoryProvider);
    final res = await repo.updateOrder(updated);
    if (!res.isSuccess) {
      state = AsyncValue.data(orders);
      return res.error ?? 'Failed to cancel production order';
    }
    return null;
  }

  /// Permanently deletes a CANCELLED production order. Cancelled orders have
  /// already restocked their materials and produced no finished goods, so the
  /// record can be removed with no accounting impact.
  Future<String?> deleteOrder(String orderId) async {
    final orders = state.value ?? [];
    final order = orders.where((o) => o.id == orderId).firstOrNull;
    if (order == null) return 'Production order not found';
    if (!order.isCancelled) {
      return 'Only cancelled orders can be deleted';
    }
    state = AsyncValue.data(orders.where((o) => o.id != orderId).toList());
    final repo = ref.read(productionOrderRepositoryProvider);
    final res = await repo.deleteOrder(orderId);
    if (!res.isSuccess) {
      state = AsyncValue.data(orders); // rollback
      return res.error ?? 'Failed to delete production order';
    }
    return null;
  }

  /// Edits non-financial fields of a production order (notes and the finishing
  /// supplier). Cost, quantity and consumed materials are locked at START.
  Future<String?> editOrder(
    String orderId, {
    String? notes,
    String? laborSupplierId,
  }) async {
    final orders = state.value ?? [];
    final order = orders.where((o) => o.id == orderId).firstOrNull;
    if (order == null) return 'Production order not found';
    final updated = order.copyWith(
      notes: notes ?? order.notes,
      laborSupplierId: laborSupplierId ?? order.laborSupplierId,
    );
    state = AsyncValue.data(
        orders.map((o) => o.id == orderId ? updated : o).toList());
    final repo = ref.read(productionOrderRepositoryProvider);
    final res = await repo.updateOrder(updated);
    if (!res.isSuccess) {
      state = AsyncValue.data(orders);
      return res.error ?? 'Failed to update production order';
    }
    return null;
  }

  Future<void> refresh() async {
    final repo = ref.read(productionOrderRepositoryProvider);
    final result = await repo.getOrders();
    if (result.isSuccess && result.data != null) {
      state = AsyncValue.data(result.data!);
    }
  }
}

final productionOrdersProvider =
    AsyncNotifierProvider<ProductionOrdersNotifier, List<ProductionOrder>>(() {
  return ProductionOrdersNotifier();
});

/// Fetches production orders for a specific product.
final productionOrdersForProductProvider =
    FutureProvider.family<List<ProductionOrder>, String>((ref, productId) async {
  final repo = ref.read(productionOrderRepositoryProvider);
  final result = await repo.getOrdersForProduct(productId);
  return result.data ?? [];
});
