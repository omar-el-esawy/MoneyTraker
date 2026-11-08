import 'package:flutter_test/flutter_test.dart';
import 'package:money_traker/sms/template_engine/sms_template_engine.dart';
import 'package:money_traker/sms/template_engine/template_models.dart';

void main() {
  group('SmsBankTemplateSet', () {
    test('supports a set of debit and credit templates for one bank', () {
      final set = SmsBankTemplateSet.compile(
        bankId: 'bank',
        senderIds: const ['CIB-Egypt'],
        templates: [
          _simpleTemplate(
            id: 'purchase',
            sample: 'تم خصم 100 جنيه من بطاقتك',
            direction: 'خصم',
            amountText: '100',
            type: SmsTemplateType.debit,
          ),
          _simpleTemplate(
            id: 'deposit',
            sample: 'تم إيداع 500 جنيه في حسابك',
            direction: 'إيداع',
            amountText: '500',
            type: SmsTemplateType.credit,
          ),
        ],
      );

      expect(
        set!.match('تم خصم 75 جنيه من بطاقتك')!.type,
        SmsTemplateType.debit,
      );
      expect(
        set.match('تم إيداع 900 جنيه في حسابك')!.type,
        SmsTemplateType.credit,
      );
    });

    test('chooses the matching template with more fixed text', () {
      const sample = 'تم خصم 100 جنيه لدى ABC';
      final set = SmsBankTemplateSet.compile(
        bankId: 'bank',
        senderIds: const ['CIB'],
        templates: [
          _template(
            id: 'broad',
            sample: sample,
            direction: 'خصم',
            amountText: '100',
            type: SmsTemplateType.debit,
            placeholders: [
              _placeholder(sample, SmsPlaceholderKind.merchant, 'ABC'),
            ],
          ),
          _simpleTemplate(
            id: 'specific',
            sample: sample,
            direction: 'خصم',
            amountText: '100',
            type: SmsTemplateType.debit,
          ),
        ],
      );

      expect(set!.match('تم خصم 250 جنيه لدى ABC')!.templateId, 'specific');
    });

    test('previews matched N of M and limits sample results', () {
      final set = SmsBankTemplateSet.compile(
        bankId: 'bank',
        senderIds: const ['CIB'],
        templates: [
          _simpleTemplate(
            id: 'purchase',
            sample: 'تم خصم 100 جنيه',
            direction: 'خصم',
            amountText: '100',
            type: SmsTemplateType.debit,
          ),
        ],
      );
      final preview = set!.preview('purchase', [
        _message('CIB', 'تم خصم 10 جنيه'),
        _message('cib', 'تم خصم 20 جنيه'),
        _message('CIB', 'تم إيداع 30 جنيه'),
        _message('OTHER', 'تم خصم 40 جنيه'),
      ], sampleLimit: 1);

      expect(preview.total, 3);
      expect(preview.matched, 2);
      expect(preview.samples, hasLength(1));
      expect(preview.samples.single.amount, 10);
    });

    test('rejects an invalid set instead of skipping bad templates', () {
      expect(
        SmsBankTemplateSet.compile(
          bankId: 'bank',
          senderIds: const ['CIB'],
          templates: [
            _simpleTemplate(
              id: 'wrong-bank',
              bankId: 'other',
              sample: 'تم خصم 100 جنيه',
              direction: 'خصم',
              amountText: '100',
              type: SmsTemplateType.debit,
            ),
          ],
        ),
        isNull,
      );
    });
  });

  group('SmsTemplateEngine sender and unrecognized flow', () {
    test('ignores a message from a sender outside the selected bank', () {
      final engine = _engine();

      final outcome = engine.process(_message('FAKE-CIB', 'تم خصم 75 جنيه'));

      expect(outcome.status, SmsProcessingStatus.ignoredSender);
      expect(engine.unrecognizedMessages, isEmpty);
    });

    test('matches sender exactly after trim and case folding', () {
      final engine = _engine();

      final outcome = engine.process(_message('  cib  ', 'تم خصم 75 جنيه'));

      expect(outcome.status, SmsProcessingStatus.parsed);
      expect(outcome.result!.amount, 75);
    });

    test(
      'saves unmatched bank messages as unrecognized and requests notice',
      () {
        final engine = _engine();
        final message = _message('CIB', 'صيغة جديدة لعملية بقيمة 75 جنيه');

        final outcome = engine.process(message);

        expect(outcome.status, SmsProcessingStatus.unrecognized);
        expect(outcome.shouldNotify, isTrue);
        expect(engine.unrecognizedMessages, hasLength(1));
        expect(engine.unrecognizedMessages.single.message, same(message));
      },
    );

    test('ignores the same sender and exact text within two minutes', () {
      final engine = _engine();
      final firstAt = DateTime(2026, 11, 6, 12);

      expect(
        engine
            .process(_message('CIB', 'تم خصم 75 جنيه', receivedAt: firstAt))
            .status,
        SmsProcessingStatus.parsed,
      );
      expect(
        engine
            .process(
              _message(
                'cib',
                'تم خصم 75 جنيه',
                receivedAt: firstAt.add(const Duration(minutes: 2)),
              ),
            )
            .status,
        SmsProcessingStatus.duplicate,
      );
      expect(
        engine
            .process(
              _message(
                'CIB',
                'تم خصم 75 جنيه',
                receivedAt: firstAt.add(const Duration(minutes: 2, seconds: 1)),
              ),
            )
            .status,
        SmsProcessingStatus.parsed,
      );
    });

    test('does not dedupe by amount', () {
      final engine = _engine();
      final firstAt = DateTime(2026, 11, 6, 12);

      final first = engine.process(
        _message('CIB', 'تم خصم 75 جنيه', receivedAt: firstAt),
      );
      final second = engine.process(
        _message(
          'CIB',
          'تم خصم 80 جنيه',
          receivedAt: firstAt.add(const Duration(seconds: 30)),
        ),
      );

      expect(first.status, SmsProcessingStatus.parsed);
      expect(second.status, SmsProcessingStatus.parsed);
    });

    test('does not dedupe by merchant', () {
      const sample = 'تم خصم 100 جنيه لدى STAR';
      final set = SmsBankTemplateSet.compile(
        bankId: 'bank',
        senderIds: const ['CIB'],
        templates: [
          _template(
            id: 'merchant-purchase',
            sample: sample,
            direction: 'خصم',
            amountText: '100',
            type: SmsTemplateType.debit,
            placeholders: [
              _placeholder(sample, SmsPlaceholderKind.merchant, 'STAR'),
            ],
          ),
        ],
      );
      final engine = SmsTemplateEngine(banks: [set!]);
      final firstAt = DateTime(2026, 11, 6, 12);

      final first = engine.process(
        _message('CIB', 'تم خصم 75 جنيه لدى STAR', receivedAt: firstAt),
      );
      final second = engine.process(
        _message(
          'CIB',
          'تم خصم 75 جنيه لدى MARKET',
          receivedAt: firstAt.add(const Duration(seconds: 30)),
        ),
      );

      expect(first.status, SmsProcessingStatus.parsed);
      expect(second.status, SmsProcessingStatus.parsed);
    });

    test('does not guess OTP or advertising messages', () {
      final engine = _engine();

      final otp = engine.process(_message('CIB', 'Your OTP is 123456'));
      final advert = engine.process(
        _message('CIB', 'خصم 20% على المشتريات اليوم'),
      );

      expect(otp.status, SmsProcessingStatus.unrecognized);
      expect(advert.status, SmsProcessingStatus.unrecognized);
      expect(engine.unrecognizedMessages, hasLength(2));
    });

    test('sends missing or malformed matched amounts to unrecognized', () {
      final engine = _engine();

      final malformed = engine.process(_message('CIB', 'تم خصم 1.2.3 جنيه'));
      final missing = engine.process(_message('CIB', 'تم خصم جنيه'));

      expect(malformed.status, SmsProcessingStatus.unrecognized);
      expect(missing.status, SmsProcessingStatus.unrecognized);
      expect(engine.unrecognizedMessages, hasLength(2));
    });

    test(
      'joins multipart messages in zero-based index order before parsing',
      () {
        final engine = _engine();
        final at = DateTime(2026, 11, 6, 12);

        final lastFirst = engine.process(
          _message(
            'CIB',
            'جنيه',
            receivedAt: at.add(const Duration(seconds: 2)),
            multipartId: 'long-1',
            partIndex: 2,
            partCount: 3,
          ),
        );
        final first = engine.process(
          _message(
            'CIB',
            'تم خص',
            receivedAt: at,
            multipartId: 'long-1',
            partIndex: 0,
            partCount: 3,
          ),
        );
        final complete = engine.process(
          _message(
            'CIB',
            'م 75 ',
            receivedAt: at.add(const Duration(seconds: 1)),
            multipartId: 'long-1',
            partIndex: 1,
            partCount: 3,
          ),
        );

        expect(lastFirst.status, SmsProcessingStatus.waitingForParts);
        expect(first.status, SmsProcessingStatus.waitingForParts);
        expect(complete.status, SmsProcessingStatus.parsed);
        expect(complete.result!.amount, 75);
      },
    );

    test('does not parse or save incomplete multipart messages', () {
      final engine = _engine();

      final outcome = engine.process(
        _message(
          'CIB',
          'تم خصم ',
          multipartId: 'long-2',
          partIndex: 0,
          partCount: 2,
        ),
      );

      expect(outcome.status, SmsProcessingStatus.waitingForParts);
      expect(engine.unrecognizedMessages, isEmpty);
    });
  });
}

