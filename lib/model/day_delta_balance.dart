import 'dart:math' as math;

class DayDeltaAutoBalance {
  final double income;
  final double expenses;

  const DayDeltaAutoBalance({required this.income, required this.expenses});
}

/// Fills only the side indicated by [delta].
///
/// Existing income and expense categories are independent. In particular, an
/// expense must never increase the automatically generated income amount (and
/// vice versa).
DayDeltaAutoBalance calculateDayDeltaAutoBalance({
  required double delta,
  required double manualIncome,
  required double manualExpenses,
}) {
  if (delta > 0) {
    return DayDeltaAutoBalance(
      income: math.max(0.0, delta - manualIncome),
      expenses: 0,
    );
  }
  if (delta < 0) {
    return DayDeltaAutoBalance(
      income: 0,
      expenses: math.max(0.0, -delta - manualExpenses),
    );
  }
  return const DayDeltaAutoBalance(income: 0, expenses: 0);
}

double dayDeltaUnallocated({
  required double delta,
  required double totalIncome,
  required double totalExpenses,
}) {
  if (delta > 0) return delta - totalIncome;
  if (delta < 0) return delta + totalExpenses;
  return 0;
}
