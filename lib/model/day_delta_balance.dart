import 'dart:math' as math;

class DayDeltaAutoBalance {
  final double income;
  final double expenses;

  const DayDeltaAutoBalance({required this.income, required this.expenses});
}

/// Fills the leftover that has no category.
///
/// A named expense must never inflate green Others when the day went up.
/// If the day still went down, extra tagged spend is balanced by green Others
/// so an uncategorized addition lands in Others instead of an unallocated warning.
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

  return DayDeltaAutoBalance(
    income: math.max(0.0, manualExpenses + delta - manualIncome),
    expenses: math.max(0.0, -delta - manualExpenses),
  );
}
