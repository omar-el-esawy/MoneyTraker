import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:telephony/telephony.dart';

import 'package:money_traker/data/database_helper.dart';
import 'package:money_traker/domain/entities/transaction_entity.dart';
import 'package:money_traker/services/sms_feature_store.dart';
import 'package:money_traker/services/sms_category_applier.dart';
import 'package:money_traker/services/sms_source_applier.dart';
import 'package:money_traker/services/transaction_category_assigner.dart';
import 'package:money_traker/sms/sms_hash.dart';
import 'package:money_traker/sms/template_engine/sms_template_engine.dart';
import 'package:money_traker/sms/template_engine/sms_template_mobile_store.dart';
import 'package:money_traker/sms/template_engine/template_models.dart';
import 'package:money_traker/store/money_storage.dart';

enum SmsTemplateEnableResult { enabled, disabled, oldSystemActive }

const smsInboxPreviewPageSize = 10;

const _inboxChannel = MethodChannel(
  'plugins.shounakmulay.com/foreground_sms_channel',
);

/// Android accepts LIMIT and OFFSET in the SMS provider sort clause.
String smsInboxPageSort({required int limit, required int offset}) {
  final safeLimit = limit < 1 ? smsInboxPreviewPageSize : limit;
  final safeOffset = offset < 0 ? 0 : offset;
  return 'date DESC LIMIT $safeLimit OFFSET $safeOffset';
}

({String selection, List<String> args})? smsInboxSenderFilter(
  List<String> senders,
) {
  final cleaned = [
    for (final sender in senders)
      if (sender.trim().isNotEmpty) sender.trim(),
  ];
  if (cleaned.isEmpty) return null;
  return (
    selection: List.filled(cleaned.length, 'address = ?').join(' OR '),
    args: cleaned,
  );
}

/// First sync starts at the beginning of the activation day.
/// Later syncs start at the later of that day and the last sync minus 2 minutes.
DateTime smsTemplateSyncAfter({
  required DateTime activatedAt,
  DateTime? lastSync,
}) {
  final activationStart = DateTime(
    activatedAt.year,
    activatedAt.month,
    activatedAt.day,
  );
  if (lastSync == null) return activationStart;
  final fromLastSync = lastSync.subtract(const Duration(minutes: 2));
  return fromLastSync.isBefore(activationStart)
      ? activationStart
      : fromLastSync;
}

DateTime? smsTemplateLatestSync(DateTime? global, DateTime? bank) {
  if (global == null) return bank;
  if (bank == null) return global;
  return bank.isAfter(global) ? bank : global;
}

/// The message used to teach a template changes the balance only when it
/// arrived on or after the day SMS Templates was first opened.
bool smsTaughtMessageShouldApply({
  required DateTime messageDate,
  required DateTime? activatedAt,
}) {
  if (activatedAt == null) return false;
  final start = DateTime(activatedAt.year, activatedAt.month, activatedAt.day);
  final day = DateTime(messageDate.year, messageDate.month, messageDate.day);
  return !day.isBefore(start);
}

/// Amount templates add or subtract [SmsParsedResult.amount].
/// Balance templates move the source to [SmsParsedResult.balance].
({double delta, bool debit, double recordedAmount}) smsTemplateMoneyChange({
  required SmsParsedResult result,
  required double sourceAmount,
}) {
  if (result.usesBalance && result.balance != null) {
    final delta = result.balance! - sourceAmount;
    return (delta: delta, debit: delta < 0, recordedAmount: delta.abs());
  }
  final debit = result.type == SmsTemplateType.debit;
  final delta = debit ? -result.amount : result.amount;
  return (delta: delta, debit: debit, recordedAmount: result.amount);
}

class SmsTemplateSyncResult {
  final bool supported;
  final bool permissionGranted;
  final bool disabled;
  final int copied;
  final int parsed;
  final int applied;
  final int unrecognized;
  final int duplicates;
  final int missingSource;
  final String? error;

  const SmsTemplateSyncResult({
    this.supported = true,
    this.permissionGranted = true,
    this.disabled = false,
    this.copied = 0,
    this.parsed = 0,
    this.applied = 0,
    this.unrecognized = 0,
    this.duplicates = 0,
    this.missingSource = 0,
    this.error,
  });

