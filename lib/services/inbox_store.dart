import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:money_traker/data/database_helper.dart';
import 'package:money_traker/domain/entities/transaction_entity.dart';
import 'package:money_traker/model/tag.dart';
import 'package:money_traker/services/app_update.dart';
import 'package:money_traker/services/category_suggestions.dart';
import 'package:money_traker/services/inbox_logic.dart';
import 'package:money_traker/services/transaction_category_assigner.dart';
import 'package:money_traker/store/money_storage.dart';

class InboxStore extends ChangeNotifier {
  InboxStore._();
  static final InboxStore instance = InboxStore._();

  static const _itemsKey = 'inbox.items';
  static const _seenKey = 'inbox.seen_ids';
  static const _seededKey = 'inbox.seeded';

  final _storage = MoneyStorage();
  final _db = DatabaseHelper.instance;

  List<InboxItem> items = const [];
  bool _loaded = false;
  bool _seeded = false;
  Set<int> _seen = {};
  Future<void> _tail = Future<void>.value();

  int get unreadCount => unreadCountOf(items);

  Future<void> ensureLoaded() {
    return _serial(() async {
      if (_loaded) return;
      await _read();
      _loaded = true;
      notifyListeners();
    });
  }

  Future<List<TransactionEntity>> recordBankArrivals(
    List<TransactionEntity> transactions, {
    Set<int>? baselineIds,
  }) {
    return _serial(() async {
      if (!_loaded) {
        await _read();
        _loaded = true;
      }
      final tags = await _loadTags();
      final usage = await _popularity();
      final plan = planBankArrivals(
        seeded: _seeded,
        seenIds: _seen,
        items: items,
        transactions: transactions,
        baselineIds: baselineIds,
        now: DateTime.now(),
        suggestionsFor: (transaction) => suggestionsForTransaction(
          transaction: transaction,
          tags: tags,
          usageByTagId: usage,
        ),
      );
      _seeded = plan.seeded;
      _seen = plan.seenIds;
      items = plan.items;
      await _write();
      notifyListeners();
      return plan.fresh;
    });
  }

  Future<void> syncUpdateOffer(UpdateOffer? offer) {
    return _serial(() async {
      if (!_loaded) {
        await _read();
        _loaded = true;
      }
      final card = offer == null
          ? null
          : InboxItem(
              id: updateInboxId(offer.version, offer.buildNumber),
              kind: InboxKind.update,
              createdAt: DateTime.now(),
              read: false,
              version: offer.version,
              buildNumber: offer.buildNumber,
              downloadUrl: offer.downloadUrl,
              changelog: offer.changelog,
              force: offer.force,
            );
      items = planUpdateOffer(items, offer: card);
      await _write();
      notifyListeners();
    });
  }

  Future<void> markAllRead() {
    return _serial(() async {
      if (!_loaded) {
        await _read();
        _loaded = true;
      }
      final next = markInboxRead(items);
      final changed = next.length != items.length ||
          next.asMap().entries.any((entry) => entry.value.read != items[entry.key].read);
      items = next;
      if (changed) await _write();
      notifyListeners();
    });
  }

  Future<void> chooseCategory(String itemId, SuggestedCategory choice) {
    return _serial(() async {
      if (!_loaded) {
        await _read();
        _loaded = true;
      }
      final index = items.indexWhere((item) => item.id == itemId);
      if (index < 0) return;
      final item = items[index];
      final transactionId = item.transactionId;
      if (transactionId == null || choice.name.trim().isEmpty) return;
      final transaction = await _db.getTransactionById(transactionId);
      if (transaction == null) {
        throw StateError('Transaction is no longer saved');
      }
      final tag = await TransactionCategoryAssigner.instance.assign(
        transaction: transaction,
        name: choice.name,
        type: choice.type,
      );
      final next = [...items];
      next[index] = item.copyWith(needsCategory: false, chosenName: tag.name);
      items = next;
      await _write();
      notifyListeners();
    });
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<List<Tag>> _loadTags() async {
    try {
      return await _storage.getTags();
    } catch (e) {
      debugPrint('Inbox categories unavailable: $e');
      return const [];
    }
  }

  Future<Map<int, int>> _popularity() async {
    final usage = <int, int>{};
    try {
      final fromDays = await _storage.tagUsageCounts();
      final fromTransactions = await _db.transactionCategoryCounts();
      usage.addAll(fromDays);
      for (final entry in fromTransactions.entries) {
        usage[entry.key] = (usage[entry.key] ?? 0) + entry.value;
      }
    } catch (e) {
      debugPrint('Inbox category ranking unavailable: $e');
    }
    return usage;
  }

  Future<void> _read() async {
    final prefs = await SharedPreferences.getInstance();
    _seeded = prefs.getBool(_seededKey) ?? false;
    _seen = (prefs.getStringList(_seenKey) ?? const <String>[]).map(int.tryParse).whereType<int>().toSet();
    final raw = prefs.getString(_itemsKey);
    if (raw == null || raw.isEmpty) {
      items = const [];
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        items = const [];
        return;
      }
      items = [
        for (final item in decoded)
          if (item is Map) InboxItem.fromJson(Map<String, dynamic>.from(item)),
      ].where((item) => item.id.isNotEmpty).toList();
    } catch (e) {
      debugPrint('Inbox file was not valid: $e');
      items = const [];
    }
  }

  Future<void> _write() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seededKey, _seeded);
    final seen = [for (final id in _seen) '$id']..sort();
    await prefs.setStringList(_seenKey, seen);
    await prefs.setString(_itemsKey, jsonEncode([for (final item in items) item.toJson()]));
  }
}
