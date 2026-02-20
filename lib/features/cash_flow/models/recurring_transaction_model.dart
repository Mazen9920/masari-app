enum RecurrenceFrequency {
  weekly,
  monthly,
  yearly,
}

class RecurringTransaction {
  final String id;
  final String title;
  final double amount;
  final bool isIncome;
  final RecurrenceFrequency frequency;
  final DateTime nextDueDate;
  final String? category;
  final String? note;
  final bool isActive;

  const RecurringTransaction({
    required this.id,
    required this.title,
    required this.amount,
    required this.isIncome,
    required this.frequency,
    required this.nextDueDate,
    this.category,
    this.note,
    this.isActive = true,
  });

  RecurringTransaction copyWith({
    String? id,
    String? title,
    double? amount,
    bool? isIncome,
    RecurrenceFrequency? frequency,
    DateTime? nextDueDate,
    String? category,
    String? note,
    bool? isActive,
  }) {
    return RecurringTransaction(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      isIncome: isIncome ?? this.isIncome,
      frequency: frequency ?? this.frequency,
      nextDueDate: nextDueDate ?? this.nextDueDate,
      category: category ?? this.category,
      note: note ?? this.note,
      isActive: isActive ?? this.isActive,
    );
  }
}
