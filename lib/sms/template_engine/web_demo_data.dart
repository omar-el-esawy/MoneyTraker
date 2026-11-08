import 'package:money_traker/sms/template_engine/sms_template_engine.dart';
import 'package:money_traker/sms/template_engine/template_models.dart';

class WebSmsDemoBank {
  final String id;
  final String name;
  final List<String> senders;
  final List<SmsTemplate> templates;
  final SmsBankTemplateSet templateSet;
  final List<SmsEnvelope> messages;

  const WebSmsDemoBank({
    required this.id,
    required this.name,
    required this.senders,
    required this.templates,
    required this.templateSet,
    required this.messages,
  });
}

class WebSmsDemoCatalog {
  const WebSmsDemoCatalog._();

  static List<WebSmsDemoBank> build() {
    return [_cib(), _qnb()];
  }

  static WebSmsDemoBank _cib() {
    const purchaseSample =
        'تم خصم 1,500.00 جنيه من بطاقة 4521 لدى STAR MARKET '
        'بتاريخ 01/11/2026 الرصيد 9,000.00';
    const depositSample = 'تم إيداع 500 جنيه في حسابك الرصيد 9500';
    final templates = [
      _template(
        id: 'cib-purchase',
        bankId: 'cib-demo',
        sample: purchaseSample,
        type: SmsTemplateType.debit,
        amount: '1,500.00',
        direction: ['خصم'],
        placeholders: [
          _placeholder(purchaseSample, SmsPlaceholderKind.cardDigits, '4521'),
          _placeholder(
            purchaseSample,
            SmsPlaceholderKind.merchant,
            'STAR MARKET',
          ),
          _placeholder(purchaseSample, SmsPlaceholderKind.date, '01/11/2026'),
          _placeholder(purchaseSample, SmsPlaceholderKind.balance, '9,000.00'),
        ],
      ),
      _template(
        id: 'cib-deposit',
        bankId: 'cib-demo',
        sample: depositSample,
        type: SmsTemplateType.credit,
        amount: '500',
        direction: ['إيداع'],
        placeholders: [
          _placeholder(depositSample, SmsPlaceholderKind.balance, '9500'),
        ],
      ),
    ];
    const senders = ['CIB'];
    return WebSmsDemoBank(
      id: 'cib-demo',
      name: 'CIB — بيانات تجريبية',
      senders: senders,
      templates: templates,
      templateSet: SmsBankTemplateSet.compile(
        bankId: 'cib-demo',
        senderIds: senders,
        templates: templates,
      )!,
      messages: [
        _message(
          sender: 'CIB',
          body:
              'تم خصم ٢\u066C٧٥٠\u066B٥٠ جنيه من بطاقة 9988 لدى '
              'SEOUDI SILVER-STAR بتاريخ 03/11/2026 الرصيد '
              '١٢\u066C٠٠٠\u066B٢٥',
          minute: 1,
        ),
        _message(
          sender: 'CIB',
          body: 'تم إيداع 1200 جنيه في حسابك الرصيد 13200.25',
          minute: 5,
        ),
        _message(
          sender: 'CIB',
          body: 'Your OTP is 482193. Do not share it.',
          minute: 8,
        ),
        _message(
          sender: 'CIB',
          body: 'صيغة جديدة لعملية شراء بقيمة 300 جنيه',
          minute: 11,
        ),
      ],
    );
  }

  static WebSmsDemoBank _qnb() {
    const purchaseSample =
        'Card 1234 debited EGP150.00 at AMAZON EG on 01/11/2026. '
        'Balance EGP9000';
    const refundSample =
        'Your account was credited LE 75.50 refund from AMAZON EG';
    final templates = [
      _template(
        id: 'qnb-card-purchase',
        bankId: 'qnb-demo',
        sample: purchaseSample,
        type: SmsTemplateType.debit,
        amount: '150.00',
        direction: ['Card', 'debited'],
        placeholders: [
          _placeholder(purchaseSample, SmsPlaceholderKind.cardDigits, '1234'),
          _placeholder(
            purchaseSample,
            SmsPlaceholderKind.merchant,
            'AMAZON EG',
          ),
          _placeholder(purchaseSample, SmsPlaceholderKind.date, '01/11/2026'),
          _placeholder(purchaseSample, SmsPlaceholderKind.balance, '9000'),
        ],
      ),
      _template(
        id: 'qnb-refund',
        bankId: 'qnb-demo',
        sample: refundSample,
        type: SmsTemplateType.credit,
        amount: '75.50',
        direction: ['credited', 'refund'],
        placeholders: [
          _placeholder(refundSample, SmsPlaceholderKind.merchant, 'AMAZON EG'),
        ],
      ),
    ];
    const senders = ['QNB'];
    return WebSmsDemoBank(
      id: 'qnb-demo',
      name: 'QNB — Fake data',
      senders: senders,
      templates: templates,
      templateSet: SmsBankTemplateSet.compile(
        bankId: 'qnb-demo',
        senderIds: senders,
        templates: templates,
      )!,
      messages: [
        _message(
          sender: 'QNB',
          body:
              'Card 7788 debited EGP1,250.00 at IKEA CAIRO on '
              '04/11/2026. Balance EGP7750',
          minute: 2,
        ),
        _message(
          sender: 'QNB',
          body: 'Your account was credited LE 90 refund from UBER * TRIP 24',
          minute: 7,
        ),
        _message(
          sender: 'QNB',
          body: 'Enjoy 20% off this weekend using your QNB card',
          minute: 12,
        ),
      ],
    );
  }

  static SmsEnvelope _message({
    required String sender,
    required String body,
    required int minute,
  }) {
    return SmsEnvelope(
      sender: sender,
      body: body,
      receivedAt: DateTime(2026, 11, 6, 14, minute),
    );
  }

  static SmsTemplate _template({
    required String id,
    required String bankId,
    required String sample,
    required SmsTemplateType type,
    required String amount,
    required List<String> direction,
    List<SmsPlaceholder> placeholders = const [],
  }) {
    return SmsTemplate(
      id: id,
      bankId: bankId,
      sampleText: sample,
      type: type,
      amount: _placeholder(sample, SmsPlaceholderKind.amount, amount),
      directionRanges: [for (final word in direction) _range(sample, word)],
      placeholders: placeholders,
    );
  }

  static SmsPlaceholder _placeholder(
    String text,
    SmsPlaceholderKind kind,
    String selected,
  ) {
    return SmsPlaceholder(kind: kind, range: _range(text, selected));
  }

  static SmsTextRange _range(String text, String selected) {
    final start = text.indexOf(selected);
    if (start < 0) throw StateError('Missing demo selection: $selected');
    return SmsTextRange(start: start, end: start + selected.length);
  }
}
