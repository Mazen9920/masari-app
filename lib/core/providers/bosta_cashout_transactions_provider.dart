import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/transaction_model.dart';
import '../providers/auth_provider.dart';

/// Loads `bosta_cashouts` and maps each to a virtual [Transaction] with
/// `categoryId = 'cat_bosta_cashout'` so they appear in the transactions list.
///
/// These are display-only — they are NOT persisted in the `transactions`
/// collection and cannot be edited/deleted.
final bostaCashoutTransactionsProvider =
    FutureProvider<List<Transaction>>((ref) async {
  final userId = ref.read(authProvider).user?.id;
  if (userId == null) return [];

  final snap = await FirebaseFirestore.instance
      .collection('bosta_cashouts')
      .where('user_id', isEqualTo: userId)
      .orderBy('transaction_date', descending: true)
      .get();

  return snap.docs.map((doc) {
    final data = doc.data();
    final amount = (data['amount'] as num?)?.toDouble() ?? 0;
    final dateStr = data['transaction_date'] as String? ?? '';
    final txId = data['transaction_id'] as String? ?? doc.id;

    // Parse YYYY-MM-DD date string.
    DateTime date;
    try {
      date = DateTime.parse(dateStr);
    } catch (_) {
      date = (data['synced_at'] as Timestamp?)?.toDate() ?? DateTime.now();
    }

    return Transaction(
      id: 'bosta_cashout_$txId',
      userId: userId,
      title: 'Bosta Cashout',
      amount: amount.abs(), // Always positive (income).
      dateTime: date,
      categoryId: 'cat_bosta_cashout',
      note: 'Bosta Transaction ID: $txId',
      paymentMethod: 'Bank Transfer',
      excludeFromPL: true, // Cashouts are not P&L - they're balance sheet.
    );
  }).toList();
});
