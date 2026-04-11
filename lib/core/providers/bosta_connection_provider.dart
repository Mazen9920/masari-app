import 'dart:async';
import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/bosta_connection_model.dart';
import '../services/bosta_api_service.dart';
import '../services/result.dart';
import 'auth_provider.dart';

void _log(String msg) => dev.log(msg, name: 'BostaConn');

/// Manages the user's Bosta connection lifecycle.
///
/// Reads the connection doc from `bosta_connections/{userId}` in
/// Firestore, and exposes methods to connect/disconnect/sync/refresh.
/// The API key is handled exclusively on the server — the client
/// only sends it once during [connect].
class BostaConnectionNotifier extends AsyncNotifier<BostaConnection?> {
  late final BostaApiService _api;
  StreamSubscription<DocumentSnapshot>? _progressSub;

  @override
  Future<BostaConnection?> build() async {
    _api = BostaApiService();

    final userId = ref.read(authProvider).user?.id;
    _log('build() userId=$userId');
    if (userId == null) return null;

    ref.onDispose(() {
      _progressSub?.cancel();
    });

    final doc = await FirebaseFirestore.instance
        .doc('bosta_connections/$userId')
        .get();

    _log('build() doc.exists=${doc.exists} data=${doc.data()}');
    if (!doc.exists || doc.data() == null) return null;
    final conn = BostaConnection.fromJson(doc.data()!);
    _log('build() connection: status=${conn.status} autoSync=${conn.autoSyncEnabled} lastSync=${conn.lastSyncAt}');
    return conn;
  }

  /// Starts a real-time listener on the connection doc for sync progress.
  void _listenForProgress() {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;

    _progressSub?.cancel();
    _progressSub = FirebaseFirestore.instance
        .doc('bosta_connections/$userId')
        .snapshots()
        .listen((snap) {
      if (!snap.exists || snap.data() == null) return;
      final conn = BostaConnection.fromJson(snap.data()!);
      state = AsyncValue.data(conn);
    });
  }

  /// Stops the real-time progress listener.
  void _stopListeningForProgress() {
    _progressSub?.cancel();
    _progressSub = null;
  }

  /// Connects to Bosta.
  ///
  /// Sends the raw API key to the `connectBosta` Cloud Function which
  /// validates it, encrypts it, and writes the connection doc.
  Future<Result<void>> connect({
    required String apiKey,
    String? businessId,
  }) async {
    _log('connect() calling API...');
    final result = await _api.connect(
      apiKey: apiKey,
      businessId: businessId,
    );
    _log('connect() result: success=${result.isSuccess} error=${result.error} data=${result.data}');

    if (result.isSuccess) {
      _log('connect() refreshing state...');
      await refresh();
      _log('connect() state after refresh: ${state.value?.status}');
      return Result.success(null);
    }
    return Result.failure(result.error ?? 'Failed to connect to Bosta');
  }

  /// Disconnects from Bosta.
  Future<Result<void>> disconnect() async {
    _log('disconnect() calling API...');
    final result = await _api.disconnect();
    _log('disconnect() result: success=${result.isSuccess} error=${result.error}');

    if (result.isSuccess) {
      state = const AsyncValue.data(null);
      return Result.success(null);
    }
    return Result.failure(result.error ?? 'Failed to disconnect from Bosta');
  }

  /// Triggers a manual sync of Bosta shipments.
  ///
  /// Automatically resumes if the sync times out (large account).
  /// Listens to the connection doc for real-time progress updates.
  Future<Result<Map<String, dynamic>>> triggerSync({
    bool fullSync = false,
    String? dateFrom,
    String? dateTo,
  }) async {
    _log('triggerSync(fullSync=$fullSync, dateFrom=$dateFrom, dateTo=$dateTo)');

    // Start listening for live progress updates
    _listenForProgress();

    int startPage = 1;
    Map<String, dynamic>? lastResult;

    try {
      // Loop handles auto-resume for large syncs
      while (true) {
        _log('triggerSync: calling API startPage=$startPage');
        final result = await _api.syncShipments(
          fullSync: fullSync,
          startPage: startPage,
          dateFrom: dateFrom,
          dateTo: dateTo,
        );

        if (!result.isSuccess) {
          _stopListeningForProgress();
          await refresh();
          return result;
        }

        lastResult = result.data;
        final isComplete = lastResult?['complete'] == true;
        final resumePage = (lastResult?['resumePage'] as num?)?.toInt() ?? 0;

        _log('triggerSync: complete=$isComplete resumePage=$resumePage');

        if (isComplete || resumePage <= 0) {
          break;
        }

        // Auto-resume from where we left off
        startPage = resumePage;
        _log('triggerSync: auto-resuming from page $startPage');
      }
    } finally {
      _stopListeningForProgress();
    }

    await refresh();
    return Result.success(lastResult ?? {});
  }

  /// Toggles auto-sync on the connection doc.
  Future<Result<void>> updateAutoSync(bool enabled) async {
    final current = state.value;
    if (current == null) {
      return Result.failure('No active Bosta connection');
    }

    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return Result.failure('Not authenticated');

    try {
      await FirebaseFirestore.instance
          .doc('bosta_connections/$userId')
          .update({'auto_sync_enabled': enabled});

      state = AsyncValue.data(current.copyWith(autoSyncEnabled: enabled));
      return Result.success(null);
    } catch (e) {
      return Result.failure('Failed to update auto-sync: $e');
    }
  }

  /// Reloads the connection doc from Firestore.
  /// Preserves the previous value during reload so the UI doesn't flash.
  Future<void> refresh() async {
    _log('refresh() fetching from server...');
    final newState = await AsyncValue.guard(() async {
      final userId = ref.read(authProvider).user?.id;
      if (userId == null) {
        _log('refresh() no userId');
        return null;
      }

      final doc = await FirebaseFirestore.instance
          .doc('bosta_connections/$userId')
          .get(const GetOptions(source: Source.server));

      _log('refresh() doc.exists=${doc.exists} data=${doc.data()}');
      if (!doc.exists || doc.data() == null) return null;
      final conn = BostaConnection.fromJson(doc.data()!);
      _log('refresh() connection: status=${conn.status} lastSync=${conn.lastSyncAt}');
      return conn;
    });
    if (newState.hasError) {
      _log('refresh() ERROR: ${newState.error}');
    }
    state = newState;
  }
}

// ── Providers ──────────────────────────────────────────────

final bostaConnectionProvider =
    AsyncNotifierProvider<BostaConnectionNotifier, BostaConnection?>(() {
  return BostaConnectionNotifier();
});

/// Convenience — true when an active Bosta connection exists.
final isBostaConnectedProvider = Provider<bool>((ref) {
  final conn = ref.watch(bostaConnectionProvider).value;
  return conn != null && conn.isActive;
});
