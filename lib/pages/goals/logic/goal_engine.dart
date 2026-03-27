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

class GoalEngine {
  final MoneyStorage _storage;

  GoalEngine(this._storage);

  Future<GoalProgress> computeProgress(Goal goal, {DateTime? asOf}) async {
    final cycle = goal.currentCycle(now: asOf).range;

    // Load days in range.
    final db = await _storage.database;
    final days = await db.query(
      'total_money_days',
      where: 'date >= ? AND date < ?',
      whereArgs: [cycle.start.toIso8601String(), cycle.end.toIso8601String()],
      columns: const ['id', 'date', 'totalAmount'],
      orderBy: 'date ASC',
    );

    if (days.isEmpty) {
      return GoalProgress(goal: goal, cycle: cycle, totalIncome: 0, totalExpenses: 0);
    }

    // Seed previous total from the last day before range.
    final firstDate = DateTime.parse(days.first['date'] as String);
    final prevDayRows = await db.query(
      'total_money_days',
      where: 'date < ?',
      whereArgs: [firstDate.toIso8601String()],
      columns: const ['totalAmount'],
      orderBy: 'date DESC',
      limit: 1,
    );

    double? prevTotal = prevDayRows.isNotEmpty ? (prevDayRows.first['totalAmount'] as num).toDouble() : null;

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

    // Load tagged entries for all days in cycle.
    final dayIds = days.map((e) => e['id'] as int).toList(growable: false);
    final placeholders = List.filled(dayIds.length, '?').join(',');

    final excludedIds = goal.excludedTagIds.toSet();

    final entries = await db.rawQuery('''
      SELECT e.amount, e.tagId, t.type
      FROM total_money_day_delta_entries e
      JOIN tags t ON t.id = e.tagId
      WHERE e.dayId IN ($placeholders)
    ''', dayIds);

    double taggedIncome = 0;
    double taggedExpense = 0;

    for (final row in entries) {
      final tagId = row['tagId'] as int;
      if (excludedIds.contains(tagId)) continue;
      final type = TagTypeDb.fromDb(row['type'] as String);
      final amount = (row['amount'] as num).toDouble();
      if (type == TagType.income) {
        taggedIncome += amount;
      } else {
        taggedExpense += amount;
      }
    }

    // Others/unallocated after exclusions.
    final othersIncome = (totalIncomeDelta - taggedIncome);
    final othersExpense = (totalExpenseDelta - taggedExpense);

    final totalIncome = taggedIncome + (othersIncome > 0 ? othersIncome : 0);
    final totalExpenses = taggedExpense + (othersExpense > 0 ? othersExpense : 0);

    return GoalProgress(goal: goal, cycle: cycle, totalIncome: totalIncome, totalExpenses: totalExpenses);
  }
}

