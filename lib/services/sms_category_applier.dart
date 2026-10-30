import 'dart:convert';

import 'package:money_traker/data/database_helper.dart';
import 'package:money_traker/domain/entities/transaction_entity.dart';
import 'package:money_traker/model/tag.dart';
import 'package:money_traker/services/manual_category_guard.dart';
import 'package:money_traker/sms/sms_category_plan.dart';
import 'package:money_traker/sms/sms_models.dart';
import 'package:money_traker/sms/sms_rule_engine.dart';
import 'package:money_traker/store/money_storage.dart';

class SmsCategoryChoice {
  final SmsCategoryRule rule;
  final Tag tag;
  final bool reduces;

  const SmsCategoryChoice({
    required this.rule,
    required this.tag,
    required this.reduces,
  });
}

class SmsCategoryApplier {
  SmsCategoryApplier._();
  static final SmsCategoryApplier instance = SmsCategoryApplier._();

  final _storage = MoneyStorage();
  final _db = DatabaseHelper.instance;

  SmsCategoryChoice? match({
    required String body,
    required bool debit,
    required List<SmsCategoryRule> rules,
    required List<Tag> tags,
  }) {
    final byId = <int, Tag>{for (final tag in tags) if (tag.id != null) tag.id!: tag};
    for (final rule in SmsRuleEngine.rankCategoryRules(body, rules)) {
      final tag = byId[rule.tagId];
      if (tag == null) continue;
      final expense = tag.type == TagType.expense;
      return SmsCategoryChoice(rule: rule, tag: tag, reduces: expense != debit);
    }
    return null;
  }

  Future<void> syncAll({String? bankId}) async {
    final rules = await _db.getSmsCategoryRules();
    final tags = await _storage.getTags();
    final copies = await _db.getSmsCopies();
    final transactions = await _db.getAllTransactions();
    final bySmsId = <String, TransactionEntity>{};
    for (final transaction in transactions) {
      final smsId = transaction.smsId;
      if (smsId != null && smsId.isNotEmpty) bySmsId[smsId] = transaction;
    }

    final bankCopies = [
      for (final copy in copies)
        if (bankId == null || copy.bankId == bankId) copy,
    ];
    final relevant = <TransactionEntity>[];
    for (final copy in bankCopies) {
      final transaction = bySmsId[copy.smsId];
      if (transaction?.id != null) relevant.add(transaction!);
    }

    final historyDays = await _storage.getTotalMoneyDays();
    bool historyHasDay(DateTime day) {
      for (final item in historyDays) {
        if (item.date.year == day.year && item.date.month == day.month && item.date.day == day.day) {
          return true;
        }
      }
      return false;
    }

    final handPicked = await ManualCategoryGuard.ids();
    final planned = <int>{};
    final choiceById = <int, SmsCategoryChoice>{};
    for (final copy in bankCopies) {
      if (!copy.sourceApplied || copy.smsId.isEmpty) continue;
      final transaction = bySmsId[copy.smsId];
      final id = transaction?.id;
      if (transaction == null || id == null || transaction.amount <= categoryAmountEpsilon) continue;
      final bankRules = rules.where((rule) => rule.bankId == copy.bankId).toList();
      final choice = match(
        body: copy.body,
        debit: transaction.type == TransactionType.debit,
        rules: bankRules,
        tags: tags,
      );
      if (choice == null) continue;
      choiceById[id] = choice;
      final day = categoryDay(copy.date);
      if (!choice.reduces && !historyHasDay(day)) continue;
      planned.add(id);
    }

    final previousByTag = <int, Map<DateTime, double>>{};
    final previousEncoded = <int, String>{};
    for (final transaction in relevant) {
      final id = transaction.id;
      final tagId = transaction.categoryTagId;
      if (id == null || tagId == null) continue;
      if (keepHandPickedCategory(handPicked: handPicked.contains(id), rulePlanned: planned.contains(id))) {
        continue;
      }
      final slices = slicesFromTransaction(transaction);
      final encoded = encodeCategoryAllocations(slices);
      if (encoded == null) continue;
      previousEncoded[id] = encoded;
      final totals = previousByTag.putIfAbsent(tagId, () => {});
      for (final entry in sumCategorySlices(slices).entries) {
        totals[entry.key] = (totals[entry.key] ?? 0) + entry.value;
      }
    }

    final events = <SmsCategoryEvent>[];
    for (final copy in bankCopies) {
      if (!copy.sourceApplied || copy.smsId.isEmpty) continue;
      final transaction = bySmsId[copy.smsId];
      final id = transaction?.id;
      final choice = id == null ? null : choiceById[id];
      if (transaction == null || id == null || choice == null || !planned.contains(id)) continue;
      events.add(
        SmsCategoryEvent(
          transactionId: id,
          day: categoryDay(copy.date),
          tagId: choice.rule.tagId,
          amount: transaction.amount,
          addition: !choice.reduces,
        ),
      );
    }

    final tagIds = <int>{
      ...previousByTag.keys,
      for (final event in events) event.tagId,
    };
    final openingByTag = <int, Map<DateTime, double>>{};
    for (final tagId in tagIds) {
      final current = await _storage.amountsForTag(tagId);
      openingByTag[tagId] = manualCategoryBalances(
        current: current,
        previousSms: previousByTag[tagId] ?? const {},
      );
    }

    final plans = {
      for (final plan in planSmsCategories(events: events, openingByTag: openingByTag))
        plan.transactionId: plan,
    };
    final nextByTag = <int, Map<DateTime, double>>{};
    for (final plan in plans.values) {
      final totals = nextByTag.putIfAbsent(plan.tagId, () => {});
      for (final entry in sumCategorySlices(plan.slices).entries) {
        totals[entry.key] = (totals[entry.key] ?? 0) + entry.value;
      }
    }

    for (final tagId in tagIds) {
      final deltas = categoryBalanceDeltas(
        previousSms: previousByTag[tagId] ?? const {},
        nextSms: nextByTag[tagId] ?? const {},
      );
      for (final delta in deltas.entries) {
        await _storage.adjustCategorizedAmount(
          date: delta.key,
          tagId: tagId,
          delta: delta.value,
        );
      }
    }

    for (final transaction in relevant) {
      final id = transaction.id;
      if (id == null) continue;
      if (keepHandPickedCategory(handPicked: handPicked.contains(id), rulePlanned: planned.contains(id))) {
        continue;
      }
      final plan = plans[id];
      final encoded = plan == null ? null : encodeCategoryAllocations(plan.slices);
      final signed = plan == null || plan.slices.isEmpty ? null : plan.signed;
      final tagId = plan == null || plan.slices.isEmpty ? null : plan.tagId;
      final previous = previousEncoded[id];
      final sameTag = transaction.categoryTagId == tagId;
      final sameAmount = _sameAmount(transaction.categoryAmount, signed);
      final sameSlices = previous == encoded || (previous == null && encoded == null);
      if (sameTag && sameAmount && sameSlices) continue;
      await _db.setTransactionCategory(id, tagId: tagId, amount: signed, allocations: encoded);
    }
    await ManualCategoryGuard.forgetAll(planned);
  }

