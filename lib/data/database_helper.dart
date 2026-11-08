import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'package:money_traker/domain/entities/failed_sms.dart';
import 'package:money_traker/domain/entities/transaction_entity.dart';
import 'package:money_traker/sms/sms_hash.dart';
import 'package:money_traker/sms/sms_models.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static const _dbName = 'money_traker_sms.db';
  static const _dbVersion = 10;

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bank TEXT NOT NULL,
            amount REAL NOT NULL,
            type TEXT NOT NULL,
            date INTEGER NOT NULL,
            raw_sms TEXT NOT NULL,
            sms_id TEXT,
            sms_hash TEXT,
            rule_id TEXT,
            rule_version INTEGER
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_transactions_date ON transactions(date)',
        );
        await db.execute(
          'CREATE INDEX idx_transactions_sms_id ON transactions(sms_id)',
        );

        await db.execute('''
          CREATE TABLE processed_sms (
            sms_id TEXT PRIMARY KEY,
            processed_at INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE failed_sms (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sms_id TEXT NOT NULL,
            sender TEXT,
            body TEXT NOT NULL,
            failed_at INTEGER NOT NULL
          )
        ''');
        await _createSmsLearningTables(db);
        await _createSmsTypeWordTable(db);
        await _createSmsCategoryRuleTable(db);
        await _addReadingColumns(db);
        await _addCategoryColumns(db);
        await _addSourceAppliedColumn(db);
        await _createRawSmsAndVersioning(db);
        await _createSmsTemplateV2Tables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS processed_sms (
              sms_id TEXT PRIMARY KEY,
              processed_at INTEGER NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS failed_sms (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              sms_id TEXT NOT NULL,
              sender TEXT,
              body TEXT NOT NULL,
              failed_at INTEGER NOT NULL
            )
          ''');

          final cols = await db.rawQuery("PRAGMA table_info('transactions')");
          final hasSmsId = cols.any((c) => (c['name'] as String?) == 'sms_id');
          if (!hasSmsId) {
            await db.execute('ALTER TABLE transactions ADD COLUMN sms_id TEXT');
          }
        }
        if (oldVersion < 3) {
          await _createSmsLearningTables(db);
          await _addReadingColumns(db);
        }
        if (oldVersion < 4) {
          await _createSmsTypeWordTable(db);
        }
        if (oldVersion < 5) {
          await _addSourceAppliedColumn(db);
        }
        if (oldVersion < 6) {
          await _createRawSmsAndVersioning(db);
        }
        if (oldVersion < 7) {
          await _createSmsCategoryRuleTable(db);
          await _addCategoryColumns(db);
        }
        if (oldVersion < 8) {
          await _addCategoryColumns(db);
        }
        if (oldVersion < 9) {
          await _addRulePatternColumns(db);
        }
        if (oldVersion < 10) {
          await _createSmsTemplateV2Tables(db);
        }
      },
    );
  }

  Future<int> insertSmsCopy(SmsCopy copy) async {
    final db = await database;
    final map = copy.toMap()..remove('id');
    final id = await db.insert(
      'sms_copies',
      map,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await _upsertRawSms(copy);
    return id;
  }

  Future<List<SmsCopy>> getRawSms({String? bankId}) async {
    final db = await database;
    final rows = await db.query(
      'raw_sms',
      where: bankId == null ? null : 'bank_id = ?',
      whereArgs: bankId == null ? null : [bankId],
      orderBy: 'date DESC',
    );
    return rows.map((row) {
      return SmsCopy(
        smsId: row['sms_id'] as String? ?? '',
        sender: row['sender'] as String? ?? '',
        body: row['body'] as String? ?? '',
        date: DateTime.fromMillisecondsSinceEpoch((row['date'] as int?) ?? 0),
        bankId: row['bank_id'] as String? ?? '',
        status: SmsCopyStatus.pending,
        copiedAt: DateTime.fromMillisecondsSinceEpoch(
          (row['copied_at'] as int?) ?? 0,
        ),
      );
    }).toList();
  }

  Future<List<SmsCopy>> getSmsCopies() async {
    final db = await database;
    final rows = await db.query('sms_copies', orderBy: 'date DESC');
    return rows.map(SmsCopy.fromMap).toList();
  }

  Future<void> deleteStoredSmsBefore(DateTime date) async {
    final db = await database;
    final boundary = DateTime(
      date.year,
      date.month,
      date.day,
    ).millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.delete('sms_copies', where: 'date < ?', whereArgs: [boundary]);
      await txn.delete('raw_sms', where: 'date < ?', whereArgs: [boundary]);
    });
  }

  Future<void> updateSmsCopyStatus(int id, SmsCopyStatus status) async {
    final db = await database;
    await db.update(
      'sms_copies',
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markSourceApplied(int id, {bool applied = true}) async {
    final db = await database;
    await db.update(
      'sms_copies',
      {'source_applied': applied ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> reopenUnreadable(String bankId) async {
    final db = await database;
    await db.update(
      'sms_copies',
      {'status': SmsCopyStatus.pending.name},
      where: 'bank_id = ? AND status = ?',
      whereArgs: [bankId, SmsCopyStatus.unreadable.name],
    );
  }

  Future<int> insertSmsRule(SmsReadRule rule) async {
    final db = await database;
    final map = rule.toMap()..remove('id');
    return db.insert(
      'sms_rules',
      map,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<SmsReadRule>> getSmsRules() async {
    final db = await database;
    final rows = await db.query('sms_rules', orderBy: 'created_at ASC');
    return rows.map(SmsReadRule.fromMap).toList();
  }

  Future<void> deleteSmsRule(int id) async {
    final db = await database;
    await db.delete('sms_rules', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertSmsTypeWord(SmsTypeWord word) async {
    final db = await database;
    final map = word.toMap()..remove('id');
    return db.insert(
      'sms_type_words',
      map,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<SmsTypeWord>> getSmsTypeWords({String? bankId}) async {
    final db = await database;
    final rows = await db.query(
      'sms_type_words',
      where: bankId == null ? null : 'bank_id = ?',
      whereArgs: bankId == null ? null : [bankId],
      orderBy: 'created_at ASC',
    );
    return rows.map(SmsTypeWord.fromMap).toList();
  }

  Future<void> deleteSmsTypeWord(int id) async {
    final db = await database;
    await db.delete('sms_type_words', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertSmsCategoryRule(SmsCategoryRule rule) async {
    final db = await database;
    final existing = await getSmsCategoryRules(bankId: rule.bankId);
    for (final item in existing) {
      final id = item.id;
      final samePattern = item.pattern?.key == rule.pattern?.key;
      final sameLegacyWord =
          item.pattern == null &&
          rule.pattern == null &&
          item.word.toLowerCase() == rule.word.toLowerCase();
      if (id != null && (samePattern || sameLegacyWord)) {
        await deleteSmsCategoryRule(id);
      }
    }
    final map = rule.toMap()..remove('id');
    return db.insert('sms_category_rules', map);
  }

  Future<List<SmsCategoryRule>> getSmsCategoryRules({String? bankId}) async {
    final db = await database;
    final rows = await db.query(
      'sms_category_rules',
      where: bankId == null ? null : 'bank_id = ?',
      whereArgs: bankId == null ? null : [bankId],
      orderBy: 'created_at ASC',
    );
    return rows.map(SmsCategoryRule.fromMap).toList();
  }

  Future<void> deleteSmsCategoryRule(int id) async {
    final db = await database;
    await db.delete('sms_category_rules', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setTransactionCategory(
    int id, {
    int? tagId,
    double? amount,
    String? allocations,
  }) async {
    final db = await database;
    await db.update(
      'transactions',
      {
        'category_tag_id': tagId,
        'category_amount': amount,
        'category_allocations': allocations,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<TransactionEntity?> getTransactionById(int id) async {
    final db = await database;
    final rows = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TransactionEntity.fromMap(rows.first);
  }

  Future<Map<int, int>> transactionCategoryCounts() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT category_tag_id AS tagId, COUNT(*) AS uses
      FROM transactions
      WHERE category_tag_id IS NOT NULL
      GROUP BY category_tag_id
    ''');
    final counts = <int, int>{};
    for (final row in rows) {
      final tagId = (row['tagId'] as num?)?.toInt();
      if (tagId == null) continue;
      counts[tagId] = (row['uses'] as num?)?.toInt() ?? 0;
    }
    return counts;
  }

  Future<TransactionEntity?> getTransactionBySmsId(String smsId) async {
    final db = await database;
    final rows = await db.query(
      'transactions',
      where: 'sms_id = ?',
      whereArgs: [smsId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TransactionEntity.fromMap(rows.first);
  }

  Future<bool> hasTransactionForSms(String smsId) async {
    final db = await database;
    final rows = await db.query(
      'transactions',
      columns: const ['id'],
      where: 'sms_id = ?',
      whereArgs: [smsId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<int> insertTransaction(TransactionEntity transaction) async {
    final db = await database;
    final map = transaction.toMap();
    map.remove('id');
    return db.insert('transactions', map);
  }

  Future<TransactionEntity?> getTransactionByHash(String hash) async {
    final db = await database;
    final rows = await db.query(
      'transactions',
      where: 'sms_hash = ?',
      whereArgs: [hash],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TransactionEntity.fromMap(rows.first);
  }

  Future<TransactionEntity> upsertTransaction(
    TransactionEntity transaction,
  ) async {
    final hash = transaction.smsHash;
    TransactionEntity? existing;
    if (hash != null && hash.isNotEmpty) {
      existing = await getTransactionByHash(hash);
    }
    existing ??= transaction.smsId == null
        ? null
        : await getTransactionBySmsId(transaction.smsId!);
    if (existing == null) {
      final id = await insertTransaction(transaction);
      return transaction.copyWith(id: id);
    }
    final merged = transaction.copyWith(
      id: existing.id,
      categoryTagId: transaction.categoryTagId ?? existing.categoryTagId,
      categoryAmount: transaction.categoryAmount ?? existing.categoryAmount,
      categoryAllocations:
          transaction.categoryAllocations ?? existing.categoryAllocations,
    );
    final db = await database;
    final map = merged.toMap()..remove('id');
    await db.update(
      'transactions',
      map,
      where: 'id = ?',
      whereArgs: [existing.id],
    );
    return merged;
  }

  Future<List<TransactionEntity>> getAllTransactions() async {
    final db = await database;
    final rows = await db.query('transactions', orderBy: 'date DESC');
    return rows.map(TransactionEntity.fromMap).toList();
  }

  Future<void> deleteTransactionByHash(String hash) async {
    final db = await database;
    await db.delete('transactions', where: 'sms_hash = ?', whereArgs: [hash]);
  }

  Future<TransactionEntity?> getOldestTransaction() async {
    final db = await database;
    final rows = await db.query('transactions', orderBy: 'date ASC', limit: 1);
    if (rows.isEmpty) return null;
    return TransactionEntity.fromMap(rows.first);
  }

  Future<bool> isProcessed(String smsId) async {
    final db = await database;
    final rows = await db.query(
      'processed_sms',
      columns: const ['sms_id'],
      where: 'sms_id = ?',
      whereArgs: [smsId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> markAsProcessed(String smsId) async {
    final db = await database;
    await db.insert('processed_sms', {
      'sms_id': smsId,
      'processed_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> insertFailedSms(FailedSms failedSms) async {
    final db = await database;
    final map = failedSms.toMap();
    map.remove('id');
    await db.insert('failed_sms', map);
  }

  static const smsBackupTables = <String>[
    'transactions',
    'processed_sms',
    'failed_sms',
    'sms_copies',
    'sms_rules',
    'sms_type_words',
    'sms_category_rules',
    'raw_sms',
    'sms_template_banks_v2',
    'sms_templates_v2',
    'sms_template_messages_v2',
    'sms_template_applications_v2',
  ];

  Future<Map<String, dynamic>> exportSmsTables() async {
    final db = await database;
    final out = <String, dynamic>{};
    for (final table in smsBackupTables) {
      out[table] = await db.query(table);
    }
    return out;
  }

  Future<void> importSmsTables(Map<String, dynamic> sms) async {
    final db = await database;
    await db.transaction((txn) async {
      final importedTables = [
        for (final table in smsBackupTables)
          if (sms[table] is List) table,
      ];
      for (final table in importedTables) {
        await txn.delete(table);
      }
      final sequence = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'sqlite_sequence'",
      );
      if (sequence.isNotEmpty) {
        if (importedTables.isNotEmpty) {
          final placeholders = List.filled(
            importedTables.length,
            '?',
          ).join(',');
          await txn.delete(
            'sqlite_sequence',
            where: 'name IN ($placeholders)',
            whereArgs: importedTables,
          );
        }
      }
      for (final table in importedTables) {
        final rows = sms[table];
        if (rows is! List) continue;
        for (final row in rows) {
          if (row is! Map) continue;
          await txn.insert(
            table,
            row.map((key, value) => MapEntry(key.toString(), value)),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }
}

Future<void> _createSmsLearningTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sms_copies (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sms_id TEXT NOT NULL UNIQUE,
      sender TEXT NOT NULL,
      body TEXT NOT NULL,
      date INTEGER NOT NULL,
      bank_id TEXT NOT NULL,
      status TEXT NOT NULL,
      copied_at INTEGER NOT NULL,
      source_applied INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sms_rules (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bank_id TEXT NOT NULL,
      field TEXT NOT NULL,
      type_hint TEXT NOT NULL DEFAULT '',
      prefix TEXT NOT NULL,
      suffix TEXT NOT NULL,
      sample_sms_id TEXT,
      created_at INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE UNIQUE INDEX IF NOT EXISTS idx_sms_rules_unique
    ON sms_rules(bank_id, field, type_hint, prefix, suffix)
  ''');
}

Future<void> _createSmsTypeWordTable(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sms_type_words (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bank_id TEXT NOT NULL,
      word TEXT NOT NULL,
      type_hint TEXT NOT NULL,
      pattern TEXT,
      created_at INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE UNIQUE INDEX IF NOT EXISTS idx_sms_type_words_unique
    ON sms_type_words(bank_id, word, type_hint, pattern)
  ''');
}

Future<void> _addSourceAppliedColumn(Database db) async {
  final cols = await db.rawQuery("PRAGMA table_info('sms_copies')");
  final names = cols.map((c) => c['name'] as String?).toSet();
  if (!names.contains('source_applied')) {
    await db.execute(
      'ALTER TABLE sms_copies ADD COLUMN source_applied INTEGER NOT NULL DEFAULT 0',
    );
  }
}

Future<void> _createRawSmsAndVersioning(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS raw_sms (
      sms_hash TEXT PRIMARY KEY,
      sms_id TEXT,
      sender TEXT NOT NULL,
      body TEXT NOT NULL,
      date INTEGER NOT NULL,
      bank_id TEXT NOT NULL,
      copied_at INTEGER NOT NULL
    )
  ''');
  final cols = await db.rawQuery("PRAGMA table_info('transactions')");
  final names = cols.map((c) => c['name'] as String?).toSet();
  if (!names.contains('sms_hash')) {
    await db.execute('ALTER TABLE transactions ADD COLUMN sms_hash TEXT');
  }
  if (!names.contains('rule_id')) {
    await db.execute('ALTER TABLE transactions ADD COLUMN rule_id TEXT');
  }
  if (!names.contains('rule_version')) {
    await db.execute(
      'ALTER TABLE transactions ADD COLUMN rule_version INTEGER',
    );
  }

  final copies = await db.query('sms_copies');
  for (final row in copies) {
    final sender = row['sender'] as String? ?? '';
    final body = row['body'] as String? ?? '';
    final smsId = row['sms_id'] as String? ?? '';
    final hash = SmsHash.of(smsId: smsId, sender: sender, body: body);
    await db.insert('raw_sms', {
      'sms_hash': hash,
      'sms_id': smsId,
      'sender': sender,
      'body': body,
      'date': row['date'] ?? 0,
      'bank_id': row['bank_id'] ?? '',
      'copied_at': row['copied_at'] ?? 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    if (smsId.isNotEmpty) {
      await db.update(
        'transactions',
        {'sms_hash': hash},
        where: 'sms_id = ? AND (sms_hash IS NULL OR sms_hash = \'\')',
        whereArgs: [smsId],
      );
    }
  }
  final hashed = await db.query(
    'transactions',
    columns: const ['id', 'sms_hash'],
    orderBy: 'id ASC',
  );
  final seen = <String>{};
  for (final row in hashed) {
    final hash = row['sms_hash'] as String?;
    if (hash == null || hash.isEmpty) continue;
    if (!seen.add(hash)) {
      await db.delete('transactions', where: 'id = ?', whereArgs: [row['id']]);
    }
  }
  await db.execute(
    "CREATE UNIQUE INDEX IF NOT EXISTS idx_transactions_sms_hash ON transactions(sms_hash) WHERE sms_hash IS NOT NULL AND sms_hash != ''",
  );
}

Future<void> _upsertRawSms(SmsCopy copy) async {
  final db = await DatabaseHelper.instance.database;
  final hash = SmsHash.of(
    smsId: copy.smsId,
    sender: copy.sender,
    body: copy.body,
  );
  await db.insert('raw_sms', {
    'sms_hash': hash,
    'sms_id': copy.smsId,
    'sender': copy.sender,
    'body': copy.body,
    'date': copy.date.millisecondsSinceEpoch,
    'bank_id': copy.bankId,
    'copied_at': copy.copiedAt.millisecondsSinceEpoch,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<void> _createSmsCategoryRuleTable(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sms_category_rules (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bank_id TEXT NOT NULL,
      word TEXT NOT NULL,
      tag_id INTEGER NOT NULL,
      pattern TEXT,
      created_at INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE UNIQUE INDEX IF NOT EXISTS idx_sms_category_rules_unique
    ON sms_category_rules(bank_id, word, pattern)
  ''');
}

Future<void> _addRulePatternColumns(Database db) async {
  for (final table in ['sms_type_words', 'sms_category_rules']) {
    final cols = await db.rawQuery("PRAGMA table_info('$table')");
    final names = cols.map((c) => c['name'] as String?).toSet();
    if (!names.contains('pattern')) {
      await db.execute('ALTER TABLE $table ADD COLUMN pattern TEXT');
    }
  }
  await db.execute('DROP INDEX IF EXISTS idx_sms_type_words_unique');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_sms_type_words_unique '
    'ON sms_type_words(bank_id, word, type_hint, pattern)',
  );
  await db.execute('DROP INDEX IF EXISTS idx_sms_category_rules_unique');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_sms_category_rules_unique '
    'ON sms_category_rules(bank_id, word, pattern)',
  );
}

Future<void> _addCategoryColumns(Database db) async {
  final cols = await db.rawQuery("PRAGMA table_info('transactions')");
  final names = cols.map((c) => c['name'] as String?).toSet();
  if (!names.contains('category_tag_id')) {
    await db.execute(
      'ALTER TABLE transactions ADD COLUMN category_tag_id INTEGER',
    );
  }
  if (!names.contains('category_amount')) {
    await db.execute(
      'ALTER TABLE transactions ADD COLUMN category_amount REAL',
    );
  }
  if (!names.contains('category_allocations')) {
    await db.execute(
      'ALTER TABLE transactions ADD COLUMN category_allocations TEXT',
    );
  }
}

Future<void> _addReadingColumns(Database db) async {
  final cols = await db.rawQuery("PRAGMA table_info('transactions')");
  final names = cols.map((c) => c['name'] as String?).toSet();
  if (!names.contains('balance')) {
    await db.execute('ALTER TABLE transactions ADD COLUMN balance REAL');
  }
  if (!names.contains('account_hint')) {
    await db.execute('ALTER TABLE transactions ADD COLUMN account_hint TEXT');
  }
}

Future<void> _createSmsTemplateV2Tables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sms_template_banks_v2 (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      senders_json TEXT NOT NULL,
      source_id INTEGER,
      created_at INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sms_templates_v2 (
      id TEXT PRIMARY KEY,
      bank_id TEXT NOT NULL,
      template_json TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sms_templates_v2_bank '
    'ON sms_templates_v2(bank_id)',
  );
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sms_template_messages_v2 (
      sms_hash TEXT PRIMARY KEY,
      sms_id TEXT,
      sender TEXT NOT NULL,
      body TEXT NOT NULL,
      date INTEGER NOT NULL,
      bank_id TEXT NOT NULL,
      status TEXT NOT NULL,
      template_id TEXT,
      copied_at INTEGER NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sms_template_messages_v2_bank '
    'ON sms_template_messages_v2(bank_id, date DESC)',
  );
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sms_template_applications_v2 (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sms_hash TEXT NOT NULL UNIQUE,
      sms_id TEXT,
      bank_id TEXT NOT NULL,
      bank_name TEXT NOT NULL,
      template_id TEXT NOT NULL,
      source_id INTEGER NOT NULL,
      source_name TEXT NOT NULL,
      amount REAL NOT NULL,
      delta REAL NOT NULL,
      before_amount REAL NOT NULL,
      after_amount REAL NOT NULL,
      occurred_at INTEGER NOT NULL,
      raw_sms TEXT NOT NULL,
      undone INTEGER NOT NULL DEFAULT 0,
      undone_at INTEGER,
      created_at INTEGER NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sms_template_applications_v2_date '
    'ON sms_template_applications_v2(occurred_at DESC)',
  );
}
