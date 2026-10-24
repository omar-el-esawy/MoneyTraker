import 'package:flutter/material.dart';
import 'package:money_traker/model/goal.dart';
import 'package:money_traker/model/tag.dart';
import 'package:money_traker/store/money_storage.dart';

class GoalProgress {
  final Goal goal;
  final DateTimeRange cycle;
  final double totalIncome;
  final double totalExpenses;

  const GoalProgress({
    required this.goal,
    required this.cycle,
    required this.totalIncome,
    required this.totalExpenses,
  });

  double get progress {
    switch (goal.direction) {
      case GoalDirection.spendingLimit:
        return totalExpenses;
      case GoalDirection.savingsTarget:
        return totalIncome - totalExpenses;
    }
  }

  double get remaining => goal.targetAmount - progress;

  double get percent => goal.targetAmount <= 0 ? 0 : (progress / goal.targetAmount);

  int get daysRemaining {
    final now = DateTime.now();
    final end = cycle.end;
    final d = DateTime(end.year, end.month, end.day);
    final n = DateTime(now.year, now.month, now.day);
    final diff = d.difference(n).inDays;
    return diff < 0 ? 0 : diff;
  }
}

class GoalDayPoint {
  final DateTime date;
  final double dailyDelta;
  final double progress;

  const GoalDayPoint({
    required this.date,
    required this.dailyDelta,
    required this.progress,
  });
}

class GoalTaggedAmount {
  final int tagId;
  final bool income;
  final double amount;
  final bool autoBalanced;

  const GoalTaggedAmount({
    required this.tagId,
    required this.income,
    required this.amount,
    this.autoBalanced = false,
  });
}

class GoalDayContribution {
  final double income;
  final double expense;

  const GoalDayContribution({required this.income, required this.expense});

  double deltaFor(GoalDirection direction) {
    return direction == GoalDirection.spendingLimit ? expense : income - expense;
  }
}

/// The part of a balance drop that has no expense category yet.
/// Insights adds this to the Others slice.
double uncategorizedGap(double movement, double tagged) {
  final gap = movement - tagged;
  return gap > 0 ? gap : 0;
}

/// The Expenses number Insights shows for the same days.
/// Categorized spending is kept, and any drop with no category is included.
/// Income does not reduce it. Excluded categories are taken back out.
double insightsStyleExpense({
  required double balanceDrops,
  required double taggedExpenses,
  double excludedExpenses = 0,
}) {
  final shown = taggedExpenses + uncategorizedGap(balanceDrops, taggedExpenses);
  final expense = shown - excludedExpenses;
  return expense > 0 ? expense : 0;
}

/// Savings goals still use the day's net change. Tagged rows explain part of
/// [netChange], and anything left over was never given a category.
GoalDayContribution goalDayContribution({
  required double netChange,
  required List<GoalTaggedAmount> tags,
  required Set<int> excludedTagIds,
}) {
  var explainedIncome = 0.0;
  var explainedExpense = 0.0;
  var countedIncome = 0.0;
  var countedExpense = 0.0;

  for (final tag in tags) {
    if (tag.income) {
      explainedIncome += tag.amount;
    } else {
      explainedExpense += tag.amount;
    }
    if (excludedTagIds.contains(tag.tagId)) continue;
    if (tag.income) {
      countedIncome += tag.amount;
    } else {
      countedExpense += tag.amount;
    }
  }

  final gap = netChange - (explainedIncome - explainedExpense);
  if (gap > 0.0000001) countedIncome += gap;
  if (gap < -0.0000001) countedExpense += -gap;
  return GoalDayContribution(income: countedIncome, expense: countedExpense);
}

class _DayBucket {
  _DayBucket(this.date);

  final DateTime date;
  int? id;
  double total = 0;
}

class GoalEngine {
  final MoneyStorage _storage;

  GoalEngine(this._storage);

  Future<GoalProgress> computeProgress(Goal goal, {DateTime? asOf}) async {
    final series = await buildSeries(goal, asOf: asOf);
    return GoalProgress(
      goal: goal,
      cycle: series.cycle,
      totalIncome: series.totalIncome,
      totalExpenses: series.totalExpenses,
    );
  }

  Future<({DateTimeRange cycle, double totalIncome, double totalExpenses, List<GoalDayPoint> days})>
      buildSeries(Goal goal, {DateTime? asOf}) async {
    final cycle = goal.currentCycle(now: asOf).range;
    final excludedIds = goal.excludedTagIds.toSet();
    final ordered = await _calendarDays();
    final cycleIds = <int>[
      for (final day in ordered)
        if (_inCycle(day.date, cycle) && day.id != null) day.id!,
    ];
    final tagsByDay = await _tagsByDay(cycleIds);

    final points = <GoalDayPoint>[];
    var totalIncome = 0.0;
    var totalExpenses = 0.0;
    var cumulative = 0.0;

    if (goal.direction == GoalDirection.spendingLimit) {
      final spending = await _spendingLikeInsights(cycle, excludedIds);
      return (
        cycle: cycle,
        totalIncome: 0.0,
        totalExpenses: spending.expense,
        days: spending.days,
      );
    } else {
      for (var i = 0; i < ordered.length; i++) {
        final day = ordered[i];
        if (!_inCycle(day.date, cycle)) continue;

        final net = i == 0 ? 0.0 : day.total - ordered[i - 1].total;
        final contribution = goalDayContribution(
          netChange: net,
          tags: day.id == null ? const [] : (tagsByDay[day.id] ?? const []),
          excludedTagIds: excludedIds,
        );
        totalIncome += contribution.income;
        totalExpenses += contribution.expense;
        final daily = contribution.deltaFor(goal.direction);
        cumulative += daily;
        points.add(GoalDayPoint(date: day.date, dailyDelta: daily, progress: cumulative));
      }
    }

    return (
      cycle: cycle,
      totalIncome: totalIncome,
      totalExpenses: totalExpenses,
      days: points,
    );
  }

