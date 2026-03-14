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

  factory RecurringTransaction.fromJson(Map<String, dynamic> json) {
    return RecurringTransaction(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      isIncome: json['is_income'] as bool? ?? false,
      frequency: RecurrenceFrequency.values.firstWhere(
        (f) => f.name == (json['frequency'] as String? ?? 'monthly'),
        orElse: () => RecurrenceFrequency.monthly,
      ),
      nextDueDate: json['next_due_date'] != null
          ? DateTime.parse(json['next_due_date'] as String)
          : DateTime.now(),
      category: json['category'] as String?,
      note: json['note'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'amount': amount,
    'is_income': isIncome,
    'frequency': frequency.name,
    'next_due_date': nextDueDate.toIso8601String(),
    if (category != null) 'category': category,
    if (note != null) 'note': note,
    'is_active': isActive,
  };
}
