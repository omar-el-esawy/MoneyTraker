import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:money_traker/constants/app_constants.dart';
import 'package:money_traker/model/goal.dart';
import 'package:money_traker/model/tag.dart';
import 'package:money_traker/pages/goals/goal_detail_view.dart';
import 'package:money_traker/pages/goals/logic/goal_engine.dart';
import 'package:money_traker/pages/widgets/obscurable_amount.dart';
import 'package:money_traker/store/money_storage.dart';
import 'package:money_traker/tour/app_tour.dart';

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

const _incomePalette = <Color>[
  Color(0xFF1B5E20),
  Color(0xFF2E7D32),
  Color(0xFF00897B),
  Color(0xFF388E3C),
  Color(0xFF00796B),
  Color(0xFF558B2F),
  Color(0xFF00695C),
  Color(0xFF43A047),
  Color(0xFF689F38),
  Color(0xFF26A69A),
];

const _expensePalette = <Color>[
  Color(0xFFC62828),
  Color(0xFFE53935),
  Color(0xFFD81B60),
  Color(0xFF6D4C41),
  Color(0xFFEF6C00),
  Color(0xFF8E24AA),
  Color(0xFF5E35B1),
  Color(0xFF3949AB),
  Color(0xFF00838F),
  Color(0xFFF4511E),
];

const _othersColor = Color(0xFF9CA3AF);
const _cardBorder = Color(0xFFE6E8EC);

class InsightsPage extends StatefulWidget {
  final bool showAmounts;

  const InsightsPage({super.key, this.showAmounts = true});

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  final MoneyStorage _storage = MoneyStorage();
  final NumberFormat _money = NumberFormat('#,##0.00');

  InsightsRange _range = InsightsRange.month;
  DateTime _anchor = DateTime.now();
  bool _showingExpenses = true;
  int _touchedIndex = -1;

  bool _loading = true;
  bool _hasLoaded = false;

  bool _loadingMainGoal = true;
  GoalProgress? _mainGoal;

  // tagName -> total
  Map<String, double> _income = {};
  Map<String, double> _expense = {};

