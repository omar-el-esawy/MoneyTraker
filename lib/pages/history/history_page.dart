import 'package:flutter/material.dart';
import 'package:money_traker/model/total_money_day.dart';
import 'package:money_traker/store/money_storage.dart';
import 'widget/history_chart.dart';
import 'package:money_traker/constants/app_constants.dart';
import 'logic/history_logic.dart';
import '../widgets/note_popup.dart';

class HistoryPage extends StatefulWidget {
  final List<TotalMoneyDay> historyDays;

  const HistoryPage({super.key, required this.historyDays});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late List<TotalMoneyDay> _historyDays;

  @override
  void initState() {
    super.initState();
    _historyDays = List<TotalMoneyDay>.from(widget.historyDays);
  }

  Future<void> _editNote(BuildContext context, int index, TotalMoneyDay item) async {
    final newNote = await showDialog<String>(
      context: context,
      builder: (context) => NotePopup(
        initialNote: item.note,
      ),
    );
    if (newNote != null && newNote != item.note) {
      final updated = TotalMoneyDay(
        id: item.id,
        date: item.date,
        totalAmount: item.totalAmount,
        note: newNote,
      );
      await MoneyStorage().updateTotalMoneyDay(updated);
      setState(() {
        _historyDays[_historyDays.length - 1 - index] = updated;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HistoryChart(historyDays: _historyDays),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: _historyDays.length,
            itemBuilder: (context, index) {
              final item = _historyDays[_historyDays.length - 1 - index];
              final date = item.date;
              Color amountColor = Colors.black;
              if (_historyDays.length > 1 && index < _historyDays.length - 1) {
                final prev = _historyDays[_historyDays.length - index - 2];
                final change = getChangeType(prev, item);
                if (change == ChangeType.increase) {
                  amountColor = AppConstants.accentColor;
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
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
                        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                      ),
                      if (item.note != null && item.note!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            'Note: ${item.note}',
                            style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                          ),
                        ),
                    ],
                  ),
                  onTap: () => _editNote(context, index, item),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
