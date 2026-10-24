import 'package:flutter/foundation.dart';

@immutable
class FailedSms {
  final int? id;
  final String smsId;
  final String? sender;
  final String body;
  final DateTime failedAt;

  const FailedSms({
    this.id,
    required this.smsId,
    this.sender,
    required this.body,
    required this.failedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sms_id': smsId,
      'sender': sender,
      'body': body,
      'failed_at': failedAt.millisecondsSinceEpoch,
    };
  }

  factory FailedSms.fromMap(Map<String, dynamic> map) {
    return FailedSms(
      id: map['id'] as int?,
      smsId: map['sms_id'] as String? ?? '',
      sender: map['sender'] as String?,
      body: map['body'] as String? ?? '',
      failedAt: DateTime.fromMillisecondsSinceEpoch((map['failed_at'] as int?) ?? 0),
    );
  }
}

