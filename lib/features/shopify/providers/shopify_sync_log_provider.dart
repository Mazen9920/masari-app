import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../core/repositories/shopify_sync_log_repository.dart';

/// Provides the recent sync log entries for the current user.
///
/// Exposes an [AsyncNotifier] so the UI can call [refresh()] after
/// a sync operation completes.
class ShopifySyncLogNotifier
    extends AsyncNotifier<List<ShopifySyncLogEntry>> {
  @override
  Future<List<ShopifySyncLogEntry>> build() async {
    final repo = ref.read(shopifySyncLogRepositoryProvider);
    final result = await repo.getRecentLogs(limit: 100);
    return result.isSuccess ? result.data! : [];
  }

  /// Re-fetches the logs from Firestore.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => build());
  }

  /// Deletes all sync logs for the current user.
  Future<void> clearAll() async {
    final repo = ref.read(shopifySyncLogRepositoryProvider);
    await repo.clearLogs();
    state = const AsyncValue.data([]);
  }
}

/// Provider for Shopify sync log entries.
final shopifySyncLogProvider = AsyncNotifierProvider<
    ShopifySyncLogNotifier, List<ShopifySyncLogEntry>>(() {
  return ShopifySyncLogNotifier();
});
