import 'package:flutter_test/flutter_test.dart';
import 'package:masari_app/shared/models/supplier_model.dart';

void main() {
  group('Supplier Model Tests', () {
    final supplier = Supplier(
      id: 'sup_123',
      userId: 'user_1',
      name: 'Acme Corp',
      category: 'Wholesale',
      phone: '1234567890',
      email: 'acme@test.com',
      balance: 1000.0,
      paymentTerms: 'Net 30',
      lastTransaction: DateTime(2026, 1, 1),
      dueDate: DateTime.now().add(const Duration(days: 5)),
    );

    test('initials property formats correctly', () {
      expect(supplier.initials, 'AC');
      
      final singleNamePart = supplier.copyWith(name: 'Acme');
      expect(singleNamePart.initials, 'AC');
    });

    test('isOverdue and daysOverdue calculate correctly', () {
      // Future due date
      expect(supplier.isOverdue, false);
      expect(supplier.daysOverdue, 0);

      // Past due date
      final pastDueSupplier = supplier.copyWith(
        dueDate: DateTime.now().subtract(const Duration(days: 10)),
      );
      expect(pastDueSupplier.isOverdue, true);
      expect(pastDueSupplier.daysOverdue, 10);
    });

    test('balance status getters evaluate correctly', () {
      expect(supplier.hasDue, true);
      expect(supplier.isPaid, false);

      final paidSupplier = supplier.copyWith(balance: 0.0);
      expect(paidSupplier.hasDue, false);
      expect(paidSupplier.isPaid, true);
    });

    test('JSON serialization works correctly', () {
      final json = supplier.toJson();

      expect(json['id'], 'sup_123');
      expect(json['user_id'], 'user_1');
      expect(json['name'], 'Acme Corp');
      expect(json['balance'], 1000.0);
      expect(json['payment_terms'], 'Net 30');
    });

    test('JSON deserialization creates correct object', () {
      final json = {
        'id': 'sup_456',
        'user_id': 'user_2',
        'name': 'Globex',
        'category': 'Services',
        'phone': '0987654321',
        'balance': 500.0,
        'payment_terms': 'On Receipt',
        'last_transaction': DateTime(2026, 2, 1).toIso8601String(),
      };

      final deserialized = Supplier.fromJson(json);

      expect(deserialized.id, 'sup_456');
      expect(deserialized.name, 'Globex');
      expect(deserialized.balance, 500.0);
      expect(deserialized.hasDue, true);
    });
  });
}
