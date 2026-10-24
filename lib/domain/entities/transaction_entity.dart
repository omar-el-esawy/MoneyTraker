import 'package:flutter/foundation.dart';

enum TransactionType { debit, credit }

extension TransactionTypeDb on TransactionType {
  String get dbValue => this == TransactionType.debit ? 'debit' : 'credit';

  static TransactionType fromDb(String value) {
    return value.toLowerCase() == 'debit' ? TransactionType.debit : TransactionType.credit;
  }
}

@immutable
class TransactionEntity {
  final int? id;
  final String bank;
  final double amount;
  final TransactionType type;
  final DateTime date;
  final String rawSms;
  final String? smsId;
  final double? balance;
  final String? accountHint;
  final String? smsHash;
  final String? ruleId;
  final int? ruleVersion;
  final int? categoryTagId;
  final double? categoryAmount;
  final String? categoryAllocations;

  const TransactionEntity({
    this.id,
    required this.bank,
    required this.amount,
    required this.type,
    required this.date,
    required this.rawSms,
    this.smsId,
    this.balance,
    this.accountHint,
    this.smsHash,
    this.ruleId,
    this.ruleVersion,
    this.categoryTagId,
    this.categoryAmount,
    this.categoryAllocations,
  });

  TransactionEntity copyWith({
    int? id,
    String? bank,
    double? amount,
    TransactionType? type,
    DateTime? date,
    String? rawSms,
    String? smsId,
    double? balance,
    String? accountHint,
    String? smsHash,
    String? ruleId,
    int? ruleVersion,
    int? categoryTagId,
    double? categoryAmount,
    String? categoryAllocations,
  }) {
    return TransactionEntity(
      id: id ?? this.id,
      bank: bank ?? this.bank,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      date: date ?? this.date,
      rawSms: rawSms ?? this.rawSms,
      smsId: smsId ?? this.smsId,
      balance: balance ?? this.balance,
      accountHint: accountHint ?? this.accountHint,
      smsHash: smsHash ?? this.smsHash,
      ruleId: ruleId ?? this.ruleId,
      ruleVersion: ruleVersion ?? this.ruleVersion,
      categoryTagId: categoryTagId ?? this.categoryTagId,
      categoryAmount: categoryAmount ?? this.categoryAmount,
      categoryAllocations: categoryAllocations ?? this.categoryAllocations,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bank': bank,
      'amount': amount,
      'type': type.dbValue,
      'date': date.millisecondsSinceEpoch,
      'raw_sms': rawSms,
      'sms_id': smsId,
      'balance': balance,
      'account_hint': accountHint,
      'sms_hash': smsHash,
      'rule_id': ruleId,
      'rule_version': ruleVersion,
      'category_tag_id': categoryTagId,
      'category_amount': categoryAmount,
      'category_allocations': categoryAllocations,
    };
  }

  factory TransactionEntity.fromMap(Map<String, dynamic> map) {
    return TransactionEntity(
      id: map['id'] as int?,
      bank: map['bank'] as String? ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      type: TransactionTypeDb.fromDb(map['type'] as String? ?? 'credit'),
      date: DateTime.fromMillisecondsSinceEpoch((map['date'] as int?) ?? 0),
      rawSms: map['raw_sms'] as String? ?? '',
      smsId: map['sms_id'] as String?,
      balance: (map['balance'] as num?)?.toDouble(),
      accountHint: map['account_hint'] as String?,
      smsHash: map['sms_hash'] as String?,
      ruleId: map['rule_id'] as String?,
      ruleVersion: (map['rule_version'] as num?)?.toInt(),
      categoryTagId: (map['category_tag_id'] as num?)?.toInt(),
      categoryAmount: (map['category_amount'] as num?)?.toDouble(),
      categoryAllocations: map['category_allocations'] as String?,
    );
  }
}

