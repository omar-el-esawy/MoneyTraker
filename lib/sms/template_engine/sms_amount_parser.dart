import 'package:money_traker/sms/template_engine/sms_normalizer.dart';

class SmsAmountParser {
  const SmsAmountParser._();

  static final _number = RegExp(r'\d+(?:[.,]\d+)*');

  static double? parse(String raw) {
    final normalized = SmsNormalizer.normalize(raw).text;
    final matches = _number.allMatches(normalized).toList();
    if (matches.length != 1) return null;

    final numeric = matches.single.group(0)!;
    final canonical = _canonicalize(numeric);
    if (canonical == null) return null;

    final value = double.tryParse(canonical);
    if (value == null || !value.isFinite || value <= 0) return null;
    return value;
  }

  static String? _canonicalize(String value) {
    final commas = ','.allMatches(value).length;
    final dots = '.'.allMatches(value).length;
    if (commas == 0 && dots == 0) return value;

    if (commas > 0 && dots > 0) {
      final decimal = value.lastIndexOf(',') > value.lastIndexOf('.')
          ? ','
          : '.';
      final grouping = decimal == ',' ? '.' : ',';
      return _withDecimalAndGrouping(value, decimal, grouping);
    }

    final separator = commas > 0 ? ',' : '.';
    final parts = value.split(separator);
    if (parts.any((part) => part.isEmpty)) return null;

    if (parts.length == 2) {
      final fractionLength = parts.last.length;
      if (fractionLength <= 2) return '${parts.first}.${parts.last}';
      if (fractionLength == 3 && _validGroupedParts(parts)) {
        return parts.join();
      }
      return null;
    }

    if (_validGroupedParts(parts)) return parts.join();

    final fraction = parts.last;
    if (fraction.length > 2) return null;
    final integerParts = parts.sublist(0, parts.length - 1);
    if (!_validGroupedParts(integerParts)) return null;
    return '${integerParts.join()}.$fraction';
  }

  static String? _withDecimalAndGrouping(
    String value,
    String decimal,
    String grouping,
  ) {
    if (decimal.allMatches(value).length != 1) return null;
    final decimalIndex = value.lastIndexOf(decimal);
    final integer = value.substring(0, decimalIndex);
    final fraction = value.substring(decimalIndex + 1);
    if (fraction.isEmpty ||
        fraction.length > 2 ||
        fraction.contains(grouping)) {
      return null;
    }

    final integerParts = integer.split(grouping);
    if (!_validGroupedParts(integerParts)) return null;
    return '${integerParts.join()}.$fraction';
  }

  static bool _validGroupedParts(List<String> parts) {
    if (parts.isEmpty ||
        parts.first.isEmpty ||
        parts.any((part) => part.isEmpty)) {
      return false;
    }
    if (parts.length == 1) return true;
    if (parts.first.length > 3) return false;
    return parts.skip(1).every((part) => part.length == 3);
  }
}
