import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:money_traker/data/transaction_repository.dart';
import 'package:money_traker/domain/entities/transaction_entity.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<TransactionEntity> _recent = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await TransactionRepository.instance.getRecentFromSms(limit: 20);
    if (!mounted) return;
    setState(() => _recent = data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('آخر التحويلات')),
      body: _recent.isEmpty
          ? const Center(child: Text('مفيش تحويلات جديدة'))
          : ListView.builder(
              itemCount: _recent.length,
              itemBuilder: (context, index) {
                final t = _recent[index];
                return ListTile(
                  leading: Icon(
                    t.type == TransactionType.debit ? Icons.arrow_upward : Icons.arrow_downward,
                    color: t.type == TransactionType.debit ? Colors.red : Colors.green,
                  ),
                  title: Text('${t.amount} جنيه'),
                  subtitle: Text(t.bank),
                  trailing: Text(
                    DateFormat('dd/MM − HH:mm').format(t.date),
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              },
            ),
    );
  }
}

