import 'package:flutter_test/flutter_test.dart';
import 'package:money_traker/sms/sms_hash.dart';
import 'package:money_traker/sms/sms_models.dart';
import 'package:money_traker/sms/sms_rule_engine.dart';

void main() {
  test(
    'marking a number builds a rule that reads a similar Arabic message',
    () {
      const sample = 'تم خصم 150 جنيه من حساب 4521 والرصيد المتاح 9000';
      final numbers = SmsRuleEngine.findNumbers(sample);
      expect(numbers.map((n) => n.text).toList(), ['150', '4521', '9000']);

      final amountContext = SmsRuleEngine.contextFor(
        sample,
        numbers[0],
        numbers,
      );
      final accountContext = SmsRuleEngine.contextFor(
        sample,
        numbers[1],
        numbers,
      );
      final balanceContext = SmsRuleEngine.contextFor(
        sample,
        numbers[2],
        numbers,
      );

      final rules = [
        SmsReadRule(
          bankId: 'cib',
          field: SmsField.amount,
          typeHint: 'debit',
          prefix: amountContext.prefix,
          suffix: amountContext.suffix,
          createdAt: DateTime(2026),
        ),
        SmsReadRule(
          bankId: 'cib',
          field: SmsField.account,
          prefix: accountContext.prefix,
          suffix: accountContext.suffix,
          createdAt: DateTime(2026),
        ),
        SmsReadRule(
          bankId: 'cib',
          field: SmsField.balance,
          prefix: balanceContext.prefix,
          suffix: balanceContext.suffix,
          createdAt: DateTime(2026),
        ),
      ];

      const next = 'تم خصم 1,250.50 جنيه من حساب 9999 والرصيد المتاح 300';
      final reading = SmsRuleEngine.parse(
        next,
        rules,
        typeWords: [
          SmsTypeWord(
            bankId: 'cib',
            word: 'خصم',
            typeHint: 'debit',
            createdAt: DateTime(2026),
          ),
        ],
      );
      expect(reading.amount, 1250.50);
      expect(reading.typeHint, 'debit');
      expect(reading.account, '9999');
      expect(reading.balance, 300);
    },
  );

  test('the same marking works for an English message', () {
    const sample =
        'Debited EGP 150.00 from account 1234. Available balance EGP 900';
    final numbers = SmsRuleEngine.findNumbers(sample);
    final amount = numbers.firstWhere((n) => n.text == '150.00');
    final context = SmsRuleEngine.contextFor(sample, amount, numbers);
    final rule = SmsReadRule(
      bankId: 'cib',
      field: SmsField.amount,
      typeHint: 'debit',
      prefix: context.prefix,
      suffix: context.suffix,
      createdAt: DateTime(2026),
    );

    const next = 'Debited EGP 80 from account 1234. Available balance EGP 20';
    final reading = SmsRuleEngine.parse(
      next,
      [rule],
      typeWords: [
        SmsTypeWord(
          bankId: 'cib',
          word: 'Debited',
          typeHint: 'debit',
          createdAt: DateTime(2026),
        ),
      ],
    );
    expect(reading.amount, 80);
    expect(reading.typeHint, 'debit');
  });

  test('arabic digits are read as amounts', () {
    expect(SmsRuleEngine.parseAmount('١\u066C٢٥٠\u066B٥٠'), 1250.50);
  });

  test('sender matching prefers the longest configured name', () {
    const banks = [
      BankConfig(id: 'cib', nameEn: 'CIB', nameAr: 'CIB', senders: ['CIB']),
      BankConfig(
        id: 'cib-eg',
        nameEn: 'CIB Egypt',
        nameAr: 'CIB',
        senders: ['CIB-Egypt'],
      ),
    ];
    expect(SmsRuleEngine.matchBank('CIB-Egypt', banks)?.id, 'cib-eg');
    expect(SmsRuleEngine.matchBank('CIB', banks)?.id, 'cib');
  });

  test('a marked word such as خصم makes later messages debit', () {
    const sample = 'تم خصم 150 جنيه';
    final numbers = SmsRuleEngine.findNumbers(sample);
    final amountContext = SmsRuleEngine.contextFor(
      sample,
      numbers.first,
      numbers,
    );
    final rules = [
      SmsReadRule(
        bankId: 'cib',
        field: SmsField.amount,
        prefix: amountContext.prefix,
        suffix: amountContext.suffix,
        createdAt: DateTime(2026),
      ),
    ];
    final typeWords = [
      SmsTypeWord(
        bankId: 'cib',
        word: 'خصم',
        typeHint: 'debit',
        createdAt: DateTime(2026),
      ),
      SmsTypeWord(
        bankId: 'cib',
        word: 'إيداع',
        typeHint: 'credit',
        createdAt: DateTime(2026),
      ),
    ];

    expect(
      SmsRuleEngine.parse(
        'تم خصم 80 جنيه',
        rules,
        typeWords: typeWords,
      ).typeHint,
      'debit',
    );
    expect(
      SmsRuleEngine.parse(
        'تم إيداع 80 جنيه',
        rules,
        typeWords: typeWords,
      ).typeHint,
      'credit',
    );
  });

  test(
    'a marked amount still matches when other numbers in the same shape change',
    () {
      const sample = 'Your account credited EGP 200 on 15/10/2026 Balance 9000';
      final numbers = SmsRuleEngine.findNumbers(sample);
      final amount = numbers.firstWhere((n) => n.text == '200');
      final context = SmsRuleEngine.contextFor(sample, amount, numbers);
      final rules = [
        SmsReadRule(
          bankId: 'cib',
          field: SmsField.amount,
          prefix: context.prefix,
          suffix: context.suffix,
          createdAt: DateTime(2026),
        ),
      ];
      final typeWords = [
        SmsTypeWord(
          bankId: 'cib',
          word: 'credited',
          typeHint: 'credit',
          createdAt: DateTime(2026),
        ),
      ];

      final other = 'Your account credited EGP 350 on 16/11/2026 Balance 100';
      final reading = SmsRuleEngine.parse(other, rules, typeWords: typeWords);
      expect(reading.typeHint, 'credit');
      expect(reading.amount, 350);
    },
  );

  test('credited still matches Credit with a different case', () {
    const sample = 'Your account credited EGP 200 on 15/10/2026 Balance 9000';
    final numbers = SmsRuleEngine.findNumbers(sample);
    final amount = numbers.firstWhere((n) => n.text == '200');
    final context = SmsRuleEngine.contextFor(sample, amount, numbers);
    final rules = [
      SmsReadRule(
        bankId: 'cib',
        field: SmsField.amount,
        typeHint: 'credit',
        prefix: context.prefix,
        suffix: context.suffix,
        createdAt: DateTime(2026),
      ),
    ];
    final typeWords = [
      SmsTypeWord(
        bankId: 'cib',
        word: 'credit',
        typeHint: 'credit',
        createdAt: DateTime(2026),
      ),
    ];

    final other = 'Your account CREDITED EGP 80 on 16/10/2026 Balance 100';
    final reading = SmsRuleEngine.parse(other, rules, typeWords: typeWords);
    expect(reading.typeHint, 'credit');
    expect(reading.amount, 80);
    expect(reading.isComplete, isTrue);
  });

  test('a bare amount template is not blocked', () {
    final rules = [
      SmsReadRule(
        bankId: 'cib',
        field: SmsField.amount,
        prefix: '',
        suffix: '',
        createdAt: DateTime(2026),
      ),
    ];
    final report = SmsRuleEngine.test(
      corpus: [
        _copy(sender: 'CIB', body: 'Your OTP is 1234'),
        _copy(sender: 'Promo', body: 'Offer 50 percent off'),
        _copy(sender: 'CIB', body: 'credited 200'),
      ],
      rules: rules,
      typeWords: const [],
      senders: const ['CIB'],
    );
    expect(report.tooGeneric, isFalse);
    expect(report.reasons, isEmpty);
  });

  test(
    'a specific rule with sender is accepted and counts affected messages',
    () {
      const sample = 'تم خصم 150 جنيه من حسابك';
      final numbers = SmsRuleEngine.findNumbers(sample);
      final context = SmsRuleEngine.contextFor(sample, numbers.first, numbers);
      final rules = [
        SmsReadRule(
          bankId: 'cib',
          field: SmsField.amount,
          prefix: context.prefix,
          suffix: context.suffix,
          createdAt: DateTime(2026),
        ),
      ];
      final typeWords = [
        SmsTypeWord(
          bankId: 'cib',
          word: 'خصم',
          typeHint: 'debit',
          createdAt: DateTime(2026),
        ),
      ];
      final report = SmsRuleEngine.test(
        corpus: [
          _copy(sender: 'CIB', body: 'تم خصم 80 جنيه من حسابك'),
          _copy(sender: 'CIB', body: 'تم خصم 20 جنيه من حسابك'),
          _copy(sender: 'OTP', body: 'Your OTP is 4455'),
          _copy(sender: 'Promo', body: 'خصم 70% على كل العروض'),
        ],
        rules: rules,
        typeWords: typeWords,
        senders: const ['CIB'],
      );
      expect(report.hasSender, isTrue);
      expect(report.tooGeneric, isFalse);
      expect(report.matched, 2);
      expect(report.total, 2);
      expect(report.foreignMatches, 0);
    },
  );

  test(
    'a short amount rule is not blocked when a specific rule also exists',
    () {
      const sample = 'تم خصم 150 جنيه من حسابك';
      final numbers = SmsRuleEngine.findNumbers(sample);
      final context = SmsRuleEngine.contextFor(sample, numbers.first, numbers);
      final rules = [
        SmsReadRule(
          bankId: 'cib',
          field: SmsField.amount,
          prefix: context.prefix,
          suffix: context.suffix,
          createdAt: DateTime(2026),
        ),
        SmsReadRule(
          bankId: 'cib',
          field: SmsField.amount,
          prefix: 'is',
          suffix: '',
          createdAt: DateTime(2026),
        ),
      ];
      final report = SmsRuleEngine.test(
        corpus: [
          _copy(sender: 'CIB', body: 'تم خصم 80 جنيه من حسابك'),
          _copy(sender: 'OTP', body: 'Your OTP is 4455'),
        ],
        rules: rules,
        typeWords: [
          SmsTypeWord(
            bankId: 'cib',
            word: 'خصم',
            typeHint: 'debit',
            createdAt: DateTime(2026),
          ),
        ],
        senders: const ['CIB'],
      );
      expect(report.tooGeneric, isFalse);
      expect(report.reasons, isEmpty);
      expect(report.matched, 1);
      expect(report.total, 1);
    },
  );

  test('a category word matches the message and the longer word wins', () {
    final rules = [
      SmsCategoryRule(
        bankId: 'cib',
        word: 'Uber',
        tagId: 1,
        createdAt: DateTime(2026),
      ),
      SmsCategoryRule(
        bankId: 'cib',
        word: 'UberEats',
        tagId: 2,
        createdAt: DateTime(2026),
      ),
      SmsCategoryRule(
        bankId: 'cib',
        word: 'Netflix',
        tagId: 3,
        createdAt: DateTime(2026),
      ),
    ];

    expect(
      SmsRuleEngine.rankCategoryRules(
        'تم خصم 50 لدى UberEats',
        rules,
      ).first.tagId,
      2,
    );
    expect(
      SmsRuleEngine.rankCategoryRules(
        'Purchase at NETFLIX 120 EGP',
        rules,
      ).first.tagId,
      3,
    );
    expect(
      SmsRuleEngine.rankCategoryRules(
        'تم خصم 20 Uber اليوم',
        rules,
      ).first.tagId,
      1,
    );
    expect(SmsRuleEngine.rankCategoryRules('no merchant here', rules), isEmpty);
    expect(
      SmsRuleEngine.firstExactWordIndex('مدفوع Netflix.', 'Netflix'),
      greaterThanOrEqualTo(0),
    );
  });

  test(
    'selected text sets debit, credit, or a category when it appears again',
    () {
      expect(
        SmsRuleEngine.detectType('IPN outward transfer for EGP 50', [
          SmsTypeWord(
            bankId: 'hsbc',
            word: 'IPN out',
            typeHint: 'debit',
            createdAt: DateTime(2026),
          ),
        ]),
        'debit',
      );
      expect(
        SmsRuleEngine.detectType('Salary to account 001', [
          SmsTypeWord(
            bankId: 'hsbc',
            word: 'Salary',
            typeHint: 'credit',
            createdAt: DateTime(2026),
          ),
        ]),
        'credit',
      );
      expect(
        SmsRuleEngine.detectType('IPN outward transfer', [
          SmsTypeWord(
            bankId: 'hsbc',
            word: 'IPN',
            typeHint: 'credit',
            createdAt: DateTime(2026),
          ),
          SmsTypeWord(
            bankId: 'hsbc',
            word: 'IPN outward',
            typeHint: 'debit',
            createdAt: DateTime(2026),
          ),
        ]),
        'debit',
      );
      expect(
        SmsRuleEngine.rankCategoryRules('card SEOUDI SILVER STAR 9001', [
          SmsCategoryRule(
            bankId: 'cib',
            word: 'SILVER',
            tagId: 1,
            createdAt: DateTime(2026),
          ),
          SmsCategoryRule(
            bankId: 'cib',
            word: 'SILVER STAR',
            tagId: 2,
            createdAt: DateTime(2026),
          ),
        ]).first.tagId,
        2,
      );
    },
  );

  test('a match from another sender does not block the rule', () {
    final report = SmsRuleEngine.test(
      corpus: [
        _copy(sender: 'HSBC', body: 'Salary EGP 100'),
        _copy(sender: 'CIB', body: 'Cashback EGP 90'),
        _copy(sender: 'CIB', body: 'Refund EGP 40'),
      ],
      rules: [
        SmsReadRule(
          bankId: 'hsbc',
          field: SmsField.amount,
          prefix: 'EGP',
          suffix: '',
          typeHint: 'credit',
          createdAt: DateTime(2026),
        ),
      ],
      typeWords: const [],
      senders: const ['HSBC'],
    );
    expect(report.matched, 1);
    expect(report.foreignMatches, 2);
    expect(report.tooGeneric, isFalse);
  });

  test('saved text is matched again even when it is more than one word', () {
    final typeWords = [
      SmsTypeWord(
        bankId: 'cib',
        word: 'تحويل الى',
        typeHint: 'credit',
        createdAt: DateTime(2026),
      ),
      SmsTypeWord(
        bankId: 'cib',
        word: 'تحويل من',
        typeHint: 'debit',
        createdAt: DateTime(2026),
      ),
    ];

    expect(
      SmsRuleEngine.detectType('تم تحويل الى حسابك مبلغ 500', typeWords),
      'credit',
    );
    expect(
      SmsRuleEngine.detectType('تم تحويل من حسابك مبلغ 500', typeWords),
      'debit',
    );
    expect(SmsRuleEngine.detectType('تم تحويل 500 جنيه', typeWords), '');
    expect(SmsRuleEngine.detectType('تم تحويل مبلغ الى حسابك', typeWords), '');
    expect(
      SmsRuleEngine.detectType('تم تحويل الى حسابك', [
        SmsTypeWord(
          bankId: 'cib',
          word: 'تم',
          typeHint: 'debit',
          createdAt: DateTime(2026),
        ),
        ...typeWords,
      ]),
      'credit',
    );
  });

  test('a number glued to letters or symbols is read as the number only', () {
    expect(SmsRuleEngine.parseAmount('500EGP'), 500);
    expect(SmsRuleEngine.parseAmount('EGP1,250.50'), 1250.50);
    expect(SmsRuleEngine.parseAmount('ج.م150'), 150);
    expect(SmsRuleEngine.parseAmount('١\u066C٢٥٠\u066B٥٠EGP'), 1250.50);
    expect(SmsRuleEngine.singleNumberIn('15/10/2026'), isNull);
    expect(SmsRuleEngine.singleNumberIn('500EGP')?.text, '500');
    expect(SmsRuleEngine.tokenize('خصم 500EGP').last.isNumber, isTrue);

    const sample = 'تم تحويل الى حسابك EGP150.75 والرصيد 4521';
    final numbers = SmsRuleEngine.findNumbers(sample);
    final amount = numbers.firstWhere((n) => n.text == '150.75');
    final context = SmsRuleEngine.contextFor(sample, amount, numbers);
    final reading = SmsRuleEngine.parse(
      'تم تحويل الى حسابك EGP80 والرصيد 9999',
      [
        SmsReadRule(
          bankId: 'cib',
          field: SmsField.amount,
          prefix: context.prefix,
          suffix: context.suffix,
          createdAt: DateTime(2026),
        ),
      ],
      typeWords: [
        SmsTypeWord(
          bankId: 'cib',
          word: 'تحويل الى',
          typeHint: 'credit',
          createdAt: DateTime(2026),
        ),
      ],
    );
    expect(reading.amount, 80);
    expect(reading.typeHint, 'credit');

    const stuckAfter = 'تم تحويل من حسابك 200EGP';
    final stuckNumbers = SmsRuleEngine.findNumbers(stuckAfter);
    final stuckAmount = stuckNumbers.firstWhere((n) => n.text == '200');
    final stuckContext = SmsRuleEngine.contextFor(
      stuckAfter,
      stuckAmount,
      stuckNumbers,
    );
    final stuck = SmsRuleEngine.parse(
      'تم تحويل من حسابك 90.5EGP',
      [
        SmsReadRule(
          bankId: 'cib',
          field: SmsField.amount,
          prefix: stuckContext.prefix,
          suffix: stuckContext.suffix,
          createdAt: DateTime(2026),
        ),
      ],
      typeWords: [
        SmsTypeWord(
          bankId: 'cib',
          word: 'تحويل من',
          typeHint: 'debit',
          createdAt: DateTime(2026),
        ),
      ],
    );
    expect(stuck.amount, 90.5);
    expect(stuck.typeHint, 'debit');
  });

  test(
    'the same raw sms keeps a stable hash so reprocessing updates instead of duplicating',
    () {
      const a = 'sms-1';
      const sender = 'CIB';
      const body = 'تم خصم 150 جنيه';
      expect(
        SmsHash.of(smsId: a, sender: sender, body: body),
        SmsHash.of(smsId: a, sender: sender, body: body),
      );
      expect(
        SmsHash.of(smsId: a, sender: sender, body: body),
        isNot(SmsHash.of(smsId: 'sms-2', sender: sender, body: body)),
      );
    },
  );
}

SmsCopy _copy({required String sender, required String body}) {
  return SmsCopy(
    smsId: '$sender-$body',
    sender: sender,
    body: body,
    date: DateTime(2026),
    bankId: 'cib',
    status: SmsCopyStatus.pending,
    copiedAt: DateTime(2026),
  );
}
