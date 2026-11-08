import 'package:flutter_test/flutter_test.dart';
import 'package:money_traker/sms/template_engine/sms_placeholder_patterns.dart';
import 'package:money_traker/sms/template_engine/template_models.dart';

void main() {
  group('SmsPlaceholderPatterns', () {
    test('accepts realistic date values with normalized digits', () {
      expect(
        SmsPlaceholderPatterns.matches(SmsPlaceholderKind.date, '٠١/١١/٢٠٢٦'),
        isTrue,
      );
      expect(
        SmsPlaceholderPatterns.matches(SmsPlaceholderKind.date, '2026-11-01'),
        isTrue,
      );
      expect(
        SmsPlaceholderPatterns.matches(SmsPlaceholderKind.date, 'tomorrow'),
        isFalse,
      );
    });

    test('accepts time values', () {
      expect(
        SmsPlaceholderPatterns.matches(SmsPlaceholderKind.time, '10:30 PM'),
        isTrue,
      );
      expect(
        SmsPlaceholderPatterns.matches(SmsPlaceholderKind.time, '٠٩.٤٥'),
        isTrue,
      );
    });

    test('validates balance with the strict amount parser', () {
      expect(
        SmsPlaceholderPatterns.matches(
          SmsPlaceholderKind.balance,
          '١\u066C٥٠٠\u066B٢٥',
        ),
        isTrue,
      );
      expect(
        SmsPlaceholderPatterns.matches(SmsPlaceholderKind.balance, '12,34,500'),
        isFalse,
      );
    });

    test('accepts changing card digits and reference values', () {
      expect(
        SmsPlaceholderPatterns.matches(SmsPlaceholderKind.cardDigits, '٤٥٢١'),
        isTrue,
      );
      expect(
        SmsPlaceholderPatterns.matches(
          SmsPlaceholderKind.reference,
          'IPN-AB_120/5',
        ),
        isTrue,
      );
    });

    test('merchant and other placeholders require a non-empty value', () {
      expect(
        SmsPlaceholderPatterns.matches(
          SmsPlaceholderKind.merchant,
          'STAR\nMARKET & CO.',
        ),
        isTrue,
      );
      expect(
        SmsPlaceholderPatterns.matches(SmsPlaceholderKind.other, '   '),
        isFalse,
      );
    });
  });
}
