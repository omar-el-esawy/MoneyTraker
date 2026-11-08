import 'package:money_traker/sms/template_engine/sms_normalizer.dart';
import 'package:money_traker/sms/template_engine/template_models.dart';

class SmsDirectionPattern {
  final List<String> anchors;

  const SmsDirectionPattern._(this.anchors);

  static SmsDirectionPattern? compile(
    String sample,
    List<SmsTextRange> ranges,
  ) {
    if (ranges.isEmpty || ranges.any((range) => !range.isValid)) return null;
    final ordered = [...ranges]..sort((a, b) => a.start.compareTo(b.start));
    for (var i = 1; i < ordered.length; i++) {
      if (ordered[i - 1].end > ordered[i].start) return null;
    }

    final normalized = SmsNormalizer.normalize(sample);
    final anchors = <String>[];
    for (final range in ordered) {
      if (range.end > sample.length) return null;
      final normalizedRange = normalized.normalizedRange(
        range.start,
        range.end,
      );
      if (normalizedRange == null) return null;
      final anchor = normalized.text
          .substring(normalizedRange.start, normalizedRange.end)
          .trim();
      if (anchor.isEmpty) return null;
      anchors.add(anchor);
    }
    return SmsDirectionPattern._(List.unmodifiable(anchors));
  }

  bool matches(String message) {
    final body = SmsNormalizer.normalize(message).text;
    final lowerBody = body.toLowerCase();
    var cursor = 0;
    for (final anchor in anchors) {
      final lowerAnchor = anchor.toLowerCase();
      var found = lowerBody.indexOf(lowerAnchor, cursor);
      while (found >= 0 && !_hasWordBoundaries(body, found, anchor.length)) {
        found = lowerBody.indexOf(lowerAnchor, found + 1);
      }
      if (found < 0) return false;
      cursor = found + anchor.length;
    }
    return true;
  }

  static bool _hasWordBoundaries(String body, int start, int length) {
    final end = start + length;
    final first = body.substring(start, start + 1);
    final last = body.substring(end - 1, end);
    if (_isWordCharacter(first) &&
        start > 0 &&
        _isWordCharacter(body.substring(start - 1, start))) {
      return false;
    }
    if (_isWordCharacter(last) &&
        end < body.length &&
        _isWordCharacter(body.substring(end, end + 1))) {
      return false;
    }
    return true;
  }

  static bool _isWordCharacter(String character) {
    return RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(character);
  }
}