  bool _sameAmount(double? a, double? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return (a - b).abs() <= categoryAmountEpsilon;
  }
}

List<SmsCategorySlice> slicesFromTransaction(TransactionEntity transaction) {
  final raw = transaction.categoryAllocations;
  if (raw != null) return decodeCategoryAllocations(raw);
  final amount = transaction.categoryAmount;
  if (transaction.categoryTagId != null && amount != null && amount > categoryAmountEpsilon) {
    return [SmsCategorySlice(day: categoryDay(transaction.date), delta: amount)];
  }
  return const [];
}

String? encodeCategoryAllocations(List<SmsCategorySlice> slices) {
  if (slices.isEmpty) return null;
  final sorted = [...slices]..sort((a, b) => a.day.compareTo(b.day));
  return jsonEncode([
    for (final slice in sorted)
      {
        'day': categoryDay(slice.day).millisecondsSinceEpoch,
        'delta': slice.delta,
      },
  ]);
}

List<SmsCategorySlice> decodeCategoryAllocations(String raw) {
  if (raw.trim().isEmpty) return const [];
  final decoded = jsonDecode(raw);
  if (decoded is! List) return const [];
  final slices = <SmsCategorySlice>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    final dayMillis = item['day'];
    final delta = item['delta'];
    if (dayMillis is! num || delta is! num) continue;
    if (delta.toDouble().abs() <= categoryAmountEpsilon) continue;
    slices.add(
      SmsCategorySlice(
        day: categoryDay(DateTime.fromMillisecondsSinceEpoch(dayMillis.toInt())),
        delta: delta.toDouble(),
      ),
    );
  }
  return slices;
}
