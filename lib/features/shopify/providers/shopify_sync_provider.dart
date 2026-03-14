import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/shopify_sync_service.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/models/sale_model.dart';
import '../providers/shopify_connection_provider.dart';
import '../providers/shopify_sync_log_provider.dart';

// ── Sync status model ──────────────────────────────────────

enum SyncPhase { idle, syncing, success, error }

/// Immutable snapshot of the current sync operation state.
class SyncStatus {
  final SyncPhase phase;
  final String? message;
  final double progress; // 0.0 – 1.0
  final String? errorDetail;

  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.message,
    this.progress = 0,
    this.errorDetail,
  });

  bool get isSyncing => phase == SyncPhase.syncing;
  bool get isIdle => phase == SyncPhase.idle;
  bool get hasError => phase == SyncPhase.error;

  SyncStatus copyWith({
    SyncPhase? phase,
    String? message,
    double? progress,
    String? errorDetail,
  }) {
    return SyncStatus(
      phase: phase ?? this.phase,
      message: message ?? this.message,
      progress: progress ?? this.progress,
      errorDetail: errorDetail,
    );
  }
}

// ── Notifier ───────────────────────────────────────────────

/// Manages Shopify sync operations and exposes real-time
/// progress/status to the UI.
class ShopifySyncNotifier extends Notifier<SyncStatus> {
  Timer? _alwaysSyncTimer;
  bool _isSyncing = false;

  @override
  SyncStatus build() => const SyncStatus();

  ShopifySyncService get _syncService =>
      ref.read(shopifySyncServiceProvider);

  // ── 30-second background timer ───────────────────────────

