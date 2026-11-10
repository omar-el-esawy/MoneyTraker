import 'package:flutter_test/flutter_test.dart';
import 'package:money_traker/domain/entities/transaction_entity.dart';
import 'package:money_traker/model/tag.dart';
import 'package:money_traker/services/sms_category_applier.dart';
import 'package:money_traker/services/transaction_category_assigner.dart';
import 'package:money_traker/sms/sms_category_plan.dart';

void main() {
  final earlier = DateTime(2026, 10, 1);
  final day = DateTime(2026, 10, 2);

  test(
    'changing a category removes the old allocation and adds the new one once',
    () async {
      final ledger = <int, Map<DateTime, double>>{
        1: {earlier: 100, day: 50},
      };
      var writes = 0;
      final assigner = TransactionCategoryAssigner.testing(
        ensureTag: ({required name, required type}) async {
          return Tag(id: name == 'Food' ? 1 : 2, name: name, type: type);
        },
        adjustCategorizedAmount:
            ({required date, required tagId, required delta}) async {
              final days = ledger.putIfAbsent(tagId, () => {});
              days[date] = (days[date] ?? 0) + delta;
            },
        setTransactionCategory: (id, {tagId, amount, allocations}) async {
          writes += 1;
          expect(id, 7);
          expect(tagId, 2);
          expect(amount, 150);
        },
        remember: (id) async => expect(id, 7),
      );

      await assigner.assign(
        transaction: TransactionEntity(
          id: 7,
          bank: 'CIB',
          amount: 150,
          type: TransactionType.debit,
          date: DateTime(2026, 10, 2, 15),
          rawSms: 'Purchase for 150',
          categoryTagId: 1,
          categoryAmount: 150,
          categoryAllocations: encodeCategoryAllocations([
            SmsCategorySlice(day: earlier, delta: 100),
            SmsCategorySlice(day: day, delta: 50),
          ]),
        ),
        name: 'Rent',
        type: TagType.expense,
      );

      expect(writes, 1);
      expect(ledger[1]![earlier], 0);
      expect(ledger[1]![day], 0);
      expect(ledger[2]![day], 150);
      expect(ledger[2]!.length, 1);
    },
  );

  test('the first category is added once', () async {
    final ledger = <int, double>{};
    final assigner = TransactionCategoryAssigner.testing(
      ensureTag: ({required name, required type}) async =>
          Tag(id: 4, name: name, type: type),
      adjustCategorizedAmount:
          ({required date, required tagId, required delta}) async {
            ledger[tagId] = (ledger[tagId] ?? 0) + delta;
          },
      setTransactionCategory: (id, {tagId, amount, allocations}) async {},
      remember: (id) async {},
    );

    await assigner.assign(
      transaction: TransactionEntity(
        id: 3,
        bank: 'CIB',
        amount: 80,
        type: TransactionType.credit,
        date: day,
        rawSms: 'Salary',
      ),
      name: 'Salary',
      type: TagType.income,
    );

    expect(ledger, {4: 80});
  });

  test('choosing the same category does not add the amount again', () async {
    var adjustments = 0;
    var writes = 0;
    final assigner = TransactionCategoryAssigner.testing(
      ensureTag: ({required name, required type}) async =>
          Tag(id: 4, name: name, type: type),
      adjustCategorizedAmount:
          ({required date, required tagId, required delta}) async {
            adjustments += 1;
          },
      setTransactionCategory: (id, {tagId, amount, allocations}) async {
        writes += 1;
      },
      remember: (id) async {},
    );

    await assigner.assign(
      transaction: TransactionEntity(
        id: 3,
        bank: 'CIB',
        amount: 80,
        type: TransactionType.credit,
        date: day,
        rawSms: 'Salary',
        categoryTagId: 4,
        categoryAmount: 80,
      ),
      name: 'Salary',
      type: TagType.income,
    );

    expect(adjustments, 0);
    expect(writes, 0);
  });

  test('clearing a category removes its allocation and writes nothing', () async {
    final ledger = <int, double>{1: 150};
    var wrote = false;
    final assigner = TransactionCategoryAssigner.testing(
      ensureTag: ({required name, required type}) async =>
          Tag(id: 1, name: name, type: type),
      adjustCategorizedAmount:
          ({required date, required tagId, required delta}) async {
            ledger[tagId] = (ledger[tagId] ?? 0) + delta;
          },
      setTransactionCategory: (id, {tagId, amount, allocations}) async {
        wrote = true;
        expect(tagId, isNull);
        expect(amount, isNull);
        expect(allocations, isNull);
      },
      remember: (id) async => expect(id, 7),
    );

    await assigner.clear(
      TransactionEntity(
        id: 7,
        bank: 'CIB',
        amount: 150,
        type: TransactionType.debit,
        date: day,
        rawSms: 'Purchase for 150',
        categoryTagId: 1,
        categoryAmount: 150,
        categoryAllocations: encodeCategoryAllocations([
          SmsCategorySlice(day: day, delta: 150),
        ]),
      ),
    );

    expect(ledger[1], 0);
    expect(wrote, isTrue);
  });
}
