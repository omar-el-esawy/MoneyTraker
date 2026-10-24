import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart';

import 'package:money_traker/data/database_helper.dart';
import 'package:money_traker/domain/entities/transaction_entity.dart';
import 'package:money_traker/services/sms_category_applier.dart';
import 'package:money_traker/services/sms_feature_store.dart';
import 'package:money_traker/services/sms_source_applier.dart';
import 'package:money_traker/sms/sms_hash.dart';
import 'package:money_traker/sms/sms_models.dart';
import 'package:money_traker/sms/sms_rule_engine.dart';

class SyncService {
  static const lastSyncPrefsKey = 'last_sync_time';
  SyncService._();
  static final SyncService instance = SyncService._();

  final _db = DatabaseHelper.instance;
  final _telephony = Telephony.instance;
  final _store = SmsFeatureStore.instance;

  Future<SmsSyncResult> sync({
    bool fromStartDate = false,
    String? bankId,
  }) async {
    try {
      if (!Platform.isAndroid) return SmsSyncResult.unsupported;

      var config = await _store.load();
      if (config.startDate == null) {
        return const SmsSyncResult(supported: true, permissionGranted: true);
      }
      if (!config.started) {
        config = config.copyWith(started: true);
        await _store.save(config);
      }

      final permission = await _telephony.requestSmsPermissions;
      var copied = 0;
      if (permission == true) {
        final after = fromStartDate ? config.startDate! : await _lowerBound(config.startDate!, false);
        copied = await _copyInbox(after, config, bankId: bankId);
        await _updateLastSyncTime(DateTime.now().millisecondsSinceEpoch);
      }
      final applied = await _applyRules(
        config,
        after: fromStartDate ? config.startDate : null,
        bankId: bankId,
      );
      return SmsSyncResult(
        supported: true,
        permissionGranted: permission == true,
        copied: copied,
        parsed: applied.parsed,
        appliedToSource: applied.toSource,
        skipped: applied.skipped,
        unmatched: applied.unmatched,
        missingSource: applied.missingSource,
        updated: applied.updated,
      );
    } catch (e) {
      debugPrint('Sync error: $e');
      return SmsSyncResult(
        supported: true,
        permissionGranted: true,
        error: e.toString(),
      );
    }
  }

  Future<DateTime> _lowerBound(DateTime start, bool fromStartDate) async {
    if (fromStartDate) return start;
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getInt(lastSyncPrefsKey);
    if (lastSync == null) return start;
    final lastDate = DateTime.fromMillisecondsSinceEpoch(lastSync).subtract(const Duration(minutes: 5));
    return lastDate.isBefore(start) ? start : lastDate;
  }

  Future<int> _copyInbox(DateTime after, SmsFeatureConfig config, {String? bankId}) async {
    final smsList = await _readSms(after);
    var copied = 0;
    for (final sms in smsList) {
      final smsId = sms.id?.toString();
      final body = sms.body;
      final sender = sms.address;
      if (smsId == null || body == null || sender == null) continue;
      final bank = SmsRuleEngine.matchBank(sender, config.banks);
      if (bank == null) continue;
      if (bankId != null && bank.id != bankId) continue;
      final id = await _db.insertSmsCopy(
        SmsCopy(
          smsId: smsId,
          sender: sender,
          body: body,
          date: sms.date == null ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(sms.date!),
          bankId: bank.id,
          status: SmsCopyStatus.pending,
          copiedAt: DateTime.now(),
        ),
      );
      if (id > 0) copied++;
    }
    return copied;
  }

  Future<SmsSyncResult> applyUnmarked({String? bankId}) async {
    try {
      final config = await _store.load();
      final applied = await _applyRules(
        config,
        after: config.startDate,
        bankId: bankId,
      );
      return SmsSyncResult(
        supported: true,
        permissionGranted: true,
        parsed: applied.parsed,
        appliedToSource: applied.toSource,
        skipped: applied.skipped,
        unmatched: applied.unmatched,
        missingSource: applied.missingSource,
        updated: applied.updated,
      );
    } catch (e) {
      debugPrint('Apply unmarked error: $e');
      return SmsSyncResult(
        supported: true,
        permissionGranted: true,
        error: e.toString(),
      );
    }
  }

  Future<SmsSyncResult> reprocessFromRaw({String? bankId}) async {
    try {
      var config = await _store.load();
      final applied = await _applyRules(config, bankId: bankId, reprocess: true);
      return SmsSyncResult(
        supported: true,
        permissionGranted: true,
        parsed: applied.parsed,
        appliedToSource: applied.toSource,
        skipped: applied.skipped,
        unmatched: applied.unmatched,
        missingSource: applied.missingSource,
        updated: applied.updated,
      );
    } catch (e) {
      debugPrint('Reprocess error: $e');
      return SmsSyncResult(
        supported: true,
        permissionGranted: true,
        error: e.toString(),
      );
    }
  }

