import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:money_traker/domain/entities/transaction_entity.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize({required GlobalKey<NavigatorState> navigatorKey}) async {
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (_) {
        navigatorKey.currentState?.pushNamed('/notifications');
      },
    );
  }

  Future<void> sendSyncNotification({
    required int newCount,
    required List<TransactionEntity> newTransactions,
  }) async {
    if (newTransactions.isEmpty) return;

    final latest = newTransactions.first;
    final preview =
        '${latest.type == TransactionType.debit ? 'خصم' : 'إيداع'}'
        ' ${latest.amount} جنيه — ${latest.bank}';

    final expanded = newTransactions
        .map(
          (t) =>
              '${t.type == TransactionType.debit ? '🔴' : '🟢'} '
              '${t.amount} جنيه — ${t.bank}',
        )
        .join('\n');

    await _plugin.show(
      0,
      '$newCount تحويل جديد',
      preview,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'sync_channel',
          'Bank Transactions',
          channelDescription: 'إشعارات التحويلات البنكية',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          styleInformation: BigTextStyleInformation(expanded),
        ),
      ),
    );
  }
}

