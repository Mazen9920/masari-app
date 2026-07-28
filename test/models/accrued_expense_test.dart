import 'package:flutter_test/flutter_test.dart';
import 'package:revvo_app/shared/models/accrued_expense_model.dart';

AccruedExpense accrual({
  double amount = 5000,
  double? originalAmount,
  DateTime? accrualDate,
  DateTime? dueDate,
  String? categoryId,
  AccrualRecurrence recurrence = AccrualRecurrence.none,
  List<AccruedExpensePayment> payments = const [],
  AccruedExpenseStatus status = AccruedExpenseStatus.active,
}) =>
    AccruedExpense(
      id: 'a1',
      name: 'Rent',
      amount: amount,
      originalAmount: originalAmount,
      accrualDate: accrualDate,
      dueDate: dueDate,
      categoryId: categoryId,
      recurrence: recurrence,
      status: status,
      createdAt: DateTime(2026, 6, 1),
      payments: payments,
    );

void main() {
  group('P&L period — the core bug', () {
    test('accrualDate drives the period, NOT the day it was entered', () {
      // June rent typed in July must still belong to June.
      final e = accrual(accrualDate: DateTime(2026, 6, 30));
      expect(e.accrualDate, DateTime(2026, 6, 30));
      expect(e.periodKey, '2026-06');
    });

    test('legacy rows with no accrualDate fall back to createdAt', () {
      final e = accrual();
      expect(e.accrualDate, DateTime(2026, 6, 1));
      expect(e.periodKey, '2026-06');
    });
  });

  group('category', () {
    test('uses the real expense category when set', () {
      expect(accrual(categoryId: 'cat_rent').effectiveCategoryId, 'cat_rent');
    });
    test('falls back to the generic accrued category', () {
      expect(accrual().effectiveCategoryId, 'cat_accrued_expense');
    });
  });

  group('totals and progress', () {
    test('originalAmount survives part-payment', () {
      final e = accrual(
        amount: 3000, // outstanding after paying 2,000
        originalAmount: 5000,
        payments: [
          AccruedExpensePayment(
              id: 'p1', amount: 2000, date: DateTime(2026, 6, 10))
        ],
      );
      expect(e.totalAccrued, 5000);
      expect(e.totalPaid, 2000);
      expect(e.progressPct, 0.4);
    });

    test('legacy rows reconstruct the original from outstanding + paid', () {
      final e = AccruedExpense(
        id: 'legacy',
        name: 'Old',
        amount: 3000,
        createdAt: DateTime(2026, 5, 1),
        payments: [
          AccruedExpensePayment(
              id: 'p1', amount: 2000, date: DateTime(2026, 5, 9))
        ],
      );
      // originalAmount defaults to amount (3000), so fall back to 3000+2000.
      expect(e.totalAccrued, 5000);
    });

    test('zero accrual does not divide by zero', () {
      expect(accrual(amount: 0, originalAmount: 0).progressPct, 0);
    });
  });

  group('due dates and overdue', () {
    test('no due date is never overdue', () {
      expect(accrual().isOverdue, isFalse);
      expect(accrual().daysUntilDue, isNull);
    });

    test('past due with money owed is overdue', () {
      final e = accrual(
          dueDate: DateTime.now().subtract(const Duration(days: 3)));
      expect(e.isOverdue, isTrue);
      expect(e.daysUntilDue, lessThan(0));
    });

    test('a settled accrual is never overdue', () {
      final e = accrual(
        amount: 0,
        status: AccruedExpenseStatus.settled,
        dueDate: DateTime.now().subtract(const Duration(days: 30)),
      );
      expect(e.isOverdue, isFalse);
    });

    test('dueSoon flags the coming week but not the far future', () {
      final soon =
          accrual(dueDate: DateTime.now().add(const Duration(days: 3)));
      final later =
          accrual(dueDate: DateTime.now().add(const Duration(days: 40)));
      expect(soon.dueSoon(), isTrue);
      expect(later.dueSoon(), isFalse);
    });

    test('overdue is not also "due soon"', () {
      final e =
          accrual(dueDate: DateTime.now().subtract(const Duration(days: 2)));
      expect(e.dueSoon(), isFalse);
    });
  });

  group('monthly recurrence', () {
    final template = accrual(
      amount: 5000,
      originalAmount: 5000,
      accrualDate: DateTime(2026, 6, 1),
      dueDate: DateTime(2026, 6, 28),
      categoryId: 'cat_rent',
      recurrence: AccrualRecurrence.monthly,
      payments: [
        AccruedExpensePayment(
            id: 'p1', amount: 5000, date: DateTime(2026, 6, 20))
      ],
    );

    test('rolls dates forward one month', () {
      final next = template.nextRecurrence(id: 'n1');
      expect(next.accrualDate, DateTime(2026, 7, 1));
      expect(next.dueDate, DateTime(2026, 7, 28));
      expect(next.periodKey, '2026-07');
    });

    test('resets the balance and clears payments', () {
      final next = template.nextRecurrence(id: 'n1');
      expect(next.amount, 5000); // owed again, in full
      expect(next.payments, isEmpty);
      expect(next.totalPaid, 0);
    });

    test('carries category and links back to its source', () {
      final next = template.nextRecurrence(id: 'n1');
      expect(next.categoryId, 'cat_rent');
      expect(next.recurringSourceId, 'a1');
    });

    test('children do not themselves recur (no runaway generation)', () {
      final next = template.nextRecurrence(id: 'n1');
      expect(next.isRecurring, isFalse);
      // A grandchild still points at the original template.
      expect(next.nextRecurrence(id: 'n2').recurringSourceId, 'a1');
    });

    test('year rolls over correctly', () {
      final dec = accrual(
        accrualDate: DateTime(2026, 12, 1),
        dueDate: DateTime(2026, 12, 31),
        recurrence: AccrualRecurrence.monthly,
      );
      final next = dec.nextRecurrence(id: 'n');
      expect(next.accrualDate, DateTime(2027, 1, 1));
      expect(next.periodKey, '2027-01');
    });
  });

  group('settlement state', () {
    test('outstanding balance means not settled', () {
      expect(accrual(amount: 100).isSettled, isFalse);
    });
    test('zero outstanding counts as settled', () {
      expect(accrual(amount: 0).isSettled, isTrue);
    });
  });

  group('serialization round-trip', () {
    test('keeps the new fields', () {
      final e = accrual(
        amount: 3000,
        originalAmount: 5000,
        accrualDate: DateTime(2026, 6, 30),
        dueDate: DateTime(2026, 7, 15),
        categoryId: 'cat_utilities',
        recurrence: AccrualRecurrence.monthly,
      );
      final back = AccruedExpense.fromJson(e.toJson());
      expect(back.originalAmount, 5000);
      expect(back.accrualDate, DateTime(2026, 6, 30));
      expect(back.dueDate, DateTime(2026, 7, 15));
      expect(back.categoryId, 'cat_utilities');
      expect(back.recurrence, AccrualRecurrence.monthly);
      expect(back.periodKey, '2026-06');
    });
  });
}
