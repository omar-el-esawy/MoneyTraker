import 'package:money_traker/domain/entities/transaction_entity.dart';
import 'package:money_traker/model/tag.dart';
import 'package:money_traker/services/category_suggestions.dart';

enum InboxKind { transaction, update }

class InboxItem {
  final String id;
  final InboxKind kind;
  final DateTime createdAt;
  final bool read;
  final DateTime? occurredAt;
  final int? transactionId;
  final String? bank;
  final double? amount;
  final bool? debit;
  final String? preview;
  final bool needsCategory;
  final List<SuggestedCategory> suggestions;
  final String? chosenName;
  final String? version;
  final int? buildNumber;
  final String? downloadUrl;
  final String? changelog;
  final bool force;

  const InboxItem({
    required this.id,
    required this.kind,
    required this.createdAt,
    required this.read,
    this.occurredAt,
    this.transactionId,
    this.bank,
    this.amount,
    this.debit,
    this.preview,
    this.needsCategory = false,
    this.suggestions = const [],
    this.chosenName,
    this.version,
    this.buildNumber,
    this.downloadUrl,
    this.changelog,
    this.force = false,
  });

  InboxItem copyWith({
    bool? read,
    bool? needsCategory,
    String? chosenName,
    bool clearChosenName = false,
  }) {
    return InboxItem(
      id: id,
      kind: kind,
      createdAt: createdAt,
      read: read ?? this.read,
      occurredAt: occurredAt,
      transactionId: transactionId,
      bank: bank,
      amount: amount,
      debit: debit,
      preview: preview,
      needsCategory: needsCategory ?? this.needsCategory,
      suggestions: suggestions,
      chosenName: clearChosenName ? null : (chosenName ?? this.chosenName),
      version: version,
      buildNumber: buildNumber,
      downloadUrl: downloadUrl,
      changelog: changelog,
      force: force,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'read': read,
        'occurredAt': occurredAt?.millisecondsSinceEpoch,
        'transactionId': transactionId,
        'bank': bank,
        'amount': amount,
        'debit': debit,
        'preview': preview,
        'needsCategory': needsCategory,
        'suggestions': [for (final item in suggestions) item.toJson()],
        'chosenName': chosenName,
        'version': version,
        'buildNumber': buildNumber,
        'downloadUrl': downloadUrl,
        'changelog': changelog,
        'force': force,
      };

  factory InboxItem.fromJson(Map<String, dynamic> json) {
    final suggestions = <SuggestedCategory>[];
    final rawSuggestions = json['suggestions'];
    if (rawSuggestions is List) {
      for (final item in rawSuggestions) {
        if (item is Map) {
          suggestions.add(SuggestedCategory.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return InboxItem(
      id: json['id']?.toString() ?? '',
      kind: json['kind'] == InboxKind.update.name ? InboxKind.update : InboxKind.transaction,
      createdAt: DateTime.fromMillisecondsSinceEpoch((json['createdAt'] as num?)?.toInt() ?? 0),
      read: json['read'] == true,
      occurredAt: json['occurredAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch((json['occurredAt'] as num).toInt()),
      transactionId: (json['transactionId'] as num?)?.toInt(),
      bank: json['bank']?.toString(),
      amount: (json['amount'] as num?)?.toDouble(),
      debit: json['debit'] is bool ? json['debit'] as bool : null,
      preview: json['preview']?.toString(),
      needsCategory: json['needsCategory'] == true,
      suggestions: suggestions,
      chosenName: json['chosenName']?.toString(),
      version: json['version']?.toString(),
      buildNumber: (json['buildNumber'] as num?)?.toInt(),
      downloadUrl: json['downloadUrl']?.toString(),
      changelog: json['changelog']?.toString(),
      force: json['force'] == true,
    );
  }
}

class ArrivalPlan {
  final bool seeded;
  final Set<int> seenIds;
  final List<InboxItem> items;
  final List<TransactionEntity> fresh;

  const ArrivalPlan({
    required this.seeded,
    required this.seenIds,
    required this.items,
    required this.fresh,
  });
}

const inboxItemLimit = 40;

int unreadCountOf(List<InboxItem> items) => items.where((item) => !item.read).length;

List<InboxItem> markInboxRead(List<InboxItem> items) {
  return [
    for (final item in items) item.read ? item : item.copyWith(read: true),
  ];
}

String smsPreview(String raw) {
  final line = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (line.length <= 90) return line;
  return '${line.substring(0, 87)}...';
}

String updateInboxId(String version, int? buildNumber) => 'update-$version-${buildNumber ?? 0}';

InboxItem transactionNotice({
  required TransactionEntity transaction,
  required List<SuggestedCategory> suggestions,
  required DateTime now,
}) {
  final id = transaction.id!;
  final needsCategory = transaction.categoryTagId == null && transaction.amount.abs() > 0;
  return InboxItem(
    id: 'tx-$id',
    kind: InboxKind.transaction,
    createdAt: now,
    read: false,
    occurredAt: transaction.date,
    transactionId: id,
    bank: transaction.bank,
    amount: transaction.amount,
    debit: transaction.type == TransactionType.debit,
    preview: smsPreview(transaction.rawSms),
    needsCategory: needsCategory,
    suggestions: needsCategory ? suggestions : const [],
  );
}

List<InboxItem> capInbox(List<InboxItem> items) {
  if (items.length <= inboxItemLimit) return items;
  return items.take(inboxItemLimit).toList();
}

/// The first snapshot remembers transfers that were already saved.
/// [baselineIds] are the ids from before this sync, so a transfer that
/// arrives during that sync still shows up. An empty baseline means this
/// is the first import, and that history stays out of the bell.
ArrivalPlan planBankArrivals({
  required bool seeded,
  required Set<int> seenIds,
  required List<InboxItem> items,
  required List<TransactionEntity> transactions,
  required List<SuggestedCategory> Function(TransactionEntity transaction) suggestionsFor,
  required DateTime now,
  Set<int>? baselineIds,
}) {
  final known = {for (final transaction in transactions) if (transaction.id != null) transaction.id!};
  var remembered = seenIds;
  if (!seeded) {
    final baseline = baselineIds ?? known;
    if (baseline.isEmpty) {
      return ArrivalPlan(
        seeded: true,
        seenIds: known,
        items: items,
        fresh: const [],
      );
    }
    remembered = baseline;
  }

  final arrivals = transactions.where((transaction) {
    final id = transaction.id;
    return id != null && !remembered.contains(id);
  }).toList()
    ..sort((a, b) => b.date.compareTo(a.date));

  if (arrivals.isEmpty) {
    return ArrivalPlan(seeded: true, seenIds: remembered, items: items, fresh: const []);
  }

  final notices = [
    for (final transaction in arrivals)
      transactionNotice(
        transaction: transaction,
        suggestions: suggestionsFor(transaction),
        now: now,
      ),
  ];
  return ArrivalPlan(
    seeded: true,
    seenIds: {...remembered, ...known},
    items: capInbox([...notices, ...items]),
    fresh: arrivals,
  );
}

List<SuggestedCategory> suggestionsForTransaction({
  required TransactionEntity transaction,
  required List<Tag> tags,
  required Map<int, int> usageByTagId,
}) {
  if (transaction.categoryTagId != null || transaction.amount.abs() == 0) return const [];
  final type = transaction.type == TransactionType.debit ? TagType.expense : TagType.income;
  return suggestFamousCategories(type: type, tags: tags, usageByTagId: usageByTagId);
}

/// [offer] null means the installed app is current, so update cards go away.
/// The same offer keeps its read state.
List<InboxItem> planUpdateOffer(List<InboxItem> items, {InboxItem? offer}) {
  final rest = [for (final item in items) if (item.kind != InboxKind.update) item];
  if (offer == null) return rest;
  for (final item in items) {
    if (item.id == offer.id) return capInbox([item, ...rest]);
  }
  return capInbox([offer, ...rest]);
}
