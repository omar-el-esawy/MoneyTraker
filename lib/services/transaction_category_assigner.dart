import 'package:money_traker/data/database_helper.dart';
import 'package:money_traker/domain/entities/transaction_entity.dart';
import 'package:money_traker/model/tag.dart';
import 'package:money_traker/services/manual_category_guard.dart';
import 'package:money_traker/services/sms_category_applier.dart';
import 'package:money_traker/sms/sms_category_plan.dart';
import 'package:money_traker/store/money_storage.dart';

class TransactionCategoryAssigner {
  TransactionCategoryAssigner._();
  static final TransactionCategoryAssigner instance = TransactionCategoryAssigner._();

  final _storage = MoneyStorage();
  final _db = DatabaseHelper.instance;

  Future<Tag> assign({
    required TransactionEntity transaction,
    required String name,
    required TagType type,
  }) async {
    final id = transaction.id;
    if (id == null) {
      throw StateError('Transaction has no id');
    }
    final tag = await _storage.ensureTag(name: name, type: type);
    final tagId = tag.id;
    if (tagId == null) {
      throw StateError('Category was not saved');
    }
    final amount = transaction.amount.abs();
    final day = categoryDay(transaction.date);
    await _db.setTransactionCategory(
      id,
      tagId: tagId,
      amount: amount,
      allocations: encodeCategoryAllocations([
        SmsCategorySlice(day: day, delta: amount),
      ]),
    );
    await ManualCategoryGuard.remember(id);
    await _storage.adjustCategorizedAmount(date: day, tagId: tagId, delta: amount);
    return tag;
  }
}