  /// Starts a 30-second periodic timer that runs [performAutoSync].
  /// Safe to call multiple times — only one timer is active at a time.
  void startAlwaysSyncTimer() {
    if (_alwaysSyncTimer != null && _alwaysSyncTimer!.isActive) return;

    // Check if always-on mode is actually enabled
    final conn = ref.read(shopifyConnectionProvider).value;
    if (conn == null || !conn.isActive) return;
    if (conn.syncInventoryEnabled != true) return;
    if (conn.inventorySyncMode != 'always') return;

    developer.log( 'Starting always-on sync timer (30s)', name: 'ShopifySyncNotifier');
    _alwaysSyncTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _timerTick(),
    );
  }

  /// Stops the background sync timer.
  void stopAlwaysSyncTimer() {
    if (_alwaysSyncTimer != null) {
      developer.log( 'Stopping always-on sync timer', name: 'ShopifySyncNotifier');
      _alwaysSyncTimer!.cancel();
      _alwaysSyncTimer = null;
    }
  }

  /// Restarts the timer (e.g. when settings change).
  void restartAlwaysSyncTimer() {
    stopAlwaysSyncTimer();
    startAlwaysSyncTimer();
  }

  void _timerTick() {
    if (_isSyncing) {
      developer.log( 'Skipping timer tick — sync already in progress', name: 'ShopifySyncNotifier');
      return;
    }
    // Run silently — don't update state/UI for background reconciliation
    _runBackgroundReconciliation();
  }

  /// Silent background reconciliation — pulls then pushes without
  /// updating the UI state (no banners / spinners).
  /// Respects the configured inventory sync direction.
  Future<void> _runBackgroundReconciliation() async {
    if (_isSyncing) return;
    final conn = ref.read(shopifyConnectionProvider).value;
    if (conn == null || !conn.isActive) return;
    _isSyncing = true;
    try {
      final direction = conn.inventorySyncDirection ?? 'shopify_to_masari';

      // Always pull first so newly-imported products get correct stock
      // before any push compares against them.
      await _syncService.pullInventoryFromShopify();

      // Only push if direction allows masari → shopify
      if (direction == 'masari_to_shopify' || direction == 'both') {
        final pushPreview = await _syncService.previewPushInventory();
        if (pushPreview.isSuccess && pushPreview.data != null) {
          final changed = pushPreview.data!
              .where((i) => i.masariStock != i.shopifyStock)
              .toList();
          if (changed.isNotEmpty) {
            await _syncService.pushInventoryBatch(changed);
          }
        }
      }

      // Also pull product details (titles, variants, options, new products)
      final detailsResult =
          await _syncService.pullProductDetailsFromShopify();
      // Refresh the in-memory inventory state if anything changed
      final detailsChanged = detailsResult.isSuccess &&
          (detailsResult.data ?? 0) > 0;
      if (detailsChanged) {
        ref.read(inventoryProvider.notifier).refresh();
      }
    } catch (e) {
      developer.log( 'Background sync error: $e', name: 'ShopifySyncNotifier');
    } finally {
      _isSyncing = false;
    }
  }

  // ── Inventory preview cache ──────────────────────────────

  List<InventoryPreviewItem>? _pullPreview;
  List<InventoryPreviewItem>? _pushPreview;

  /// Cached pull preview items (from last [previewPull] call).
  List<InventoryPreviewItem>? get pullPreview => _pullPreview;

  /// Cached push preview items (from last [previewPush] call).
  List<InventoryPreviewItem>? get pushPreview => _pushPreview;

  // ── Push a single order to Shopify ───────────────────────

  /// Pushes local Sale changes (notes, fulfillment, tracking)
  /// back to the linked Shopify order.
  Future<void> syncOrder(Sale sale) async {
    state = const SyncStatus(
      phase: SyncPhase.syncing,
      message:  'Pushing order to Shopify…',
      progress: 0.2,
    );

    final result = await _syncService.syncOrderToShopify(sale);

    if (result.isSuccess) {
      final data = result.data!;
      state = SyncStatus(
        phase: SyncPhase.success,
        message:
             'Synced ${data.changedFields.length} field(s) to Shopify',
        progress: 1,
      );
    } else {
      state = SyncStatus(
        phase: SyncPhase.error,
        message:  'Order sync failed',
        errorDetail: result.error,
      );
      _checkTokenRevoked(result.error);
    }

    _autoClearAfterDelay();
  }

  // ── Auto-sync (always-on mode) ─────────────────────────

  /// Bi-directional auto-sync for "always on" mode.
  ///
  /// **Pull first, then push** — this ensures newly-imported products
  /// get correct stock from Shopify before a push compares against them.
  /// Respects the configured sync direction.
  /// Called on pull-to-refresh and by the 30-second background timer.
  Future<void> performAutoSync() async {
    if (_isSyncing) return; // guard against concurrent runs
    final conn = ref.read(shopifyConnectionProvider).value;
    if (conn == null || !conn.isActive) return;
    _isSyncing = true;
    try {
      final direction = conn.inventorySyncDirection ?? 'shopify_to_masari';

    state = const SyncStatus(
      phase: SyncPhase.syncing,
      message:  'Pulling Shopify changes…',
      progress: 0.1,
    );

    // 1) Pull Shopify → Masari (always — gets latest stock)
    final pullResult = await _syncService.pullInventoryFromShopify();

    // 2) Push Masari → Shopify (only if direction allows)
    int pushed = 0;
    if (direction == 'masari_to_shopify' || direction == 'both') {
      state = const SyncStatus(
        phase: SyncPhase.syncing,
        message:  'Pushing local changes to Shopify…',
        progress: 0.5,
      );

      final pushPreviewResult = await _syncService.previewPushInventory();
      if (pushPreviewResult.isSuccess &&
          pushPreviewResult.data != null &&
          pushPreviewResult.data!.isNotEmpty) {
        final changed = pushPreviewResult.data!
            .where((i) => i.masariStock != i.shopifyStock)
            .toList();
        if (changed.isNotEmpty) {
          final pushResult = await _syncService.pushInventoryBatch(changed);
          if (pushResult.isSuccess) pushed = pushResult.data ?? 0;
        }
      }
    }

    state = const SyncStatus(
      phase: SyncPhase.syncing,
      message:  'Syncing product details…',
      progress: 0.8,
    );

    // 3) Pull product details (titles, variants, options, new products)
    final detailsResult =
        await _syncService.pullProductDetailsFromShopify();

    if (!pullResult.isSuccess) {
      state = SyncStatus(
        phase: SyncPhase.error,
        message:  'Sync failed',
        errorDetail: pullResult.error,
      );
      _checkTokenRevoked(pullResult.error);
      _autoClearAfterDelay();
      return;
    }

    final pulled = pullResult.data ?? 0;
    final detailCount = detailsResult.data ?? 0;
    final detailMsg = detailCount > 0 ? ', $detailCount product(s) updated' : '';
    state = SyncStatus(
      phase: SyncPhase.success,
      message:  'Synced — pushed $pushed, pulled $pulled$detailMsg',
      progress: 1,
    );
    _autoClearAfterDelay();
    } finally {
      _isSyncing = false;
    }
  }

  // ── Inventory sync (either direction) ────────────────────

  /// Syncs inventory between Masari and Shopify.
  ///
  /// [direction] must be `"shopify_to_masari"` (pull) or
  /// `"masari_to_shopify"` (push).
  /// For push, [productId], [variantId], [newStock] are required.
  Future<void> syncInventory({
    required String direction,
    String? productId,
    String? variantId,
    int? newStock,
  }) async {
    state = SyncStatus(
      phase: SyncPhase.syncing,
      message: direction == 'shopify_to_masari'
          ? 'Pulling inventory from Shopify…'
          :  'Pushing inventory to Shopify…',
      progress: 0.1,
    );

    if (direction == 'shopify_to_masari') {
      // Pull all inventory levels from Shopify → Masari
      final result = await _syncService.pullInventoryFromShopify();
      if (result.isSuccess) {
        _pullPreview = null; // clear stale preview
        state = SyncStatus(
          phase: SyncPhase.success,
          message:  'Updated ${result.data} variant(s) from Shopify',
          progress: 1,
        );
      } else {
        state = SyncStatus(
          phase: SyncPhase.error,
          message:  'Inventory pull failed',
          errorDetail: result.error,
        );
        _checkTokenRevoked(result.error);
      }
    } else {
      // Push a single variant's stock to Shopify
      if (productId == null || variantId == null || newStock == null) {
        state = const SyncStatus(
          phase: SyncPhase.error,
          message:  'Missing product/variant/stock for push',
        );
        _autoClearAfterDelay();
        return;
      }

      final result = await _syncService.syncInventoryToShopify(
        productId: productId,
        variantId: variantId,
        newStock: newStock,
      );

      if (result.isSuccess) {
        state = const SyncStatus(
          phase: SyncPhase.success,
          message:  'Inventory pushed to Shopify',
          progress: 1,
        );
      } else {
        state = SyncStatus(
          phase: SyncPhase.error,
          message:  'Inventory push failed',
          errorDetail: result.error,
        );
        _checkTokenRevoked(result.error);
      }
    }

    _autoClearAfterDelay();
  }

  // ── Preview + Confirm flow ───────────────────────────────

  /// Fetches a preview of what pulling from Shopify would change.
  /// Caches the result in [pullPreview].
  Future<void> previewPull() async {
    state = const SyncStatus(
      phase: SyncPhase.syncing,
      message:  'Fetching Shopify stock levels…',
      progress: 0.2,
    );

    final result = await _syncService.previewPullInventory();
    if (result.isSuccess) {
      _pullPreview = result.data!;
      state = SyncStatus(
        phase: SyncPhase.success,
        message: '${_pullPreview!.length} variant(s) compared',
        progress: 1,
      );
    } else {
      _pullPreview = null;
      state = SyncStatus(
        phase: SyncPhase.error,
        message:  'Failed to fetch preview',
        errorDetail: result.error,
      );
      _checkTokenRevoked(result.error);
    }
    // Don't auto-clear — keep success state so UI can display preview
  }

  /// Applies the pull: updates Masari stock to match the cached preview.
  /// Uses the exact deltas the user reviewed instead of re-fetching.
  Future<void> confirmPull() async {
    if (_pullPreview == null || _pullPreview!.isEmpty) {
      state = const SyncStatus(
        phase: SyncPhase.error,
        message:  'No preview data — please fetch preview first',
      );
      _autoClearAfterDelay();
      return;
    }

    state = const SyncStatus(
      phase: SyncPhase.syncing,
      message:  'Applying stock changes…',
      progress: 0.5,
    );

    final result = await _syncService.applyPullPreview(_pullPreview!);
    if (result.isSuccess) {
      final count = result.data!;
      _pullPreview = null;
      state = SyncStatus(
        phase: SyncPhase.success,
        message:  'Updated $count variant(s) from Shopify',
        progress: 1,
      );
    } else {
      state = SyncStatus(
        phase: SyncPhase.error,
        message:  'Pull failed',
        errorDetail: result.error,
      );
      _checkTokenRevoked(result.error);
    }
    _autoClearAfterDelay();
  }

  /// Fetches a preview of what pushing to Shopify would change.
  /// Caches the result in [pushPreview].
  Future<void> previewPush({Set<String>? productIds}) async {
    state = const SyncStatus(
      phase: SyncPhase.syncing,
      message:  'Comparing stock levels…',
      progress: 0.2,
    );

    final result = await _syncService.previewPushInventory(
      productIds: productIds,
    );
    if (result.isSuccess) {
      _pushPreview = result.data!;
      state = SyncStatus(
        phase: SyncPhase.success,
        message: '${_pushPreview!.length} variant(s) compared',
        progress: 1,
      );
    } else {
      _pushPreview = null;
      state = SyncStatus(
        phase: SyncPhase.error,
        message:  'Failed to fetch preview',
        errorDetail: result.error,
      );
      _checkTokenRevoked(result.error);
    }
  }

  /// Pushes all confirmed items to Shopify in batch.
  /// Uses the cached [pushPreview] items.
  Future<void> confirmPush() async {
    if (_pushPreview == null || _pushPreview!.isEmpty) return;

    state = const SyncStatus(
      phase: SyncPhase.syncing,
      message:  'Pushing inventory to Shopify…',
      progress: 0.3,
    );

    final result = await _syncService.pushInventoryBatch(_pushPreview!);
    if (result.isSuccess) {
      _pushPreview = null;
      state = SyncStatus(
        phase: SyncPhase.success,
        message:  'Pushed ${result.data} variant(s) to Shopify',
        progress: 1,
      );
    } else {
      state = SyncStatus(
        phase: SyncPhase.error,
        message:  'Push failed',
        errorDetail: result.error,
      );
      _checkTokenRevoked(result.error);
    }
    _autoClearAfterDelay();
  }

  /// Clears any cached preview data.
  void clearPreviews() {
    _pullPreview = null;
    _pushPreview = null;
  }

  // ── Historical order import ──────────────────────────────

  /// Syncs product details from Shopify (creates Masari products + mappings).
  /// Returns the number of products changed/created.
  Future<int> syncProducts() async {
    final conn = ref.read(shopifyConnectionProvider).value;
    if (conn == null || !conn.isActive) return 0;

    state = const SyncStatus(
      phase: SyncPhase.syncing,
      message:  'Syncing products from Shopify…',
      progress: 0.2,
    );

    final result = await _syncService.pullProductDetailsFromShopify();

    if (result.isSuccess) {
      final count = result.data ?? 0;

      // Pull inventory levels from Shopify so newly-imported products
      // get the correct stock instead of the default 0.
      if (count > 0) {
        state = const SyncStatus(
          phase: SyncPhase.syncing,
          message:  'Pulling inventory levels…',
          progress: 0.7,
        );
        await _syncService.pullInventoryFromShopify();
      }

      state = SyncStatus(
        phase: SyncPhase.success,
        message:  'Synced $count product(s) from Shopify',
        progress: 1,
      );
      if (count > 0) {
        ref.read(inventoryProvider.notifier).refresh();
      }
      return count;
    } else {
      state = SyncStatus(
        phase: SyncPhase.error,
        message: 'Product sync failed',
        errorDetail: result.error,
      );
      _checkTokenRevoked(result.error);
      return -1;
    }
  }

  /// Imports Shopify orders from [from] to [to] into Masari.
  /// Max 3 months enforced by the sync service.
  Future<void> importHistorical({
    required DateTime from,
    required DateTime to,
  }) async {
    state = const SyncStatus(
      phase: SyncPhase.syncing,
      message:  'Importing Shopify orders…',
      progress: 0.1,
    );

    final result = await _syncService.importOrders(
      from: from,
      to: to,
    );

    if (result.isSuccess) {
      final data = result.data!;
      state = SyncStatus(
        phase: SyncPhase.success,
        message:  'Imported ${data.imported} order(s), '
            'skipped ${data.skipped}, '
            '${data.errors} error(s)',
        progress: 1,
      );
      // Refresh sales list and sync history so UI shows new data
      ref.read(salesProvider.notifier).refresh();
      ref.read(shopifySyncLogProvider.notifier).refresh();
    } else {
      state = SyncStatus(
        phase: SyncPhase.error,
        message:  'Order import failed',
        errorDetail: result.error,
      );
      _checkTokenRevoked(result.error);
    }

    _autoClearAfterDelay();
  }

  /// Resets status to idle immediately.
  void reset() {
    state = const SyncStatus();
  }

  /// Auto-resets to idle after 5 seconds so that success/error
  /// banners don't linger forever.
  void _autoClearAfterDelay() {
    Future.delayed(const Duration(seconds: 5), () {
      if (state.phase == SyncPhase.success ||
          state.phase == SyncPhase.error) {
        state = const SyncStatus();
      }
    });
  }

  /// If an error message indicates the Shopify token was revoked
  /// (401 / "reconnect"), refresh the connection provider so the UI
  /// shows the disconnected state and prompts the user to reconnect.
  void _checkTokenRevoked(String? errorMsg) {
    if (errorMsg == null) return;
    final lower = errorMsg.toLowerCase();
    if (lower.contains('unauthenticated') ||
        lower.contains('token revoked') ||
        lower.contains('reconnect') ||
        lower.contains('401')) {
      // Refresh connection provider — it will re-read Firestore where
      // the CF already set status = 'disconnected'.
      ref.read(shopifyConnectionProvider.notifier).refresh();
    }
  }
}

// ── Provider ───────────────────────────────────────────────

final shopifySyncProvider =
    NotifierProvider<ShopifySyncNotifier, SyncStatus>(() {
  return ShopifySyncNotifier();
});