  static const unsupported = SmsTemplateSyncResult(supported: false);

  String get statusMessage {
    if (disabled) return 'Turn on SMS Templates before syncing.';
    if (!supported) return 'SMS reading is available on Android only.';
    if (!permissionGranted) return 'SMS permission was not granted.';
    if (error != null && error!.isNotEmpty) return 'Sync failed: $error';
    return '$applied applied • $unrecognized need teaching';
  }
}

class SmsTemplateInboxPreview {
  final bool supported;
  final bool permissionGranted;
  final List<SmsTemplateStoredMessage> messages;
  final String? error;

  const SmsTemplateInboxPreview({
    this.supported = true,
    this.permissionGranted = true,
    this.messages = const [],
    this.error,
  });
}

class SmsTemplateSyncService {
  SmsTemplateSyncService._();
  static final instance = SmsTemplateSyncService._();

  final _telephony = Telephony.instance;
  final _store = SmsTemplateMobileStore.instance;
  final _db = DatabaseHelper.instance;
  final _moneyStorage = MoneyStorage();
  Future<void> _processTail = Future.value();

  Future<SmsTemplateEnableResult> setEnabled(bool enabled) async {
    if (!enabled) {
      await _store.setEnabled(false);
      return SmsTemplateEnableResult.disabled;
    }
    final oldConfig = await SmsFeatureStore.instance.load();
    final oldIsActive =
        oldConfig.started && oldConfig.banks.any((bank) => bank.enabled);
    if (oldIsActive) return SmsTemplateEnableResult.oldSystemActive;
    await _store.setEnabled(true);
    await _store.ensureActivatedAt();
    return SmsTemplateEnableResult.enabled;
  }

