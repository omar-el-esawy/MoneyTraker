import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:money_traker/model/mission.dart';
import 'package:money_traker/model/money_source.dart';
import 'package:money_traker/model/total_money_day.dart';

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
      version: 3, // Increment version for note column
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
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE total_money_days ADD COLUMN note TEXT');
        }
        // Drop and recreate tables to fix schema issues (dev only, will erase data)
        await db.execute('DROP TABLE IF EXISTS missions');
        await db.execute('DROP TABLE IF EXISTS money_sources');
        await db.execute('DROP TABLE IF EXISTS total_money_days');
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
      },
    );
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
    await db.delete('money_sources', where: 'id = ?', whereArgs: [int.parse(id)]);
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

  Future<void> updateTotalMoneyDay(TotalMoneyDay day) async {
    final db = await database;
    await db.update(
      'total_money_days',
      day.toMap(),
      where: 'id = ?',
      whereArgs: [day.id],
    );
  }

  Future<void> deleteTotalMoneyDay(String id) async {
    final db = await database;
    await db.delete('total_money_days', where: 'id = ?', whereArgs: [int.parse(id)]);
  }
}
