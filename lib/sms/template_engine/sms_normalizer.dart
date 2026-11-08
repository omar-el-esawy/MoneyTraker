class NormalizedSms {
  final String original;
  final String text;
  final List<int> _sourceStarts;
  final List<int> _sourceEnds;

  const NormalizedSms._({
    required this.original,
    required this.text,
    required List<int> sourceStarts,
    required List<int> sourceEnds,
  }) : _sourceStarts = sourceStarts,
       _sourceEnds = sourceEnds;

  ({int start, int end}) originalRange(int normalizedStart, int normalizedEnd) {
    if (normalizedStart < 0 ||
        normalizedEnd <= normalizedStart ||
        normalizedEnd > text.length) {
      throw RangeError.range(normalizedEnd, normalizedStart + 1, text.length);
    }
    return (
      start: _sourceStarts[normalizedStart],
      end: _sourceEnds[normalizedEnd - 1],
    );
  }

  ({int start, int end})? normalizedRange(int originalStart, int originalEnd) {
    if (originalStart < 0 ||
        originalEnd <= originalStart ||
        originalEnd > original.length) {
      throw RangeError.range(originalEnd, originalStart + 1, original.length);
    }

    int? start;
    int? end;
    for (var i = 0; i < text.length; i++) {
      final overlaps =
          _sourceEnds[i] > originalStart && _sourceStarts[i] < originalEnd;
      if (!overlaps) continue;
      start ??= i;
      end = i + 1;
    }
    if (start == null || end == null) return null;
    return (start: start, end: end);
  }
}

class SmsNormalizer {
  const SmsNormalizer._();

  static final _whitespace = RegExp(r'\s', unicode: true);

  static NormalizedSms normalize(String input) {
    final output = StringBuffer();
    final sourceStarts = <int>[];
    final sourceEnds = <int>[];
    var sourceOffset = 0;
    int? whitespaceStart;
    var whitespaceEnd = 0;

    void appendMapped(String value, int start, int end) {
      output.write(value);
      for (var i = 0; i < value.length; i++) {
        sourceStarts.add(start);
        sourceEnds.add(end);
      }
    }

    for (final rune in input.runes) {
      final glyph = String.fromCharCode(rune);
      final glyphEnd = sourceOffset + glyph.length;
      if (_whitespace.hasMatch(glyph)) {
        if (output.isNotEmpty) {
          whitespaceStart ??= sourceOffset;
          whitespaceEnd = glyphEnd;
        }
        sourceOffset = glyphEnd;
        continue;
      }

      if (whitespaceStart != null) {
        appendMapped(' ', whitespaceStart, whitespaceEnd);
        whitespaceStart = null;
      }
      appendMapped(_normalizeGlyph(glyph), sourceOffset, glyphEnd);
      sourceOffset = glyphEnd;
    }

    return NormalizedSms._(
      original: input,
      text: output.toString(),
      sourceStarts: List.unmodifiable(sourceStarts),
      sourceEnds: List.unmodifiable(sourceEnds),
    );
  }

  static String _normalizeGlyph(String glyph) {
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
    final arabicIndex = arabicDigits.indexOf(glyph);
    if (arabicIndex >= 0) return '$arabicIndex';
    final persianIndex = persianDigits.indexOf(glyph);
    if (persianIndex >= 0) return '$persianIndex';

    return switch (glyph) {
      '\u060C' || '\u066C' => ',',
      '\u061B' => ';',
      '\u061F' => '?',
      '\u066B' => '.',
      _ => glyph,
    };
  }
}
