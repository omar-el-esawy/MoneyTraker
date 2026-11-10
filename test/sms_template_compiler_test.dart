import 'package:flutter_test/flutter_test.dart';
import 'package:money_traker/sms/template_engine/sms_template_compiler.dart';
import 'package:money_traker/sms/template_engine/template_models.dart';

void main() {
  group('SmsTemplateCompiler', () {
    test('compiles and matches a realistic Arabic purchase template', () {
      const sample =
          'تم خصم 1,500.00 جنيه من بطاقة 4521 لدى STAR MARKET '
          'بتاريخ 01/11/2026 الساعة 10:30 الرصيد 9,000.00';
      final compiled = SmsTemplateCompiler.compile(
        _template(
          id: 'arabic-purchase',
          sample: sample,
          type: SmsTemplateType.debit,
          direction: ['خصم'],
          amountText: '1,500.00',
          placeholders: [
            _placeholder(sample, SmsPlaceholderKind.cardDigits, '4521'),
            _placeholder(sample, SmsPlaceholderKind.merchant, 'STAR MARKET'),
            _placeholder(sample, SmsPlaceholderKind.date, '01/11/2026'),
            _placeholder(sample, SmsPlaceholderKind.time, '10:30'),
            _placeholder(sample, SmsPlaceholderKind.balance, '9,000.00'),
          ],
        ),
      );

      final result = compiled!.match(
        'تم خصم ٢\u066C٧٥٠\u066B٥٠ جنيه من بطاقة 9988 لدى '
        'SEOUDI\nSILVER-STAR & CO. بتاريخ 03/12/2026 الساعة 09:45 '
        'الرصيد ١٢\u066C٠٠٠\u066B٢٥',
      );

      expect(result, isNotNull);
      expect(result!.templateId, 'arabic-purchase');
      expect(result.amount, 2750.50);
      expect(result.type, SmsTemplateType.debit);
      expect(result.merchant, 'SEOUDI SILVER-STAR & CO.');
      expect(result.balance, 12000.25);
    });

    test('matches currency before, after, and attached to amount', () {
      for (final example in [
        (
          sample: 'Debited EGP 1500 from card 1234',
          amount: '1500',
          incoming: 'Debited EGP 75 from card 9999',
          expected: 75.0,
        ),
        (
          sample: 'Debited 1500 EGP from card 1234',
          amount: '1500',
          incoming: 'Debited 80.50 EGP from card 9999',
          expected: 80.50,
        ),
        (
          sample: 'Debited EGP1500 from card 1234',
          amount: '1500',
          incoming: 'Debited EGP1,250.00 from card 9999',
          expected: 1250.0,
        ),
        (
          sample: 'Debited 1500EGP from card 1234',
          amount: '1500',
          incoming: 'Debited 90EGP from card 9999',
          expected: 90.0,
        ),
      ]) {
        final compiled = SmsTemplateCompiler.compile(
          _template(
            id: example.sample,
            sample: example.sample,
            type: SmsTemplateType.debit,
            direction: ['Debited'],
            amountText: example.amount,
            placeholders: [
              _placeholder(
                example.sample,
                SmsPlaceholderKind.cardDigits,
                '1234',
              ),
            ],
          ),
        );

        expect(compiled!.match(example.incoming)!.amount, example.expected);
      }
    });

    test(
      'extracts only the marked amount when the message has many numbers',
      () {
        const sample =
            'Card 4521 debited EGP 150 on 01/11/2026. Balance EGP 9000';
        final compiled = SmsTemplateCompiler.compile(
          _template(
            id: 'many-numbers',
            sample: sample,
            type: SmsTemplateType.debit,
            direction: ['debited'],
            amountText: '150',
            placeholders: [
              _placeholder(sample, SmsPlaceholderKind.cardDigits, '4521'),
              _placeholder(sample, SmsPlaceholderKind.date, '01/11/2026'),
              _placeholder(sample, SmsPlaceholderKind.balance, '9000'),
            ],
          ),
        );

        final result = compiled!.match(
          'Card 9988 debited EGP 75 on 02/12/2026. Balance EGP 5000',
        );

        expect(result!.amount, 75);
        expect(result.balance, 5000);
      },
    );

    test('uses the final valid merchant delimiter', () {
      const sample = 'تم خصم 100 لدى STAR بتاريخ 01/11/2026 تم بنجاح';
      final compiled = SmsTemplateCompiler.compile(
        _template(
          id: 'delimiter',
          sample: sample,
          type: SmsTemplateType.debit,
          direction: ['خصم'],
          amountText: '100',
          placeholders: [
            _placeholder(sample, SmsPlaceholderKind.merchant, 'STAR'),
            _placeholder(sample, SmsPlaceholderKind.date, '01/11/2026'),
          ],
        ),
      );

      final result = compiled!.match(
        'تم خصم 250 لدى معرض بتاريخ 01/01/2020 فرع بتاريخ '
        '03/12/2026 تم بنجاح',
      );

      expect(result!.merchant, 'معرض بتاريخ 01/01/2020 فرع');
    });

    test('merges adjacent generic words into one changing section', () {
      const sample = 'تم خصم EGP 325 عند El Moemen El Bashar 7 في 07/11/26';
      const changingText = 'El Moemen El Bashar 7';
      final changingStart = sample.indexOf(changingText);
      final changingWords = [
        for (final match in RegExp(r'\S+').allMatches(changingText))
          SmsPlaceholder(
            kind: SmsPlaceholderKind.other,
            range: SmsTextRange(
              start: changingStart + match.start,
              end: changingStart + match.end,
            ),
          ),
      ];
      final compiled = SmsTemplateCompiler.compile(
        _template(
          id: 'generic-merchant',
          sample: sample,
          type: SmsTemplateType.debit,
          direction: ['خصم'],
          amountText: '325',
          placeholders: changingWords,
        ),
      );

      final result = compiled!.match(
        'تم خصم EGP 600 عند SAKKARA TOURS CAIRO في 07/11/26',
      );

      expect(result, isNotNull);
      expect(result!.amount, 600);
    });

    test('merchant and balance are optional template fields', () {
      const sample = 'Your account was credited USD 500 reference ABC-10';
      final compiled = SmsTemplateCompiler.compile(
        _template(
          id: 'deposit',
          sample: sample,
          type: SmsTemplateType.credit,
          direction: ['credited'],
          amountText: '500',
          placeholders: [
            _placeholder(sample, SmsPlaceholderKind.reference, 'ABC-10'),
          ],
        ),
      );

      final result = compiled!.match(
        'Your account was credited USD 900 reference XYZ-55',
      );

      expect(result!.amount, 900);
      expect(result.type, SmsTemplateType.credit);
      expect(result.merchant, isNull);
      expect(result.balance, isNull);
    });

    test('rejects a structurally matched message with an invalid amount', () {
      const sample = 'تم خصم 150 جنيه بنجاح';
      final compiled = SmsTemplateCompiler.compile(
        _template(
          id: 'invalid-amount',
          sample: sample,
          type: SmsTemplateType.debit,
          direction: ['خصم'],
          amountText: '150',
        ),
      );

      expect(compiled!.match('تم خصم 1.2.3 جنيه بنجاح'), isNull);
      expect(compiled.match('تم خصم جنيه بنجاح'), isNull);
    });

    test('does not infer or change the template transaction type', () {
      const sample = 'تمت إضافة مبلغ 500 إلى حسابك';
      final compiled = SmsTemplateCompiler.compile(
        _template(
          id: 'fixed-credit',
          sample: sample,
          type: SmsTemplateType.credit,
          direction: ['تمت إضافة', 'إلى'],
          amountText: '500',
        ),
      );

      final result = compiled!.match('تمت إضافة مبلغ 750 إلى حسابك');

      expect(result!.type, SmsTemplateType.credit);
    });

    test('returns null when the bank format changes', () {
      const sample = 'تم خصم 150 جنيه من حسابك';
      final compiled = SmsTemplateCompiler.compile(
        _template(
          id: 'old-format',
          sample: sample,
          type: SmsTemplateType.debit,
          direction: ['خصم'],
          amountText: '150',
        ),
      );

      expect(compiled!.match('عملية شراء جديدة بقيمة 150 جنيه'), isNull);
    });

    test('allows a direction word to also be a changing part', () {
      const sample = 'تم خصم 150 جنيه';
      final direction = _rangeOf(sample, 'خصم');
      final compiled = SmsTemplateCompiler.compile(
        SmsTemplate(
          id: 'shared-direction',
          bankId: 'bank',
          sampleText: sample,
          type: SmsTemplateType.debit,
          amount: _placeholder(sample, SmsPlaceholderKind.amount, '150'),
          directionRanges: [direction],
          placeholders: [
            SmsPlaceholder(kind: SmsPlaceholderKind.other, range: direction),
          ],
        ),
      );

      expect(compiled, isNotNull);
      expect(compiled!.match(sample), isNotNull);
    });

    test('a balance template reports the account balance', () {
      const sample = 'Your available balance is 900.00 EGP';
      final compiled = SmsTemplateCompiler.compile(
        SmsTemplate(
          id: 'balance-only',
          bankId: 'bank',
          sampleText: sample,
          type: SmsTemplateType.debit,
          amount: _placeholder(sample, SmsPlaceholderKind.balance, '900.00'),
          directionRanges: [_rangeOf(sample, 'balance')],
        ),
      );

      final result = compiled!.match('Your available balance is 750.50 EGP');

      expect(result, isNotNull);
      expect(result!.usesBalance, isTrue);
      expect(result.balance, 750.50);
      expect(result.amount, 750.50);
    });

    test('matches from the message text when debit or credit is already chosen', () {
      const sample = 'تم خصم 150 جنيه';
      final amount = _placeholder(sample, SmsPlaceholderKind.amount, '150');
      final compiled = SmsTemplateCompiler.compile(
        SmsTemplate(
          id: 'no-direction',
          bankId: 'bank',
          sampleText: sample,
          type: SmsTemplateType.debit,
          amount: amount,
          directionRanges: const [],
        ),
      );

      expect(compiled, isNotNull);
      expect(compiled!.match('تم خصم 80 جنيه')?.amount, 80);
      expect(compiled.match('تم خصم 80 جنيه')?.type, SmsTemplateType.debit);
      expect(compiled.match('تم إيداع 80 جنيه'), isNull);
      expect(
        SmsTemplateCompiler.compile(
          SmsTemplate(
            id: 'overlap',
            bankId: 'bank',
            sampleText: sample,
            type: SmsTemplateType.debit,
            amount: amount,
            directionRanges: [_rangeOf(sample, 'خصم 150')],
          ),
        ),
        isNull,
      );
    });
  });
}

SmsTemplate _template({
  required String id,
  required String sample,
  required SmsTemplateType type,
  required List<String> direction,
  required String amountText,
  List<SmsPlaceholder> placeholders = const [],
}) {
  return SmsTemplate(
    id: id,
    bankId: 'bank',
    sampleText: sample,
    type: type,
    amount: _placeholder(sample, SmsPlaceholderKind.amount, amountText),
    directionRanges: [for (final word in direction) _rangeOf(sample, word)],
    placeholders: placeholders,
  );
}

SmsPlaceholder _placeholder(
  String text,
  SmsPlaceholderKind kind,
  String selected,
) {
  return SmsPlaceholder(kind: kind, range: _rangeOf(text, selected));
}

SmsTextRange _rangeOf(String text, String selected) {
  final start = text.indexOf(selected);
  if (start < 0) throw ArgumentError.value(selected, 'selected');
  return SmsTextRange(start: start, end: start + selected.length);
}
