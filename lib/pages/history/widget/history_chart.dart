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

    // Dynamically control label interval (show ~20 total for X, ~10 for Y)
    final double xInterval = (xLabels.length / 40).ceilToDouble().clamp(1, double.infinity);

    double minY = spots.isEmpty ? 0 : spots.map((e) => e.y).reduce((a, b) => a < b ? a : b);
    double maxY = spots.isEmpty ? 0 : spots.map((e) => e.y).reduce((a, b) => a > b ? a : b);

// Round to nearest 100 for cleaner ticks
    minY = (minY / 100).floor() * 100;
    maxY = (maxY / 100).ceil() * 100;

    final int ySteps = 5;
    final double rawInterval = ((maxY - minY) / ySteps);
    final double yInterval = rawInterval < 1 ? 1 : (rawInterval / 100).ceil() * 100;

    return SizedBox(
      height: 220,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: (spots.length * 70).clamp(400, 1500).toDouble(), // more horizontal space per day
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: LineChart(
              LineChartData(
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: false,
                    barWidth: 2,
                    color: Colors.blue,
                    dotData: FlDotData(show: false),
                  ),
                ],
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: yInterval, // <-- Y axis interval
                      getTitlesWidget: (value, meta) {
                        String label;
                        if (value.abs() >= 1000) {
                          label = '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}k';
                        } else {
                          label = value.toStringAsFixed(0);
                        }
                        return Text(
                          label,
                          style: const TextStyle(fontSize: 10),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: xInterval, // <-- X axis interval
                      getTitlesWidget: (value, meta) {
                        int idx = value.toInt();
                        if (idx < 0 || idx >= xLabels.length) return const SizedBox.shrink();
                        return Transform.rotate(
                          angle: -0.4, // ~ -22 degrees
                          child: Text(
                            xLabels[idx],
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(show: true),
                borderData: FlBorderData(show: true),
                minX: 0,
                maxX: (spots.length - 1).toDouble(),
                minY: minY,
                maxY: maxY,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
