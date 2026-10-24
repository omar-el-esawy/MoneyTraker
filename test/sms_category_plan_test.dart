import 'package:flutter_test/flutter_test.dart';
import 'package:money_traker/sms/sms_category_plan.dart';

void main() {
  final day1 = DateTime(2026, 10, 21);
  final day2 = DateTime(2026, 10, 22);

  SmsCategoryPlan? planFor(List<SmsCategoryPlan> plans, int id) {
    for (final plan in plans) {
      if (plan.transactionId == id) return plan;
    }
    return null;
  }

  test('a later refund removes an earlier charge of the same category', () {
    final plans = planSmsCategories(
      events: [
        SmsCategoryEvent(transactionId: 1, day: day1, tagId: 7, amount: 5, addition: true),
        SmsCategoryEvent(transactionId: 2, day: day2, tagId: 7, amount: 5, addition: false),
      ],
      openingByTag: const {},
    );

    final charge = planFor(plans, 1)!;
    final refund = planFor(plans, 2)!;
    expect(charge.slices.single.day, day1);
    expect(charge.slices.single.delta, 5);
    expect(refund.slices.single.day, day1);
    expect(refund.slices.single.delta, -5);
    expect(sumCategorySlices([...charge.slices, ...refund.slices]), isEmpty);
  });

  test('a refund on the same day cancels the charge even if it is listed first', () {
    final plans = planSmsCategories(
      events: [
        SmsCategoryEvent(transactionId: 2, day: day1, tagId: 7, amount: 5, addition: false),
        SmsCategoryEvent(transactionId: 1, day: day1, tagId: 7, amount: 5, addition: true),
      ],
      openingByTag: const {},
    );

    expect(planFor(plans, 2)!.slices.single.delta, -5);
    expect(sumCategorySlices(plans.expand((plan) => plan.slices)), isEmpty);
  });

  test('a refund takes the newest category days first', () {
    final plans = planSmsCategories(
      events: [
        SmsCategoryEvent(transactionId: 1, day: day1, tagId: 7, amount: 5, addition: true),
        SmsCategoryEvent(transactionId: 2, day: day2, tagId: 7, amount: 3, addition: true),
        SmsCategoryEvent(transactionId: 3, day: day2, tagId: 7, amount: 6, addition: false),
      ],
      openingByTag: const {},
    );

    final refund = planFor(plans, 3)!;
    expect(refund.slices.map((slice) => (slice.day, slice.delta)).toList(), [
      (day2, -3.0),
      (day1, -3.0),
    ]);
    expect(refund.signed, -6);
  });

  test('a refund does not cancel a later charge and does nothing when nothing was spent', () {
    final plans = planSmsCategories(
      events: [
        SmsCategoryEvent(transactionId: 1, day: day2, tagId: 7, amount: 5, addition: true),
        SmsCategoryEvent(transactionId: 2, day: day1, tagId: 7, amount: 5, addition: false),
        SmsCategoryEvent(transactionId: 3, day: day1, tagId: 8, amount: 10, addition: false),
      ],
      openingByTag: const {},
    );

    expect(planFor(plans, 2), isNull);
    expect(planFor(plans, 3), isNull);
    expect(planFor(plans, 1)!.signed, 5);
  });

  test('a refund reduces a category that was already on that day', () {
    final plans = planSmsCategories(
      events: [
        SmsCategoryEvent(transactionId: 4, day: day1, tagId: 7, amount: 10, addition: false),
      ],
      openingByTag: {
        7: {day1: 5},
      },
    );

    expect(planFor(plans, 4)!.slices.single.delta, -5);
  });

  test('recomputing the same charge and refund does not change the stored balance', () {
    final previous = <DateTime, double>{day1: 0};
    final opening = manualCategoryBalances(current: {day1: 0}, previousSms: previous);
    final plans = planSmsCategories(
      events: [
        SmsCategoryEvent(transactionId: 1, day: day1, tagId: 7, amount: 5, addition: true),
        SmsCategoryEvent(transactionId: 2, day: day1, tagId: 7, amount: 5, addition: false),
      ],
      openingByTag: {7: opening},
    );
    final next = sumCategorySlices(plans.expand((plan) => plan.slices));
    expect(categoryBalanceDeltas(previousSms: previous, nextSms: next), isEmpty);
  });
}
