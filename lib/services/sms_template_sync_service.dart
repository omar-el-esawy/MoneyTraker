import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:telephony/telephony.dart';

import 'package:money_traker/data/database_helper.dart';
import 'package:money_traker/domain/entities/transaction_entity.dart';
import 'package:money_traker/services/sms_feature_store.dart';
import 'package:money_traker/services/sms_source_applier.dart';
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
      final lastSync = await _store.lastSyncAt();
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
      await _store.setLastSyncAt(DateTime.now());
      return result;
    } catch (error, stackTrace) {
      debugPrint('SMS Templates sync failed: $error\n$stackTrace');
      return SmsTemplateSyncResult(error: error.toString());
    }
  }

  /// Reads one page of matching inbox messages for teaching a template.
  /// Nothing is written here. The chosen message is stored only after a
  /// template is saved from it.
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
    await _store.upsertMessage(
      SmsTemplateStoredMessage(
        hash: message.hash,
        smsId: message.smsId,
        sender: message.sender,
        body: message.body,
        date: message.date,
        bankId: template.bankId,
        status: SmsTemplateMessageStatus.parsed,
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
    final incomingHashes = {
      for (final item in inbox)
        SmsHash.of(smsId: item.smsId, sender: item.sender, body: item.body),
    };
    final seen = [
      for (final message in existingMessages)
        if (!incomingHashes.contains(message.hash)) message,
    ];

    for (final item in inbox) {
      SmsTemplateBank? bank;
      for (final candidate in banks) {
        if (bankId != null && candidate.id != bankId) continue;
        if (_senderMatches(item.sender, candidate.senders)) {
          bank = candidate;
          break;
        }
      }
      if (bank == null) continue;

      final hash = SmsHash.of(
        smsId: item.smsId,
        sender: item.sender,
        body: item.body,
      );
      final prior = previousByHash[hash];
      if (prior == null) copied++;

      final duplicate = seen.any(
        (message) =>
            message.hash != hash &&
            message.sender.trim().toLowerCase() ==
                item.sender.trim().toLowerCase() &&
            message.body == item.body &&
            message.date.difference(item.date).abs() <=
                const Duration(minutes: 2),
      );
      if (duplicate) {
        duplicates++;
        await _saveMessage(
          item,
          hash,
          bank.id,
          status: SmsTemplateMessageStatus.duplicate,
        );
        seen.add(
          _storedMessage(
            item,
            hash,
            bank.id,
            status: SmsTemplateMessageStatus.duplicate,
          ),
        );
        continue;
      }

      if (await _store.hasApplication(hash)) {
        final stored = _storedMessage(
          item,
          hash,
          bank.id,
          status: SmsTemplateMessageStatus.parsed,
          templateId: prior?.templateId,
        );
        await _store.upsertMessage(stored);
        seen.add(stored);
        continue;
      }
      if (await _db.getTransactionByHash(hash) != null) {
        duplicates++;
        final stored = _storedMessage(
          item,
          hash,
          bank.id,
          status: SmsTemplateMessageStatus.duplicate,
        );
        await _store.upsertMessage(stored);
        seen.add(stored);
        continue;
      }

      final result = sets[bank.id]?.match(item.body);
      if (result == null) {
        unrecognized++;
        final stored = _storedMessage(
          item,
          hash,
          bank.id,
          status: SmsTemplateMessageStatus.unrecognized,
        );
        await _store.upsertMessage(stored);
        seen.add(stored);
        continue;
      }

      parsed++;
      final stored = _storedMessage(
        item,
        hash,
        bank.id,
        status: SmsTemplateMessageStatus.parsed,
        templateId: result.templateId,
      );
      await _store.upsertMessage(stored);
      seen.add(stored);
      if (bank.sourceId == null) {
        missingSource++;
        continue;
      }
      final didApply = await _apply(
        bank: bank,
        item: item,
        hash: hash,
        result: result,
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
  }) async {
    final sources = await _moneyStorage.getMoneySources();
    final source = sources
        .where((candidate) => candidate.id == bank.sourceId)
        .firstOrNull;
    if (source == null || source.id == null) return false;
    final debit = result.type == SmsTemplateType.debit;
    final delta = debit ? -result.amount : result.amount;
    final applied = await SmsSourceApplier.instance.applySignedDelta(
      sourceId: source.id!,
      delta: delta,
      date: item.date,
      note: 'SMS Templates • ${bank.name}',
    );
    if (!applied) return false;

    await _db.upsertTransaction(
      TransactionEntity(
        bank: bank.name,
        amount: result.amount,
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
    final applicationId = await _store.insertApplication(
      SmsTemplateApplication(
        smsHash: hash,
        smsId: item.smsId,
        bankId: bank.id,
        bankName: bank.name,
        templateId: result.templateId,
        sourceId: source.id!,
        sourceName: source.name,
        amount: result.amount,
        delta: delta,
        beforeAmount: source.amount,
        afterAmount: source.amount + delta,
        occurredAt: item.date,
        rawSms: item.body,
        createdAt: DateTime.now(),
      ),
    );
    return applicationId > 0;
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
        await _db.deleteTransactionByHash(application.smsHash);
      }
      return true;
    } catch (_) {
      await _store.restoreActive(id);
      rethrow;
    }
  }

  Future<void> _saveMessage(
    _InboxEnvelope item,
    String hash,
    String bankId, {
    required SmsTemplateMessageStatus status,
    String? templateId,
  }) {
    return _store.upsertMessage(
      _storedMessage(
        item,
        hash,
        bankId,
        status: status,
        templateId: templateId,
      ),
    );
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
    final candidate = sender.trim().toLowerCase();
    return configured.any((item) => item.trim().toLowerCase() == candidate);
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
