import 'package:flutter_test/flutter_test.dart';
import 'package:money_traker/model/day_delta_balance.dart';

void main() {
  group('calculateDayDeltaAutoBalance', () {
    test('positive change does not consume categorized expenses', () {
      final balance = calculateDayDeltaAutoBalance(
        delta: 200,
        manualIncome: 0,
        manualExpenses: 400,
      );

      expect(balance.income, 200);
      expect(balance.expenses, 0);
    });

    test('negative change does not consume categorized income', () {
      final balance = calculateDayDeltaAutoBalance(
        delta: -200,
        manualIncome: 400,
        manualExpenses: 0,
      );

      expect(balance.income, 0);
      expect(balance.expenses, 200);
    });

    test('manual allocation reduces Others only on the same side', () {
      final balance = calculateDayDeltaAutoBalance(
        delta: 600,
        manualIncome: 400,
        manualExpenses: 300,
      );

      expect(balance.income, 200);
      expect(balance.expenses, 0);
    });

    test('uncategorized income shrinks red Others leftover', () {
      final before = calculateDayDeltaAutoBalance(
        delta: -200,
        manualIncome: 0,
        manualExpenses: 0,
      );
      final after = calculateDayDeltaAutoBalance(
        delta: -150,
        manualIncome: 0,
        manualExpenses: 0,
      );

      expect(before.income, 0);
      expect(before.expenses, 200);
      expect(after.income, 0);
      expect(after.expenses, 150);
    });

    test('uncategorized addition lands in green Others', () {
      final balance = calculateDayDeltaAutoBalance(
        delta: -200,
        manualIncome: 0,
        manualExpenses: 400,
      );

      expect(balance.income, 200);
      expect(balance.expenses, 0);
    });
  });
}
