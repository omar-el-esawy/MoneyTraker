import 'package:flutter/material.dart';
import 'package:money_traker/constants/app_constants.dart';
import 'package:money_traker/model/mission.dart';
import 'package:money_traker/pages/total_money/total_money_page.dart';
import 'package:money_traker/pages/history/history_page.dart';
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
        _sources = [
          MoneySource.create(name: 'Cash at home', amount: 18900.0),
          MoneySource.create(name: 'CIB', amount: 13.01),
          MoneySource.create(name: 'HSBC', amount: 392.30),
          MoneySource.create(name: 'I loan', amount: 6000.0),
          MoneySource.create(name: 'etisalat', amount: 891.32),
          MoneySource.create(name: 'Money on my hand', amount: 80),
          MoneySource.create(name: 'Hossam', amount: 762.0),
          MoneySource.create(name: 'e&Mashreq', amount: 606.15),
        ];
        for (var source in _sources) {
          await _storage.addMoneySource(source);
        }

        final now = DateTime.now();
        final initialHistory = <TotalMoneyDay>[
          TotalMoneyDay.create(
            date: now.subtract(const Duration(days: 6)),
            totalAmount: 30109.64,
          ),
          TotalMoneyDay.create(
            date: now.subtract(const Duration(days: 5)),
            totalAmount: 29892.12,
          ),
          TotalMoneyDay.create(
            date: now.subtract(const Duration(days: 4)),
            totalAmount: 29802.12,
          ),
          TotalMoneyDay.create(
            date: now.subtract(const Duration(days: 3)),
            totalAmount: 29820.22,
          ),
          TotalMoneyDay.create(
            date: now.subtract(const Duration(days: 2)),
            totalAmount: 29213.21,
          ),
          TotalMoneyDay.create(
            date: now.subtract(const Duration(days: 1)),
            totalAmount: 27644.78,
          ),
          TotalMoneyDay.create(
            date: now,
            totalAmount: _sources.fold(0.0, (sum, e) => sum + e.amount),
          ),
        ];
        for (var day in initialHistory) {
          await _storage.addTotalMoneyDay(day);
        }
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
    setState(() {
      _sources.removeWhere((source) => source.id == id);
    });
    await _storage.deleteMoneySource(id.toString());
    await _addOrUpdateTodayHistory();
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
          if (source != null && source.id != null) {
            _editMoneySource(source.id!, newName, newAmount);
          }
        },
        onDeleteSource: (name) {
          final source = _sources.firstWhere(
            (s) => s.name == name,
            orElse: () => MoneySource.create(name: '', amount: 0.0),
          );
          if (source != null && source.id != null) {
            _deleteMoneySource(source.id!);
          }
        },
        mission: _mission,
        onAddMission: _addMission,
      ),
      HistoryPage(historyDays: _historyDays),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_selectedIndex]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.white,
        // Selected icon color
        unselectedItemColor: Colors.black,
        // Unselected icon color
        items: const [
          BottomNavigationBarItem(
            icon: FaIcon(FontAwesomeIcons.wallet),
            label: 'Total Money',
          ),
          BottomNavigationBarItem(
            icon: FaIcon(FontAwesomeIcons.moneyCheckAlt),
            label: 'History',
          ),
        ],
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
    );
  }
}
