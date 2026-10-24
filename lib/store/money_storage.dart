import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:money_traker/model/mission.dart';
import 'package:money_traker/model/money_source.dart';
import 'package:money_traker/model/total_money_day.dart';
import 'package:money_traker/model/total_money_day_delta_entry.dart';
import 'package:money_traker/model/tag.dart';
import 'package:money_traker/model/goal.dart';
import 'package:money_traker/model/money_source_change.dart';

class MoneyStorage {
  static final MoneyStorage _instance = MoneyStorage._internal();
  static Database? _database;

  MoneyStorage._internal();

  factory MoneyStorage() => _instance;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'money_traker.db');

    return await openDatabase(
      path,
      version: 8,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE missions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            targetAmount REAL,
            startDate TEXT,
            endDate TEXT,
            spentAmount REAL
          )
        ''');
        await db.execute('''
          CREATE TABLE money_sources (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            amount REAL
          )
        ''');
        await db.execute('''
          CREATE TABLE total_money_days (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT,
            totalAmount REAL,
            note TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            type TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE UNIQUE INDEX idx_tags_name_type ON tags(name, type)
        ''');

        await db.execute('''
          CREATE TABLE total_money_day_delta_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            dayId INTEGER NOT NULL,
            tagId INTEGER NOT NULL,
            amount REAL NOT NULL,
            autoBalanced INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY(dayId) REFERENCES total_money_days(id) ON DELETE CASCADE,
            FOREIGN KEY(tagId) REFERENCES tags(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE UNIQUE INDEX idx_delta_day_tag ON total_money_day_delta_entries(dayId, tagId)
        ''');

        await db.execute('''
          CREATE TABLE goals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            targetAmount REAL NOT NULL,
            type TEXT NOT NULL,
            direction TEXT NOT NULL,
            monthStartDay INTEGER,
            repeatEveryDays INTEGER,
            repeatStartDate TEXT,
            periodStart TEXT,
            periodEnd TEXT,
            excludedTagIds TEXT,
            isMain INTEGER NOT NULL DEFAULT 0,
            isActive INTEGER NOT NULL DEFAULT 1,
            createdAt TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_goals_active_createdAt ON goals(isActive, createdAt)');
        await db.execute('CREATE INDEX idx_goals_isMain ON goals(isMain)');

        await db.execute('''
          CREATE TABLE money_source_changes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sourceId INTEGER NOT NULL,
            deltaAmount REAL NOT NULL,
            resultingAmount REAL NOT NULL,
            createdAt TEXT NOT NULL,
            type TEXT NOT NULL,
            note TEXT,
            FOREIGN KEY(sourceId) REFERENCES money_sources(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('CREATE INDEX idx_source_changes_source_created ON money_source_changes(sourceId, createdAt)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // IMPORTANT: Never drop tables here. Always migrate forward while keeping data.
        // Add migrations incrementally as you bump the DB version.

        if (oldVersion < 2) {
          // Example reserved for older migrations if you had any.
          // (No-op in this project right now.)
        }

        if (oldVersion < 3) {
          // v3 introduced the "note" column on total_money_days.
          await db.execute('ALTER TABLE total_money_days ADD COLUMN note TEXT');
        }

        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS tags (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              type TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_name_type ON tags(name, type)
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS total_money_day_delta_entries (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              dayId INTEGER NOT NULL,
              tagId INTEGER NOT NULL,
              amount REAL NOT NULL,
              autoBalanced INTEGER NOT NULL DEFAULT 0,
              FOREIGN KEY(dayId) REFERENCES total_money_days(id) ON DELETE CASCADE,
              FOREIGN KEY(tagId) REFERENCES tags(id) ON DELETE CASCADE
            )
          ''');
          await db.execute('''
            CREATE UNIQUE INDEX IF NOT EXISTS idx_delta_day_tag ON total_money_day_delta_entries(dayId, tagId)
          ''');
        }

        if (oldVersion < 5) {
          await db.execute(
            'ALTER TABLE total_money_day_delta_entries ADD COLUMN autoBalanced INTEGER NOT NULL DEFAULT 0',
          );
        }

        if (oldVersion < 6) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS goals (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              targetAmount REAL NOT NULL,
              type TEXT NOT NULL,
              direction TEXT NOT NULL,
              monthStartDay INTEGER,
              repeatEveryDays INTEGER,
              repeatStartDate TEXT,
              periodStart TEXT,
              periodEnd TEXT,
              excludedTagIds TEXT,
              isMain INTEGER NOT NULL DEFAULT 0,
              isActive INTEGER NOT NULL DEFAULT 1,
              createdAt TEXT NOT NULL
            )
          ''');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_goals_active_createdAt ON goals(isActive, createdAt)',
          );
        }

        // v7: introduce "main goal" toggle.
        if (oldVersion < 7) {
          // Make this migration safe to run even if earlier versions already created
          // the column (some builds shipped v6 goals with isMain included).
          final cols = await db.rawQuery("PRAGMA table_info('goals')");
          final hasIsMain = cols.any((c) => (c['name'] as String?) == 'isMain');
          if (!hasIsMain) {
            await db.execute('ALTER TABLE goals ADD COLUMN isMain INTEGER NOT NULL DEFAULT 0');
          }
          await db.execute('CREATE INDEX IF NOT EXISTS idx_goals_isMain ON goals(isMain)');
        }

        if (oldVersion < 8) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS money_source_changes (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              sourceId INTEGER NOT NULL,
              deltaAmount REAL NOT NULL,
              resultingAmount REAL NOT NULL,
              createdAt TEXT NOT NULL,
              type TEXT NOT NULL,
              note TEXT,
              FOREIGN KEY(sourceId) REFERENCES money_sources(id) ON DELETE CASCADE
            )
          ''');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_source_changes_source_created ON money_source_changes(sourceId, createdAt)',
          );
        }
      },
    );
  }

  // ---------------- Goals ----------------

  Future<int> addGoal(Goal goal) async {
    final db = await database;
    final map = goal.toMap();
    map.remove('id');
    return db.insert('goals', map);
  }

  Future<void> updateGoal(Goal goal) async {
    final db = await database;
    if (goal.id == null) throw Exception('updateGoal requires an id');
    await db.update('goals', goal.toMap(), where: 'id = ?', whereArgs: [goal.id]);
  }

  Future<void> deleteGoal(int id) async {
    final db = await database;
    await db.delete('goals', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Goal>> getGoals({bool includeInactive = true}) async {
    final db = await database;
    final rows = await db.query(
      'goals',
      where: includeInactive ? null : 'isActive = 1',
      orderBy: 'createdAt DESC',
    );
    return rows.map(Goal.fromMap).toList();
  }

  Future<Goal?> getMainGoal() async {
    final db = await database;
    final rows = await db.query(
      'goals',
      where: 'isMain = 1',
      orderBy: 'createdAt DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Goal.fromMap(rows.first);
  }

  Future<void> setMainGoal(int? goalId) async {
    final db = await database;
    await db.transaction((txn) async {
      // Clear any existing main goal.
      await txn.update('goals', {'isMain': 0}, where: 'isMain = 1');
      if (goalId != null) {
        await txn.update('goals', {'isMain': 1}, where: 'id = ?', whereArgs: [goalId]);
      }
    });
  }

  // Mission CRUD
  Future<int> addMission(Mission mission) async {
    final db = await database;
    final map = mission.toMap();
    map.remove('id'); // Remove id for auto-increment
    return await db.insert('missions', map);
  }

  Future<List<Mission>> getMissions() async {
    final db = await database;
    final result = await db.query('missions');
    return result.map((map) => Mission.fromMap(map)).toList();
  }

  Future<void> updateMission(Mission mission) async {
    final db = await database;
    await db.update(
      'missions',
      mission.toMap(),
      where: 'id = ?',
      whereArgs: [mission.id],
    );
  }

  Future<void> deleteMission(String id) async {
    final db = await database;
    await db.delete('missions', where: 'id = ?', whereArgs: [int.parse(id)]);
  }

  // MoneySource CRUD
  Future<int> addMoneySource(MoneySource source) async {
    final db = await database;
    final map = source.toMap();
    map.remove('id'); // Remove id for auto-increment
    return await db.insert('money_sources', map);
  }

  Future<List<MoneySource>> getMoneySources() async {
    final db = await database;
    final result = await db.query('money_sources');
    return result.map((map) => MoneySource.fromMap(map)).toList();
  }

  Future<void> updateMoneySource(MoneySource source) async {
    final db = await database;
    await db.update(
      'money_sources',
      source.toMap(),
      where: 'id = ?',
      whereArgs: [source.id],
    );
  }

  Future<void> deleteMoneySource(String id) async {
    final db = await database;
    final parsedId = int.parse(id);
    await db.delete('money_source_changes', where: 'sourceId = ?', whereArgs: [parsedId]);
    await db.delete('money_sources', where: 'id = ?', whereArgs: [parsedId]);
  }

  Future<int> addMoneySourceChange(MoneySourceChange change) async {
    final db = await database;
    final map = change.toMap();
    map.remove('id');
    return db.insert('money_source_changes', map);
  }

  Future<List<MoneySourceChange>> getMoneySourceChanges(int sourceId) async {
    final db = await database;
    final rows = await db.query(
      'money_source_changes',
      where: 'sourceId = ?',
      whereArgs: [sourceId],
      orderBy: 'createdAt DESC, id DESC',
    );
    return rows.map(MoneySourceChange.fromMap).toList();
  }

  Future<void> deleteMoneySourceChange(int changeId) async {
    final db = await database;
    await db.delete('money_source_changes', where: 'id = ?', whereArgs: [changeId]);
  }

  // TotalMoneyDay CRUD
  Future<int> addTotalMoneyDay(TotalMoneyDay day) async {
    final db = await database;
    final map = day.toMap();
    map.remove('id'); // Remove id for auto-increment
    return await db.insert('total_money_days', map);
  }

  Future<List<TotalMoneyDay>> getTotalMoneyDays() async {
    final db = await database;
    final result = await db.query('total_money_days');
    return result.map((map) => TotalMoneyDay.fromMap(map)).toList();
  }

  Future<void> applyAmountDeltaToHistory(DateTime effectiveDate, double delta) async {
    if (delta.abs() <= 0.0000001) return;
    final dateOnly = DateTime(effectiveDate.year, effectiveDate.month, effectiveDate.day);
    final days = await getTotalMoneyDays();
    days.sort((a, b) => a.date.compareTo(b.date));

    final existingIndex = days.indexWhere((d) =>
        d.date.year == dateOnly.year && d.date.month == dateOnly.month && d.date.day == dateOnly.day);

    if (existingIndex == -1) {
      double baseTotal;
      final previousDays = days.where((d) => d.date.isBefore(dateOnly)).toList();
      if (previousDays.isNotEmpty) {
        previousDays.sort((a, b) => a.date.compareTo(b.date));
        baseTotal = previousDays.last.totalAmount;
      } else if (days.isNotEmpty) {
        baseTotal = days.first.totalAmount;
      } else {
        final sources = await getMoneySources();
        baseTotal = sources.fold<double>(0, (sum, source) => sum + source.amount) - delta;
      }
      await addTotalMoneyDay(TotalMoneyDay.create(date: dateOnly, totalAmount: baseTotal + delta));
    } else {
      final day = days[existingIndex];
      await updateTotalMoneyDay(TotalMoneyDay(
        id: day.id,
        date: day.date,
        totalAmount: day.totalAmount + delta,
        note: day.note,
      ));
    }

    final refreshed = await getTotalMoneyDays();
    for (final day in refreshed) {
      final dayOnly = DateTime(day.date.year, day.date.month, day.date.day);
      if (!dayOnly.isAfter(dateOnly)) continue;
      await updateTotalMoneyDay(TotalMoneyDay(
        id: day.id,
        date: day.date,
        totalAmount: day.totalAmount + delta,
        note: day.note,
      ));
    }
  }

  Future<void> updateTotalMoneyDay(TotalMoneyDay day) async {
    final db = await database;
    if (day.id == null) {
      throw Exception('updateTotalMoneyDay requires an id');
    }

    // Protect notes from being accidentally wiped by callers that update only totals.
    // If the incoming note is null, treat it as "unchanged" and preserve the stored value.
    String? noteToWrite = day.note;
    if (noteToWrite == null) {
      final existing = await db.query(
        'total_money_days',
        columns: const ['note'],
        where: 'id = ?',
        whereArgs: [day.id],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        noteToWrite = existing.first['note'] as String?;
      }
    }

    await db.update(
      'total_money_days',
      {
        'id': day.id,
        'date': day.date.toIso8601String(),
        'totalAmount': day.totalAmount,
        'note': noteToWrite,
      },
      where: 'id = ?',
      whereArgs: [day.id],
    );
  }

  Future<void> deleteTotalMoneyDay(String id) async {
    final db = await database;
    await db.delete('total_money_days', where: 'id = ?', whereArgs: [int.parse(id)]);
  }

  Future<void> clearTotalMoneyDayNote(int dayId) async {
    final db = await database;
    await db.update(
      'total_money_days',
      {'note': null},
      where: 'id = ?',
      whereArgs: [dayId],
    );
  }

  // ---------------- Tags ----------------
  Future<Tag> ensureTag({required String name, required TagType type}) async {
    final db = await database;
    final normalized = name.trim();
    if (normalized.isEmpty) throw Exception('Tag name can\'t be empty');

    final existing = await db.query(
      'tags',
      where: 'name = ? AND type = ?',
      whereArgs: [normalized, type.dbValue],
      limit: 1,
    );
    if (existing.isNotEmpty) return Tag.fromMap(existing.first);

    final id = await db.insert('tags', {'name': normalized, 'type': type.dbValue});
    return Tag(id: id, name: normalized, type: type);
  }

  Future<List<Tag>> getTags({TagType? type}) async {
    final db = await database;
    final rows = await db.query(
      'tags',
      where: type == null ? null : 'type = ?',
      whereArgs: type == null ? null : [type.dbValue],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Tag.fromMap).toList();
  }

  Future<void> deleteTag(int id) async {
    final db = await database;
    await db.delete('tags', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> renameTag({
    required int id,
    required String newName,
  }) async {
    final db = await database;
    final normalized = newName.trim();
    if (normalized.isEmpty) {
      throw Exception('Tag name can\'t be empty');
    }

    await db.update(
      'tags',
      {'name': normalized},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------- Delta entries ----------------
  Future<List<TotalMoneyDayDeltaEntry>> getDeltaEntriesForDay(int dayId) async {
    final db = await database;
    final rows = await db.query(
      'total_money_day_delta_entries',
      where: 'dayId = ?',
      whereArgs: [dayId],
    );
    return rows.map(TotalMoneyDayDeltaEntry.fromMap).toList();
  }

  Future<List<Map<String, dynamic>>> getDeltaEntriesForDayDetailed(int dayId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT e.id, e.dayId, e.tagId, e.amount, e.autoBalanced, t.name AS tagName, t.type AS tagType
      FROM total_money_day_delta_entries e
      JOIN tags t ON t.id = e.tagId
      WHERE e.dayId = ?
    ''', [dayId]);
    return rows;
  }

  Future<Map<int, DayDeltaCategorySummary>> getDeltaSummariesForDays(List<int> dayIds) async {
    if (dayIds.isEmpty) return {};

    final db = await database;
    final placeholders = List.filled(dayIds.length, '?').join(',');
    final rows = await db.rawQuery('''
      SELECT
        e.dayId AS dayId,
        SUM(CASE WHEN t.type = 'income' THEN e.amount ELSE 0 END) AS incomeTotal,
        SUM(CASE WHEN t.type = 'expense' THEN e.amount ELSE 0 END) AS expenseTotal,
        COUNT(*) AS categoryCount
      FROM total_money_day_delta_entries e
      JOIN tags t ON t.id = e.tagId
      WHERE e.dayId IN ($placeholders)
      GROUP BY e.dayId
    ''', dayIds);

    final out = <int, DayDeltaCategorySummary>{};
    for (final row in rows) {
      final dayId = row['dayId'] as int;
      out[dayId] = DayDeltaCategorySummary(
        dayId: dayId,
        totalIncome: ((row['incomeTotal'] as num?) ?? 0).toDouble(),
        totalExpenses: ((row['expenseTotal'] as num?) ?? 0).toDouble(),
        totalCategories: (row['categoryCount'] as int?) ?? 0,
      );
    }
    return out;
  }

  Future<Map<DateTime, double>> amountsForTag(int tagId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT d.date AS date, e.amount AS amount
      FROM total_money_day_delta_entries e
      JOIN total_money_days d ON d.id = e.dayId
      WHERE e.tagId = ?
    ''', [tagId]);
    final totals = <DateTime, double>{};
    for (final row in rows) {
      final parsed = DateTime.tryParse(row['date'] as String? ?? '');
      if (parsed == null) continue;
      final day = DateTime(parsed.year, parsed.month, parsed.day);
      totals[day] = (totals[day] ?? 0) + ((row['amount'] as num?)?.toDouble() ?? 0);
    }
    return totals;
  }

  Future<int?> dayIdFor(DateTime date) async {
    final days = await getTotalMoneyDays();
    for (final day in days) {
      if (day.date.year == date.year && day.date.month == date.month && day.date.day == date.day) {
        return day.id;
      }
    }
    return null;
  }

  /// Adds [delta] to one category on that day.
  /// If the day already has an auto-balanced "Others" row, rebuild it so the
  /// new category does not sit on top of the old remainder.
  Future<void> adjustCategorizedAmount({
    required DateTime date,
    required int tagId,
    required double delta,
  }) async {
    if (delta.abs() < 0.0000001) return;
    final dayId = await dayIdFor(date);
    if (dayId == null) return;

    final rows = await getDeltaEntriesForDayDetailed(dayId);
    final hasAuto = rows.any((row) => ((row['autoBalanced'] as num?) ?? 0) > 0);
    if (!hasAuto) {
      var current = 0.0;
      for (final row in rows) {
        if (row['tagId'] == tagId) {
          current += ((row['amount'] as num?) ?? 0).toDouble();
        }
      }
      final next = current + delta;
      await upsertDeltaEntry(
        dayId: dayId,
        tagId: tagId,
        amount: next < 0 ? 0 : next,
        autoBalanced: false,
      );
      return;
    }

    final days = await getTotalMoneyDays();
    days.sort((a, b) => a.date.compareTo(b.date));
    final index = days.indexWhere((day) => day.id == dayId);
    if (index < 0) return;
    final dayDelta = index == 0
        ? days[index].totalAmount
        : days[index].totalAmount - days[index - 1].totalAmount;

    final manual = <int, double>{};
    final manualType = <int, String>{};
    for (final row in rows) {
      if (((row['autoBalanced'] as num?) ?? 0) > 0) continue;
      final id = row['tagId'] as int;
      final amount = ((row['amount'] as num?) ?? 0).toDouble();
      if (amount <= 0.0000001) continue;
      manual[id] = amount;
      manualType[id] = row['tagType'] as String? ?? TagType.expense.dbValue;
    }

    var manualIncome = 0.0;
    var manualExpense = 0.0;
    for (final entry in manual.entries) {
      if (manualType[entry.key] == TagType.income.dbValue) {
        manualIncome += entry.value;
      } else {
        manualExpense += entry.value;
      }
    }

    final old = manual[tagId] ?? 0;
    if (old > 0) {
      if (manualType[tagId] == TagType.income.dbValue) {
        manualIncome -= old;
      } else {
        manualExpense -= old;
      }
    }
    final next = old + delta;
    String? nextType = manualType[tagId];
    if (next > 0.0000001) {
      final tags = await getTags();
      for (final tag in tags) {
        if (tag.id == tagId) nextType = tag.type.dbValue;
      }
      nextType ??= TagType.expense.dbValue;
      manual[tagId] = next;
      manualType[tagId] = nextType;
      if (nextType == TagType.income.dbValue) {
        manualIncome += next;
      } else {
        manualExpense += next;
      }
    } else {
      manual.remove(tagId);
    }

    final autoIncome = dayDelta + manualExpense - manualIncome;
    final autoExpense = manualIncome - manualExpense - dayDelta;
    final snap = Map<int, double>.from(manual);
    final autoIds = <int>{};
    if (autoIncome > 0.0000001) {
      final incomeOthers = await ensureTag(name: 'Others', type: TagType.income);
      if (incomeOthers.id != null) {
        snap[incomeOthers.id!] = autoIncome;
        autoIds.add(incomeOthers.id!);
      }
    }
    if (autoExpense > 0.0000001) {
      final expenseOthers = await ensureTag(name: 'Others', type: TagType.expense);
      if (expenseOthers.id != null) {
        snap[expenseOthers.id!] = autoExpense;
        autoIds.add(expenseOthers.id!);
      }
    }
    await replaceDeltaEntriesForDay(
      dayId: dayId,
      tagIdToAmount: snap,
      autoBalancedTagIds: autoIds,
    );
  }

  Future<void> upsertDeltaEntry({
    required int dayId,
    required int tagId,
    required double amount,
    bool autoBalanced = false,
  }) async {
    final db = await database;
    // If amount is 0, delete to keep DB clean.
    if (amount.abs() < 0.0000001) {
      await db.delete(
        'total_money_day_delta_entries',
        where: 'dayId = ? AND tagId = ?',
        whereArgs: [dayId, tagId],
      );
      return;
    }

    await db.insert(
      'total_money_day_delta_entries',
      {
        'dayId': dayId,
        'tagId': tagId,
        'amount': amount,
        'autoBalanced': autoBalanced ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> replaceDeltaEntriesForDay({
    required int dayId,
    required Map<int, double> tagIdToAmount,
    Set<int> autoBalancedTagIds = const {},
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'total_money_day_delta_entries',
        where: 'dayId = ?',
        whereArgs: [dayId],
      );
      for (final entry in tagIdToAmount.entries) {
        final amount = entry.value;
        if (amount.abs() < 0.0000001) continue;
        await txn.insert(
          'total_money_day_delta_entries',
          {
            'dayId': dayId,
            'tagId': entry.key,
            'amount': amount,
            'autoBalanced': autoBalancedTagIds.contains(entry.key) ? 1 : 0,
          },
        );
      }
    });
  }

  // ---------------- Backup ----------------
  static const int backupSchemaVersion = 5;

  Future<Map<String, dynamic>> exportBackupJson() async {
    final db = await database;
    final missions = await db.query('missions');
    final sources = await db.query('money_sources');
    final days = await db.query('total_money_days');
    final tags = await db.query('tags');
    final deltaEntries = await db.query('total_money_day_delta_entries');
    final goals = await db.query('goals');
    final sourceChanges = await db.query('money_source_changes');

    return {
      'schemaVersion': backupSchemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'missions': missions,
      'money_sources': sources,
      'total_money_days': days,
      'tags': tags,
      'total_money_day_delta_entries': deltaEntries,
      'goals': goals,
      'money_source_changes': sourceChanges,
    };
  }

  Future<void> importBackupJson(
    Map<String, dynamic> json, {
    bool replace = true,
  }) async {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion is! int || schemaVersion < 1 || schemaVersion > backupSchemaVersion) {
      throw Exception('Unsupported backup schemaVersion: $schemaVersion');
    }

    final missions = (json['missions'] as List?)?.cast<Map>() ?? const [];
    final sources = (json['money_sources'] as List?)?.cast<Map>() ?? const [];
    final days = (json['total_money_days'] as List?)?.cast<Map>() ?? const [];
    final tags = (json['tags'] as List?)?.cast<Map>() ?? const [];
    final deltaEntries = (json['total_money_day_delta_entries'] as List?)?.cast<Map>() ?? const [];
    final goals = (json['goals'] as List?)?.cast<Map>() ?? const [];
    final sourceChanges = (json['money_source_changes'] as List?)?.cast<Map>() ?? const [];

    final db = await database;

    await db.transaction((txn) async {
      if (replace) {
        await txn.delete('missions');
        await txn.delete('money_source_changes');
        await txn.delete('money_sources');
        await txn.delete('total_money_days');
        await txn.delete('tags');
        await txn.delete('total_money_day_delta_entries');
        await txn.delete('goals');
        await txn.delete('sqlite_sequence');
      }

      for (final m in missions) {
        await txn.insert(
          'missions',
          m.map((k, v) => MapEntry(k.toString(), v)),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final s in sources) {
        await txn.insert(
          'money_sources',
          s.map((k, v) => MapEntry(k.toString(), v)),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final d in days) {
        await txn.insert(
          'total_money_days',
          d.map((k, v) => MapEntry(k.toString(), v)),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      // v1 backups might not have tags/entries.
      for (final t in tags) {
        await txn.insert(
          'tags',
          t.map((k, v) => MapEntry(k.toString(), v)),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final e in deltaEntries) {
        await txn.insert(
          'total_money_day_delta_entries',
          e.map((k, v) => MapEntry(k.toString(), v)),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // v1/v2 backups might not have goals.
      for (final g in goals) {
        await txn.insert(
          'goals',
          g.map((k, v) => MapEntry(k.toString(), v)),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      for (final c in sourceChanges) {
        await txn.insert(
          'money_source_changes',
          c.map((k, v) => MapEntry(k.toString(), v)),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }
}
