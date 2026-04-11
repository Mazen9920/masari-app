import 'dart:developer' as dev;

import 'package:cloud_functions/cloud_functions.dart' hide Result;

import 'result.dart';

void _log(String msg) => dev.log(msg, name: 'BostaAPI');

/// Low-level Bosta API service.
///
/// Every call goes via the `bostaProxy` Cloud Function so the
/// Bosta API key never leaves the server.
class BostaApiService {
  final FirebaseFunctions _functions;

  BostaApiService({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'us-central1');

  HttpsCallable get _proxy => _functions.httpsCallable(
        'bostaProxy',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
      );

  // ── Deliveries ───────────────────────────────────────────

  /// Fetches a single Bosta delivery by tracking number.
  ///
  /// Returns the full delivery detail including `wallet.cashCycle`.
  Future<Result<Map<String, dynamic>>> getDelivery({
    required String trackingNumber,
  }) async {
    _log('getDelivery($trackingNumber)');
    try {
      final result = await _proxy.call<Map<String, dynamic>>({
        'action': 'getDelivery',
        'params': {'trackingNumber': trackingNumber},
      });
      _log('getDelivery OK: ${result.data}');
      return Result.success(result.data);
    } on FirebaseFunctionsException catch (e) {
      _log('getDelivery ERROR: code=${e.code} message=${e.message} details=${e.details}');
      return Result.failure(e.message ?? 'Failed to fetch Bosta delivery');
    } catch (e) {
      _log('getDelivery EXCEPTION: $e');
      return Result.failure('Failed to fetch Bosta delivery: $e');
    }
  }

  /// Searches Bosta deliveries with optional filters.
  ///
  /// Returns paginated results (search does NOT include wallet.cashCycle).
  Future<Result<Map<String, dynamic>>> searchDeliveries({
    int pageNumber = 1,
    int pageLimit = 50,
    String? state,
    String? dateFrom,
    String? dateTo,
  }) async {
    _log('searchDeliveries(page=$pageNumber, limit=$pageLimit, state=$state)');
    try {
      final params = <String, dynamic>{
        'pageNumber': pageNumber,
        'pageLimit': pageLimit,
      };
      if (state != null) params['state'] = state;
      if (dateFrom != null) params['dateFrom'] = dateFrom;
      if (dateTo != null) params['dateTo'] = dateTo;

      final result = await _proxy.call<Map<String, dynamic>>({
        'action': 'searchDeliveries',
        'params': params,
      });
      _log('searchDeliveries OK: ${result.data.keys}');
      return Result.success(result.data);
    } on FirebaseFunctionsException catch (e) {
      _log('searchDeliveries ERROR: code=${e.code} message=${e.message} details=${e.details}');
      return Result.failure(e.message ?? 'Failed to search Bosta deliveries');
    } catch (e) {
      _log('searchDeliveries EXCEPTION: $e');
      return Result.failure('Failed to search Bosta deliveries: $e');
    }
  }

  // ── Connection ───────────────────────────────────────────

  /// Tests a Bosta API key by making a minimal search request.
  Future<Result<Map<String, dynamic>>> testConnection() async {
    _log('testConnection()');
    try {
      final result = await _proxy.call<Map<String, dynamic>>({
        'action': 'testConnection',
        'params': <String, dynamic>{},
      });
      _log('testConnection OK: ${result.data}');
      return Result.success(result.data);
    } on FirebaseFunctionsException catch (e) {
      _log('testConnection ERROR: code=${e.code} message=${e.message} details=${e.details}');
      return Result.failure(e.message ?? 'Connection test failed');
    } catch (e) {
      _log('testConnection EXCEPTION: $e');
      return Result.failure('Connection test failed: $e');
    }
  }

  // ── Sync ─────────────────────────────────────────────────

  /// Triggers a manual Bosta shipments sync.
  ///
  /// [fullSync] if true, syncs all deliveries; otherwise incremental (recent).
  /// [startPage] page to resume from (for large syncs that timed out).
  /// [dateFrom] optional YYYY-MM-DD start date filter.
  /// [dateTo] optional YYYY-MM-DD end date filter.
  /// Returns the sync result summary.
  Future<Result<Map<String, dynamic>>> syncShipments({
    bool fullSync = false,
    int startPage = 1,
    String? dateFrom,
    String? dateTo,
  }) async {
    _log('syncShipments(fullSync=$fullSync, startPage=$startPage, dateFrom=$dateFrom, dateTo=$dateTo)');
    try {
      final callable = _functions.httpsCallable(
        'syncBostaShipments',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 600)),
      );
      final params = <String, dynamic>{
        'fullSync': fullSync,
        'startPage': startPage,
      };
      if (dateFrom != null) params['dateFrom'] = dateFrom;
      if (dateTo != null) params['dateTo'] = dateTo;
      final result = await callable.call<Map<String, dynamic>>(params);
      _log('syncShipments OK: ${result.data}');
      return Result.success(result.data);
    } on FirebaseFunctionsException catch (e) {
      _log('syncShipments ERROR: code=${e.code} message=${e.message} details=${e.details}');
      return Result.failure(e.message ?? 'Sync failed');
    } catch (e) {
      _log('syncShipments EXCEPTION: $e');
      return Result.failure('Sync failed: $e');
    }
  }

  /// Connects to Bosta by saving an encrypted API key.
  Future<Result<Map<String, dynamic>>> connect({
    required String apiKey,
    String? businessId,
  }) async {
    _log('connect(apiKey=${apiKey.substring(0, 6)}..., businessId=$businessId)');
    try {
      final callable = _functions.httpsCallable(
        'connectBosta',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final result = await callable.call<Map<String, dynamic>>({
        'apiKey': apiKey,
        'businessId': businessId,
      });
      _log('connect OK: ${result.data}');
      return Result.success(result.data);
    } on FirebaseFunctionsException catch (e) {
      _log('connect ERROR: code=${e.code} message=${e.message} details=${e.details}');
      return Result.failure(e.message ?? 'Failed to connect to Bosta');
    } catch (e) {
      _log('connect EXCEPTION: $e');
      return Result.failure('Failed to connect to Bosta: $e');
    }
  }

  /// Disconnects from Bosta.
  Future<Result<Map<String, dynamic>>> disconnect() async {
    _log('disconnect()');
    try {
      final callable = _functions.httpsCallable(
        'disconnectBosta',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final result = await callable.call<Map<String, dynamic>>({});
      _log('disconnect OK: ${result.data}');
      return Result.success(result.data);
    } on FirebaseFunctionsException catch (e) {
      return Result.failure(e.message ?? 'Failed to disconnect from Bosta');
    } catch (e) {
      return Result.failure('Failed to disconnect from Bosta: $e');
    }
  }
}
