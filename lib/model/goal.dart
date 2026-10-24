import 'dart:convert';

import 'package:flutter/material.dart';

enum GoalType {
  monthly,
  repeatingDays,
  fixedPeriod,
}

extension GoalTypeDb on GoalType {
  String get dbValue {
    switch (this) {
      case GoalType.monthly:
        return 'monthly';
      case GoalType.repeatingDays:
        return 'repeatingDays';
      case GoalType.fixedPeriod:
        return 'fixedPeriod';
    }
  }

  static GoalType fromDb(String v) {
    switch (v) {
      case 'monthly':
        return GoalType.monthly;
      case 'repeatingDays':
        return GoalType.repeatingDays;
      case 'fixedPeriod':
        return GoalType.fixedPeriod;
      default:
        throw Exception('Unknown GoalType: $v');
    }
  }
}

enum GoalDirection {
  spendingLimit,
  savingsTarget,
}

extension GoalDirectionDb on GoalDirection {
  String get dbValue => this == GoalDirection.spendingLimit ? 'spendingLimit' : 'savingsTarget';

  static GoalDirection fromDb(String v) {
    switch (v) {
      case 'spendingLimit':
        return GoalDirection.spendingLimit;
      case 'savingsTarget':
        return GoalDirection.savingsTarget;
      default:
        throw Exception('Unknown GoalDirection: $v');
    }
  }
}

class Goal {
  final int? id;
  final String name;
  final double targetAmount;
  final GoalType type;
  final GoalDirection direction;

  final int? monthStartDay;
  final int? repeatEveryDays;
  final DateTime? repeatStartDate;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  final List<int> excludedTagIds;
  final bool isMain;
  final bool isActive;
  final DateTime createdAt;

  const Goal({
    this.id,
    required this.name,
    required this.targetAmount,
    required this.type,
    required this.direction,
    this.monthStartDay,
    this.repeatEveryDays,
    this.repeatStartDate,
    this.periodStart,
    this.periodEnd,
    this.excludedTagIds = const [],
    this.isMain = false,
    this.isActive = true,
    required this.createdAt,
  });

  Goal copyWith({
    int? id,
    String? name,
    double? targetAmount,
    GoalType? type,
    GoalDirection? direction,
    int? monthStartDay,
    int? repeatEveryDays,
    DateTime? repeatStartDate,
    DateTime? periodStart,
    DateTime? periodEnd,
    List<int>? excludedTagIds,
    bool? isMain,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return Goal(
      id: id ?? this.id,
      name: name ?? this.name,
      targetAmount: targetAmount ?? this.targetAmount,
      type: type ?? this.type,
      direction: direction ?? this.direction,
      monthStartDay: monthStartDay ?? this.monthStartDay,
      repeatEveryDays: repeatEveryDays ?? this.repeatEveryDays,
      repeatStartDate: repeatStartDate ?? this.repeatStartDate,
      periodStart: periodStart ?? this.periodStart,
      periodEnd: periodEnd ?? this.periodEnd,
      excludedTagIds: excludedTagIds ?? this.excludedTagIds,
      isMain: isMain ?? this.isMain,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'targetAmount': targetAmount,
      'type': type.dbValue,
      'direction': direction.dbValue,
      'monthStartDay': monthStartDay,
      'repeatEveryDays': repeatEveryDays,
      'repeatStartDate': repeatStartDate?.toIso8601String(),
      'periodStart': periodStart?.toIso8601String(),
      'periodEnd': periodEnd?.toIso8601String(),
      'excludedTagIds': jsonEncode(excludedTagIds),
      'isMain': isMain ? 1 : 0,
      'isActive': isActive ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Goal.fromMap(Map<String, dynamic> map) {
    List<int> parseExcluded(dynamic v) {
      if (v == null) return const [];
      try {
        final decoded = jsonDecode(v as String);
        if (decoded is List) {
          return decoded.map((e) => (e as num).toInt()).toList();
        }
      } catch (_) {}
      return const [];
    }

    return Goal(
      id: map['id'] as int?,
      name: map['name'] as String,
      targetAmount: (map['targetAmount'] as num).toDouble(),
      type: GoalTypeDb.fromDb(map['type'] as String),
      direction: GoalDirectionDb.fromDb(map['direction'] as String),
      monthStartDay: map['monthStartDay'] as int?,
      repeatEveryDays: map['repeatEveryDays'] as int?,
      repeatStartDate:
          map['repeatStartDate'] == null ? null : DateTime.parse(map['repeatStartDate'] as String),
      periodStart: map['periodStart'] == null ? null : DateTime.parse(map['periodStart'] as String),
      periodEnd: map['periodEnd'] == null ? null : DateTime.parse(map['periodEnd'] as String),
      excludedTagIds: parseExcluded(map['excludedTagIds']),
      isMain: ((map['isMain'] as num?) ?? 0) > 0,
      isActive: ((map['isActive'] as num?) ?? 1) > 0,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}

class GoalCycle {
  final DateTimeRange range;
  final DateTime nextReset;

  const GoalCycle({required this.range, required this.nextReset});
}

extension GoalCycleCalc on Goal {
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  GoalCycle currentCycle({DateTime? now}) {
    final anchor = _dateOnly(now ?? DateTime.now());

    switch (type) {
      case GoalType.monthly:
        final startDay = (monthStartDay ?? 1).clamp(1, 28);
        final thisMonthStart = DateTime(anchor.year, anchor.month, startDay);
        final rangeStart = anchor.isBefore(thisMonthStart)
            ? DateTime(anchor.year, anchor.month - 1, startDay)
            : thisMonthStart;
        final nextReset = DateTime(rangeStart.year, rangeStart.month + 1, startDay);
        return GoalCycle(range: DateTimeRange(start: rangeStart, end: nextReset), nextReset: nextReset);

      case GoalType.repeatingDays:
        final every = (repeatEveryDays ?? 1).clamp(1, 3650);
        final start = _dateOnly(repeatStartDate ?? anchor);
        final diff = anchor.difference(start).inDays;
        final cycles = diff >= 0 ? (diff ~/ every) : -(((-diff - 1) ~/ every) + 1);
        final rangeStart = start.add(Duration(days: cycles * every));
        final nextReset = rangeStart.add(Duration(days: every));
        return GoalCycle(range: DateTimeRange(start: rangeStart, end: nextReset), nextReset: nextReset);

      case GoalType.fixedPeriod:
        final s = _dateOnly(periodStart ?? anchor);
        final e = _dateOnly(periodEnd ?? anchor).add(const Duration(days: 1));
        return GoalCycle(range: DateTimeRange(start: s, end: e), nextReset: e);
    }
  }
}


