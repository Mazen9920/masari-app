import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../shared/models/balance_sheet_entries.dart';
import '../../services/result.dart';
import '../balance_sheet_repository.dart';

/// Firestore implementation — stores one document per user at
/// `balance_sheet/{uid}`.
class FirestoreBalanceSheetRepository implements BalanceSheetRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError( 'Not authenticated');
    return user.uid;
  }

  DocumentReference<Map<String, dynamic>> get _doc =>
      _firestore.collection('balance_sheet').doc(_uid);

  @override
  Future<Result<BalanceSheetEntries>> getEntries() async {
    try {
      final snapshot = await _doc.get();
      if (!snapshot.exists) {
        return Result.success(const BalanceSheetEntries());
      }
      return Result.success(BalanceSheetEntries.fromJson(snapshot.data()!));
    } catch (e) {
      return Result.failure( 'Failed to load balance sheet: $e');
    }
  }

  @override
  Future<Result<BalanceSheetEntries>> saveEntries(
      BalanceSheetEntries entries) async {
    try {
      final json = entries.toJson();
      json['updated_at'] = DateTime.now().toIso8601String();
      await _doc.set(json, SetOptions(merge: true));
      return Result.success(entries);
    } catch (e) {
      return Result.failure( 'Failed to save balance sheet: $e');
    }
  }

  @override
  Future<Result<void>> deleteEntries() async {
    try {
      await _doc.delete();
      return Result.success(null);
    } catch (e) {
      return Result.failure( 'Failed to delete balance sheet: $e');
    }
  }
}
