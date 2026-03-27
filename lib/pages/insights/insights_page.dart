import 'package:flutter/material.dart';
import 'package:money_traker/model/tag.dart';
import 'package:money_traker/model/goal.dart';
import 'package:money_traker/pages/goals/logic/goal_engine.dart';
import 'package:money_traker/store/money_storage.dart';

enum InsightsRange { day, week, month }

extension InsightsRangeUi on InsightsRange {
  String get label {
    switch (this) {
      case InsightsRange.day:
        return 'Day';
      case InsightsRange.week:
        return 'Week';
      case InsightsRange.month:
        return 'Month';
    }
  }
}

class InsightsPage extends StatefulWidget {
  const InsightsPage({super.key});

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> with SingleTickerProviderStateMixin {
  final MoneyStorage _storage = MoneyStorage();

  late final TabController _tabController;

  InsightsRange _range = InsightsRange.month;
  DateTime _anchor = DateTime.now();

  bool _loading = true;

  bool _loadingMainGoal = true;
  GoalProgress? _mainGoal;

  // tagName -> total
  Map<String, double> _income = {};
  Map<String, double> _expense = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
    _loadMainGoal();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _startOfWeek(DateTime d) {
    final dd = _dateOnly(d);
    // make Monday start (1)
    return dd.subtract(Duration(days: dd.weekday - DateTime.monday));
  }

  DateTime _startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

  DateTimeRange _currentRange() {
    final a = _dateOnly(_anchor);
    switch (_range) {
      case InsightsRange.day:
        return DateTimeRange(start: a, end: a.add(const Duration(days: 1)));
      case InsightsRange.week:
        final s = _startOfWeek(a);
        return DateTimeRange(start: s, end: s.add(const Duration(days: 7)));
      case InsightsRange.month:
        final s = _startOfMonth(a);
        final e = (s.month == 12) ? DateTime(s.year + 1, 1, 1) : DateTime(s.year, s.month + 1, 1);
        return DateTimeRange(start: s, end: e);
    }
  }

  String _fmt(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final db = await _storage.database;
    final range = _currentRange();

    // Pull days (id + totalAmount + date) in range.
    final days = await db.query(
      'total_money_days',
      where: 'date >= ? AND date < ?',
      whereArgs: [range.start.toIso8601String(), range.end.toIso8601String()],
      columns: const ['id', 'date', 'totalAmount'],
      orderBy: 'date ASC',
    );

    if (days.isEmpty) {
      if (!mounted) return;
      setState(() {
        _income = {'Others': 0};
        _expense = {'Others': 0};
        _loading = false;
      });
      return;
    }

    // Total positive/negative deltas inside the range.
    // For the first day in range we need the previous day just before the range starts.
    final firstDate = DateTime.parse(days.first['date'] as String);
    final prevDayRows = await db.query(
      'total_money_days',
      where: 'date < ?',
      whereArgs: [firstDate.toIso8601String()],
      columns: const ['date', 'totalAmount'],
      orderBy: 'date DESC',
      limit: 1,
    );

    double? prevTotal = prevDayRows.isNotEmpty
        ? (prevDayRows.first['totalAmount'] as num).toDouble()
        : null;

    double totalIncomeDelta = 0;
    double totalExpenseDelta = 0;

    for (final row in days) {
      final curTotal = (row['totalAmount'] as num).toDouble();
      if (prevTotal != null) {
        final delta = curTotal - prevTotal;
        if (delta > 0) totalIncomeDelta += delta;
        if (delta < 0) totalExpenseDelta += delta.abs();
      }
      prevTotal = curTotal;
    }

    final dayIds = days.map((e) => e['id'] as int).toList();
    final placeholders = List.filled(dayIds.length, '?').join(',');

    // Load tagged entries for all days in range
    final entries = await db.rawQuery('''
      SELECT e.amount, t.name, t.type
      FROM total_money_day_delta_entries e
      JOIN tags t ON t.id = e.tagId
      WHERE e.dayId IN ($placeholders)
    ''', dayIds);

    final income = <String, double>{};
    final expense = <String, double>{};

    for (final row in entries) {
      final name = row['name'] as String;
      final type = TagTypeDb.fromDb(row['type'] as String);
      final amount = (row['amount'] as num).toDouble();

      if (type == TagType.income) {
        income[name] = (income[name] ?? 0) + amount;
      } else {
        expense[name] = (expense[name] ?? 0) + amount;
      }
    }

    double sumMap(Map<String, double> m) => m.values.fold(0.0, (a, b) => a + b);

    // Force an Others bucket to represent untagged activity.
    // If the user tagged nothing, Others becomes the whole total.
    final taggedIncome = sumMap(income);
    final taggedExpense = sumMap(expense);

    final computedOthersIncome = (totalIncomeDelta - taggedIncome);
    final computedOthersExpense = (totalExpenseDelta - taggedExpense);

    // Never show negative Others due to rounding; clamp to 0.
    income['Others'] = (income['Others'] ?? 0) + (computedOthersIncome > 0 ? computedOthersIncome : 0);
    expense['Others'] = (expense['Others'] ?? 0) + (computedOthersExpense > 0 ? computedOthersExpense : 0);

    // sort maps by value desc but keep Others present
    Map<String, double> sortByValueDesc(Map<String, double> m) {
      final entries = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return {for (final e in entries) e.key: e.value};
    }

    if (!mounted) return;
    setState(() {
      _income = sortByValueDesc(income);
      _expense = sortByValueDesc(expense);
      _loading = false;
    });
  }

  Future<void> _loadMainGoal() async {
    if (!mounted) return;
    setState(() => _loadingMainGoal = true);
    try {
      final mg = await _storage.getMainGoal();
      if (mg == null || !mg.isActive) {
        if (!mounted) return;
        setState(() {
          _mainGoal = null;
          _loadingMainGoal = false;
        });
        return;
      }

      final engine = GoalEngine(_storage);
      final progress = await engine.computeProgress(mg);
      if (!mounted) return;
      setState(() {
        _mainGoal = progress;
        _loadingMainGoal = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _mainGoal = null;
        _loadingMainGoal = false;
      });
    }
  }

  Widget _buildMainGoalCard(BuildContext context) {
    if (_loadingMainGoal) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const SizedBox(
          height: 44,
          child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
        ),
      );
    }