  @override
  void initState() {
    super.initState();
    _load();
    _loadMainGoal();
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
        final e =
            (s.month == 12)
                ? DateTime(s.year + 1, 1, 1)
                : DateTime(s.year, s.month + 1, 1);
        return DateTimeRange(start: s, end: e);
    }
  }

  bool get _canGoForward {
    final today = _dateOnly(DateTime.now());
    final endInclusive = _currentRange().end.subtract(const Duration(days: 1));
    return endInclusive.isBefore(today);
  }

  String _rangeLabel() {
    final range = _currentRange();
    final start = range.start;
    final end = range.end.subtract(const Duration(days: 1));
    switch (_range) {
      case InsightsRange.day:
        final today = _dateOnly(DateTime.now());
        if (start == today) return 'Today';
        if (start == today.subtract(const Duration(days: 1)))
          return 'Yesterday';
        return DateFormat('EEE, d MMM yyyy').format(start);
      case InsightsRange.week:
        if (start.year == end.year && start.month == end.month) {
          return '${DateFormat('d').format(start)} – ${DateFormat('d MMM yyyy').format(end)}';
        }
        if (start.year == end.year) {
          return '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM yyyy').format(end)}';
        }
        return '${DateFormat('d MMM yyyy').format(start)} – ${DateFormat('d MMM yyyy').format(end)}';
      case InsightsRange.month:
        return DateFormat('MMMM yyyy').format(start);
    }
  }

  String? _rangeCaption() {
    if (_range != InsightsRange.month) return null;
    final range = _currentRange();
    final start = range.start;
    final end = range.end.subtract(const Duration(days: 1));
    return '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM').format(end)}';
  }

  String _netCaption() {
    final today = _dateOnly(DateTime.now());
    final range = _currentRange();
    final current = !today.isBefore(range.start) && today.isBefore(range.end);
    switch (_range) {
      case InsightsRange.day:
        return current ? 'Net today' : 'Net for the day';
      case InsightsRange.week:
        return current ? 'Net this week' : 'Net for the week';
      case InsightsRange.month:
        return current ? 'Net this month' : 'Net for the month';
    }
  }

  String _signed(double value) {
    if (value > 0) return '+${_money.format(value)}';
    return _money.format(value);
  }

  double _sum(Map<String, double> values) =>
      values.values.fold(0.0, (a, b) => a + b);

  List<MapEntry<String, double>> _visible(Map<String, double> values) {
    return values.entries.where((e) => e.value > 0.0001).toList();
  }

  bool _isOthers(String name) => name.trim().toLowerCase() == 'others';

  Color _sliceColor(
    List<MapEntry<String, double>> entries,
    int index,
    bool income,
  ) {
    if (_isOthers(entries[index].key)) return _othersColor;
    var paletteIndex = 0;
    for (var i = 0; i < index; i++) {
      if (!_isOthers(entries[i].key)) paletteIndex++;
    }
    final palette = income ? _incomePalette : _expensePalette;
    return palette[paletteIndex % palette.length];
  }

  String _percentLabel(double part, double total) {
    if (total <= 0) return '0%';
    final pct = part / total * 100;
    if (pct >= 10) return '${pct.round()}%';
    return '${pct.toStringAsFixed(1)}%';
  }

  String _initial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, 1).toUpperCase();
  }

  Future<void> _shiftPeriod(int direction) async {
    if (direction > 0 && !_canGoForward) return;
    final current = _dateOnly(_anchor);
    final DateTime next;
    switch (_range) {
      case InsightsRange.day:
        next = current.add(Duration(days: direction));
      case InsightsRange.week:
        next = current.add(Duration(days: 7 * direction));
      case InsightsRange.month:
        next = DateTime(current.year, current.month + direction, 1);
    }
    setState(() {
      _anchor = next;
      _touchedIndex = -1;
    });
    await _load();
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
        _hasLoaded = true;
        _touchedIndex = -1;
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

    double? prevTotal =
        prevDayRows.isNotEmpty
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
    income['Others'] =
        (income['Others'] ?? 0) +
        (computedOthersIncome > 0 ? computedOthersIncome : 0);
    expense['Others'] =
        (expense['Others'] ?? 0) +
        (computedOthersExpense > 0 ? computedOthersExpense : 0);

    // sort maps by value desc but keep Others present
    Map<String, double> sortByValueDesc(Map<String, double> m) {
      final entries =
          m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return {for (final e in entries) e.key: e.value};
    }

    if (!mounted) return;
    setState(() {
      _income = sortByValueDesc(income);
      _expense = sortByValueDesc(expense);
      _loading = false;
      _hasLoaded = true;
      _touchedIndex = -1;
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

  Future<void> _pickAnchorDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchor,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _anchor = picked;
      _touchedIndex = -1;
    });
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
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete tag'),
            content: Text(
              'Delete "$normalized"? This will remove it from all days in your history.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFC62828),
                ),
                child: const Text('Delete'),
              ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Tag not found.')));
      return;
    }

    final tagId = rows.first['id'] as int;

    // Ensure entries are deleted even if SQLite foreign keys are disabled.
    await db.transaction((txn) async {
      await txn.delete(
        'total_money_day_delta_entries',
        where: 'tagId = ?',
        whereArgs: [tagId],
      );
      await txn.delete('tags', where: 'id = ?', whereArgs: [tagId]);
    });

    if (!mounted) return;
    await _load();
  }

  Future<void> _renameTagByName(String tagName, TagType type) async {
    final normalized = tagName.trim();
    if (normalized.toLowerCase() == 'others') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The "Others" tag can\'t be renamed.')),
      );
      return;
    }

    final controller = TextEditingController(text: normalized);
    final newName = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Edit category name'),
            content: TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Category name'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
    );

    if (newName == null) return;
    if (newName.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Category name can\'t be empty.')),
      );
      return;
    }
    if (newName == normalized) return;
    if (newName.toLowerCase() == 'others') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('"Others" is reserved and can\'t be used.'),
        ),
      );
      return;
    }

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Tag not found.')));
      return;
    }

    final tagId = rows.first['id'] as int;
    try {
      await _storage.renameTag(id: tagId, newName: newName);
    } on DatabaseException catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A category with this name already exists.'),
        ),
      );
      return;
    }

    if (!mounted) return;
    await _load();
  }

  BoxDecoration _cardDecoration({Color? color}) {
    return BoxDecoration(
      color: color ?? AppConstants.surfaceColor,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _cardBorder),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  Widget _segmented({
    required List<String> labels,
    required int selected,
    required ValueChanged<int> onChanged,
    Color? selectedColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF1F4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final on = index == selected;
          return Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: on ? null : () => onChanged(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: on ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow:
                        on
                            ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                            : null,
                  ),
                  child: Text(
                    labels[index],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                      color:
                          on
                              ? (selectedColor ?? AppConstants.textPrimary)
                              : AppConstants.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _roundButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
  }) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(side: BorderSide(color: _cardBorder)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              icon,
              size: 22,
              color:
                  enabled
                      ? AppConstants.textPrimary
                      : AppConstants.textTertiary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final caption = _rangeCaption();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Insights',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            _roundButton(
              icon: Icons.calendar_month_rounded,
              tooltip: 'Choose a date',
              onPressed: _pickAnchorDate,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _segmented(
          labels: InsightsRange.values.map((r) => r.label).toList(),
          selected: _range.index,
          selectedColor: AppConstants.primaryColor,
          onChanged: (index) async {
            final next = InsightsRange.values[index];
            if (next == _range) return;
            setState(() {
              _range = next;
              _touchedIndex = -1;
            });
            await _load();
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _roundButton(
              icon: Icons.chevron_left_rounded,
              tooltip: 'Previous',
              onPressed: () => _shiftPeriod(-1),
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickAnchorDate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      Text(
                        _rangeLabel(),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (caption != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          caption,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            _roundButton(
              icon: Icons.chevron_right_rounded,
              tooltip: 'Next',
              onPressed: _canGoForward ? () => _shiftPeriod(1) : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _statTile({
    required String label,
    required double amount,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.92)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: ObscurableAmount(
              amount: _money.format(amount),
              visible: widget.showAmounts,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final income = _sum(_income);
    final expense = _sum(_expense);
    final net = income - expense;
    final quiet = income == 0 && expense == 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32), Color(0xFF43A047)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B5E20).withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _netCaption(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: ObscurableAmount(
              amount: _signed(net),
              visible: widget.showAmounts,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ),
          if (quiet && widget.showAmounts) ...[
            const SizedBox(height: 6),
            Text(
              'No movement in this period',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _statTile(
                  label: 'Income',
                  amount: income,
                  icon: Icons.call_received_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statTile(
                  label: 'Expenses',
                  amount: expense,
                  icon: Icons.call_made_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMainGoalCard(BuildContext context) {
    if (_loadingMainGoal) {
      return Container(
        height: 92,
        alignment: Alignment.center,
        decoration: _cardDecoration(),
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final p = _mainGoal;
    if (p == null) return const SizedBox.shrink();

    final spentMode = p.goal.direction == GoalDirection.spendingLimit;
    final accent =
        spentMode ? const Color(0xFFC62828) : AppConstants.primaryColor;
    final remaining = p.goal.targetAmount - p.progress;
    final exceeded = remaining < 0;
    final pct = p.percent.isNaN ? 0.0 : p.percent.clamp(0.0, 1.0);
    final verb = spentMode ? 'Spent' : 'Saved';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => GoalDetailPageView(goal: p.goal)),
          );
          await _loadMainGoal();
        },
        child: Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color:
                      spentMode
                          ? const Color(0xFFFFEBEE)
                          : AppConstants.primarySurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  spentMode ? Icons.trending_down_rounded : Icons.flag_rounded,
                  size: 18,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.goal.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      spentMode ? 'Spending limit' : 'Saving goal',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: ObscurableAmount(
                  amount: '${(pct * 100).round()}%',
                  visible: widget.showAmounts,
                  style: TextStyle(
                    color:
                        widget.showAmounts ? accent : const Color(0xFF6B7280),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: widget.showAmounts ? pct : 0,
              minHeight: 8,
              backgroundColor: accent.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(
                widget.showAmounts ? accent : const Color(0xFFE5E7EB),
              ),
            ),
          ),
          const SizedBox(height: 10),
          ObscurableAmount(
            amount:
                '$verb ${_money.format(p.progress)} of ${_money.format(p.goal.targetAmount)}',
            visible: widget.showAmounts,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppConstants.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          ObscurableAmount(
            amount:
                exceeded
                    ? 'Over by ${_money.format(remaining.abs())}'
                    : '${_money.format(remaining)} left',
            visible: widget.showAmounts,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color:
                  widget.showAmounts && exceeded
                      ? const Color(0xFFC62828)
                      : AppConstants.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }

  Widget _buildDonut({
    required List<MapEntry<String, double>> entries,
    required double total,
    required bool income,
    required int touched,
  }) {
    final focus =
        touched >= 0 && touched < entries.length ? entries[touched] : null;
    final centerAmount = focus?.value ?? total;
    final centerLabel = focus?.key ?? (income ? 'Income' : 'Expenses');

    return SizedBox(
      height: 214,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              startDegreeOffset: -90,
              centerSpaceRadius: 62,
              sectionsSpace: entries.length <= 1 ? 0 : 3,
              pieTouchData: PieTouchData(
                enabled: widget.showAmounts,
                touchCallback: (event, response) {
                  if (!widget.showAmounts) return;
                  if (!event.isInterestedForInteractions) return;
                  final index =
                      response?.touchedSection?.touchedSectionIndex ?? -1;
                  final next = index < 0 ? -1 : index;
                  if (next == _touchedIndex) return;
                  setState(() => _touchedIndex = next);
                },
              ),
              sections:
                  widget.showAmounts
                      ? [
                        for (var i = 0; i < entries.length; i++)
                          PieChartSectionData(
                            value: entries[i].value,
                            color: _sliceColor(entries, i, income),
                            radius: i == touched ? 36 : 30,
                            showTitle: false,
                          ),
                      ]
                      : [
                        PieChartSectionData(
                          value: 1,
                          color: const Color(0xFFE5E7EB),
                          radius: 30,
                          showTitle: false,
                        ),
                      ],
            ),
          ),
          SizedBox(
            width: 112,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: ObscurableAmount(
                    amount: _money.format(centerAmount),
                    visible: widget.showAmounts,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppConstants.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  centerLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppConstants.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyBreakdown(BuildContext context, bool income) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppConstants.primarySurface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              income ? Icons.savings_outlined : Icons.pie_chart_outline_rounded,
              color: AppConstants.primaryColor,
              size: 30,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            income ? 'No income in this period' : 'No expenses in this period',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Tag a change from History and it will show up here.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTile({
    required MapEntry<String, double> entry,
    required int index,
    required List<MapEntry<String, double>> entries,
    required double total,
    required bool income,
    required int touched,
    required TagType type,
  }) {
    final color = _sliceColor(entries, index, income);
    final others = _isOthers(entry.key);
    final selected = index == touched;
    final fraction = total <= 0 ? 0.0 : (entry.value / total).clamp(0.0, 1.0);

    return Material(
      color: selected ? color.withValues(alpha: 0.08) : Colors.transparent,
      child: InkWell(
        onTap: others ? null : () => _renameTagByName(entry.key, type),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  _initial(entry.key),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppConstants.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ObscurableAmount(
                          amount: _money.format(entry.value),
                          visible: widget.showAmounts,
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            color: AppConstants.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: widget.showAmounts ? fraction : 0,
                              minHeight: 6,
                              backgroundColor: color.withValues(alpha: 0.12),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                widget.showAmounts
                                    ? color
                                    : const Color(0xFFE5E7EB),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 42,
                          child: ObscurableAmount(
                            amount: _percentLabel(entry.value, total),
                            visible: widget.showAmounts,
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              color: AppConstants.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (others) ...[
                      const SizedBox(height: 4),
                      const Text(
                        'Not tagged yet',
                        style: TextStyle(
                          color: AppConstants.textTertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                width: 48,
                height: 48,
                child:
                    others
                        ? null
                        : PopupMenuButton<String>(
                          tooltip: 'Edit or delete',
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.more_horiz_rounded,
                            color: AppConstants.textTertiary,
                          ),
                          onSelected: (value) {
                            if (value == 'rename')
                              _renameTagByName(entry.key, type);
                            if (value == 'delete')
                              _deleteTagByName(entry.key, type);
                          },
                          itemBuilder:
                              (context) => const [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text('Rename'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ],
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBreakdown(BuildContext context) {
    final income = !_showingExpenses;
    final source = income ? _income : _expense;
    final entries = _visible(source);
    final total = _sum(source);
    final type = income ? TagType.income : TagType.expense;
    final accent = income ? AppConstants.primaryColor : const Color(0xFFC62828);
    final touched =
        _touchedIndex >= 0 && _touchedIndex < entries.length
            ? _touchedIndex
            : -1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Categories',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        _segmented(
          labels: const ['Expenses', 'Income'],
          selected: income ? 1 : 0,
          selectedColor: accent,
          onChanged: (index) {
            setState(() {
              _showingExpenses = index == 0;
              _touchedIndex = -1;
            });
          },
        ),
        const SizedBox(height: 12),
        if (entries.isEmpty)
          _emptyBreakdown(context, income)
        else
          Container(
            decoration: _cardDecoration(),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: _buildDonut(
                    entries: entries,
                    total: total,
                    income: income,
                    touched: touched,
                  ),
                ),
                const Divider(height: 1, color: _cardBorder),
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 66, color: _cardBorder),
                  _buildCategoryTile(
                    entry: entries[i],
                    index: i,
                    entries: entries,
                    total: total,
                    income: income,
                    touched: touched,
                    type: type,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tour = AppTourScope.maybeOf(context);
    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      body: RefreshIndicator(
        color: AppConstants.primaryColor,
        onRefresh: () async {
          await _loadMainGoal();
          await _load();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            KeyedSubtree(
              key: tour?.insightsHeader,
              child: _buildHeader(context),
            ),
            const SizedBox(height: 16),
            if (_loading && _hasLoaded)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(99)),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    color: AppConstants.primaryColor,
                    backgroundColor: Color(0xFFE5E7EB),
                  ),
                ),
              ),
            KeyedSubtree(
              key: tour?.insightsSummary,
              child:
                  !_hasLoaded
                      ? const SizedBox(
                        height: 140,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppConstants.primaryColor,
                          ),
                        ),
                      )
                      : _buildSummary(context),
            ),
            if (_hasLoaded) ...[
              const SizedBox(height: 14),
              _buildMainGoalCard(context),
              if (_loadingMainGoal || _mainGoal != null)
                const SizedBox(height: 18),
              _buildBreakdown(context),
            ],
          ],
        ),
      ),
    );
  }
}
