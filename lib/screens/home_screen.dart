import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:money_traker/data/transaction_repository.dart';
import 'package:money_traker/domain/entities/transaction_entity.dart';
import 'package:money_traker/services/notification_service.dart';
import 'package:money_traker/services/sync_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<TransactionEntity> _transactions = [];
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _sync();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _sync() async {
    if (_isSyncing) return;
    if (!mounted) return;
    setState(() => _isSyncing = true);

    final before = _transactions.length;
    await SyncService.instance.sync();
    final updated = await TransactionRepository.instance.getAll();
    final newCount = updated.length - before;

    if (!mounted) return;
    setState(() {
      _transactions = updated;
      _isSyncing = false;
    });

    if (newCount > 0) {
      await NotificationService.instance.sendSyncNotification(
        newCount: newCount,
        newTransactions: updated.take(newCount).toList(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      body: _isSyncing && _transactions.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : TransactionsList(transactions: _transactions),
    );
  }
}

class TransactionsList extends StatelessWidget {
  final List<TransactionEntity> transactions;

  const TransactionsList({super.key, required this.transactions});

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return const Center(child: Text('No transactions yet.'));
    }

    return ListView.builder(
      itemCount: transactions.length,
      itemBuilder: (context, index) {
        final t = transactions[index];
        final color = t.type == TransactionType.debit ? Colors.red : Colors.green;
        final icon = t.type == TransactionType.debit ? Icons.arrow_upward : Icons.arrow_downward;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            leading: Icon(icon, color: color),
            title: Text('${t.amount} جنيه'),
            subtitle: Text(t.bank),
            trailing: Text(
              DateFormat('dd/MM − HH:mm').format(t.date),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        );
      },
    );
  }
}

