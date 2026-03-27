class TotalMoneyDayDeltaEntry {
  final int? id;
  final int dayId;
  final int tagId;
  final double amount;
  final bool autoBalanced;

  const TotalMoneyDayDeltaEntry({
    this.id,
    required this.dayId,
    required this.tagId,
    required this.amount,
    this.autoBalanced = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'dayId': dayId,
      'tagId': tagId,
      'amount': amount,
      'autoBalanced': autoBalanced ? 1 : 0,
    };
  }

  factory TotalMoneyDayDeltaEntry.fromMap(Map<String, dynamic> map) {
    return TotalMoneyDayDeltaEntry(
      id: map['id'] as int?,
      dayId: map['dayId'] as int,
      tagId: map['tagId'] as int,
      amount: (map['amount'] as num).toDouble(),
      autoBalanced: ((map['autoBalanced'] as num?) ?? 0) > 0,
    );
  }
}

class CategoryAllocation {
  final int tagId;
  final String categoryName;
  final double amount;
  final bool autoBalanced;

  const CategoryAllocation({
    required this.tagId,
    required this.categoryName,
    required this.amount,
    this.autoBalanced = false,
  });
}

class DayDeltaBreakdown {
  final double netDelta;
  final List<CategoryAllocation> incomeCategories;
  final List<CategoryAllocation> expenseCategories;

  const DayDeltaBreakdown({
    required this.netDelta,
    required this.incomeCategories,
    required this.expenseCategories,
  });

  double get totalIncome => incomeCategories.fold(0.0, (s, c) => s + c.amount);

  double get totalExpenses => expenseCategories.fold(0.0, (s, c) => s + c.amount);

  double get unallocated => netDelta - (totalIncome - totalExpenses);
}

class DayDeltaCategorySummary {
  final int dayId;
  final double totalIncome;
  final double totalExpenses;
  final int totalCategories;

  const DayDeltaCategorySummary({
    required this.dayId,
    required this.totalIncome,
    required this.totalExpenses,
    required this.totalCategories,
  });

  bool get hasAnyCategory => totalCategories > 0;
}


