enum SmsTemplateType { debit, credit }

enum SmsPlaceholderKind {
  amount,
  merchant,
  date,
  time,
  balance,
  cardDigits,
  reference,
  other,
}

class SmsTextRange {
  final int start;
  final int end;

  const SmsTextRange({required this.start, required this.end});

  bool get isValid => start >= 0 && end > start;

  Map<String, dynamic> toJson() => {'start': start, 'end': end};

  factory SmsTextRange.fromJson(Map<String, dynamic> json) {
    return SmsTextRange(
      start: (json['start'] as num?)?.toInt() ?? -1,
      end: (json['end'] as num?)?.toInt() ?? -1,
    );
  }
}

class SmsPlaceholder {
  final SmsPlaceholderKind kind;
  final SmsTextRange range;

  const SmsPlaceholder({required this.kind, required this.range});

  Map<String, dynamic> toJson() => {'kind': kind.name, 'range': range.toJson()};

  factory SmsPlaceholder.fromJson(Map<String, dynamic> json) {
    return SmsPlaceholder(
      kind: SmsPlaceholderKind.values.firstWhere(
        (item) => item.name == json['kind'],
        orElse: () => SmsPlaceholderKind.other,
      ),
      range: SmsTextRange.fromJson(
        Map<String, dynamic>.from(json['range'] as Map? ?? const {}),
      ),
    );
  }
}

class SmsTemplate {
  final String id;
  final String bankId;
  final String sampleText;
  final SmsTemplateType type;
  final SmsPlaceholder amount;
  final List<SmsTextRange> directionRanges;
  final List<SmsPlaceholder> placeholders;

  const SmsTemplate({
    required this.id,
    required this.bankId,
    required this.sampleText,
    required this.type,
    required this.amount,
    required this.directionRanges,
    this.placeholders = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'bankId': bankId,
    'sampleText': sampleText,
    'type': type.name,
    'amount': amount.toJson(),
    'directionRanges': [for (final range in directionRanges) range.toJson()],
    'placeholders': [
      for (final placeholder in placeholders) placeholder.toJson(),
    ],
  };

  factory SmsTemplate.fromJson(Map<String, dynamic> json) {
    return SmsTemplate(
      id: json['id']?.toString() ?? '',
      bankId: json['bankId']?.toString() ?? '',
      sampleText: json['sampleText']?.toString() ?? '',
      type: SmsTemplateType.values.firstWhere(
        (item) => item.name == json['type'],
        orElse: () => SmsTemplateType.debit,
      ),
      amount: SmsPlaceholder.fromJson(
        Map<String, dynamic>.from(json['amount'] as Map? ?? const {}),
      ),
      directionRanges: [
        for (final item in json['directionRanges'] as List? ?? const [])
          if (item is Map)
            SmsTextRange.fromJson(Map<String, dynamic>.from(item)),
      ],
      placeholders: [
        for (final item in json['placeholders'] as List? ?? const [])
          if (item is Map)
            SmsPlaceholder.fromJson(Map<String, dynamic>.from(item)),
      ],
    );
  }
}

class SmsParsedResult {
  final String templateId;
  final double amount;
  final SmsTemplateType type;
  final String? merchant;
  final double? balance;

  const SmsParsedResult({
    required this.templateId,
    required this.amount,
    required this.type,
    this.merchant,
    this.balance,
  });
}
