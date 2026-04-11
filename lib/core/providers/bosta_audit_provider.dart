import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/bosta_shipment_model.dart';
import 'auth_provider.dart';
import 'bosta_connection_provider.dart';

/// Accrual audit stats for the dashboard.
class BostaAuditStats {
  final double totalEstimates;
  final double totalAdjustments;
  final double netActual;
  final double runningAverage;
  final int estimateOnlyCount;
  final int reconciledCount;
  final int pendingEstimateCount;
  final int totalShipments;

  const BostaAuditStats({
    this.totalEstimates = 0,
    this.totalAdjustments = 0,
    this.netActual = 0,
    this.runningAverage = 0,
    this.estimateOnlyCount = 0,
    this.reconciledCount = 0,
    this.pendingEstimateCount = 0,
    this.totalShipments = 0,
  });
}

/// Filter for the audit shipment list.
enum BostaAuditFilter { all, reconciled, estimateOnly, pending }

/// Sort order for the audit shipment list.
enum BostaAuditSort { fulfillment, settlement, adjustment }

/// Provides accrual audit stats from transaction totals + shipment counts.
final bostaAuditStatsProvider =
    FutureProvider.autoDispose<BostaAuditStats>((ref) async {
  final userId = ref.read(authProvider).user?.id;
  if (userId == null) return const BostaAuditStats();

  final db = FirebaseFirestore.instance;

  // Run all three queries in parallel
  final results = await Future.wait([
    // [0] Estimate transactions (bosta_est_daily_*)
    db
        .collection('transactions')
        .where('user_id', isEqualTo: userId)
        .where('is_estimate', isEqualTo: true)
        .where('payment_method', isEqualTo: 'bosta')
        .get(),
    // [1] Reconciliation transactions (bosta_rec_daily_*)
    db
        .collection('transactions')
        .where('user_id', isEqualTo: userId)
        .where('is_reconciliation', isEqualTo: true)
        .where('payment_method', isEqualTo: 'bosta')
        .get(),
    // [2] All shipments for counts
    db
        .collection('bosta_shipments')
        .where('user_id', isEqualTo: userId)
        .get(),
  ]);

  final estSnap = results[0];
  final recSnap = results[1];
  final shipmentsSnap = results[2];

  double totalEstimates = 0;
  for (final doc in estSnap.docs) {
    totalEstimates += (doc.data()['amount'] as num?)?.toDouble().abs() ?? 0;
  }

  double totalAdjustments = 0;
  for (final doc in recSnap.docs) {
    totalAdjustments += (doc.data()['amount'] as num?)?.toDouble() ?? 0;
  }

  int estimateOnly = 0;
  int reconciled = 0;
  int pendingEstimate = 0;

  for (final doc in shipmentsSnap.docs) {
    final d = doc.data();
    final hasEstimate = d['estimated_fee'] != null;
    final isReconciled =
        d['total_fees'] != null && (d['estimate_recorded'] == true);

    if (isReconciled) {
      reconciled++;
    } else if (hasEstimate) {
      estimateOnly++;
    } else {
      pendingEstimate++;
    }
  }

  // Running average from connection doc
  final conn = ref.read(bostaConnectionProvider).value;
  final runningAverage = conn?.averageBostaFee ?? 0;

  final netActual = totalEstimates + totalAdjustments; // adjustments are signed

  return BostaAuditStats(
    totalEstimates: totalEstimates,
    totalAdjustments: totalAdjustments,
    netActual: netActual,
    runningAverage: runningAverage,
    estimateOnlyCount: estimateOnly,
    reconciledCount: reconciled,
    pendingEstimateCount: pendingEstimate,
    totalShipments: shipmentsSnap.size,
  );
});

/// Provides the per-shipment audit list with filtering.
final bostaAuditListProvider = FutureProvider.autoDispose
    .family<List<BostaShipment>, BostaAuditFilter>((ref, filter) async {
  final userId = ref.read(authProvider).user?.id;
  if (userId == null) return [];

  final db = FirebaseFirestore.instance;
  Query query = db
      .collection('bosta_shipments')
      .where('user_id', isEqualTo: userId);

  switch (filter) {
    case BostaAuditFilter.reconciled:
      query = query.where('estimate_recorded', isEqualTo: true);
      break;
    case BostaAuditFilter.estimateOnly:
      query = query
          .where('awaiting_settlement', isEqualTo: true);
      break;
    case BostaAuditFilter.pending:
      // No estimate yet — fetch all and filter client-side
      break;
    case BostaAuditFilter.all:
      break;
  }

  query = query.orderBy('deposited_at', descending: true).limit(200);
  final snap = await query.get();
  final shipments =
      snap.docs.map((d) => BostaShipment.fromJson(d.data() as Map<String, dynamic>)).toList();

  // Client-side post-filters
  if (filter == BostaAuditFilter.reconciled) {
    return shipments.where((s) => s.totalFees != null).toList();
  }
  if (filter == BostaAuditFilter.pending) {
    return shipments.where((s) => !s.estimateRecorded).toList();
  }
  if (filter == BostaAuditFilter.estimateOnly) {
    return shipments.where((s) => s.estimateRecorded && s.totalFees == null).toList();
  }
  return shipments;
});
