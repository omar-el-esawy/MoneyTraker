import 'package:money_traker/model/money_source.dart';
import 'package:money_traker/model/money_source_change.dart';
import 'package:money_traker/store/money_storage.dart';

class SmsSourceApplier {
  SmsSourceApplier._();
  static final SmsSourceApplier instance = SmsSourceApplier._();

  final _storage = MoneyStorage();

  Future<bool> apply({
    required int sourceId,
    required double amount,
    required bool debit,
    required DateTime date,
    String? note,
  }) async {
    if (amount <= 0) return false;
    final sources = await _storage.getMoneySources();
    MoneySource? source;
    for (final item in sources) {
      if (item.id == sourceId) source = item;
    }
    if (source == null || source.id == null) return false;

    final delta = debit ? -amount : amount;
    final updated = source.copyWith(amount: source.amount + delta);
    await _storage.updateMoneySource(updated);
    await _storage.addMoneySourceChange(
      MoneySourceChange(
        sourceId: source.id!,
        deltaAmount: delta,
        resultingAmount: updated.amount,
        createdAt: date,
        type: debit ? MoneySourceChangeType.subtract : MoneySourceChangeType.add,
        note: note,
      ),
    );
    await _storage.applyAmountDeltaToHistory(date, delta);
    return true;
  }

  Future<bool> applySignedDelta({
    required int sourceId,
    required double delta,
    required DateTime date,
    String? note,
  }) async {
    if (delta.abs() < 0.0001) return true;
    return apply(
      sourceId: sourceId,
      amount: delta.abs(),
      debit: delta < 0,
      date: date,
      note: note,
    );
  }
}