  Future<SmsTemplateSyncResult> sync({String? bankId}) async {
    if (!await _store.isEnabled()) {
      return const SmsTemplateSyncResult(disabled: true);
    }
    if (kIsWeb || !Platform.isAndroid) {
      return SmsTemplateSyncResult.unsupported;
    }
    try {
      final permission = await _telephony.requestSmsPermissions;
      if (permission != true) {
        return const SmsTemplateSyncResult(permissionGranted: false);
      }
      final activatedAt = await _store.ensureActivatedAt();
      final globalLastSync = await _store.lastSyncAt();
      final bankLastSync = bankId == null
          ? null
          : await _store.lastSyncAt(bankId: bankId);
      final lastSync = smsTemplateLatestSync(globalLastSync, bankLastSync);
      final after = smsTemplateSyncAfter(
        activatedAt: activatedAt,
        lastSync: lastSync,
      );
      final smsList = await _telephony.getInboxSms(
        columns: const [
          SmsColumn.ID,
          SmsColumn.ADDRESS,
          SmsColumn.BODY,
          SmsColumn.DATE,
        ],
        filter: SmsFilter.where(
          SmsColumn.DATE,
        ).greaterThanOrEqualTo(after.millisecondsSinceEpoch.toString()),
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.ASC)],
      );
      final envelopes = <_InboxEnvelope>[];
      for (final sms in smsList) {
        final sender = sms.address?.trim();
        final body = sms.body;
        if (sender == null || sender.isEmpty || body == null || body.isEmpty) {
          continue;
        }
        envelopes.add(
          _InboxEnvelope(
            smsId:
                sms.id?.toString() ??
                '${sms.date ?? 0}:${sender.hashCode}:${body.hashCode}',
            sender: sender,
            body: body,
            date: sms.date == null
                ? DateTime.now()
                : DateTime.fromMillisecondsSinceEpoch(sms.date!),
          ),
        );
      }
      final result = await _process(envelopes, bankId: bankId);
      await _store.setLastSyncAt(DateTime.now(), bankId: bankId);
      return result;
    } catch (error, stackTrace) {
      debugPrint('SMS Templates sync failed: $error\n$stackTrace');
      return SmsTemplateSyncResult(error: error.toString());
    }
  }

  /// Reads one page of matching inbox messages for teaching a template.
  /// Nothing is written here. The chosen message is stored only after a
  /// template is saved from it. A sample from before SMS Templates was opened
  /// is not applied to a balance.
  Future<SmsTemplateInboxPreview> previewInboxPage({
    required String bankId,
    required List<String> senders,
    required int offset,
    int limit = smsInboxPreviewPageSize,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      return const SmsTemplateInboxPreview(supported: false);
    }
    final filter = smsInboxSenderFilter(senders);
    if (filter == null) {
      return const SmsTemplateInboxPreview();
    }
    try {
      final permission = await _telephony.requestSmsPermissions;
      if (permission != true) {
        return const SmsTemplateInboxPreview(permissionGranted: false);
      }
      final raw = await _inboxChannel.invokeMethod<List<dynamic>>(
        'getAllInboxSms',
        {
          'projection': ['_id', 'address', 'body', 'date'],
          'selection': filter.selection,
          'selection_args': filter.args,
          'sort_order': smsInboxPageSort(limit: limit, offset: offset),
        },
      );
      final messages = <SmsTemplateStoredMessage>[];
      for (final item in raw ?? const <dynamic>[]) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final sender = map['address']?.toString().trim();
        final body = map['body']?.toString();
        if (sender == null || sender.isEmpty || body == null || body.isEmpty) {
          continue;
        }
        if (!_senderMatches(sender, senders)) continue;
        final dateMillis = int.tryParse(map['date']?.toString() ?? '');
        final smsId =
            map['_id']?.toString() ??
            '${dateMillis ?? 0}:${sender.hashCode}:${body.hashCode}';
        messages.add(
          SmsTemplateStoredMessage(
            hash: SmsHash.of(smsId: smsId, sender: sender, body: body),
            smsId: smsId,
            sender: sender,
            body: body,
            date: dateMillis == null
                ? DateTime.now()
                : DateTime.fromMillisecondsSinceEpoch(dateMillis),
            bankId: bankId,
            status: SmsTemplateMessageStatus.pending,
            copiedAt: DateTime.now(),
          ),
        );
      }
      return SmsTemplateInboxPreview(messages: messages);
    } catch (error, stackTrace) {
      debugPrint('SMS Templates inbox preview failed: $error\n$stackTrace');
      return SmsTemplateInboxPreview(error: error.toString());
    }
  }

  Future<void> saveTaughtTemplate({
    required SmsTemplate template,
    required SmsTemplateStoredMessage message,
  }) async {
    await _store.saveTemplate(template);
    final applyToBalance = smsTaughtMessageShouldApply(
      messageDate: message.date,
      activatedAt: await _store.activatedAt(),
    );
    await _store.upsertMessage(
      SmsTemplateStoredMessage(
        hash: message.hash,
        smsId: message.smsId,
        sender: message.sender,
        body: message.body,
        date: message.date,
        bankId: template.bankId,
        status: applyToBalance
            ? SmsTemplateMessageStatus.parsed
            : SmsTemplateMessageStatus.sample,
        templateId: template.id,
        copiedAt: DateTime.now(),
      ),
    );
  }

  Future<SmsTemplateSyncResult> reprocessBank(String bankId) async {
    if (!await _store.isEnabled()) {
      return const SmsTemplateSyncResult(disabled: true);
    }
    final messages = await _store.getMessages(bankId: bankId);
    return _process([
      for (final message in messages)
        _InboxEnvelope(
          smsId: message.smsId ?? message.hash,
          sender: message.sender,
          body: message.body,
          date: message.date,
        ),
    ], bankId: bankId);
  }

  Future<SmsTemplateSyncResult> _process(
    List<_InboxEnvelope> inbox, {
    String? bankId,
  }) {
    final completer = Completer<SmsTemplateSyncResult>();
    _processTail = _processTail.then((_) async {
      try {
        completer.complete(await _processUnlocked(inbox, bankId: bankId));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<SmsTemplateSyncResult> _processUnlocked(
    List<_InboxEnvelope> inbox, {
    String? bankId,
  }) async {
    inbox.sort((a, b) => a.date.compareTo(b.date));
    final banks = await _store.getBanks();
    final templates = await _store.getTemplates();
    final existingMessages = await _store.getMessages();
    final previousByHash = {
      for (final message in existingMessages) message.hash: message,
    };
    final sets = <String, SmsBankTemplateSet>{};
    for (final bank in banks) {
      if (bankId != null && bank.id != bankId) continue;
      final set = SmsBankTemplateSet.compile(
        bankId: bank.id,
        senderIds: bank.senders,
        templates: [
          for (final template in templates)
            if (template.bankId == bank.id) template,
        ],
      );
      if (set != null) sets[bank.id] = set;
    }

    var copied = 0;
    var parsed = 0;
    var applied = 0;
    var unrecognized = 0;
    var duplicates = 0;
    var missingSource = 0;

    for (final item in inbox) {
      final matches = smsTemplateBanksForSender(banks, item.sender);
      if (matches.length != 1) continue;
      final bank = matches.single;
      if (bankId != null && bank.id != bankId) continue;

      final hash = SmsHash.of(
        smsId: item.smsId,
        sender: item.sender,
        body: item.body,
      );
      final prior = previousByHash[hash];
      if (prior == null) copied++;

      // Saved from a message older than the day SMS Templates was opened.
      if (prior?.status == SmsTemplateMessageStatus.sample) {
        continue;
      }

      if (await _store.hasApplication(hash)) {
        await _store.upsertMessage(
          _storedMessage(
            item,
            hash,
            bank.id,
            status: SmsTemplateMessageStatus.parsed,
            templateId: prior?.templateId,
          ),
        );
        continue;
      }
      final existingTransaction = await _db.getTransactionByHash(hash);
      final templateOwnedTransaction =
          existingTransaction?.ruleId?.startsWith('sms-template-v2:') == true;
      if (existingTransaction != null && !templateOwnedTransaction) {
        duplicates++;
        await _store.upsertMessage(
          _storedMessage(
            item,
            hash,
            bank.id,
            status: SmsTemplateMessageStatus.duplicate,
          ),
        );
        continue;
      }

      final result = sets[bank.id]?.match(item.body);
      if (result == null) {
        unrecognized++;
        await _store.upsertMessage(
          _storedMessage(
            item,
            hash,
            bank.id,
            status: SmsTemplateMessageStatus.unrecognized,
          ),
        );
        continue;
      }

      parsed++;
      await _store.upsertMessage(
        _storedMessage(
          item,
          hash,
          bank.id,
          status: SmsTemplateMessageStatus.parsed,
          templateId: result.templateId,
        ),
      );
      if (bank.sourceId == null) {
        missingSource++;
        continue;
      }
      final didApply = await _apply(
        bank: bank,
        item: item,
        hash: hash,
        result: result,
        existingTransaction: templateOwnedTransaction
            ? existingTransaction
            : null,
      );
      if (didApply) applied++;
    }

    return SmsTemplateSyncResult(
      copied: copied,
      parsed: parsed,
      applied: applied,
      unrecognized: unrecognized,
      duplicates: duplicates,
      missingSource: missingSource,
    );
  }

  Future<bool> _apply({
    required SmsTemplateBank bank,
    required _InboxEnvelope item,
    required String hash,
    required SmsParsedResult result,
    TransactionEntity? existingTransaction,
  }) async {
    final sources = await _moneyStorage.getMoneySources();
    final source = sources
        .where((candidate) => candidate.id == bank.sourceId)
        .firstOrNull;
    if (source == null || source.id == null) return false;
    final operationKey = 'sms-template-v2:$hash';
    var moneyResult = await SmsSourceApplier.instance.resultForOperation(
      operationKey,
    );
    late final bool debit;
    late final double recordedAmount;
    if (moneyResult != null) {
      if (moneyResult.sourceId != source.id) {
        throw StateError('SMS money operation belongs to another source');
      }
      debit = moneyResult.delta < 0;
      recordedAmount = moneyResult.delta.abs();
    } else if (existingTransaction != null) {
      // Older builds wrote the transaction after changing the source but did
      // not have an idempotency key. Rebuild the missing application without
      // moving money a second time.
      debit = existingTransaction.type == TransactionType.debit;
      final delta = debit
          ? -existingTransaction.amount
          : existingTransaction.amount;
      recordedAmount = existingTransaction.amount;
      moneyResult = MoneySourceDeltaResult(
        sourceId: source.id!,
        newlyApplied: false,
        beforeAmount: source.amount - delta,
        afterAmount: source.amount,
        delta: delta,
      );
    } else {
      final change = smsTemplateMoneyChange(
        result: result,
        sourceAmount: source.amount,
      );
      debit = change.debit;
      recordedAmount = change.recordedAmount;
      moneyResult = await SmsSourceApplier.instance.applySignedDeltaOnce(
        sourceId: source.id!,
        delta: change.delta,
        date: item.date,
        operationKey: operationKey,
        note: 'SMS Templates • ${bank.name}',
      );
      if (moneyResult == null) return false;
    }

    final saved =
        existingTransaction ??
        await _db.upsertTransaction(
          TransactionEntity(
            bank: bank.name,
            amount: recordedAmount,
            type: debit ? TransactionType.debit : TransactionType.credit,
            date: item.date,
            rawSms: item.body,
            smsId: item.smsId,
            balance: result.balance,
            accountHint: result.merchant,
            smsHash: hash,
            ruleId: 'sms-template-v2:${result.templateId}',
            ruleVersion: 1,
          ),
        );
    await _assignWordCategory(
      bankId: bank.id,
      transaction: saved,
      body: item.body,
      debit: debit,
    );
    final applicationId = await _store.insertApplication(
      SmsTemplateApplication(
        smsHash: hash,
        smsId: item.smsId,
        bankId: bank.id,
        bankName: bank.name,
        templateId: result.templateId,
        sourceId: source.id!,
        sourceName: source.name,
        amount: recordedAmount,
        delta: moneyResult.delta,
        beforeAmount: moneyResult.beforeAmount,
        afterAmount: moneyResult.afterAmount,
        occurredAt: item.date,
        rawSms: item.body,
        createdAt: DateTime.now(),
      ),
    );
    return applicationId > 0;
  }

  Future<void> _assignWordCategory({
    required String bankId,
    required TransactionEntity transaction,
    required String body,
    required bool debit,
  }) async {
    if (transaction.id == null || transaction.amount <= 0) return;
    try {
      final rules = await _db.getSmsCategoryRules(bankId: bankId);
      if (rules.isEmpty) return;
      final tags = await _moneyStorage.getTags();
      final choice = SmsCategoryApplier.instance.match(
        body: body,
        debit: debit,
        rules: rules,
        tags: tags,
      );
      if (choice == null) return;
      await TransactionCategoryAssigner.instance.assign(
        transaction: transaction,
        name: choice.tag.name,
        type: choice.tag.type,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'SMS template category assignment failed: $error\n$stackTrace',
      );
    }
  }

  Future<bool> undo(SmsTemplateApplication application) async {
    final id = application.id;
    if (id == null || application.undone) return false;
    final claimed = await _store.markUndone(id, DateTime.now());
    if (!claimed) return false;
    try {
      final reverted = await SmsSourceApplier.instance.applySignedDelta(
        sourceId: application.sourceId,
        delta: -application.delta,
        date: DateTime.now(),
        note: 'Undo SMS Templates • ${application.bankName}',
      );
      if (!reverted) {
        await _store.restoreActive(id);
        return false;
      }
      final transaction = await _db.getTransactionByHash(application.smsHash);
      if (transaction?.ruleId?.startsWith('sms-template-v2:') == true) {
        if (transaction!.categoryTagId != null) {
          await TransactionCategoryAssigner.instance.clear(transaction);
        }
        await _db.deleteTransactionByHash(application.smsHash);
      }
      return true;
    } catch (_) {
      await _store.restoreActive(id);
      rethrow;
    }
  }

  SmsTemplateStoredMessage _storedMessage(
    _InboxEnvelope item,
    String hash,
    String bankId, {
    required SmsTemplateMessageStatus status,
    String? templateId,
  }) {
    return SmsTemplateStoredMessage(
      hash: hash,
      smsId: item.smsId,
      sender: item.sender,
      body: item.body,
      date: item.date,
      bankId: bankId,
      status: status,
      templateId: templateId,
      copiedAt: DateTime.now(),
    );
  }

  bool _senderMatches(String sender, List<String> configured) {
    final candidate = smsTemplateNormalizedSender(sender);
    if (candidate.isEmpty) return false;
    return configured.any(
      (item) => smsTemplateNormalizedSender(item) == candidate,
    );
  }
}

class _InboxEnvelope {
  final String smsId;
  final String sender;
  final String body;
  final DateTime date;

  const _InboxEnvelope({
    required this.smsId,
    required this.sender,
    required this.body,
    required this.date,
  });
}
