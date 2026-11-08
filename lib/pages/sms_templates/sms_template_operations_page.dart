import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:money_traker/constants/app_constants.dart';
import 'package:money_traker/services/sms_template_sync_service.dart';
import 'package:money_traker/sms/template_engine/sms_template_mobile_store.dart';

class SmsTemplateOperationsPage extends StatefulWidget {
  const SmsTemplateOperationsPage({super.key});

  @override
  State<SmsTemplateOperationsPage> createState() =>
      _SmsTemplateOperationsPageState();
}

class _SmsTemplateOperationsPageState extends State<SmsTemplateOperationsPage> {
  List<SmsTemplateApplication> _items = const [];
  bool _loading = true;
  int? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await SmsTemplateMobileStore.instance.getApplications();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _undo(SmsTemplateApplication item) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Undo this balance change?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              '${item.sourceName} will receive the inverse change '
              '(${_signed(-item.delta)}). Its other changes stay untouched.',
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Keep it'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Undo'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || item.id == null) return;
    setState(() => _busyId = item.id);
    final undone = await SmsTemplateSyncService.instance.undo(item);
    await _load();
    if (!mounted) return;
    setState(() => _busyId = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          undone
              ? 'Balance change was undone.'
              : 'This change was already undone or its source no longer exists.',
        ),
      ),
    );
  }

  String _signed(double value) {
    final sign = value > 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Balance changes')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const _EmptyOperations()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return _OperationCard(
                    item: item,
                    busy: _busyId == item.id,
                    signed: _signed,
                    onUndo: item.undone ? null : () => _undo(item),
                  );
                },
              ),
            ),
    );
  }
}

class _OperationCard extends StatelessWidget {
  final SmsTemplateApplication item;
  final bool busy;
  final String Function(double) signed;
  final VoidCallback? onUndo;

  const _OperationCard({
    required this.item,
    required this.busy,
    required this.signed,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    final credit = item.delta > 0;
    final color = credit ? const Color(0xFF15803D) : AppConstants.errorColor;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    credit ? Icons.south_west : Icons.north_east,
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.bankName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${item.sourceName} • ${DateFormat('d MMM, HH:mm').format(item.occurredAt)}',
                      ),
                    ],
                  ),
                ),
                Text(
                  signed(item.delta),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: item.undone ? AppConstants.textTertiary : color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppConstants.backgroundColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${item.beforeAmount.toStringAsFixed(2)}  →  '
                '${item.afterAmount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (item.undone)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: AppConstants.textTertiary,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Undone',
                      style: TextStyle(color: AppConstants.textTertiary),
                    ),
                  ],
                ),
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: busy ? null : onUndo,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.undo, size: 18),
                  label: const Text('Undo change'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyOperations extends StatelessWidget {
  const _EmptyOperations();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              size: 52,
              color: AppConstants.textTertiary,
            ),
            const SizedBox(height: 14),
            Text(
              'No balance changes yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Matched messages will appear here with an Undo action.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
