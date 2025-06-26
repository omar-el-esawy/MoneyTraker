import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:money_traker/model/money_source.dart';
import 'package:money_traker/model/total_money_day.dart';
import 'package:money_traker/model/mission.dart';

typedef DirectoryProvider = Future<Directory> Function();
typedef FileFactory       = File Function(String fullPath);

class MoneyStorage {
  MoneyStorage({
    DirectoryProvider? directoryProvider,
    FileFactory?       fileFactory,
  })  : _dirProvider = directoryProvider ?? getApplicationDocumentsDirectory,
        _fileFactory = fileFactory       ?? ((p) => File(p));

  // --------------------------------------------------------------------------
  // Internals
  // --------------------------------------------------------------------------
  final DirectoryProvider _dirProvider;
  final FileFactory       _fileFactory;

  static const _sourcesFile = 'money_sources.json';
  static const _historyFile = 'money_history.json';

  Future<File> _file(String name) async {
    final dir = await _dirProvider();
    return _fileFactory(p.join(dir.path, name));
  }

  // --------------------------------------------------------------------------
  // Public API
  // --------------------------------------------------------------------------
  Future<void> saveMoneySources(List<MoneySource> sources) async {
    final file = await _file(_sourcesFile);
    final json = jsonEncode(
      sources.map((e) => {'name': e.name, 'amount': e.amount}).toList(),
    );
    await file.writeAsString(json);
  }

  Future<List<MoneySource>> loadMoneySources() async {
    final file = await _file(_sourcesFile);
    if (!await file.exists()) return [];
    final data = jsonDecode(await file.readAsString()) as List<dynamic>;
    print('Loaded money sources: $data');
    return data
        .map((e) => MoneySource(
      name: e['name'].toString(),
      amount: (e['amount'] as num).toDouble(),
    ))
        .toList();
  }

  Future<void> updateMoneySourceAmount(
      String sourceName, double newAmount) async {
    final list = await loadMoneySources();
    for (final s in list) {
      if (s.name == sourceName) {
        s.amount = newAmount;
        break;
      }
    }
    await saveMoneySources(list);
  }

  Future<void> deleteMoneySource(String sourceName) async {
    final list = await loadMoneySources();
    list.removeWhere((source) => source.name == sourceName);
    await saveMoneySources(list);
  }

  Future<void> saveHistory(List<TotalMoneyDay> history) async {
    final file = await _file(_historyFile);
    final json = jsonEncode(
      history
          .map((e) => {
        'date': e.date.toIso8601String(),
        'totalAmount': e.totalAmount,
      })
          .toList(),
    );
    await file.writeAsString(json);
  }

  Future<List<TotalMoneyDay>> loadHistory() async {
    final file = await _file(_historyFile);
    if (!await file.exists()) return [];
    final data = jsonDecode(await file.readAsString()) as List<dynamic>;
    print('Loaded history: $data');
    List<TotalMoneyDay> history = data
        .map((e) => TotalMoneyDay(
      date: DateTime.parse(e['date'].toString()),
      totalAmount: (e['totalAmount'] as num).toDouble(),
    ))
        .toList();

    if (history.isEmpty) return history;

    // Sort by date ascending
    history.sort((a, b) => a.date.compareTo(b.date));

    final last = history.last;
    final today = DateTime.now();
    final lastDay = DateTime(last.date.year, last.date.month, last.date.day);
    final todayDay = DateTime(today.year, today.month, today.day);

    DateTime fillDay = lastDay.add(const Duration(days: 1));
    while (fillDay.isBefore(todayDay) || fillDay.isAtSameMomentAs(todayDay)) {
      history.add(TotalMoneyDay(date: fillDay, totalAmount: last.totalAmount));
      fillDay = fillDay.add(const Duration(days: 1));
    }

    return history;
  }

  Future<void> updateTotalMoneyOfDay(
      DateTime date, double newTotalAmount) async {
    final hist = await loadHistory();
    var found = false;
    for (final h in hist) {
      if (_sameDay(h.date, date)) {
        h.totalAmount = newTotalAmount;
        found = true;
        break;
      }
    }
    if (!found) {
      hist.add(TotalMoneyDay(date: date, totalAmount: newTotalAmount));
    }
    await saveHistory(hist);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // --------------------------------------------------------------------------
  // Mission Storage
  // --------------------------------------------------------------------------
  final List<Mission> _missions = [];

  List<Mission> get missions => _missions;

  void addMission(Mission mission) {
    _missions.add(mission);
    saveMissions();
  }

  void updateMission(Mission updatedMission) {
    final index = _missions.indexWhere((m) => m.id == updatedMission.id);
    if (index != -1) {
      _missions[index] = updatedMission;
      saveMissions();
    }
  }

  void deleteMission(String missionId) {
    _missions.removeWhere((m) => m.id == missionId);
    saveMissions();
  }

  void saveMissions() {
    // Save missions to persistent storage (e.g., SharedPreferences or a database)
    // ...existing code for saving...
  }

  void loadMissions() {
    // Load missions from persistent storage
    // ...existing code for loading...
  }

  void updateSpentAmount(String missionId, double amount) {
    final mission = _missions.firstWhere((m) => m.id == missionId, orElse: () => null as Mission);
    if (mission != null) {
      mission.spentAmount += amount;
      saveMissions();
    }
  }
}
