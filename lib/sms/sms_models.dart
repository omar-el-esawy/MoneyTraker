enum SmsField { amount, balance, account }

enum SmsCopyStatus { pending, parsed, unreadable }

class BankConfig {
  final String id;
  final String nameEn;
  final String nameAr;
  final List<String> senders;
  final bool enabled;
  final int? sourceId;
  final int ruleVersion;

  const BankConfig({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    required this.senders,
    this.enabled = true,
    this.sourceId,
    this.ruleVersion = 1,
  });

  String nameFor(bool arabic) => arabic ? nameAr : nameEn;

  BankConfig copyWith({
    String? id,
    String? nameEn,
    String? nameAr,
    List<String>? senders,
    bool? enabled,
    int? sourceId,
    bool clearSourceId = false,
    int? ruleVersion,
  }) {
    return BankConfig(
      id: id ?? this.id,
      nameEn: nameEn ?? this.nameEn,
      nameAr: nameAr ?? this.nameAr,
      senders: senders ?? this.senders,
      enabled: enabled ?? this.enabled,
      sourceId: clearSourceId ? null : (sourceId ?? this.sourceId),
      ruleVersion: ruleVersion ?? this.ruleVersion,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nameEn': nameEn,
        'nameAr': nameAr,
        'senders': senders,
        'enabled': enabled,
        'sourceId': sourceId,
        'ruleVersion': ruleVersion,
      };

  factory BankConfig.fromJson(Map<String, dynamic> json) {
    return BankConfig(
      id: json['id'] as String? ?? '',
      nameEn: json['nameEn'] as String? ?? '',
      nameAr: json['nameAr'] as String? ?? '',
      senders: (json['senders'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      enabled: json['enabled'] as bool? ?? true,
      sourceId: (json['sourceId'] as num?)?.toInt(),
      ruleVersion: (json['ruleVersion'] as num?)?.toInt() ?? 1,
    );
  }

  static List<BankConfig> defaults() => const [
        BankConfig(
          id: 'cib',
          nameEn: 'CIB',
          nameAr: 'بنك CIB',
          senders: ['CIB-Egypt', 'CIBEGYPT', 'CIB'],
        ),
        BankConfig(
          id: 'nbe',
          nameEn: 'NBE',
          nameAr: 'البنك الأهلي',
          senders: ['NBE', 'AlAhlyBank', 'NationalBank'],
        ),
        BankConfig(
          id: 'banque_misr',
          nameEn: 'Banque Misr',
          nameAr: 'بنك مصر',
          senders: ['BanqueMisr', 'B-Misr'],
        ),
        BankConfig(
          id: 'qnb',
          nameEn: 'QNB',
          nameAr: 'بنك QNB',
          senders: ['QNBALAHLI', 'QNB'],
        ),
        BankConfig(
          id: 'alex',
          nameEn: 'Alex Bank',
          nameAr: 'بنك الإسكندرية',
          senders: ['AlexBank', 'ABE'],
        ),
        BankConfig(
          id: 'adcb',
          nameEn: 'ADCB',
          nameAr: 'بنك أبوظبي التجاري',
          senders: ['ADCB'],
        ),
        BankConfig(
          id: 'hsbc',
          nameEn: 'HSBC',
          nameAr: 'HSBC',
          senders: ['HSBC'],
        ),
        BankConfig(
          id: 'fawry',
          nameEn: 'Fawry',
          nameAr: 'فوري',
          senders: ['Fawry', 'FawryPay'],
        ),
      ];
}

class SmsFeatureConfig {
  final bool started;
  final DateTime? startDate;
  final String languageCode;
  final List<BankConfig> banks;

  const SmsFeatureConfig({
    required this.started,
    required this.startDate,
    required this.languageCode,
    required this.banks,
  });

  bool get arabic => languageCode == 'ar';

  SmsFeatureConfig copyWith({
    bool? started,
    DateTime? startDate,
    bool clearStartDate = false,
    String? languageCode,
    List<BankConfig>? banks,
  }) {
    return SmsFeatureConfig(
      started: started ?? this.started,
      startDate: clearStartDate ? null : (startDate ?? this.startDate),
      languageCode: languageCode ?? this.languageCode,
      banks: banks ?? this.banks,
    );
  }

  Map<String, dynamic> toJson() => {
        'started': started,
        'startDate': startDate?.millisecondsSinceEpoch,
        'languageCode': languageCode,
        'banks': banks.map((b) => b.toJson()).toList(),
      };

  factory SmsFeatureConfig.fromJson(Map<String, dynamic> json) {
    final rawBanks = json['banks'] as List?;
    return SmsFeatureConfig(
      started: json['started'] as bool? ?? false,
      startDate: json['startDate'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(json['startDate'] as int),
      languageCode: json['languageCode'] as String? ?? 'en',
      banks: rawBanks == null
          ? BankConfig.defaults()
          : rawBanks.map((e) => BankConfig.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
    );
  }

  factory SmsFeatureConfig.fresh({String languageCode = 'en'}) {
    return SmsFeatureConfig(
      started: false,
      startDate: null,
      languageCode: languageCode,
      banks: BankConfig.defaults(),
    );
  }
}

class SmsCopy {
  final int? id;
  final String smsId;
  final String sender;
  final String body;
  final DateTime date;
  final String bankId;
  final SmsCopyStatus status;
  final DateTime copiedAt;
  final bool sourceApplied;

  const SmsCopy({
    this.id,
    required this.smsId,
    required this.sender,
    required this.body,
    required this.date,
    required this.bankId,
    required this.status,
    required this.copiedAt,
    this.sourceApplied = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'sms_id': smsId,
        'sender': sender,
        'body': body,
        'date': date.millisecondsSinceEpoch,
        'bank_id': bankId,
        'status': status.name,
        'copied_at': copiedAt.millisecondsSinceEpoch,
        'source_applied': sourceApplied ? 1 : 0,
      };

  factory SmsCopy.fromMap(Map<String, dynamic> map) {
    return SmsCopy(
      id: map['id'] as int?,
      smsId: map['sms_id'] as String? ?? '',
      sender: map['sender'] as String? ?? '',
      body: map['body'] as String? ?? '',
      date: DateTime.fromMillisecondsSinceEpoch((map['date'] as int?) ?? 0),
      bankId: map['bank_id'] as String? ?? '',
      status: SmsCopyStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => SmsCopyStatus.pending,
      ),
      copiedAt: DateTime.fromMillisecondsSinceEpoch((map['copied_at'] as int?) ?? 0),
      sourceApplied: (map['source_applied'] as num?)?.toInt() == 1,
    );
  }
}

class SmsReadRule {
  final int? id;
  final String bankId;
  final SmsField field;
  final String typeHint;
  final String prefix;
  final String suffix;
  final String? sampleSmsId;
  final DateTime createdAt;

  const SmsReadRule({
    this.id,
    required this.bankId,
    required this.field,
    this.typeHint = '',
    required this.prefix,
    required this.suffix,
    this.sampleSmsId,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'bank_id': bankId,
        'field': field.name,
        'type_hint': typeHint,
        'prefix': prefix,
        'suffix': suffix,
        'sample_sms_id': sampleSmsId,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory SmsReadRule.fromMap(Map<String, dynamic> map) {
    return SmsReadRule(
      id: map['id'] as int?,
      bankId: map['bank_id'] as String? ?? '',
      field: SmsField.values.firstWhere(
        (f) => f.name == map['field'],
        orElse: () => SmsField.amount,
      ),
      typeHint: map['type_hint'] as String? ?? '',
      prefix: map['prefix'] as String? ?? '',
      suffix: map['suffix'] as String? ?? '',
      sampleSmsId: map['sample_sms_id'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch((map['created_at'] as int?) ?? 0),
    );
  }
}

class SmsCategoryRule {
  final int? id;
  final String bankId;
  final String word;
  final int tagId;
  final DateTime createdAt;

  const SmsCategoryRule({
    this.id,
    required this.bankId,
    required this.word,
    required this.tagId,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'bank_id': bankId,
        'word': word,
        'tag_id': tagId,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory SmsCategoryRule.fromMap(Map<String, dynamic> map) {
    return SmsCategoryRule(
      id: map['id'] as int?,
      bankId: map['bank_id'] as String? ?? '',
      word: map['word'] as String? ?? '',
      tagId: (map['tag_id'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch((map['created_at'] as int?) ?? 0),
    );
  }
}

class SmsTypeWord {
  final int? id;
  final String bankId;
  final String word;
  final String typeHint;
  final DateTime createdAt;

  const SmsTypeWord({
    this.id,
    required this.bankId,
    required this.word,
    required this.typeHint,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'bank_id': bankId,
        'word': word,
        'type_hint': typeHint,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory SmsTypeWord.fromMap(Map<String, dynamic> map) {
    return SmsTypeWord(
      id: map['id'] as int?,
      bankId: map['bank_id'] as String? ?? '',
      word: map['word'] as String? ?? '',
      typeHint: map['type_hint'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch((map['created_at'] as int?) ?? 0),
    );
  }
}

class SmsNumberSpan {
  final int start;
  final int end;
  final String text;

  const SmsNumberSpan({
    required this.start,
    required this.end,
    required this.text,
  });
}

class SmsToken {
  final int start;
  final int end;
  final String text;
  final bool isNumber;

  const SmsToken({
    required this.start,
    required this.end,
    required this.text,
    required this.isNumber,
  });
}

class SmsRuleContext {
  final String prefix;
  final String suffix;

  const SmsRuleContext({required this.prefix, required this.suffix});

  bool get isUseful => prefix.isNotEmpty || suffix.isNotEmpty;
}

class SmsReading {
  final double? amount;
  final String typeHint;
  final double? balance;
  final String? account;

  const SmsReading({
    this.amount,
    this.typeHint = '',
    this.balance,
    this.account,
  });

  bool get isComplete => amount != null && typeHint.isNotEmpty;
}

class SmsRuleTestHit {
  final String smsId;
  final String sender;
  final String body;
  final DateTime date;
  final SmsReading reading;
  final bool senderBelongsToBank;

  const SmsRuleTestHit({
    this.smsId = '',
    required this.sender,
    required this.body,
    required this.date,
    required this.reading,
    required this.senderBelongsToBank,
  });
}

class SmsRuleTestReport {
  final int total;
  final int matched;
  final int unmatched;
  final int foreignMatches;
  final bool hasSender;
  final int fixedLetterCount;
  final bool tooGeneric;
  final List<String> reasons;
  final List<SmsRuleTestHit> hits;

  const SmsRuleTestReport({
    required this.total,
    required this.matched,
    required this.unmatched,
    required this.foreignMatches,
    required this.hasSender,
    required this.fixedLetterCount,
    required this.tooGeneric,
    required this.reasons,
    required this.hits,
  });

  List<SmsRuleTestHit> get sampleHits {
    return [
      ...hits.where((hit) => hit.senderBelongsToBank),
      ...hits.where((hit) => !hit.senderBelongsToBank),
    ];
  }
}

class SmsSyncResult {
  final bool supported;
  final bool permissionGranted;
  final int copied;
  final int parsed;
  final int appliedToSource;
  final int skipped;
  final int unmatched;
  final int missingSource;
  final int updated;
  final String error;

  const SmsSyncResult({
    required this.supported,
    required this.permissionGranted,
    this.copied = 0,
    this.parsed = 0,
    this.appliedToSource = 0,
    this.skipped = 0,
    this.unmatched = 0,
    this.missingSource = 0,
    this.updated = 0,
    this.error = '',
  });

  static const unsupported = SmsSyncResult(supported: false, permissionGranted: false);
  static const denied = SmsSyncResult(supported: true, permissionGranted: false);
}
