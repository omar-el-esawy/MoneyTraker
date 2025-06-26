import 'package:flutter/material.dart';
import 'package:money_traker/constants/app_constants.dart';
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
  bool _isLoading = true; // New flag

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    try {
      final loadedSources = await _storage.loadMoneySources();
      if (loadedSources.isEmpty) {
        _sources = [
          MoneySource(name: 'Cash', amount: 0.0),
          MoneySource(name: 'Bank', amount: 0.0),
          MoneySource(name: 'Other', amount: 0.0),
        ];
        await _storage.saveMoneySources(_sources);
      } else {
        _sources = loadedSources;
      }

      _historyDays = await _storage.loadHistory();
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
    setState(() {
      _sources.add(MoneySource(name: name, amount: amount));
    });
    await _storage.saveMoneySources(_sources);
    await _addOrUpdateTodayHistory();
  }

  Future<void> _editMoneySource(String oldName, String newName, double newAmount) async {
    final index = _sources.indexWhere((e) => e.name == oldName);
    if (index != -1) {
      setState(() {
        _sources[index] = MoneySource(name: newName, amount: newAmount);
      });
      await _storage.saveMoneySources(_sources);
      await _addOrUpdateTodayHistory();
    }
  }

  Future<void> _deleteMoneySource(String name) async {
    setState(() {
      _sources.removeWhere((source) => source.name == name);
    });
    await _storage.deleteMoneySource(name);
    await _addOrUpdateTodayHistory();
  }

  double _getTotalMoney() {
    return _sources.fold(0.0, (sum, e) => sum + e.amount);
  }

  Future<void> _addOrUpdateTodayHistory() async {
    final today = DateTime.now();
    final total = _getTotalMoney();
    await _storage.updateTotalMoneyOfDay(today, total);
    _historyDays = await _storage.loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      // Show splash image instead of CircularProgressIndicator
      return Scaffold(
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
        onEditSource: _editMoneySource,
        onDeleteSource: _deleteMoneySource, // Pass the delete callback
      ),
      HistoryPage(historyDays: _historyDays),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.homePageTitle),
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        items: const [
          BottomNavigationBarItem(
            icon: FaIcon(FontAwesomeIcons.wallet), // Replaced with Font Awesome icon
            label: 'Total Money',
          ),
          BottomNavigationBarItem(
            icon: FaIcon(FontAwesomeIcons.moneyCheckAlt), // Replaced with Font Awesome icon
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
