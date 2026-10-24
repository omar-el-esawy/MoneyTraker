import 'package:money_traker/model/total_money_day.dart';

/// Returns today - previous. If there is no previous day, returns 0.
double dayDelta(List<TotalMoneyDay> sortedAscDays, int sortedIndex) {
  if (sortedIndex <= 0 || sortedIndex >= sortedAscDays.length) return 0;
  final prev = sortedAscDays[sortedIndex - 1];
  final cur = sortedAscDays[sortedIndex];
  return cur.totalAmount - prev.totalAmount;
}