  Future<({int parsed, int toSource, int skipped, int unmatched, int missingSource, int updated})> _applyRules(
    SmsFeatureConfig config, {
    DateTime? after,
    String? bankId,
    bool reprocess = false,
  }) async {
    final rules = await _db.getSmsRules();
    final typeWords = await _db.getSmsTypeWords();
    final copies = reprocess ? await _db.getRawSms(bankId: bankId) : await _db.getSmsCopies();
    final appliedCopies = {
      for (final copy in await _db.getSmsCopies()) copy.smsId: copy,
    };
    var parsed = 0;
    var toSource = 0;
    var skipped = 0;
    var unmatched = 0;
    var missingSource = 0;
    var updated = 0;
    final afterDay = after == null ? null : DateTime(after.year, after.month, after.day);

    for (final raw in copies) {
      final copy = appliedCopies[raw.smsId] ?? raw;
      if (bankId != null && copy.bankId != bankId) continue;
      if (afterDay != null) {
        final copyDay = DateTime(copy.date.year, copy.date.month, copy.date.day);
        if (copyDay.isBefore(afterDay)) continue;
      }
      final bank = _bankById(config, copy.bankId);
      if (bank == null) continue;
      if (!reprocess && copy.sourceApplied) {
        skipped++;
        continue;
      }

      final bankRules = rules.where((rule) => rule.bankId == copy.bankId).toList();
      final bankWords = typeWords.where((word) => word.bankId == copy.bankId).toList();
      final reading = SmsRuleEngine.parse(copy.body, bankRules, typeWords: bankWords);
      if (!reading.isComplete) {
        if (copy.id != null) {
          await _db.updateSmsCopyStatus(copy.id!, SmsCopyStatus.unreadable);
        }
        unmatched++;
        continue;
      }

      final isDebit = reading.typeHint == 'debit';
      final hash = SmsHash.of(smsId: copy.smsId, sender: copy.sender, body: copy.body);
      final previous = await _db.getTransactionByHash(hash) ??
          (copy.smsId.isEmpty ? null : await _db.getTransactionBySmsId(copy.smsId));
      final upserted = await _db.upsertTransaction(
        TransactionEntity(
          bank: bank.nameEn,
          amount: reading.amount!,
          type: isDebit ? TransactionType.debit : TransactionType.credit,
          date: copy.date,
          rawSms: copy.body,
          smsId: copy.smsId,
          balance: reading.balance,
          accountHint: reading.account,
          smsHash: hash,
          ruleId: SmsRuleEngine.ruleSetId(rules: bankRules, typeWords: bankWords),
          ruleVersion: bank.ruleVersion,
        ),
      );
      if (copy.id != null) {
        await _db.updateSmsCopyStatus(copy.id!, SmsCopyStatus.parsed);
      }
      if (previous == null) {
        parsed++;
      } else if (previous.amount != upserted.amount || previous.type != upserted.type) {
        updated++;
      }

      final sourceId = bank.sourceId;
      if (sourceId == null) {
        missingSource++;
        continue;
      }

      if (reprocess) {
        if (copy.sourceApplied && previous != null) {
          final oldSigned = previous.type == TransactionType.debit ? -previous.amount : previous.amount;
          final newSigned = isDebit ? -reading.amount! : reading.amount!;
          await SmsSourceApplier.instance.applySignedDelta(
            sourceId: sourceId,
            delta: newSigned - oldSigned,
            date: copy.date,
            note: bank.nameEn,
          );
        }
        continue;
      }

      if (copy.sourceApplied) {
        skipped++;
        continue;
      }

      final applied = await SmsSourceApplier.instance.apply(
        sourceId: sourceId,
        amount: reading.amount!,
        debit: isDebit,
        date: copy.date,
        note: bank.nameEn,
      );
      if (applied && copy.id != null) {
        await _db.markSourceApplied(copy.id!);
        toSource++;
      }
    }
    await syncCategories(bankId: bankId);
    return (
      parsed: parsed,
      toSource: toSource,
      skipped: skipped,
      unmatched: unmatched,
      missingSource: missingSource,
      updated: updated,
    );
  }

  Future<void> syncCategories({String? bankId}) {
    return SmsCategoryApplier.instance.syncAll(bankId: bankId);
  }

  BankConfig? _bankById(SmsFeatureConfig config, String id) {
    for (final bank in config.banks) {
      if (bank.id == id) return bank;
    }
    return null;
  }

  Future<List<SmsMessage>> _readSms(DateTime after) async {
    return _telephony.getInboxSms(
      columns: [
        SmsColumn.ID,
        SmsColumn.ADDRESS,
        SmsColumn.BODY,
        SmsColumn.DATE,
      ],
      filter: SmsFilter.where(SmsColumn.DATE)
          .greaterThanOrEqualTo(after.millisecondsSinceEpoch.toString()),
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.ASC)],
    );
  }

  Future<void> _updateLastSyncTime(int? date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      lastSyncPrefsKey,
      date ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}
