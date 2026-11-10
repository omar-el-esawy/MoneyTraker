import 'package:flutter/foundation.dart';

import 'package:money_traker/data/database_helper.dart';
import 'package:money_traker/domain/entities/transaction_entity.dart';
import 'package:money_traker/model/tag.dart';
import 'package:money_traker/services/manual_category_guard.dart';
import 'package:money_traker/services/sms_category_applier.dart';
import 'package:money_traker/sms/sms_category_plan.dart';
import 'package:money_traker/store/money_storage.dart';

typedef EnsureCategoryTag =
    Future<Tag> Function({required String name, required TagType type});

typedef AdjustCategoryAmount =
    Future<void> Function({
      required DateTime date,
      required int tagId,
      required double delta,
    });

typedef WriteTransactionCategory =
    Future<void> Function(
      int id, {
      int? tagId,
      double? amount,
      String? allocations,
    });

typedef RememberManualCategory = Future<void> Function(int id);

class TransactionCategoryAssigner {
  TransactionCategoryAssigner._()
    : this._bound(MoneyStorage(), DatabaseHelper.instance);

  TransactionCategoryAssigner._bound(MoneyStorage storage, DatabaseHelper db)
    : _ensureTag = storage.ensureTag,
      _adjustCategorizedAmount = storage.adjustCategorizedAmount,
      _setTransactionCategory = db.setTransactionCategory,
      _remember = ManualCategoryGuard.remember;

  @visibleForTesting
  TransactionCategoryAssigner.testing({
    required EnsureCategoryTag ensureTag,
    required AdjustCategoryAmount adjustCategorizedAmount,
    required WriteTransactionCategory setTransactionCategory,
    required RememberManualCategory remember,
  }) : _ensureTag = ensureTag,
       _adjustCategorizedAmount = adjustCategorizedAmount,
       _setTransactionCategory = setTransactionCategory,
       _remember = remember;

  static final TransactionCategoryAssigner instance =
      TransactionCategoryAssigner._();

  final EnsureCategoryTag _ensureTag;
  final AdjustCategoryAmount _adjustCategorizedAmount;
  final WriteTransactionCategory _setTransactionCategory;
  final RememberManualCategory _remember;

  Future<Tag> assign({
    required TransactionEntity transaction,
    required String name,
    required TagType type,
  }) async {
    final id = transaction.id;
    if (id == null) {
      throw StateError('Transaction has no id');
    }
    final tag = await _ensureTag(name: name, type: type);
    final tagId = tag.id;
    if (tagId == null) {
      throw StateError('Category was not saved');
    }
    final previousTagId = transaction.categoryTagId;
    if (previousTagId != tagId) {
      if (previousTagId != null) {
        final reversals = sumCategorySlices(
          slicesFromTransaction(transaction),
        ).entries.toList()..sort((a, b) => a.key.compareTo(b.key));
        for (final reversal in reversals) {
          await _adjustCategorizedAmount(
            date: reversal.key,
            tagId: previousTagId,
            delta: -reversal.value,
          );
        }
      }
      final amount = transaction.amount.abs();
      final day = categoryDay(transaction.date);
      await _setTransactionCategory(
        id,
        tagId: tagId,
        amount: amount,
        allocations: encodeCategoryAllocations([
          SmsCategorySlice(day: day, delta: amount),
        ]),
      );
      await _adjustCategorizedAmount(date: day, tagId: tagId, delta: amount);
    }
    await _remember(id);
    return tag;
  }

  Future<void> clear(TransactionEntity transaction) async {
    final id = transaction.id;
    if (id == null) {
      throw StateError('Transaction has no id');
    }
    final previousTagId = transaction.categoryTagId;
    if (previousTagId != null) {
      final reversals = sumCategorySlices(
        slicesFromTransaction(transaction),
      ).entries.toList()..sort((a, b) => a.key.compareTo(b.key));
      for (final reversal in reversals) {
        await _adjustCategorizedAmount(
          date: reversal.key,
          tagId: previousTagId,
          delta: -reversal.value,
        );
      }
      await _setTransactionCategory(
        id,
        tagId: null,
        amount: null,
        allocations: null,
      );
    }
    await _remember(id);
  }
}
