import 'package:money_traker/sms/template_engine/sms_amount_parser.dart';
import 'package:money_traker/sms/template_engine/sms_normalizer.dart';
import 'package:money_traker/sms/template_engine/template_models.dart';

class SmsPlaceholderPatterns {
  const SmsPlaceholderPatterns._();

  static const numberSource = r'\d+(?:[.,]\d+)*';
  static const dateSource = r'\d{1,4}[/-]\d{1,2}[/-]\d{1,4}';
  static const timeSource = r'\d{1,2}[:.]\d{2}(?:\s*[AaPp][Mm])?';
  static const cardDigitsSource = r'\d+';
  static const referenceSource = r'[\p{L}\p{N}._/-]+';

  static String sourceFor(SmsPlaceholderKind kind) {
    return switch (kind) {
      SmsPlaceholderKind.amount || SmsPlaceholderKind.balance => numberSource,
      SmsPlaceholderKind.date => dateSource,
      SmsPlaceholderKind.time => timeSource,
      SmsPlaceholderKind.cardDigits => cardDigitsSource,
      SmsPlaceholderKind.reference => referenceSource,
      SmsPlaceholderKind.merchant || SmsPlaceholderKind.other => r'.+?',
    };
  }

  static bool matches(SmsPlaceholderKind kind, String raw) {
    if ((kind == SmsPlaceholderKind.amount ||
            kind == SmsPlaceholderKind.balance) &&
        SmsAmountParser.parse(raw) == null) {
      return false;
    }
    final value = SmsNormalizer.normalize(raw).text;
    if (value.isEmpty) return false;
    return RegExp(
      '^${sourceFor(kind)}\$',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(value);
  }
}
