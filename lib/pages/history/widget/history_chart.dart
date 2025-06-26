import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:money_traker/model/total_money_day.dart';

class HistoryChart extends StatelessWidget {
  final List<TotalMoneyDay> historyDays;

  const HistoryChart({super.key, required this.historyDays});

  @override
  Widget build(BuildContext context) {
    final sortedHistory = [...historyDays]..sort((a, b) => a.date.compareTo(b.date));
    final spots = List.generate(
      sortedHistory.length,
      (i) => FlSpot(
        i.toDouble(),
        sortedHistory[i].totalAmount,
      ),
    );
    final xLabels = sortedHistory
        .map((e) => "${e.date.month}/${e.date.day}")
        .toList();

    return SizedBox(
      height: 200,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: LineChart(
          LineChartData(
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: false, // Make the line sharp (not curved)
                barWidth: 2,
                color: Colors.blue,
                dotData: FlDotData(show: false),
              ),
            ],
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(showTitles: true, reservedSize: 40),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    int idx = value.toInt();
                    if (idx < 0 || idx >= xLabels.length) return const SizedBox.shrink();
                    return Text(xLabels[idx], style: const TextStyle(fontSize: 10));
                  },
                  interval: 1,
                  reservedSize: 32,
                ),
              ),
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: FlGridData(show: true),
            borderData: FlBorderData(show: true),
            minX: 0,
            maxX: (spots.length - 1).toDouble(),
            minY: spots.isEmpty ? 0 : spots.map((e) => e.y).reduce((a, b) => a < b ? a : b),
            maxY: spots.isEmpty ? 0 : spots.map((e) => e.y).reduce((a, b) => a > b ? a : b),
          ),
        ),
      ),
    );
  }
}
