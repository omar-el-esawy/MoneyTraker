import 'package:flutter_test/flutter_test.dart';
import 'package:money_traker/sms/template_engine/sms_merchant_extractor.dart';

void main() {
  group('SmsMerchantExtractor', () {
    test('extracts a one-word merchant between fixed anchors', () {
      final extractor = SmsMerchantExtractor(prefix: 'لدى', suffix: 'بتاريخ');

      expect(
        extractor.extract('تم خصم 150 جنيه لدى NETFLIX بتاريخ 01/11/2026'),
        'NETFLIX',
      );
    });

    test('extracts many words with digits and symbols', () {
      final extractor = SmsMerchantExtractor(prefix: 'at', suffix: 'on');

      expect(
        extractor.extract(
          'Card purchase at STAR-MARKET 24 * A&B.CO on 01/11/2026',
        ),
        'STAR-MARKET 24 * A&B.CO',
      );
    });

    test('accepts a line break inside the merchant and trims whitespace', () {
      final extractor = SmsMerchantExtractor(prefix: 'لدى', suffix: 'بتاريخ');

      expect(
        extractor.extract('شراء لدى   SEOUDI\nSILVER STAR   بتاريخ 01/11/2026'),
        'SEOUDI SILVER STAR',
      );
    });

    test(
      'ignores a delimiter inside merchant unless the expected tail matches',
      () {
        final extractor = SmsMerchantExtractor(
          prefix: 'لدى',
          suffix: 'بتاريخ',
          expectedAfterSuffix: RegExp(r'\d{1,2}[/-]\d{1,2}[/-]\d{2,4}(?:\s|$)'),
        );

        expect(
          extractor.extract(
            'شراء لدى متجر بتاريخ فرع النيل بتاريخ 01/11/2026 الساعة 10:30',
          ),
          'متجر بتاريخ فرع النيل',
        );
      },
    );

    test('uses the last qualifying delimiter when several qualify', () {
      final extractor = SmsMerchantExtractor(
        prefix: 'لدى',
        suffix: 'بتاريخ',
        expectedAfterSuffix: RegExp(r'\d{1,2}[/-]\d{1,2}[/-]\d{2,4}(?:\s|$)'),
      );

      expect(
        extractor.extract(
          'شراء لدى معرض بتاريخ 01/01/2020 فرع بتاريخ 01/11/2026',
        ),
        'معرض بتاريخ 01/01/2020 فرع',
      );
    });

    test('returns null when anchors or merchant are missing', () {
      final extractor = SmsMerchantExtractor(prefix: 'لدى', suffix: 'بتاريخ');

      expect(extractor.extract('تم خصم 150 جنيه'), isNull);
      expect(extractor.extract('تم خصم 150 لدى بتاريخ 01/11/2026'), isNull);
    });
  });
}
