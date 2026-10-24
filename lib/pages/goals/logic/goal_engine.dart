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

    final db = await _storage.database;
    final excludedIds = goal.excludedTagIds.toSet();

    // Strictly sum tagged entries inside the goal cycle window.
    final entries = await db.rawQuery('''
      SELECT e.amount, e.tagId, t.type
      FROM total_money_day_delta_entries e
      JOIN tags t ON t.id = e.tagId
      JOIN total_money_days d ON d.id = e.dayId
      WHERE d.date >= ? AND d.date < ?
    ''', [cycle.start.toIso8601String(), cycle.end.toIso8601String()]);

    double totalIncome = 0;
    double totalExpenses = 0;

    for (final row in entries) {
      final tagId = row['tagId'] as int;
      if (excludedIds.contains(tagId)) continue;

      final type = TagTypeDb.fromDb(row['type'] as String);
      final amount = (row['amount'] as num).toDouble();
      if (type == TagType.income) {
        totalIncome += amount;
      } else {
        totalExpenses += amount;
      }
    }

    return GoalProgress(
      goal: goal,
      cycle: cycle,
      totalIncome: totalIncome,
      totalExpenses: totalExpenses,
    );
  }
}