    final p = _mainGoal;
    if (p == null) return const SizedBox.shrink();

    final spentMode = p.goal.direction == GoalDirection.spendingLimit;
    final accent = spentMode ? const Color(0xFFD32F2F) : const Color(0xFF1B5E20);

    final remaining = p.goal.targetAmount - p.progress;
    final exceeded = remaining < 0;
    final remainingColor = exceeded ? const Color(0xFFD32F2F) : const Color(0xFF6B7280);

    final pct = p.percent.isNaN ? 0.0 : p.percent.clamp(0.0, 1.0);

    final modeLabel = spentMode ? 'Spending' : 'Saving';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  p.goal.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                modeLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF9CA3AF)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 10,
              backgroundColor: const Color(0xFFF0F0F0),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${p.progress.toStringAsFixed(2)} / ${p.goal.targetAmount.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                'Remaining: ${remaining.toStringAsFixed(2)}',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: remainingColor, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickAnchorDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchor,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _anchor = picked);
    await _load();
  }

  Future<void> _deleteTagByName(String tagName, TagType type) async {
    final normalized = tagName.trim();
    if (normalized.toLowerCase() == 'others') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The "Others" tag can\'t be deleted.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete tag'),
        content: Text('Delete "$normalized"? This will remove it from all days in your history.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirmed != true) return;

    final db = await _storage.database;
    final rows = await db.query(
      'tags',
      columns: const ['id'],
      where: 'name = ? AND type = ?',
      whereArgs: [normalized, type.dbValue],
      limit: 1,
    );

    if (rows.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tag not found.')),
      );
      return;
    }

    final tagId = rows.first['id'] as int;

    // Ensure entries are deleted even if SQLite foreign keys are disabled.
    await db.transaction((txn) async {
      await txn.delete('total_money_day_delta_entries', where: 'tagId = ?', whereArgs: [tagId]);
      await txn.delete('tags', where: 'id = ?', whereArgs: [tagId]);
    });

    if (!mounted) return;
    await _load();
  }

  Widget _buildList(
    Map<String, double> m, {
    required Color dot,
    required String emptyText,
    required TagType type,
  }) {
    if (m.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(emptyText),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          ...m.entries.map(
            (e) {
              final isOthers = e.key.trim().toLowerCase() == 'others';
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                title: Text(e.key),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(e.value.toStringAsFixed(2)),
                    const SizedBox(width: 8),
                    if (!isOthers)
                      IconButton(
                        tooltip: 'Delete tag',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteTagByName(e.key, type),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final range = _currentRange();
    final rangeTitle = '${_fmt(range.start)} → ${_fmt(range.end.subtract(const Duration(days: 1)))}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Expenses'),
            Tab(text: 'Income'),
          ],
        ),
        actions: [
          IconButton(onPressed: _pickAnchorDate, icon: const Icon(Icons.calendar_today)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadMainGoal();
          await _load();
        },
        child: _loading
            ? ListView(children: const [SizedBox(height: 250), Center(child: CircularProgressIndicator())])
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildMainGoalCard(context),
                  if (_mainGoal != null) const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: InsightsRange.values
                        .map(
                          (r) => ChoiceChip(
                            label: Text(r.label),
                            selected: _range == r,
                            onSelected: (v) async {
                              if (!v) return;
                              setState(() => _range = r);
                              await _load();
                            },
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 10),
                  Text(rangeTitle, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.70,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildList(
                          _expense,
                          dot: const Color(0xFFDC2626),
                          emptyText: 'No expenses tagged in this range yet.',
                          type: TagType.expense,
                        ),
                        _buildList(
                          _income,
                          dot: const Color(0xFF16A34A),
                          emptyText: 'No income tagged in this range yet.',
                          type: TagType.income,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

