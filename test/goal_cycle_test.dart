import 'package:flutter_test/flutter_test.dart';
import 'package:money_traker/model/goal.dart';

Goal _goal({
  required GoalType type,
  int? monthStartDay,
  int? repeatEveryDays,
  DateTime? repeatStartDate,
  DateTime? periodStart,
  DateTime? periodEnd,
}) {
  return Goal(
    name: 'Test',
    targetAmount: 100,
    type: type,
    direction: GoalDirection.spendingLimit,
    monthStartDay: monthStartDay,
    repeatEveryDays: repeatEveryDays,
    repeatStartDate: repeatStartDate,
    periodStart: periodStart,
    periodEnd: periodEnd,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  test('repeating goal stays on its first cycle before the start date', () {
    final goal = _goal(
      type: GoalType.repeatingDays,
      repeatEveryDays: 30,
      repeatStartDate: DateTime(2026, 11, 10),
    );

    final cycle = goal.currentCycle(now: DateTime(2026, 10, 24));

    expect(cycle.range.start, DateTime(2026, 11, 10));
    expect(cycle.range.end, DateTime(2026, 12, 10));
  });

  test('repeating goal advances after the start date', () {
    final goal = _goal(
      type: GoalType.repeatingDays,
      repeatEveryDays: 14,
      repeatStartDate: DateTime(2026, 10, 1),
    );

    final cycle = goal.currentCycle(now: DateTime(2026, 10, 24));

    expect(cycle.range.start, DateTime(2026, 10, 15));
    expect(cycle.range.end, DateTime(2026, 10, 29));
  });

  test('monthly goal uses the previous window before the start day', () {
    final goal = _goal(type: GoalType.monthly, monthStartDay: 10);

    final cycle = goal.currentCycle(now: DateTime(2026, 10, 5));

    expect(cycle.range.start, DateTime(2026, 9, 10));
    expect(cycle.range.end, DateTime(2026, 10, 10));
  });

  test('fixed period includes the end date and survives an inverted range', () {
    final goal = _goal(
      type: GoalType.fixedPeriod,
      periodStart: DateTime(2026, 11, 10),
      periodEnd: DateTime(2026, 11, 1),
    );

    final cycle = goal.currentCycle(now: DateTime(2026, 10, 24));

    expect(cycle.range.start, DateTime(2026, 11, 10));
    expect(cycle.range.end.isAfter(cycle.range.start), isTrue);
  });
}