SmsTemplateEngine _engine() {
  final set = SmsBankTemplateSet.compile(
    bankId: 'bank',
    senderIds: const ['CIB'],
    templates: [
      _simpleTemplate(
        id: 'debit',
        sample: 'تم خصم 100 جنيه',
        direction: 'خصم',
        amountText: '100',
        type: SmsTemplateType.debit,
      ),
    ],
  );
  return SmsTemplateEngine(banks: [set!]);
}

SmsEnvelope _message(
  String sender,
  String body, {
  DateTime? receivedAt,
  String? multipartId,
  int? partIndex,
  int? partCount,
}) {
  return SmsEnvelope(
    sender: sender,
    body: body,
    receivedAt: receivedAt ?? DateTime(2026, 11, 6, 12),
    multipartId: multipartId,
    partIndex: partIndex,
    partCount: partCount,
  );
}

SmsTemplate _simpleTemplate({
  required String id,
  String bankId = 'bank',
  required String sample,
  required String direction,
  required String amountText,
  required SmsTemplateType type,
}) {
  return _template(
    id: id,
    bankId: bankId,
    sample: sample,
    direction: direction,
    amountText: amountText,
    type: type,
  );
}

SmsTemplate _template({
  required String id,
  String bankId = 'bank',
  required String sample,
  required String direction,
  required String amountText,
  required SmsTemplateType type,
  List<SmsPlaceholder> placeholders = const [],
}) {
  return SmsTemplate(
    id: id,
    bankId: bankId,
    sampleText: sample,
    type: type,
    amount: _placeholder(sample, SmsPlaceholderKind.amount, amountText),
    directionRanges: [_rangeOf(sample, direction)],
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
  return SmsTextRange(start: start, end: start + selected.length);
}
