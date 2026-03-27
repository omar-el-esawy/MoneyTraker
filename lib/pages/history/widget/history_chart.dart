import 'package:flutter/material.dart';
import 'package:money_traker/model/total_money_day.dart';
import 'zoomable_balance_chart.dart';

class HistoryChart extends StatelessWidget {
  final List<TotalMoneyDay> historyDays;

  const HistoryChart({super.key, required this.historyDays});

  @override
  Widget build(BuildContext context) {
    return ZoomableBalanceChart(historyDays: historyDays);
  }
}
