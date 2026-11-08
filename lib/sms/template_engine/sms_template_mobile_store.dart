import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:money_traker/data/database_helper.dart';
import 'package:money_traker/sms/template_engine/template_models.dart';

class SmsTemplateBank {
  final String id;
  final String name;
  final List<String> senders;
  final int? sourceId;
  final DateTime createdAt;

  const SmsTemplateBank({
    required this.id,
    required this.name,
    required this.senders,
    this.sourceId,
    required this.createdAt,
  });

  SmsTemplateBank copyWith({
    String? name,
    List<String>? senders,
    int? sourceId,
    bool clearSourceId = false,
  }) {
    return SmsTemplateBank(
      id: id,
      name: name ?? this.name,
      senders: senders ?? this.senders,
      sourceId: clearSourceId ? null : (sourceId ?? this.sourceId),
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'senders_json': jsonEncode(senders),
    'source_id': sourceId,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory SmsTemplateBank.fromMap(Map<String, dynamic> map) {
    final raw = jsonDecode(map['senders_json'] as String? ?? '[]');
    return SmsTemplateBank(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      senders: raw is List
          ? raw.map((item) => item.toString()).toList()
          : const [],
      sourceId: (map['source_id'] as num?)?.toInt(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['created_at'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

enum SmsTemplateMessageStatus { pending, parsed, unrecognized, duplicate }

class SmsTemplateStoredMessage {
  final String hash;
  final String? smsId;
  final String sender;
  final String body;
  final DateTime date;
  final String bankId;
  final SmsTemplateMessageStatus status;
  final String? templateId;
  final DateTime copiedAt;

  const SmsTemplateStoredMessage({
    required this.hash,
    this.smsId,
    required this.sender,
    required this.body,
    required this.date,
    required this.bankId,
    required this.status,
    this.templateId,
    required this.copiedAt,
  });

  Map<String, dynamic> toMap() => {
    'sms_hash': hash,
    'sms_id': smsId,
    'sender': sender,
    'body': body,
    'date': date.millisecondsSinceEpoch,
    'bank_id': bankId,
    'status': status.name,
    'template_id': templateId,
    'copied_at': copiedAt.millisecondsSinceEpoch,
  };

  factory SmsTemplateStoredMessage.fromMap(Map<String, dynamic> map) {
    return SmsTemplateStoredMessage(
      hash: map['sms_hash'] as String? ?? '',
      smsId: map['sms_id'] as String?,
      sender: map['sender'] as String? ?? '',
      body: map['body'] as String? ?? '',
      date: DateTime.fromMillisecondsSinceEpoch(
        (map['date'] as num?)?.toInt() ?? 0,
      ),
      bankId: map['bank_id'] as String? ?? '',
      status: SmsTemplateMessageStatus.values.firstWhere(
        (item) => item.name == map['status'],
        orElse: () => SmsTemplateMessageStatus.pending,
      ),
      templateId: map['template_id'] as String?,
      copiedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['copied_at'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

class SmsTemplateApplication {
  final int? id;
  final String smsHash;
  final String? smsId;
  final String bankId;
  final String bankName;
  final String templateId;
  final int sourceId;
  final String sourceName;
  final double amount;
  final double delta;
  final double beforeAmount;
  final double afterAmount;
  final DateTime occurredAt;
  final String rawSms;
  final bool undone;
  final DateTime? undoneAt;
  final DateTime createdAt;

  const SmsTemplateApplication({
    this.id,
    required this.smsHash,
    this.smsId,
    required this.bankId,
    required this.bankName,
    required this.templateId,
    required this.sourceId,
    required this.sourceName,
    required this.amount,
    required this.delta,
    required this.beforeAmount,
    required this.afterAmount,
    required this.occurredAt,
    required this.rawSms,
    this.undone = false,
    this.undoneAt,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'sms_hash': smsHash,
    'sms_id': smsId,
    'bank_id': bankId,
    'bank_name': bankName,
    'template_id': templateId,
    'source_id': sourceId,
    'source_name': sourceName,
    'amount': amount,
    'delta': delta,
    'before_amount': beforeAmount,
    'after_amount': afterAmount,
    'occurred_at': occurredAt.millisecondsSinceEpoch,
    'raw_sms': rawSms,
    'undone': undone ? 1 : 0,
    'undone_at': undoneAt?.millisecondsSinceEpoch,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory SmsTemplateApplication.fromMap(Map<String, dynamic> map) {
    return SmsTemplateApplication(
      id: (map['id'] as num?)?.toInt(),
      smsHash: map['sms_hash'] as String? ?? '',
      smsId: map['sms_id'] as String?,
      bankId: map['bank_id'] as String? ?? '',
      bankName: map['bank_name'] as String? ?? '',
      templateId: map['template_id'] as String? ?? '',
      sourceId: (map['source_id'] as num?)?.toInt() ?? 0,
      sourceName: map['source_name'] as String? ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      delta: (map['delta'] as num?)?.toDouble() ?? 0,
      beforeAmount: (map['before_amount'] as num?)?.toDouble() ?? 0,
      afterAmount: (map['after_amount'] as num?)?.toDouble() ?? 0,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(
        (map['occurred_at'] as num?)?.toInt() ?? 0,
      ),
      rawSms: map['raw_sms'] as String? ?? '',
      undone: (map['undone'] as num?)?.toInt() == 1,
      undoneAt: map['undone_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (map['undone_at'] as num).toInt(),
            ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['created_at'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

class SmsTemplateMobileStore {
  SmsTemplateMobileStore._();
  static final instance = SmsTemplateMobileStore._();

  static const enabledKey = 'sms_templates_v2_enabled';
  static const lastSyncKey = 'sms_templates_v2_last_sync';
  static const activatedAtKey = 'sms_templates_v2_activated_at';

  Future<Database> get _db => DatabaseHelper.instance.database;

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(enabledKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledKey, enabled);
  }

  Future<DateTime?> lastSyncAt() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(lastSyncKey);
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<void> setLastSyncAt(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(lastSyncKey, date.millisecondsSinceEpoch);
  }

  Future<DateTime?> activatedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(activatedAtKey);
    if (value == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  /// Keeps the first activation day. Writes the start of today when missing.
  Future<DateTime> ensureActivatedAt() async {
    final existing = await activatedAt();
    if (existing != null) {
      return DateTime(existing.year, existing.month, existing.day);
    }
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(activatedAtKey, start.millisecondsSinceEpoch);
    return start;
  }

  Future<List<SmsTemplateBank>> getBanks() async {
    final db = await _db;
    final rows = await db.query(
      'sms_template_banks_v2',
      orderBy: 'created_at ASC',
    );
    return rows.map(SmsTemplateBank.fromMap).toList();
  }

  Future<void> saveBank(SmsTemplateBank bank) async {
    final db = await _db;
    await db.insert(
      'sms_template_banks_v2',
      bank.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteBank(String bankId) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        'sms_templates_v2',
        where: 'bank_id = ?',
        whereArgs: [bankId],
      );
      await txn.delete(
        'sms_template_messages_v2',
        where: 'bank_id = ?',
        whereArgs: [bankId],
      );
      await txn.delete(
        'sms_template_banks_v2',
        where: 'id = ?',
        whereArgs: [bankId],
      );
    });
  }

  Future<List<SmsTemplate>> getTemplates({String? bankId}) async {
    final db = await _db;
    final rows = await db.query(
      'sms_templates_v2',
      where: bankId == null ? null : 'bank_id = ?',
      whereArgs: bankId == null ? null : [bankId],
      orderBy: 'created_at ASC',
    );
    return [
      for (final row in rows)
        SmsTemplate.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(row['template_json'] as String) as Map,
          ),
        ),
    ];
  }

  Future<void> saveTemplate(SmsTemplate template) async {
    final db = await _db;
    await db.insert('sms_templates_v2', {
      'id': template.id,
      'bank_id': template.bankId,
      'template_json': jsonEncode(template.toJson()),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteTemplate(String id) async {
    final db = await _db;
    await db.delete('sms_templates_v2', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> upsertMessage(SmsTemplateStoredMessage message) async {
    final db = await _db;
    await db.insert(
      'sms_template_messages_v2',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SmsTemplateStoredMessage>> getMessages({String? bankId}) async {
    final db = await _db;
    final rows = await db.query(
      'sms_template_messages_v2',
      where: bankId == null ? null : 'bank_id = ?',
      whereArgs: bankId == null ? null : [bankId],
      orderBy: 'date DESC',
    );
    return rows.map(SmsTemplateStoredMessage.fromMap).toList();
  }

  Future<bool> hasApplication(String hash) async {
    final db = await _db;
    final rows = await db.query(
      'sms_template_applications_v2',
      columns: const ['id'],
      where: 'sms_hash = ?',
      whereArgs: [hash],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<int> insertApplication(SmsTemplateApplication application) async {
    final db = await _db;
    final map = application.toMap()..remove('id');
    return db.insert(
      'sms_template_applications_v2',
      map,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<SmsTemplateApplication>> getApplications() async {
    final db = await _db;
    final rows = await db.query(
      'sms_template_applications_v2',
      orderBy: 'occurred_at DESC, id DESC',
    );
    return rows.map(SmsTemplateApplication.fromMap).toList();
  }

  Future<bool> markUndone(int id, DateTime at) async {
    final db = await _db;
    final changed = await db.update(
      'sms_template_applications_v2',
      {'undone': 1, 'undone_at': at.millisecondsSinceEpoch},
      where: 'id = ? AND undone = 0',
      whereArgs: [id],
    );
    return changed == 1;
  }

  Future<void> restoreActive(int id) async {
    final db = await _db;
    await db.update(
      'sms_template_applications_v2',
      {'undone': 0, 'undone_at': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