  Future<List<_DayBucket>> _calendarDays() async {
    final days = await _storage.getTotalMoneyDays();
    days.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      return (a.id ?? 0).compareTo(b.id ?? 0);
    });

    final ordered = <_DayBucket>[];
    for (final day in days) {
      if (day.id == null) continue;
      final key = DateTime(day.date.year, day.date.month, day.date.day);
      if (ordered.isEmpty || ordered.last.date != key) {
        ordered.add(_DayBucket(key));
      }
      final bucket = ordered.last;
      bucket.id = day.id;
      bucket.total = day.totalAmount;
    }
    return ordered;
  }

  Future<Map<int, List<GoalTaggedAmount>>> _tagsByDay(List<int> dayIds) async {
    if (dayIds.isEmpty) return {};
    final db = await _storage.database;
    final placeholders = List.filled(dayIds.length, '?').join(',');
    final rows = await db.rawQuery('''
      SELECT e.dayId, e.tagId, e.amount, e.autoBalanced, t.type
      FROM total_money_day_delta_entries e
      JOIN tags t ON t.id = e.tagId
      WHERE e.dayId IN ($placeholders)
    ''', dayIds);

    final out = <int, List<GoalTaggedAmount>>{};
    for (final row in rows) {
      final dayId = row['dayId'] as int;
      final type = TagTypeDb.fromDb(row['type'] as String);
      out.putIfAbsent(dayId, () => []).add(
        GoalTaggedAmount(
          tagId: row['tagId'] as int,
          income: type == TagType.income,
          amount: (row['amount'] as num).toDouble(),
          autoBalanced: ((row['autoBalanced'] as num?) ?? 0) > 0,
        ),
      );
    }
    return out;
  }

  Future<({double expense, List<GoalDayPoint> days})> _spendingLikeInsights(
    DateTimeRange cycle,
    Set<int> excludedIds,
  ) async {
    final db = await _storage.database;
    final start = DateTime(cycle.start.year, cycle.start.month, cycle.start.day);
    final end = DateTime(cycle.end.year, cycle.end.month, cycle.end.day);
    final rows = await db.query(
      'total_money_days',
      where: 'date >= ? AND date < ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      columns: const ['id', 'date', 'totalAmount'],
      orderBy: 'date ASC',
    );
    if (rows.isEmpty) return (expense: 0.0, days: const <GoalDayPoint>[]);

    final prevRows = await db.query(
      'total_money_days',
      where: 'date < ?',
      whereArgs: [rows.first['date'] as String],
      columns: const ['totalAmount'],
      orderBy: 'date DESC',
      limit: 1,
    );
    double? previous = prevRows.isNotEmpty ? (prevRows.first['totalAmount'] as num).toDouble() : null;

    final dropsByDay = <DateTime, double>{};
    var balanceDrops = 0.0;
    final dayIds = <int>[];
    for (final row in rows) {
      final id = row['id'] as int;
      final current = (row['totalAmount'] as num).toDouble();
      final parsed = DateTime.parse(row['date'] as String);
      final day = DateTime(parsed.year, parsed.month, parsed.day);
      dayIds.add(id);
      var drop = 0.0;
      if (previous != null) {
        final delta = current - previous;
        if (delta < 0) drop = delta.abs();
      }
      previous = current;
      balanceDrops += drop;
      dropsByDay[day] = (dropsByDay[day] ?? 0) + drop;
    }

    final tagsByDay = await _tagsByDay(dayIds);
    var taggedExpenses = 0.0;
    var excludedExpenses = 0.0;
    for (final entry in tagsByDay.entries) {
      for (final tag in entry.value) {
        if (tag.income) continue;
        taggedExpenses += tag.amount;
        if (excludedIds.contains(tag.tagId)) excludedExpenses += tag.amount;
      }
    }

    final expense = insightsStyleExpense(
      balanceDrops: balanceDrops,
      taggedExpenses: taggedExpenses,
      excludedExpenses: excludedExpenses,
    );

    final dates = dropsByDay.keys.toList()..sort();
    final points = <GoalDayPoint>[];
    var cumulative = 0.0;
    for (final date in dates) {
      final daily = dropsByDay[date] ?? 0;
      cumulative += daily;
      points.add(GoalDayPoint(date: date, dailyDelta: daily, progress: cumulative));
    }
    final remainder = expense - cumulative;
    if (points.isNotEmpty && remainder.abs() > 0.0000001) {
      final last = points.removeLast();
      final daily = last.dailyDelta + remainder;
      points.add(GoalDayPoint(date: last.date, dailyDelta: daily, progress: expense));
    }

    return (expense: expense, days: points);
  }

  bool _inCycle(DateTime day, DateTimeRange cycle) {
    final start = DateTime(cycle.start.year, cycle.start.month, cycle.start.day);
    final end = DateTime(cycle.end.year, cycle.end.month, cycle.end.day);
    return !day.isBefore(start) && day.isBefore(end);
  }
}
