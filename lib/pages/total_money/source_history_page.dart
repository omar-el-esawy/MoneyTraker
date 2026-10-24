import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:money_traker/model/money_source_change.dart';
import 'package:money_traker/model/total_money_day.dart';
import 'package:money_traker/pages/history/widget/history_chart.dart';
import 'package:money_traker/pages/widgets/obscurable_amount.dart';
import 'package:money_traker/store/money_storage.dart';

class SourceHistoryPage extends StatefulWidget {
  final int sourceId;
  final String sourceName;
  final bool showAmounts;

  const SourceHistoryPage({
    super.key,
    required this.sourceId,
    required this.sourceName,
    this.showAmounts = true,
  });

  @override
  State<SourceHistoryPage> createState() => _SourceHistoryPageState();
}

class _SourceHistoryPageState extends State<SourceHistoryPage> {
  final MoneyStorage _storage = MoneyStorage();

  bool _loading = true;
  List<MoneySourceChange> _changes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final changes = await _storage.getMoneySourceChanges(widget.sourceId);
    if (!mounted) return;
    setState(() {
      _changes = changes;
      _loading = false;
    });
  }

  String _typeLabel(MoneySourceChangeType type) {
    switch (type) {
      case MoneySourceChangeType.created:
        return 'Created';
      case MoneySourceChangeType.edited:
        return 'Edited';
      case MoneySourceChangeType.add:
        return 'Added';
      case MoneySourceChangeType.subtract:
        return 'Subtracted';
      case MoneySourceChangeType.transferIn:
        return 'Transfer In';
      case MoneySourceChangeType.transferOut:
        return 'Transfer Out';
    }
  }

  Future<void> _deleteChange(MoneySourceChange change) async {
    if (change.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete change'),
        content: const Text('Delete this change card from history?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirmed != true) return;

    await _storage.deleteMoneySourceChange(change.id!);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final asc = [..._changes]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final chartData = asc
        .map(
          (c) => TotalMoneyDay(
            id: c.id,
            date: c.createdAt,
            totalAmount: c.resultingAmount,
          ),
        )
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: Text('${widget.sourceName} history')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                const SizedBox(height: 16),
                HistoryChart(
                  historyDays: chartData,
                  showAmounts: widget.showAmounts,
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Changes',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                if (_changes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text('No changes yet for this source.'),
                  )
                else
                  ..._changes.map((change) {
                    final sign = change.deltaAmount >= 0 ? '+' : '';
                    final deltaColor =
                        widget.showAmounts
                            ? (change.deltaAmount >= 0
                                ? const Color(0xFF1B5E20)
                                : const Color(0xFFD32F2F))
                            : const Color(0xFF6B7280);
                    final time = DateFormat('yyyy-MM-dd HH:mm').format(change.createdAt);

                    return Slidable(
                      key: ValueKey(change.id ?? '${change.sourceId}-${change.createdAt.toIso8601String()}'),
                      endActionPane: ActionPane(
                        motion: const DrawerMotion(),
                        children: [
                          SlidableAction(
                            onPressed: (_) => _deleteChange(change),
                            backgroundColor: Theme.of(context).colorScheme.error,
                            foregroundColor: Colors.white,
                            icon: Icons.delete,
                            label: 'Delete',
                          ),
                        ],
                      ),
                      child: Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: ListTile(
                          title: Text(_typeLabel(change.type)),
                          subtitle: Text(time),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              ObscurableAmount(
                                amount:
                                    '$sign${change.deltaAmount.toStringAsFixed(2)}',
                                visible: widget.showAmounts,
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  color: deltaColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              ObscurableAmount(
                                amount:
                                    'Balance: ${change.resultingAmount.toStringAsFixed(2)}',
                                visible: widget.showAmounts,
                                textAlign: TextAlign.end,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          onLongPress: () => _deleteChange(change),
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}

