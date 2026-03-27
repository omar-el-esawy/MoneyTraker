import 'package:flutter/material.dart';
import 'package:money_traker/constants/app_constants.dart';
import 'package:money_traker/model/mission.dart';
import 'package:money_traker/pages/total_money/total_money_page.dart';
import 'package:money_traker/pages/history/history_page.dart';
import 'package:money_traker/pages/insights/insights_page.dart';
import 'package:money_traker/pages/settings/settings_page.dart';
import 'package:money_traker/store/money_storage.dart';
import 'package:money_traker/model/money_source.dart';
import 'package:money_traker/model/total_money_day.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const HomePage();
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  final MoneyStorage _storage = MoneyStorage();
  List<MoneySource> _sources = [];
  List<TotalMoneyDay> _historyDays = [];
  bool _isLoading = true;

  Mission? _mission;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    try {
      final loadedSources = await _storage.getMoneySources();
      if (loadedSources.isEmpty) {
        // No static/demo data: start with an empty state.
        _sources = [];
      } else {
        _sources = loadedSources;
      }

      _historyDays = await _storage.getTotalMoneyDays();
      // Load the latest mission if exists
      final missions = await _storage.getMissions();
      if (missions.isNotEmpty) {
        _mission = missions.last;
      }
      await _addOrUpdateTodayHistory();
    } catch (e, stack) {
      print('Error in _initData: $e\n$stack');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _addMoneySource(String name, double amount) async {
    final newSource = MoneySource.create(name: name, amount: amount);
    setState(() {
      _sources.add(newSource);
    });
    await _storage.addMoneySource(newSource);
    await _addOrUpdateTodayHistory();
  }

  Future<void> _editMoneySource(
    int id,
    String newName,
    double newAmount,
  ) async {
    final index = _sources.indexWhere((e) => e.id == id);
    if (index != -1) {
      final updatedSource = MoneySource(
        id: id,
        name: newName,
        amount: newAmount,
      );
      setState(() {
        _sources[index] = updatedSource;
      });
      await _storage.updateMoneySource(updatedSource);
      await _addOrUpdateTodayHistory();
    }
  }

  Future<void> _deleteMoneySource(int id) async {
    _sources.removeWhere((source) => source.id == id);
    await _storage.deleteMoneySource(id.toString());
    await _addOrUpdateTodayHistory();
    setState(() {});
  }

  double _getTotalMoney() {
    return _sources.fold(0.0, (sum, e) => sum + e.amount);
  }

  Future<void> _addOrUpdateTodayHistory() async {
    final today = DateTime.now();
    final total = _getTotalMoney();

    // Ensure history is sorted by date
    _historyDays.sort((a, b) => a.date.compareTo(b.date));

    if (_historyDays.isNotEmpty) {
      final lastDay = _historyDays.last.date;
      final daysGap =
          today
              .difference(DateTime(lastDay.year, lastDay.month, lastDay.day))
              .inDays;

      // If there is a gap, fill it with the last known amount
      if (daysGap > 1) {
        for (int i = 1; i < daysGap; i++) {
          final gapDate = DateTime(
            lastDay.year,
            lastDay.month,
            lastDay.day,
          ).add(Duration(days: i));
          final gapDay = TotalMoneyDay.create(
            date: gapDate,
            totalAmount: _historyDays.last.totalAmount,
          );
          await _storage.addTotalMoneyDay(gapDay);
        }
      }
    }

    final existingDay = _historyDays.firstWhere(
      (day) =>
          day.date.year == today.year &&
          day.date.month == today.month &&
          day.date.day == today.day,
      orElse: () => TotalMoneyDay.create(date: today, totalAmount: 0.0),
    );

    if (existingDay.id == null) {
      final newDay = TotalMoneyDay.create(date: today, totalAmount: total);
      await _storage.addTotalMoneyDay(newDay);
    } else {
      final updatedDay = TotalMoneyDay(
        id: existingDay.id,
        date: today,
        totalAmount: total,
        note: existingDay.note,
      );
      await _storage.updateTotalMoneyDay(updatedDay);
    }

    _historyDays = await _storage.getTotalMoneyDays();
  }

  Future<void> _addMission(Mission mission) async {
    await _storage.addMission(mission);
    setState(() {
      _mission = mission;
    });
  }

  Future<void> _reloadAllData() async {
    setState(() {
      _isLoading = true;
    });
    await _initData();
  }

  Future<void> _reloadHistoryDaysOnly() async {
    try {
      final days = await _storage.getTotalMoneyDays();
      if (!mounted) return;
      setState(() {
        _historyDays = days;
      });
    } catch (e) {
      // Ignore errors; history will refresh on full reload.
    }
  }

  Future<void> _adjustMoneySourceByName(String name, double delta) async {
    final idx = _sources.indexWhere((s) => s.name == name);
    if (idx == -1) return;
    final src = _sources[idx];
    if (src.id == null) return;

    final updated = src.copyWith(amount: src.amount + delta);
    setState(() {
      _sources[idx] = updated;
    });
    await _storage.updateMoneySource(updated);
    await _addOrUpdateTodayHistory();
  }

  Future<void> _transferBetweenSources({
    required String from,
    required String to,
    required double amount,
  }) async {
    if (from == to) return;
    if (amount <= 0) return;

    final fromIdx = _sources.indexWhere((s) => s.name == from);
    final toIdx = _sources.indexWhere((s) => s.name == to);
    if (fromIdx == -1 || toIdx == -1) return;

    final fromSrc = _sources[fromIdx];
    final toSrc = _sources[toIdx];
    if (fromSrc.id == null || toSrc.id == null) return;

    // Prevent negative values.
    if (fromSrc.amount < amount) return;

    final updatedFrom = fromSrc.copyWith(amount: fromSrc.amount - amount);
    final updatedTo = toSrc.copyWith(amount: toSrc.amount + amount);

    setState(() {
      _sources[fromIdx] = updatedFrom;
      _sources[toIdx] = updatedTo;
    });

    await _storage.updateMoneySource(updatedFrom);
    await _storage.updateMoneySource(updatedTo);
    await _addOrUpdateTodayHistory();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppConstants.backgroundColor,
        body: Center(
          child: Image.asset(
            AppConstants.splashImage,
            width: 180,
            height: 180,
            fit: BoxFit.contain,
          ),
        ),
      );
    }

    final pages = [
      TotalMoneyPage(
        moneySources: {for (var s in _sources) s.name: s.amount},
        onAddSource: _addMoneySource,
        onEditSource: (name, newName, newAmount) {
          final source = _sources.firstWhere(
            (s) => s.name == name,
            orElse: () => MoneySource.create(name: '', amount: 0.0),
          );
          if (source.id != null) {
            _editMoneySource(source.id!, newName, newAmount);
          }
        },
        onDeleteSource: (name) {
          final source = _sources.firstWhere(
            (s) => s.name == name,
            orElse: () => MoneySource.create(name: '', amount: 0.0),
          );
          if (source.id != null) {
            _deleteMoneySource(source.id!);
          }
        },
        onQuickAdd: (name, delta) => _adjustMoneySourceByName(name, delta),
        onQuickSubtract: (name, delta) => _adjustMoneySourceByName(name, -delta),
        onTransfer: (from, to, amount) => _transferBetweenSources(from: from, to: to, amount: amount),
        mission: _mission,
        onAddMission: _addMission,
      ),
      HistoryPage(historyDays: _historyDays),
      const InsightsPage(),
      SettingsPage(onDataImported: _reloadAllData),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_selectedIndex]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: AppConstants.primaryColor,
        // Selected icon/label color
        unselectedItemColor: AppConstants.textTertiary,
        // Unselected icon/label color
        backgroundColor: AppConstants.surfaceColor,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: FaIcon(FontAwesomeIcons.wallet),
            label: 'Total Money',
          ),
          BottomNavigationBarItem(
            icon: FaIcon(FontAwesomeIcons.moneyCheckDollar),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.insights),
            label: 'Insights',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });

          // History notes are edited inside HistoryPage and saved to DB.
          // When leaving and returning, refresh the in-memory list so the UI
          // reflects the latest saved notes without needing an app restart.
          if (index == 1) {
            _reloadHistoryDaysOnly();
          }
        },
      ),
    );
  }
}
