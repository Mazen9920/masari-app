import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/bosta_shipment_model.dart';
import 'auth_provider.dart';
import 'bosta_connection_provider.dart';

void _log(String msg) => dev.log(msg, name: 'BostaShip');

/// Page size for cursor-based pagination.
const _kPageSize = 25;

/// Query filter for Bosta shipments.
class BostaShipmentFilter {
  final DateTime? from;
  final DateTime? to;

  /// null = all, true = settled only, false = awaiting settlement only
  final bool? settledOnly;

  /// null = all, true = matched only, false = unlinked only
  final bool? matchedOnly;

  const BostaShipmentFilter({this.from, this.to, this.settledOnly, this.matchedOnly});

  BostaShipmentFilter copyWith({
    DateTime? from,
    DateTime? to,
    bool? settledOnly,
    bool? matchedOnly,
  }) {
    return BostaShipmentFilter(
      from: from ?? this.from,
      to: to ?? this.to,
      settledOnly: settledOnly ?? this.settledOnly,
      matchedOnly: matchedOnly ?? this.matchedOnly,
    );
  }
}

/// Manages the current shipment filter state.
class BostaShipmentFilterNotifier extends Notifier<BostaShipmentFilter> {
  @override
  BostaShipmentFilter build() => const BostaShipmentFilter();

  void update(BostaShipmentFilter filter) => state = filter;
  void reset() => state = const BostaShipmentFilter();
}

/// Provider for the current shipment filter.
final bostaShipmentFilterProvider =
    NotifierProvider<BostaShipmentFilterNotifier, BostaShipmentFilter>(
  BostaShipmentFilterNotifier.new,
);

/// Paginated Bosta shipments notifier.
///
/// Loads [_kPageSize] shipments at a time using Firestore cursor-based
/// pagination. Call [loadMore] to fetch the next page.
class BostaShipmentsNotifier extends AsyncNotifier<List<BostaShipment>> {
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  /// Whether there are more pages to load.
  bool get hasMore => _hasMore;

  /// Whether a loadMore is currently in progress.
  bool get isLoadingMore => _isLoadingMore;

  @override
  Future<List<BostaShipment>> build() async {
    // Re-fetch when connection changes (e.g. after sync).
    ref.watch(bostaConnectionProvider);
    // Re-fetch when filter changes.
    ref.watch(bostaShipmentFilterProvider);

    _lastDocument = null;
    _hasMore = true;
    _isLoadingMore = false;

    return _fetchPage();
  }

  Future<List<BostaShipment>> _fetchPage() async {
    final userId = ref.read(authProvider).user?.id;
    _log('_fetchPage userId=$userId lastDoc=${_lastDocument?.id}');
    if (userId == null) return [];

    final filter = ref.read(bostaShipmentFilterProvider);

    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('bosta_shipments')
        .where('user_id', isEqualTo: userId);

    // Date range filter on deposited_at.
    if (filter.from != null) {
      query = query.where('deposited_at',
          isGreaterThanOrEqualTo: Timestamp.fromDate(filter.from!));
    }
    if (filter.to != null) {
      query = query.where('deposited_at',
          isLessThanOrEqualTo: Timestamp.fromDate(filter.to!));
    }

    // Settled / awaiting-settlement filter.
    if (filter.settledOnly == true) {
      query = query.where('expense_recorded', isEqualTo: true);
    } else if (filter.settledOnly == false) {
      query = query.where('awaiting_settlement', isEqualTo: true);
    }

    // Matched / unlinked filter.
    if (filter.matchedOnly == true) {
      query = query.where('matched', isEqualTo: true);
    } else if (filter.matchedOnly == false) {
      query = query.where('matched', isEqualTo: false);
    }

    query = query.orderBy('deposited_at', descending: true);

    // Cursor-based pagination
    if (_lastDocument != null) {
      query = query.startAfterDocument(_lastDocument!);
    }

    query = query.limit(_kPageSize);

    final snapshot = await query.get();
    _log('_fetchPage got ${snapshot.docs.length} docs (hasMore=${snapshot.docs.length >= _kPageSize})');

    if (snapshot.docs.isNotEmpty) {
      _lastDocument = snapshot.docs.last;
    }
    _hasMore = snapshot.docs.length >= _kPageSize;

    final shipments = snapshot.docs
        .map((doc) => BostaShipment.fromJson(doc.data()))
        .toList();

    for (final s in shipments.take(3)) {
      _log('  shipment: ${s.trackingNumber} state=${s.stateValue} fees=${s.totalFees} matched=${s.matched}');
    }
    if (shipments.length > 3) _log('  ... and ${shipments.length - 3} more');
    return shipments;
  }

  /// Loads the next page and appends to current list.
  Future<void> loadMore() async {
    if (!_hasMore || _isLoadingMore) return;
    _isLoadingMore = true;

    try {
      final moreItems = await _fetchPage();
      final current = state.value ?? [];
      state = AsyncData([...current, ...moreItems]);
    } catch (e, st) {
      _log('loadMore error: $e');
      // Keep existing data, just log the error
      state = AsyncError(e, st);
    } finally {
      _isLoadingMore = false;
    }
  }
}

/// Provider for paginated Bosta shipments.
final bostaShipmentsProvider =
    AsyncNotifierProvider<BostaShipmentsNotifier, List<BostaShipment>>(
  BostaShipmentsNotifier.new,
);

// ── Computed Aggregation Providers ─────────────────────────
// Stats now come from server-computed aggregates on the connection doc.
// Fallback to client-side computation from loaded shipments.

/// Summary statistics for Bosta shipments.
class BostaShipmentStats {
  final int total;
  final int matchedCount;
  final int unlinkedCount;
  final int settledCount;
  final int awaitingCount;
  final double totalFees;

  const BostaShipmentStats({
    this.total = 0,
    this.matchedCount = 0,
    this.unlinkedCount = 0,
    this.settledCount = 0,
    this.awaitingCount = 0,
    this.totalFees = 0,
  });
}

/// Stats provider — prefers server-computed stats, falls back to client-side.
final bostaShipmentStatsProvider = Provider.autoDispose<BostaShipmentStats>((ref) {
  // Try server-side stats first (from connection doc)
  final conn = ref.watch(bostaConnectionProvider).value;
  final serverStats = conn?.stats;
  if (serverStats != null && serverStats.totalShipments > 0) {
    return BostaShipmentStats(
      total: serverStats.totalShipments,
      matchedCount: serverStats.matchedCount,
      unlinkedCount: serverStats.unlinkedCount,
      settledCount: serverStats.settledCount,
      awaitingCount: serverStats.awaitingCount,
      totalFees: serverStats.totalFees,
    );
  }

  // Fallback: compute from loaded shipments
  final shipments = ref.watch(bostaShipmentsProvider).value ?? [];

  int matchedCount = 0;
  int unlinkedCount = 0;
  int settledCount = 0;
  int awaitingCount = 0;
  double totalFees = 0;

  for (final s in shipments) {
    final fee = s.totalFees ?? 0;
    totalFees += fee;

    if (s.matched) {
      matchedCount++;
    } else {
      unlinkedCount++;
    }

    if (s.expenseRecorded) {
      settledCount++;
    } else if (s.awaitingSettlement) {
      awaitingCount++;
    }
  }

  return BostaShipmentStats(
    total: shipments.length,
    matchedCount: matchedCount,
    unlinkedCount: unlinkedCount,
    settledCount: settledCount,
    awaitingCount: awaitingCount,
    totalFees: totalFees,
  );
});
