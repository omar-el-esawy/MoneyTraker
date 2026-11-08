import 'package:money_traker/sms/template_engine/sms_normalizer.dart';

class SmsMerchantExtractor {
  final String prefix;
  final String suffix;
  final RegExp? expectedAfterSuffix;

  SmsMerchantExtractor({
    required String prefix,
    required String suffix,
    this.expectedAfterSuffix,
  }) : prefix = SmsNormalizer.normalize(prefix).text,
       suffix = SmsNormalizer.normalize(suffix).text;

  String? extract(String message) {
    if (prefix.isEmpty || suffix.isEmpty) return null;
    final body = SmsNormalizer.normalize(message).text;
    final lowerBody = body.toLowerCase();
    final lowerPrefix = prefix.toLowerCase();
    final lowerSuffix = suffix.toLowerCase();
    final prefixIndex = lowerBody.indexOf(lowerPrefix);
    if (prefixIndex < 0) return null;

    final merchantStart = prefixIndex + prefix.length;
    final validSuffixes = <int>[];
    var suffixIndex = lowerBody.indexOf(lowerSuffix, merchantStart);
    while (suffixIndex >= 0) {
      final tail = body.substring(suffixIndex + suffix.length).trimLeft();
      if (expectedAfterSuffix == null ||
          expectedAfterSuffix!.matchAsPrefix(tail) != null) {
        validSuffixes.add(suffixIndex);
      }
      suffixIndex = lowerBody.indexOf(lowerSuffix, suffixIndex + 1);
    }
    if (validSuffixes.isEmpty) return null;

    final merchant = body.substring(merchantStart, validSuffixes.last).trim();
    return merchant.isEmpty ? null : merchant;
  }
}
