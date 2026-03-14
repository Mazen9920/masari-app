import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../services/result.dart';
import '../shopify_sync_log_repository.dart';

/// Firestore implementation of [ShopifySyncLogRepository].
///
/// Write-heavy, read for audit. Log entries are immutable once written.
class FirestoreShopifySyncLogRepository implements ShopifySyncLogRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('shopify_sync_log');

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError( 'Not authenticated');
    return user.uid;
  }

  @override
  Future<Result<void>> log(ShopifySyncLogEntry entry) async {
    try {
      final json = entry.toJson();
      json['user_id'] = _uid; // enforce ownership
      // Store created_at as Firestore Timestamp for index ordering
      json['created_at'] = Timestamp.fromDate(entry.createdAt);
      await _collection.add(json);
      return Result.success(null);
    } catch (e) {
      // Logging failures should not crash the app — silently fail.
      return Result.failure( 'Failed to write sync log: $e');
    }
  }

  @override
  Future<Result<List<ShopifySyncLogEntry>>> getRecentLogs(
      {int limit = 50}) async {
    try {
      final snapshot = await _collection
          .where('user_id', isEqualTo: _uid)
          .orderBy('created_at', descending: true)
          .limit(limit)
          .get();
      final logs = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        // Handle both Timestamp and ISO-8601 string for created_at
        final raw = data['created_at'];
        if (raw is Timestamp) {
          data['created_at'] = raw.toDate().toIso8601String();
        }
        return ShopifySyncLogEntry.fromJson(data);
      }).toList();
      return Result.success(logs);
    } catch (e) {
      return Result.failure( 'Failed to fetch sync logs: $e');
    }
  }

  @override
  Future<Result<void>> clearLogs() async {
    try {
      final snapshot =
          await _collection.where('user_id', isEqualTo: _uid).get();
      if (snapshot.docs.isEmpty) return Result.success(null);
      // Batch delete in chunks of 500 (Firestore limit)
      const batchLimit = 500;
      var batch = _firestore.batch();
      var count = 0;
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
        count++;
        if (count >= batchLimit) {
          await batch.commit();
          batch = _firestore.batch();
          count = 0;
        }
      }
      if (count > 0) await batch.commit();
      return Result.success(null);
    } catch (e) {
      return Result.failure( 'Failed to clear sync logs: $e');
    }
  }
}
