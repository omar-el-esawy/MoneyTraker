import 'package:flutter_test/flutter_test.dart';
import 'package:money_traker/sms/template_engine/sms_direction_pattern.dart';
import 'package:money_traker/sms/template_engine/template_models.dart';

void main() {
  group('SmsDirectionPattern', () {
    test('matches one selected direction word', () {
      const sample = 'تم خصم مبلغ 150 جنيه من حسابك';
      final pattern = SmsDirectionPattern.compile(sample, [
        _rangeOf(sample, 'خصم'),
      ]);

      expect(pattern, isNotNull);
      expect(pattern!.matches('تم خصم مبلغ 900 جنيه من حسابك'), isTrue);
      expect(pattern.matches('تم إيداع مبلغ 900 جنيه في حسابك'), isFalse);
    });

    test('requires non-adjacent selected words in order', () {
      const sample = 'تم تحويل مبلغ 500 من حسابك إلى محمد';
      final pattern = SmsDirectionPattern.compile(sample, [
        _rangeOf(sample, 'تم تحويل'),
        _rangeOf(sample, 'إلى'),
      ]);

      expect(
        pattern!.matches('تم تحويل فوري بقيمة 1200 من بطاقتك إلى أحمد'),
        isTrue,
      );
      expect(pattern.matches('إلى أحمد تم تحويل مبلغ 1200'), isFalse);
      expect(pattern.matches('تم تحويل مبلغ 1200 من حسابك'), isFalse);
    });

    test('normalizes whitespace and punctuation before matching', () {
      const sample = 'تم، تحويل المبلغ إلى المستفيد';
      final pattern = SmsDirectionPattern.compile(sample, [
        _rangeOf(sample, 'تم، تحويل'),
        _rangeOf(sample, 'إلى'),
      ]);

      expect(pattern!.matches('تم,   تحويل\n500 EGP إلى\tالمستفيد'), isTrue);
    });

    test('matches English direction anchors without case sensitivity', () {
      const sample = 'Your card was DEBITED by EGP 150';
      final pattern = SmsDirectionPattern.compile(sample, [
        _rangeOf(sample, 'card'),
        _rangeOf(sample, 'DEBITED'),
      ]);

      expect(
        pattern!.matches('YOUR CARD ending 1234 was debited by EGP900'),
        isTrue,
      );
    });

    test('does not match a selected word inside a longer word', () {
      const sample = 'تم خصم مبلغ 150';
      final pattern = SmsDirectionPattern.compile(sample, [
        _rangeOf(sample, 'خصم'),
      ]);

      expect(pattern!.matches('خصومات بقيمة 150 جنيه'), isFalse);
    });

    test('rejects empty, overlapping, or out-of-message ranges', () {
      const sample = 'تم خصم 150';

      expect(SmsDirectionPattern.compile(sample, const []), isNull);
      expect(
        SmsDirectionPattern.compile(sample, const [
          SmsTextRange(start: 0, end: 5),
          SmsTextRange(start: 3, end: 7),
        ]),
        isNull,
      );
      expect(
        SmsDirectionPattern.compile(sample, const [
          SmsTextRange(start: 20, end: 25),
        ]),
        isNull,
      );
    });
  });
}

SmsTextRange _rangeOf(String text, String selected) {
  final start = text.indexOf(selected);
  if (start < 0) throw ArgumentError.value(selected, 'selected');
  return SmsTextRange(start: start, end: start + selected.length);
}
