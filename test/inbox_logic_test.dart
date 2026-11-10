import 'package:flutter_test/flutter_test.dart';
import 'package:money_traker/domain/entities/transaction_entity.dart';
import 'package:money_traker/model/tag.dart';
import 'package:money_traker/services/category_suggestions.dart';
import 'package:money_traker/services/inbox_logic.dart';

TransactionEntity _tx({
  required int id,
  required TransactionType type,
  int? categoryTagId,
  String bank = 'CIB',
}) {
  return TransactionEntity(
    id: id,
    bank: bank,
    amount: 150,
    type: type,
    date: DateTime(2026, 10, id),
    rawSms: 'Purchase at the market for 150',
    categoryTagId: categoryTagId,
  );
}

void main() {
  final now = DateTime(2026, 10, 30, 12);

  test('the first snapshot does not notify for transfers already saved', () {
    final plan = planBankArrivals(
      seeded: false,
      seenIds: const {},
      items: const [],
      transactions: [_tx(id: 1, type: TransactionType.debit)],
      suggestionsFor: (_) => const [],
      now: now,
    );

    expect(plan.fresh, isEmpty);
    expect(plan.seeded, isTrue);
    expect(plan.seenIds, {1});
  });

  test('a transfer that arrives on the first sync is announced', () {
    final plan = planBankArrivals(
      seeded: false,
      seenIds: const {},
      items: const [],
      baselineIds: const {1},
      transactions: [
        _tx(id: 1, type: TransactionType.credit, categoryTagId: 3),
        _tx(id: 4, type: TransactionType.debit),
      ],
      suggestionsFor: (_) => const [
        SuggestedCategory(name: 'Food', type: TagType.expense),
        SuggestedCategory(name: 'Transport', type: TagType.expense),
        SuggestedCategory(name: 'Shopping', type: TagType.expense),
      ],
      now: now,
    );

    expect(plan.fresh.map((item) => item.id), [4]);
    expect(plan.items.single.needsCategory, isTrue);
    expect(plan.items.single.suggestions, hasLength(3));
  });

  test('a new uncategorized transfer asks for three categories', () {
    final plan = planBankArrivals(
      seeded: true,
      seenIds: const {1},
      items: const [],
      transactions: [
        _tx(id: 1, type: TransactionType.debit),
        _tx(id: 2, type: TransactionType.debit),
      ],
      suggestionsFor: (transaction) => suggestionsForTransaction(
        transaction: transaction,
        tags: const [
          Tag(id: 4, name: 'Food', type: TagType.expense),
          Tag(id: 5, name: 'Rent', type: TagType.expense),
          Tag(id: 6, name: 'Bills', type: TagType.expense),
          Tag(id: 7, name: 'Health', type: TagType.expense),
        ],
        usageByTagId: const {5: 4, 4: 1},
      ),
      hasOtherCategoriesFor: (_) => true,
      now: now,
    );

    expect(plan.fresh.map((item) => item.id), [2]);
    expect(plan.items, hasLength(1));
    final notice = plan.items.single;
    expect(notice.needsCategory, isTrue);
    expect(notice.debit, isTrue);
    expect(notice.suggestions.map((item) => item.name).toList(), [
      'Rent',
      'Food',
      'Bills',
    ]);
    expect(notice.hasOtherCategories, isTrue);
  });

  test('a transfer that already has a category does not ask again', () {
    final plan = planBankArrivals(
      seeded: true,
      seenIds: const {},
      items: const [],
      transactions: [
        _tx(id: 3, type: TransactionType.credit, categoryTagId: 9),
      ],
      suggestionsFor: (transaction) => suggestionsForTransaction(
        transaction: transaction,
        tags: const [],
        usageByTagId: const {},
      ),
      now: now,
    );

    expect(plan.items.single.needsCategory, isFalse);
    expect(plan.items.single.suggestions, isEmpty);
    expect(plan.items.single.debit, isFalse);
  });

  test(
    'an update stays in the list until a newer check says the app is current',
    () {
      final offer = InboxItem(
        id: updateInboxId('2.1.0', 3),
        kind: InboxKind.update,
        createdAt: now,
        read: true,
        version: '2.1.0',
        buildNumber: 3,
        downloadUrl: 'https://example.com/app.apk',
      );
      final transfer = InboxItem(
        id: 'tx-1',
        kind: InboxKind.transaction,
        createdAt: now,
        read: false,
      );

      final kept = planUpdateOffer([transfer], offer: offer);
      expect(kept.map((item) => item.id), [offer.id, transfer.id]);

      final again = planUpdateOffer([
        offer.copyWith(read: true),
        transfer,
      ], offer: offer.copyWith(read: false));
      expect(again.first.read, isTrue);

      final current = planUpdateOffer(again);
      expect(current.map((item) => item.id), [transfer.id]);
    },
  );

  test('opening the inbox marks every card read', () {
    final items = [
      InboxItem(
        id: 'tx-1',
        kind: InboxKind.transaction,
        createdAt: now,
        read: false,
      ),
      InboxItem(
        id: 'update-2.1.0-1',
        kind: InboxKind.update,
        createdAt: now,
        read: true,
      ),
    ];

    final next = markInboxRead(items);
    expect(unreadCountOf(items), 1);
    expect(unreadCountOf(next), 0);
    expect(next.first.id, 'tx-1');
  });

  test('skipping a category is remembered and stops the prompt', () {
    final asking = InboxItem(
      id: 'tx-8',
      kind: InboxKind.transaction,
      createdAt: now,
      read: false,
      debit: true,
      needsCategory: true,
      suggestions: const [
        SuggestedCategory(name: 'Food', type: TagType.expense),
      ],
    );

    final skipped = skipInboxCategory(asking);
    final restored = InboxItem.fromJson(skipped.toJson());

    expect(restored.categorySkipped, isTrue);
    expect(restored.needsCategory, isFalse);
    expect(restored.chosenName, isNull);
    expect(restored.suggestions.single.name, 'Food');
  });

  test(
    'an older notification without a skip flag still asks for a category',
    () {
      final restored = InboxItem.fromJson({
        'id': 'tx-8',
        'kind': 'transaction',
        'createdAt': now.millisecondsSinceEpoch,
        'read': false,
        'needsCategory': true,
      });

      expect(restored.categorySkipped, isFalse);
      expect(restored.needsCategory, isTrue);
    },
  );

  test(
    'choosing a category replaces a skipped card and skipping never clears a saved one',
    () {
      final asking = InboxItem(
        id: 'tx-9',
        kind: InboxKind.transaction,
        createdAt: now,
        read: true,
        debit: false,
        needsCategory: true,
      );

      final skipped = skipInboxCategory(asking);
      final chosen = chooseInboxCategory(skipped, 'Salary');
      expect(chosen.categorySkipped, isFalse);
      expect(chosen.needsCategory, isFalse);
      expect(chosen.chosenName, 'Salary');

      final changed = chooseInboxCategory(chosen, 'Gift');
      expect(changed.chosenName, 'Gift');
      expect(skipInboxCategory(changed).chosenName, 'Gift');
      expect(skipInboxCategory(changed).categorySkipped, isFalse);

      final undone = undoInboxCategorySkip(skipped);
      expect(undone.categorySkipped, isFalse);
      expect(undone.needsCategory, isTrue);
      expect(undoInboxCategorySkip(changed).chosenName, 'Gift');
    },
  );

  test('clearing a saved category leaves the card with no category', () {
    final saved = InboxItem(
      id: 'tx-10',
      kind: InboxKind.transaction,
      createdAt: now,
      read: true,
      debit: true,
      needsCategory: false,
      chosenName: 'Food',
    );

    final cleared = clearInboxCategory(saved);

    expect(cleared.chosenName, isNull);
    expect(cleared.categorySkipped, isTrue);
    expect(cleared.needsCategory, isFalse);
  });

  test('a category picker follows the transfer direction', () {
    final expense = InboxItem(
      id: 'tx-1',
      kind: InboxKind.transaction,
      createdAt: now,
      read: false,
      debit: true,
    );
    final credited = InboxItem(
      id: 'tx-2',
      kind: InboxKind.transaction,
      createdAt: now,
      read: false,
      debit: false,
      suggestions: const [
        SuggestedCategory(name: 'Salary', type: TagType.income),
      ],
    );
    final update = InboxItem(
      id: 'update-1',
      kind: InboxKind.update,
      createdAt: now,
      read: false,
    );

    expect(categoryTypeFor(expense), TagType.expense);
    expect(categoryTypeFor(credited), TagType.income);
    expect(categoryTypeFor(update), isNull);
  });
}
