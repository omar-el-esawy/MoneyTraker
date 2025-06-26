import 'package:flutter/material.dart';
import 'package:money_traker/model/total_money_day.dart';
import 'widget/history_chart.dart';
import 'package:money_traker/constants/app_constants.dart';
import 'logic/history_logic.dart';

class HistoryPage extends StatelessWidget {
  final List<TotalMoneyDay> historyDays;

  const HistoryPage({super.key, required this.historyDays});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HistoryChart(historyDays: historyDays),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: historyDays.length,
            itemBuilder: (context, index) {
              final item = historyDays[historyDays.length - 1 - index];
              final date = item.date;
              Color amountColor = Colors.black;
              if (historyDays.length > 1 && index < historyDays.length - 1) {
                final prev = historyDays[historyDays.length - index - 2];
                final change = getChangeType(prev, item);
                if (change == ChangeType.increase) {
                  amountColor = AppConstants.primaryColor;
                } else if (change == ChangeType.decrease) {
                  amountColor = AppConstants.errorColor;
                }
              }
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(
                    'Total: ${item.totalAmount.toStringAsFixed(2)}',
                    style: TextStyle(color: amountColor),
                  ),
                  subtitle: Text(
                    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
                    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
