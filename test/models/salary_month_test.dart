import 'package:flutter_test/flutter_test.dart';
import 'package:revvo_app/shared/models/salary_model.dart';

Salary emp({
  double monthly = 10000,
  DateTime? start,
  DateTime? end,
  List<SalaryPayment> payments = const [],
}) =>
    Salary(
      id: 'e1',
      employeeName: 'Test',
      type: SalaryType.fullTime,
      monthlySalary: monthly,
      startDate: start ?? DateTime(2026, 1, 1),
      endDate: end,
      createdAt: DateTime(2026, 1, 1),
      payments: payments,
    );

SalaryPayment pay(double amount, DateTime date) =>
    SalaryPayment(id: 'p$amount$date', amount: amount, date: date);

void main() {
  final june = DateTime(2026, 6, 1);

  group('paidInMonth — only counts that month', () {
    test('sums multiple payments inside the month', () {
      final s = emp(payments: [
        pay(4000, DateTime(2026, 6, 5)),
        pay(2000, DateTime(2026, 6, 20)),
      ]);
      expect(s.paidInMonth(june), 6000);
    });

    test('ignores other months (the all-time-vs-month bug)', () {
      final s = emp(payments: [
        pay(10000, DateTime(2026, 5, 28)), // May — must not leak into June
        pay(3000, DateTime(2026, 6, 3)),
        pay(9999, DateTime(2026, 7, 1)), // July
      ]);
      expect(s.paidInMonth(june), 3000);
    });

    test('no payments → 0', () {
      expect(emp().paidInMonth(june), 0);
    });
  });

  group('remainingForMonth', () {
    test('unpaid month leaves the full salary due', () {
      expect(emp().remainingForMonth(june), 10000);
    });

    test('partial payment leaves the balance', () {
      final s = emp(payments: [pay(4000, DateTime(2026, 6, 5))]);
      expect(s.remainingForMonth(june), 6000);
    });

    test('overpayment clamps to 0, never negative', () {
      final s = emp(payments: [pay(12000, DateTime(2026, 6, 5))]);
      expect(s.remainingForMonth(june), 0);
    });
  });

  group('employment window', () {
    test('nothing due before the employee starts', () {
      final s = emp(start: DateTime(2026, 8, 1));
      expect(s.isEmployedInMonth(june), isFalse);
      expect(s.dueForMonth(june), 0);
      expect(s.remainingForMonth(june), 0);
      expect(s.statusForMonth(june), MonthPayStatus.notEmployed);
    });

    test('nothing due after they leave', () {
      final s = emp(end: DateTime(2026, 4, 30));
      expect(s.isEmployedInMonth(june), isFalse);
      expect(s.dueForMonth(june), 0);
    });

    test('the leaving month itself still counts', () {
      final s = emp(end: DateTime(2026, 6, 15));
      expect(s.isEmployedInMonth(june), isTrue);
      expect(s.dueForMonth(june), 10000);
    });

    test('the starting month itself counts', () {
      final s = emp(start: DateTime(2026, 6, 20));
      expect(s.isEmployedInMonth(june), isTrue);
    });
  });

  group('statusForMonth', () {
    test('unpaid when nothing paid', () {
      expect(emp().statusForMonth(june), MonthPayStatus.unpaid);
    });
    test('partial when some paid', () {
      final s = emp(payments: [pay(1, DateTime(2026, 6, 2))]);
      expect(s.statusForMonth(june), MonthPayStatus.partial);
    });
    test('paid when fully settled', () {
      final s = emp(payments: [pay(10000, DateTime(2026, 6, 2))]);
      expect(s.statusForMonth(june), MonthPayStatus.paid);
    });
    test('last-month payment does not mark this month paid', () {
      final s = emp(payments: [pay(10000, DateTime(2026, 5, 30))]);
      expect(s.statusForMonth(june), MonthPayStatus.unpaid);
    });
  });

  group('past months keep their own dues (month navigator)', () {
    final may = DateTime(2026, 5, 1);
    final april = DateTime(2026, 4, 1);

    // Paid April in full, skipped May, part-paid June.
    final s = emp(payments: [
      pay(10000, DateTime(2026, 4, 28)),
      pay(3000, DateTime(2026, 6, 10)),
    ]);

    test('a settled past month stays settled', () {
      expect(s.statusForMonth(april), MonthPayStatus.paid);
      expect(s.remainingForMonth(april), 0);
    });

    test('a skipped month still shows the full amount owed', () {
      expect(s.statusForMonth(may), MonthPayStatus.unpaid);
      expect(s.remainingForMonth(may), 10000);
    });

    test('later payments never back-fill an earlier unpaid month', () {
      // June's 3,000 must not reduce May's outstanding balance.
      expect(s.paidInMonth(may), 0);
      expect(s.remainingForMonth(june), 7000);
    });

    test('each month is independent', () {
      expect(s.paidInMonth(april), 10000);
      expect(s.paidInMonth(may), 0);
      expect(s.paidInMonth(june), 3000);
    });
  });

  group('progressForMonth', () {
    test('half paid → 0.5', () {
      final s = emp(payments: [pay(5000, DateTime(2026, 6, 5))]);
      expect(s.progressForMonth(june), 0.5);
    });
    test('never exceeds 1.0 on overpayment', () {
      final s = emp(payments: [pay(50000, DateTime(2026, 6, 5))]);
      expect(s.progressForMonth(june), 1.0);
    });
    test('zero-salary employee does not divide by zero', () {
      expect(emp(monthly: 0).progressForMonth(june), 0);
    });
  });
}
