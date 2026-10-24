import 'dart:async';

import 'package:flutter/material.dart';
import 'package:money_traker/constants/app_constants.dart';
import 'package:money_traker/model/mission.dart';
import 'package:money_traker/pages/total_money/total_money_page.dart';
import 'package:money_traker/pages/history/history_page.dart';
import 'package:money_traker/pages/insights/insights_page.dart';
import 'package:money_traker/pages/settings/settings_page.dart';
import 'package:money_traker/store/amount_visibility_store.dart';
import 'package:money_traker/store/money_storage.dart';
import 'package:money_traker/model/money_source.dart';
import 'package:money_traker/model/money_source_change.dart';
import 'package:money_traker/model/tag.dart';
import 'package:money_traker/model/total_money_day.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:money_traker/data/transaction_repository.dart';
import 'package:money_traker/domain/entities/transaction_entity.dart';
import 'package:money_traker/services/backup_service.dart';
import 'package:money_traker/services/notification_service.dart';
import 'package:money_traker/services/sync_service.dart';
import 'package:money_traker/tour/app_tour.dart';

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

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  final MoneyStorage _storage = MoneyStorage();
  List<MoneySource> _sources = [];
  List<TotalMoneyDay> _historyDays = [];
  bool _isLoading = true;
  bool _showAmounts = true;

  bool _isSmsSyncing = false;
  List<TransactionEntity> _smsTransactions = [];

  Mission? _mission;

  final AppTourAnchors _tourAnchors = AppTourAnchors();
  List<AppTourStep> _tourSteps = const [];
  bool _tourVisible = false;
  int _tourIndex = 0;
  bool _tourCheckStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initData();
    _syncSms();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncSms();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initData() async {
    var showAmounts = _showAmounts;
    try {
      showAmounts = await AmountVisibilityStore.load();
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
      unawaited(BackupService.instance.writeAutomaticBackup());
    } catch (e, stack) {
      // Use debugPrint for safer logging in production builds.
      debugPrint('Error in _initData: $e\n$stack');
    }
    if (!mounted) return;
    setState(() {
      _showAmounts = showAmounts;
      _isLoading = false;
    });
    _scheduleTourIfNeeded();
  }

  void _setShowAmounts(bool value) {
    setState(() => _showAmounts = value);
    unawaited(AmountVisibilityStore.save(value));
  }

  void _scheduleTourIfNeeded() {
    if (_tourCheckStarted) return;
    _tourCheckStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (!mounted || _tourVisible) return;
        final seen = await AppTourStore.hasSeen();
        if (!mounted || seen || _tourVisible) return;
        _startTour();
      } catch (e, stack) {
        debugPrint('Tour check failed: $e\n$stack');
      }
    });
  }

  void _startTour() {
    final steps = AppTourSteps.compose(
      _tourAnchors,
      hasSources: _sources.isNotEmpty,
      hasHistoryDays: _historyDays.isNotEmpty,
    );
    setState(() {
      _tourSteps = steps;
      _tourIndex = 0;
      _tourVisible = true;
      _selectedIndex = steps.first.tab;
    });
  }

  void _showTourStep(int index) {
    if (index < 0 || index >= _tourSteps.length) return;
    setState(() {
      _tourIndex = index;
      _selectedIndex = _tourSteps[index].tab;
    });
    if (_selectedIndex == AppTourSteps.historyTab) {
      _reloadHistoryDaysOnly();
    }
  }

  void _tourNext() {
    if (_tourIndex >= _tourSteps.length - 1) {
      _finishTour();
      return;
    }
    _showTourStep(_tourIndex + 1);
  }

  void _tourBack() {
    if (_tourIndex == 0) return;
    _showTourStep(_tourIndex - 1);
  }

  Future<void> _finishTour() async {
    if (!mounted) return;
    setState(() {
      _tourVisible = false;
      _tourSteps = const [];
      _tourIndex = 0;
    });
    try {
      await AppTourStore.markSeen();
    } catch (e, stack) {
      debugPrint('Tour save failed: $e\n$stack');
    }
  }

  /// Apply a delta to historical total days starting from [effectiveDate].
  /// This will ensure a TotalMoneyDay exists for [effectiveDate] (creating one
  /// if needed) and then add [delta] to that day and all subsequent recorded days.
  Future<int?> _applyDeltaToHistory(
    DateTime effectiveDate,
    double delta,
  ) async {
    final dateOnly = DateTime(
      effectiveDate.year,
      effectiveDate.month,
      effectiveDate.day,
    );

    // Refresh the cached history from storage.
    _historyDays = await _storage.getTotalMoneyDays();
    _historyDays.sort((a, b) => a.date.compareTo(b.date));

    // Find an existing entry for the chosen date.
    final existingIndex = _historyDays.indexWhere(
      (d) =>
          d.date.year == dateOnly.year &&
          d.date.month == dateOnly.month &&
          d.date.day == dateOnly.day,
    );

    if (existingIndex == -1) {
      // Determine a sensible base total for the new day. Prefer the previous day's
      // total if available, otherwise fall back to the current total across sources.
      double baseTotal;
      final previousDays =
          _historyDays.where((d) => d.date.isBefore(dateOnly)).toList();
      if (previousDays.isNotEmpty) {
        previousDays.sort((a, b) => a.date.compareTo(b.date));
        baseTotal = previousDays.last.totalAmount;
      } else if (_historyDays.isNotEmpty) {
        // No previous day but there are later days; use the first known day's total as base.
        baseTotal = _historyDays.first.totalAmount;
      } else {
        // No history at all — use current total across sources.
        baseTotal = _getTotalMoney();
      }

      final newDay = TotalMoneyDay.create(
        date: dateOnly,
        totalAmount: baseTotal + delta,
      );
      await _storage.addTotalMoneyDay(newDay);
    } else {
      // Update the existing day by adding the delta.
      final day = _historyDays[existingIndex];
      final updated = TotalMoneyDay(
        id: day.id,
        date: day.date,
        totalAmount: day.totalAmount + delta,
        note: day.note,
      );
      await _storage.updateTotalMoneyDay(updated);
    }

    // Now refresh and apply the delta to all subsequent days (strictly after the chosen date).
    _historyDays = await _storage.getTotalMoneyDays();
    _historyDays.sort((a, b) => a.date.compareTo(b.date));

    for (final day in _historyDays) {
      final dayOnly = DateTime(day.date.year, day.date.month, day.date.day);
      if (!dayOnly.isAfter(dateOnly)) continue; // only subsequent days
      final updated = TotalMoneyDay(
        id: day.id,
        date: day.date,
        totalAmount: day.totalAmount + delta,
        note: day.note,
      );
      await _storage.updateTotalMoneyDay(updated);
    }

    // Refresh the in-memory cache once more so the UI can read the updated values.
    _historyDays = await _storage.getTotalMoneyDays();

    // Return the id for the effective date.
    final finalDay = _historyDays.firstWhere(
      (d) =>
          d.date.year == dateOnly.year &&
          d.date.month == dateOnly.month &&
          d.date.day == dateOnly.day,
      orElse: () => TotalMoneyDay.create(date: dateOnly, totalAmount: 0.0),
    );
    return finalDay.id;
  }

  Future<void> _addMoneySource(
    String name,
    double amount, {
    DateTime? effectiveDate,
  }) async {
    final newSource = MoneySource.create(name: name, amount: amount);
    final insertedId = await _storage.addMoneySource(newSource);
    final persistedSource = MoneySource(
      id: insertedId,
      name: name,
      amount: amount,
    );

    await _storage.addMoneySourceChange(
      MoneySourceChange(
        sourceId: insertedId,
        deltaAmount: amount,
        resultingAmount: amount,
        createdAt: effectiveDate ?? DateTime.now(),
        type: MoneySourceChangeType.created,
      ),
    );

    setState(() {
      _sources.add(persistedSource);
    });
    // If the change is being backdated to an older day, update history from that day;
    // otherwise update today as usual.
    if (effectiveDate == null) {
      await _addOrUpdateTodayHistory();
    } else {
      await _applyDeltaToHistory(effectiveDate, amount);
    }
  }

  Future<void> _editMoneySource(
    int id,
    String newName,
    double newAmount, {
    DateTime? effectiveDate,
  }) async {
    final index = _sources.indexWhere((e) => e.id == id);
    if (index != -1) {
      final oldSource = _sources[index];
      final updatedSource = MoneySource(
        id: id,
        name: newName,
        amount: newAmount,
      );
      setState(() {
        _sources[index] = updatedSource;
      });
      await _storage.updateMoneySource(updatedSource);
      await _storage.addMoneySourceChange(
        MoneySourceChange(
          sourceId: id,
          deltaAmount: newAmount - oldSource.amount,
          resultingAmount: newAmount,
          createdAt: effectiveDate ?? DateTime.now(),
          type: MoneySourceChangeType.edited,
          note:
              oldSource.name == newName
                  ? null
                  : 'Renamed from ${oldSource.name}',
        ),
      );
      final delta = newAmount - oldSource.amount;
      if (effectiveDate == null) {
        await _addOrUpdateTodayHistory();
      } else if (delta.abs() > 0.0000001) {
        await _applyDeltaToHistory(effectiveDate, delta);
      }
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

  Future<int?> _addOrUpdateTodayHistory() async {
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

    int? todayDayId;
    if (existingDay.id == null) {
      final newDay = TotalMoneyDay.create(date: today, totalAmount: total);
      todayDayId = await _storage.addTotalMoneyDay(newDay);
    } else {
      final updatedDay = TotalMoneyDay(
        id: existingDay.id,
        date: today,
        totalAmount: total,
        note: existingDay.note,
      );
      await _storage.updateTotalMoneyDay(updatedDay);
      todayDayId = existingDay.id;
    }

    _historyDays = await _storage.getTotalMoneyDays();

    if (todayDayId == null) {
      final todayRow = _historyDays.firstWhere(
        (day) =>
            day.date.year == today.year &&
            day.date.month == today.month &&
            day.date.day == today.day,
        orElse: () => TotalMoneyDay.create(date: today, totalAmount: 0.0),
      );
      todayDayId = todayRow.id;
    }

    return todayDayId;
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

  Future<void> _adjustMoneySourceByName(
    String name,
    double delta, {
    String? categoryName,
    double? categoryAmount,
    DateTime? effectiveDate,
  }) async {
    final idx = _sources.indexWhere((s) => s.name == name);
    if (idx == -1) return;
    final src = _sources[idx];
    if (src.id == null) return;

    final updated = src.copyWith(amount: src.amount + delta);
    setState(() {
      _sources[idx] = updated;
    });
    await _storage.updateMoneySource(updated);
    await _storage.addMoneySourceChange(
      MoneySourceChange(
        sourceId: src.id!,
        deltaAmount: delta,
        resultingAmount: updated.amount,
        createdAt: effectiveDate ?? DateTime.now(),
        type:
            delta >= 0
                ? MoneySourceChangeType.add
                : MoneySourceChangeType.subtract,
      ),
    );
    int? targetDayId;
    if (effectiveDate == null) {
      targetDayId = await _addOrUpdateTodayHistory();
    } else {
      targetDayId = await _applyDeltaToHistory(effectiveDate, delta);
    }

    final normalizedCategory = categoryName?.trim();
    if (targetDayId == null ||
        normalizedCategory == null ||
        normalizedCategory.isEmpty) {
      return;
    }

    final tagType = delta >= 0 ? TagType.income : TagType.expense;
    final tag = await _storage.ensureTag(
      name: normalizedCategory,
      type: tagType,
    );
    final amountToCategorize = (categoryAmount ?? delta.abs()).abs();
    if (amountToCategorize <= 0.0000001 || tag.id == null) {
      return;
    }

    final existing = await _storage.getDeltaEntriesForDay(targetDayId);
    final current = existing
        .where((e) => e.tagId == tag.id)
        .fold<double>(0.0, (sum, e) => sum + e.amount);

    await _storage.upsertDeltaEntry(
      dayId: targetDayId,
      tagId: tag.id!,
      amount: current + amountToCategorize,
      autoBalanced: false,
    );
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
    await _storage.addMoneySourceChange(
      MoneySourceChange(
        sourceId: fromSrc.id!,
        deltaAmount: -amount,
        resultingAmount: updatedFrom.amount,
        createdAt: DateTime.now(),
        type: MoneySourceChangeType.transferOut,
        note: 'To ${toSrc.name}',
      ),
    );
    await _storage.addMoneySourceChange(
      MoneySourceChange(
        sourceId: toSrc.id!,
        deltaAmount: amount,
        resultingAmount: updatedTo.amount,
        createdAt: DateTime.now(),
        type: MoneySourceChangeType.transferIn,
        note: 'From ${fromSrc.name}',
      ),
    );
    await _addOrUpdateTodayHistory();
  }

  Future<void> _syncSms() async {
    if (_isSmsSyncing) return;
    if (!mounted) return;
    setState(() => _isSmsSyncing = true);

    try {
      final before = _smsTransactions.length;
      await SyncService.instance.sync();
      final updated = await TransactionRepository.instance.getAll();
      final newCount = updated.length - before;
      final sources = await _storage.getMoneySources();
      final history = await _storage.getTotalMoneyDays();

      if (!mounted) return;
      setState(() {
        _smsTransactions = updated;
        _sources = sources;
        _historyDays = history;
        _isSmsSyncing = false;
      });

      if (newCount > 0) {
        await NotificationService.instance.sendSyncNotification(
          newCount: newCount,
          newTransactions: updated.take(newCount).toList(),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSmsSyncing = false);
    }
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
        showAmounts: _showAmounts,
        onShowAmountsChanged: _setShowAmounts,
        moneySources: {for (var s in _sources) s.name: s.amount},
        sourceIds: {
          for (var s in _sources.where((s) => s.id != null)) s.name: s.id!,
        },
        onAddSource: _addMoneySource,
        onEditSource: (name, newName, newAmount, {DateTime? effectiveDate}) {
          final source = _sources.firstWhere(
            (s) => s.name == name,
            orElse: () => MoneySource.create(name: '', amount: 0.0),
          );
          if (source.id != null) {
            _editMoneySource(
              source.id!,
              newName,
              newAmount,
              effectiveDate: effectiveDate,
            );
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
        onQuickAdd:
            (
              name,
              delta, {
              categoryName,
              categoryAmount,
              DateTime? effectiveDate,
            }) => _adjustMoneySourceByName(
              name,
              delta,
              categoryName: categoryName,
              categoryAmount: categoryAmount,
              effectiveDate: effectiveDate,
            ),
        onQuickSubtract:
            (
              name,
              delta, {
              categoryName,
              categoryAmount,
              DateTime? effectiveDate,
            }) => _adjustMoneySourceByName(
              name,
              -delta,
              categoryName: categoryName,
              categoryAmount: categoryAmount,
              effectiveDate: effectiveDate,
            ),
        onTransfer:
            (from, to, amount) =>
                _transferBetweenSources(from: from, to: to, amount: amount),
        mission: _mission,
        onAddMission: _addMission,
      ),
      HistoryPage(historyDays: _historyDays, showAmounts: _showAmounts),
      InsightsPage(showAmounts: _showAmounts),
      SettingsPage(onDataImported: _reloadAllData, onReplayTour: _startTour),
    ];

    return AppTourScope(
      anchors: _tourAnchors,
      child: Stack(
        children: [
          Scaffold(
            body: SafeArea(child: pages[_selectedIndex]),
            bottomNavigationBar: SafeArea(
              minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Container(
                key: _tourAnchors.bottomNav,
                decoration: BoxDecoration(
                  color: AppConstants.surfaceColor,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: NavigationBarTheme(
                    data: NavigationBarThemeData(
                      backgroundColor: AppConstants.surfaceColor,
                      labelTextStyle: WidgetStateProperty.resolveWith((states) {
                        final selected = states.contains(WidgetState.selected);
                        return TextStyle(
                          fontSize: 12,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color:
                              selected
                                  ? AppConstants.primaryColor
                                  : AppConstants.textTertiary,
                        );
                      }),
                      iconTheme: WidgetStateProperty.resolveWith((states) {
                        final selected = states.contains(WidgetState.selected);
                        return IconThemeData(
                          color:
                              selected
                                  ? AppConstants.primaryColor
                                  : AppConstants.textTertiary,
                          size: selected ? 22 : 20,
                        );
                      }),
                      indicatorColor: AppConstants.primarySurface,
                    ),
                    child: NavigationBar(
                      selectedIndex: _selectedIndex,
                      labelBehavior:
                          NavigationDestinationLabelBehavior.alwaysShow,
                      height: 68,
                      destinations: const [
                        NavigationDestination(
                          icon: FaIcon(FontAwesomeIcons.wallet),
                          selectedIcon: FaIcon(FontAwesomeIcons.wallet),
                          label: 'Total',
                        ),
                        NavigationDestination(
                          icon: FaIcon(FontAwesomeIcons.moneyCheckDollar),
                          selectedIcon: FaIcon(
                            FontAwesomeIcons.moneyCheckDollar,
                          ),
                          label: 'History',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.insights_outlined),
                          selectedIcon: Icon(Icons.insights),
                          label: 'Insights',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.settings_outlined),
                          selectedIcon: Icon(Icons.settings),
                          label: 'Settings',
                        ),
                      ],
                      onDestinationSelected: (index) {
                        if (_tourVisible) return;
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
                  ),
                ),
              ),
            ),
          ),
          if (_tourVisible && _tourSteps.isNotEmpty)
            Positioned.fill(
              child: AppTourOverlay(
                step: _tourSteps[_tourIndex],
                index: _tourIndex,
                total: _tourSteps.length,
                onNext: _tourNext,
                onBack: _tourBack,
                onSkip: _finishTour,
              ),
            ),
        ],
      ),
    );
  }
}
