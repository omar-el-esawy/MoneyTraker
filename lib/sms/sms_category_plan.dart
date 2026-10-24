class SmsCategorySlice {
  final DateTime day;
  final double delta;

  const SmsCategorySlice({required this.day, required this.delta});
}

class SmsCategoryEvent {
  final int transactionId;
  final DateTime day;
  final int tagId;
  final double amount;
  final bool addition;

  const SmsCategoryEvent({
    required this.transactionId,
    required this.day,
    required this.tagId,
    required this.amount,
    required this.addition,
  });
}

class SmsCategoryPlan {
  final int transactionId;
  final int tagId;
  final List<SmsCategorySlice> slices;

  const SmsCategoryPlan({
    required this.transactionId,
    required this.tagId,
    required this.slices,
  });

  double get signed {
    var total = 0.0;
    for (final slice in slices) {
      total += slice.delta;
    }
    return total;
  }
}

DateTime categoryDay(DateTime date) => DateTime(date.year, date.month, date.day);

const categoryAmountEpsilon = 0.0001;

Map<DateTime, double> manualCategoryBalances({
  required Map<DateTime, double> current,
  required Map<DateTime, double> previousSms,
}) {
  final days = <DateTime>{...current.keys, ...previousSms.keys};
  final opening = <DateTime, double>{};
  for (final day in days) {
    final manual = (current[day] ?? 0) - (previousSms[day] ?? 0);
    if (manual > categoryAmountEpsilon) opening[categoryDay(day)] = manual;
  }
  return opening;
}

Map<DateTime, double> sumCategorySlices(Iterable<SmsCategorySlice> slices) {
  final totals = <DateTime, double>{};
  for (final slice in slices) {
    final day = categoryDay(slice.day);
    totals[day] = (totals[day] ?? 0) + slice.delta;
  }
  totals.removeWhere((_, amount) => amount.abs() <= categoryAmountEpsilon);
  return totals;
}

Map<DateTime, double> categoryBalanceDeltas({
  required Map<DateTime, double> previousSms,
  required Map<DateTime, double> nextSms,
}) {
  final days = <DateTime>{...previousSms.keys, ...nextSms.keys};
  final deltas = <DateTime, double>{};
  for (final day in days) {
    final delta = (nextSms[day] ?? 0) - (previousSms[day] ?? 0);
    if (delta.abs() > categoryAmountEpsilon) deltas[categoryDay(day)] = delta;
  }
  return deltas;
}

/// Additions land on their own day. Reductions walk backward from that day
/// and stop when the balance is gone, so a later refund can cancel an earlier charge.
List<SmsCategoryPlan> planSmsCategories({
  required List<SmsCategoryEvent> events,
  required Map<int, Map<DateTime, double>> openingByTag,
}) {
  final sim = <int, Map<DateTime, double>>{};
  for (final entry in openingByTag.entries) {
    sim[entry.key] = {
      for (final day in entry.value.entries)
        if (day.value > categoryAmountEpsilon) categoryDay(day.key): day.value,
    };
  }

  Map<DateTime, double> bucket(int tagId) => sim.putIfAbsent(tagId, () => {});

  final slicesByTransaction = <int, List<SmsCategorySlice>>{};
  final tagByTransaction = <int, int>{};

  void addSlice(SmsCategoryEvent event, DateTime day, double delta) {
    tagByTransaction[event.transactionId] = event.tagId;
    slicesByTransaction.putIfAbsent(event.transactionId, () => []).add(
          SmsCategorySlice(day: categoryDay(day), delta: delta),
        );
  }

  int byDayThenId(SmsCategoryEvent a, SmsCategoryEvent b) {
    final byDay = a.day.compareTo(b.day);
    if (byDay != 0) return byDay;
    return a.transactionId.compareTo(b.transactionId);
  }

  final additions = events.where((event) => event.addition).toList()..sort(byDayThenId);
  for (final event in additions) {
    if (event.amount <= categoryAmountEpsilon) continue;
    final day = categoryDay(event.day);
    final days = bucket(event.tagId);
    days[day] = (days[day] ?? 0) + event.amount;
    addSlice(event, day, event.amount);
  }

  final reductions = events.where((event) => !event.addition).toList()..sort(byDayThenId);
  for (final event in reductions) {
    var left = event.amount;
    if (left <= categoryAmountEpsilon) continue;
    final days = bucket(event.tagId);
    final keys = days.keys.where((day) => !day.isAfter(categoryDay(event.day))).toList()
      ..sort((a, b) => b.compareTo(a));
    for (final day in keys) {
      if (left <= categoryAmountEpsilon) break;
      final available = days[day] ?? 0;
      if (available <= categoryAmountEpsilon) continue;
      final take = available < left ? available : left;
      days[day] = available - take;
      left -= take;
      addSlice(event, day, -take);
    }
  }

  return [
    for (final entry in slicesByTransaction.entries)
      SmsCategoryPlan(
        transactionId: entry.key,
        tagId: tagByTransaction[entry.key]!,
        slices: entry.value,
      ),
  ];
}
