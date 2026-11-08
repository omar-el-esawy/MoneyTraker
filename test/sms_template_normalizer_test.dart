import 'package:flutter_test/flutter_test.dart';
import 'package:money_traker/sms/template_engine/sms_normalizer.dart';

void main() {
  group('SmsNormalizer', () {
    test('normalizes Arabic, Persian, and mixed digits to ASCII', () {
      expect(SmsNormalizer.normalize('١٥۰٠ 12٣').text, '1500 123');
    });

    test('collapses spaces, tabs, and line breaks and trims the message', () {
      final normalized = SmsNormalizer.normalize(
        '  تم\t  خصم\n١٥٠٠\r\nمن الحساب  ',
      );

      expect(normalized.text, 'تم خصم 1500 من الحساب');
    });

    test('normalizes Arabic punctuation and numeric separators', () {
      final normalized = SmsNormalizer.normalize(
        'تم، الخصم؛ متاح؟ ١\u066C٥٠٠\u066B٢٥',
      );

      expect(normalized.text, 'تم, الخصم; متاح? 1,500.25');
    });

    test('keeps mixed Arabic and English text and meaningful symbols', () {
      final normalized = SmsNormalizer.normalize(
        'Purchase من STAR-MARKET & CO. بمبلغ \$150',
      );

      expect(normalized.text, 'Purchase من STAR-MARKET & CO. بمبلغ \$150');
    });

    test('maps a marked original range into normalized text', () {
      const message = 'تم خصم   ١٥٠٠\nجنيه';
      final amountStart = message.indexOf('١٥٠٠');
      final normalized = SmsNormalizer.normalize(message);

      final range = normalized.normalizedRange(
        amountStart,
        amountStart + '١٥٠٠'.length,
      );

      expect(range, isNotNull);
      expect(normalized.text.substring(range!.start, range.end), '1500');
    });

    test('maps normalized extraction back to the exact original text', () {
      const message = 'لدى STAR\t MARKET\n& CO. بتاريخ 01/11/2026';
      final normalized = SmsNormalizer.normalize(message);
      final merchantStart = normalized.text.indexOf('STAR');
      final merchantEnd = normalized.text.indexOf(' بتاريخ');

      final range = normalized.originalRange(merchantStart, merchantEnd);

      expect(message.substring(range.start, range.end), 'STAR\t MARKET\n& CO.');
    });
  });
}
