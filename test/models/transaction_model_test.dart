import 'package:flutter_test/flutter_test.dart';
import 'package:revvo_app/shared/models/transaction_model.dart';

void main() {
  group('Transaction Model Tests', () {
    final dateTime = DateTime(2026, 1, 1, 10, 0);
    
    final transaction = Transaction(
      id: 'tx_123',
      userId: 'user_1',
      title: 'Coffee',
      amount: -5.0,
      dateTime: dateTime,
      categoryId: 'cat_food',
      note: 'Morning coffee',
      paymentMethod: 'Card',
    );

    test('isIncome returns correct boolean based on amount', () {
      final incomeTx = transaction.copyWith(amount: 100.0);
      final expenseTx = transaction.copyWith(amount: -50.0);

      expect(incomeTx.isIncome, true);
      expect(expenseTx.isIncome, false);
    });

    test('formattedAmount formats correctly', () {
      final incomeTx = transaction.copyWith(amount: 15.5);
      final expenseTx = transaction.copyWith(amount: -15.5);

      expect(incomeTx.formattedAmount, '+15.50');
      expect(expenseTx.formattedAmount, '-15.50');
    });

    test('JSON serialization works correctly', () {
      final json = transaction.toJson();

      expect(json['id'], 'tx_123');
      expect(json['user_id'], 'user_1');
      expect(json['title'], 'Coffee');
      expect(json['amount'], -5.0);
      expect(json['category_id'], 'cat_food');
      expect(json['note'], 'Morning coffee');
      expect(json['payment_method'], 'Card');
    });

    test('JSON deserialization creates correct object', () {
      final json = {
        'id': 'tx_456',
        'user_id': 'user_2',
        'title': 'Salary',
        'amount': 5000.0,
        'date_time': dateTime.toIso8601String(),
        'category_id': 'cat_income',
        'payment_method': 'Bank Transfer',
      };

      final deserialized = Transaction.fromJson(json);

      expect(deserialized.id, 'tx_456');
      expect(deserialized.userId, 'user_2');
      expect(deserialized.title, 'Salary');
      expect(deserialized.amount, 5000.0);
      expect(deserialized.categoryId, 'cat_income');
      expect(deserialized.paymentMethod, 'Bank Transfer');
      expect(deserialized.isIncome, true);
    });

    test('TransactionFilter logic applies correctly', () {
      final filter = TransactionFilter(
        type: TransactionType.income,
      );

      expect(filter.activeCount, 1);
      expect(filter.isDefault, false);
    });
  });
}
