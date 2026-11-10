import 'package:money_traker/sms/sms_models.dart';

class SmsRuleEngine {
  static final _numberPattern = RegExp(
    r'[0-9\u0660-\u0669\u06F0-\u06F9]+(?:[.,\u066B\u066C][0-9\u0660-\u0669\u06F0-\u06F9]+)*',
  );

  static List<SmsNumberSpan> findNumbers(String body) {
    return _numberPattern.allMatches(body).map((match) {
      return SmsNumberSpan(
        start: match.start,
        end: match.end,
        text: match.group(0)!,
      );
    }).toList();
  }

  static List<SmsToken> tokenize(String body) {
    return RegExp(r'\S+').allMatches(body).map((match) {
      final text = match.group(0)!;
      return SmsToken(
        start: match.start,
        end: match.end,
        text: text,
        isNumber: singleNumberIn(text) != null,
      );
    }).toList();
  }

  /// The number inside [text] when letters or symbols are glued to exactly one number.
  /// `500EGP` and `EGP1,250.50` qualify. A date like `15/10/2026` does not.
  static SmsNumberSpan? singleNumberIn(String text, {int offset = 0}) {
    final matches = _numberPattern.allMatches(text).toList();
    if (matches.length != 1) return null;
    final match = matches.single;
    return SmsNumberSpan(
      start: offset + match.start,
      end: offset + match.end,
      text: match.group(0)!,
    );
  }

  static String normalizeWord(String raw) {
    return raw.replaceAll(
      RegExp(r'''^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$''', unicode: true),
      '',
    );
  }

  /// Longer text wins, then the earliest match in the message.
  static String detectType(String body, List<SmsTypeWord> words) {
    SmsTypeWord? best;
    var bestPos = 1 << 30;
    var bestLength = 0;
    for (final word in words) {
      final hit = locateRule(body, word.pattern, word.word);
      if (hit == null) continue;
      final length = word.pattern?.words.length ?? word.word.trim().length;
      final better =
          length > bestLength || (length == bestLength && hit.start < bestPos);
      if (!better) continue;
      best = word;
      bestPos = hit.start;
      bestLength = length;
    }
    return best?.typeHint ?? '';
  }

  static int firstIndexOfWord(String body, String word) {
    return locateText(body, word)?.start ?? -1;
  }

  /// Finds [text] anywhere in [body]. Capital letters do not matter.
  static ({int start, int end})? locateText(String body, String text) {
    final query = text.trim();
    if (query.isEmpty) return null;
    final match = RegExp(
      RegExp.escape(query),
      caseSensitive: false,
    ).firstMatch(body);
    if (match == null) return null;
    return (start: match.start, end: match.end);
  }

  static int firstExactWordIndex(String body, String word) {
    return firstIndexOfWord(body, word);
  }

  /// Longer text wins, then the earliest match in the message.
  static List<SmsCategoryRule> rankCategoryRules(
    String body,
    List<SmsCategoryRule> rules,
  ) {
    final hits = <({SmsCategoryRule rule, int pos, int length})>[];
    for (final rule in rules) {
      final hit = locateRule(body, rule.pattern, rule.word);
      if (hit == null) continue;
      hits.add((
        rule: rule,
        pos: hit.start,
        length: rule.pattern?.words.length ?? rule.word.trim().length,
      ));
    }

    hits.sort((a, b) {
      final byLength = b.length.compareTo(a.length);
      if (byLength != 0) return byLength;
      return a.pos.compareTo(b.pos);
    });
    return [for (final hit in hits) hit.rule];
  }

  static ({int start, int end})? locateRule(
    String body,
    SmsRulePattern? pattern,
    String legacyWord,
  ) {
    if (pattern == null) return locateText(body, legacyWord);
    if (!pattern.isValid) return null;
    final tokens = tokenize(body);
    final selected = [...pattern.words]
      ..sort((a, b) => a.index.compareTo(b.index));
    if (selected.isEmpty || tokens.isEmpty) return null;
    final first = selected.first.word;
    for (var i = 0; i < tokens.length; i++) {
      if (!_sameToken(tokens[i].text, first)) continue;
      final end = _matchSelectedFrom(tokens, selected, i);
      if (end != null) {
        return (start: tokens[i].start, end: tokens[end].end);
      }
    }
    return null;
  }

  static int? _matchSelectedFrom(
    List<SmsToken> tokens,
    List<SmsPatternWord> selected,
    int start,
  ) {
    var cursor = start;
    for (var i = 1; i < selected.length; i++) {
      final wanted = selected[i].word;
      final adjacent = selected[i].index == selected[i - 1].index + 1;
      if (adjacent) {
        cursor += 1;
        if (cursor >= tokens.length || !_sameToken(tokens[cursor].text, wanted)) {
          return null;
        }
        continue;
      }
      var found = -1;
      for (var j = cursor + 1; j < tokens.length; j++) {
        if (_sameToken(tokens[j].text, wanted)) {
          found = j;
          break;
        }
      }
      if (found < 0) return null;
      cursor = found;
    }
    return cursor;
  }

  static bool _sameToken(String actual, String expected) {
    return normalizeWord(actual).toLowerCase() ==
        expected.trim().toLowerCase();
  }

  static SmsRuleContext contextFor(
    String body,
    SmsNumberSpan span,
    List<SmsNumberSpan> all,
  ) {
    SmsNumberSpan? previous;
    SmsNumberSpan? next;
    for (final item in all) {
      if (item.end <= span.start) previous = item;
      if (item.start >= span.end) {
        next = item;
        break;
      }
    }

    final before = body.substring(previous?.end ?? 0, span.start);
    final after = body.substring(span.end, next?.start ?? body.length);
    return SmsRuleContext(
      prefix: _generalizeNumbers(_lastWords(before, 6)),
      suffix: _generalizeNumbers(_firstWords(after, 6)),
    );
  }

  static SmsReading parse(
    String body,
    List<SmsReadRule> rules, {
    List<SmsTypeWord> typeWords = const [],
  }) {
    double? amount;
    double? balance;
    String? account;
    SmsReadRule? matchedAmountRule;

    final rankedRules = [...rules]
      ..sort((a, b) {
        final bySpecificity = _ruleSpecificity(
          b,
        ).compareTo(_ruleSpecificity(a));
        if (bySpecificity != 0) return bySpecificity;
        return b.createdAt.compareTo(a.createdAt);
      });

    for (final rule in rankedRules) {
      final raw = extract(body, rule);
      if (raw == null) continue;
      switch (rule.field) {
        case SmsField.amount:
          final value = parseAmount(raw);
          if (value == null || amount != null) break;
          amount = value;
          matchedAmountRule = rule;
        case SmsField.balance:
          final value = parseAmount(raw);
          if (value == null || balance != null) break;
          balance = value;
        case SmsField.account:
          if (account != null) break;
          account = normalizeDigits(raw);
      }
    }

    var typeHint = detectType(body, typeWords);
    if (typeHint.isEmpty && matchedAmountRule != null) {
      typeHint = matchedAmountRule.typeHint;
    }

    return SmsReading(
      amount: amount,
      typeHint: typeHint,
      balance: balance,
      account: account,
    );
  }

  static String? extract(String body, SmsReadRule rule) {
    final prefix = rule.prefix.trim();
    final suffix = rule.suffix.trim();
    if (prefix.isEmpty && suffix.isEmpty) return null;
    if ((prefix.isEmpty || suffix.isEmpty) &&
        _letterCount('$prefix$suffix') < 3) {
      return null;
    }
    final source = switch ((prefix.isEmpty, suffix.isEmpty)) {
      (true, false) => '($_capture)\\s*${_flex(suffix)}',
      (false, true) => '${_flex(prefix)}\\s*($_capture)',
      _ => '${_flex(prefix)}\\s*($_capture)\\s*${_flex(suffix)}',
    };
    final pattern = RegExp(source, caseSensitive: false);
    return pattern.firstMatch(body)?.group(1);
  }

  static double? parseAmount(String raw) {
    var text = normalizeDigits(
      raw,
    ).replaceAll('\u066B', '.').replaceAll('\u066C', ',');
    final embedded = _numberPattern.allMatches(text).toList();
    if (embedded.length == 1) text = embedded.single.group(0)!;
    final hasComma = text.contains(',');
    final hasDot = text.contains('.');
    if (hasComma && hasDot) {
      if (text.lastIndexOf(',') > text.lastIndexOf('.')) {
        text = text.replaceAll('.', '').replaceAll(',', '.');
      } else {
        text = text.replaceAll(',', '');
      }
    } else if (hasComma) {
      final pieces = text.split(',');
      final thousands =
          pieces.length > 1 && pieces.skip(1).every((p) => p.length == 3);
      text = thousands ? text.replaceAll(',', '') : text.replaceAll(',', '.');
    } else if (hasDot) {
      final pieces = text.split('.');
      if (pieces.length > 2 &&
          pieces.skip(1).every((piece) => piece.length == 3)) {
        text = text.replaceAll('.', '');
      }
    }
    return double.tryParse(text);
  }

  static String normalizeDigits(String input) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final buffer = StringBuffer();
    for (final char in input.runes) {
      final glyph = String.fromCharCode(char);
      final arabicIndex = arabic.indexOf(glyph);
      if (arabicIndex >= 0) {
        buffer.write(arabicIndex);
        continue;
      }
      final persianIndex = persian.indexOf(glyph);
      if (persianIndex >= 0) {
        buffer.write(persianIndex);
        continue;
      }
      buffer.write(glyph);
    }
    return buffer.toString();
  }

  static BankConfig? matchBank(String sender, List<BankConfig> banks) {
    final haystack = sender.toLowerCase();
    BankConfig? best;
    var bestLength = 0;
    for (final bank in banks) {
      if (!bank.enabled) continue;
      for (final senderName in bank.senders) {
        final needle = senderName.trim().toLowerCase();
        if (needle.isEmpty || !haystack.contains(needle)) continue;
        if (needle.length > bestLength) {
          best = bank;
          bestLength = needle.length;
        }
      }
    }
    return best;
  }

  static const _numberSlot = '#NUM#';
  static const _capture =
      r'[0-9\u0660-\u0669\u06F0-\u06F9]+(?:[.,\u066B\u066C][0-9\u0660-\u0669\u06F0-\u06F9]+)*';

  static String _generalizeNumbers(String text) {
    return text.replaceAll(_numberPattern, _numberSlot);
  }

  static String _flex(String text) {
    final parts = text.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    return parts
        .map((part) {
          if (part == _numberSlot) return _capture;
          if (part.contains(_numberSlot)) {
            return part.split(_numberSlot).map(RegExp.escape).join(_capture);
          }
          return RegExp.escape(part);
        })
        .join(r'\s+');
  }

  static String _lastWords(String text, int max) {
    final parts = text
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length <= max) return parts.join(' ');
    return parts.sublist(parts.length - max).join(' ');
  }

  static String _firstWords(String text, int max) {
    final parts = text
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length <= max) return parts.join(' ');
    return parts.sublist(0, max).join(' ');
  }

  static String ruleSetId({
    required List<SmsReadRule> rules,
    required List<SmsTypeWord> typeWords,
  }) {
    final parts = [
      for (final rule in rules.where((item) => item.field == SmsField.amount))
        '${rule.prefix}|${rule.suffix}|${rule.typeHint}',
      for (final word in typeWords)
        '${word.pattern?.key ?? word.word}:${word.typeHint}',
    ];
    return parts.join(';');
  }

  static int _letterCount(String text) {
    return RegExp(
      r'\p{L}',
      unicode: true,
    ).allMatches(text.replaceAll(_numberSlot, '')).length;
  }

  static int amountRuleLetterCount(SmsReadRule rule) {
    return _letterCount('${rule.prefix}${rule.suffix}');
  }

  static int _ruleSpecificity(SmsReadRule rule) {
    final bothSides =
        rule.prefix.trim().isNotEmpty && rule.suffix.trim().isNotEmpty;
    return amountRuleLetterCount(rule) * 2 + (bothSides ? 1 : 0);
  }

  static int fixedLetterCount({
    required List<SmsReadRule> rules,
    required List<SmsTypeWord> typeWords,
  }) {
    final amountRules = rules.where((rule) => rule.field == SmsField.amount);
    if (amountRules.isNotEmpty) {
      return amountRules
          .map(amountRuleLetterCount)
          .reduce((a, b) => a < b ? a : b);
    }
    final buffer = StringBuffer();
    for (final word in typeWords) {
      buffer.write(word.pattern?.display ?? word.word);
    }
    return _letterCount(buffer.toString());
  }

  static bool senderBelongs(String sender, List<String> senders) {
    return matchBank(sender, [
          BankConfig(id: 'x', nameEn: 'x', nameAr: 'x', senders: senders),
        ]) !=
        null;
  }

  static SmsRuleTestReport test({
    required List<SmsCopy> corpus,
    required List<SmsReadRule> rules,
    required List<SmsTypeWord> typeWords,
    required List<String> senders,
  }) {
    final hits = <SmsRuleTestHit>[];
    var unmatched = 0;
    for (final copy in corpus) {
      final reading = parse(copy.body, rules, typeWords: typeWords);
      if (!reading.isComplete) {
        unmatched++;
        continue;
      }
      hits.add(
        SmsRuleTestHit(
          smsId: copy.smsId,
          sender: copy.sender,
          body: copy.body,
          date: copy.date,
          reading: reading,
          senderBelongsToBank: senderBelongs(copy.sender, senders),
        ),
      );
    }
    final bankHits = hits.where((hit) => hit.senderBelongsToBank).toList();
    final foreign = hits.length - bankHits.length;
    final bankTotal = senders.any((item) => item.trim().isNotEmpty)
        ? corpus.where((copy) => senderBelongs(copy.sender, senders)).length
        : 0;
    final letters = fixedLetterCount(rules: rules, typeWords: typeWords);
    final hasSender = senders.any((item) => item.trim().isNotEmpty);
    return SmsRuleTestReport(
      total: hasSender ? bankTotal : corpus.length,
      matched: bankHits.length,
      unmatched: unmatched,
      foreignMatches: foreign,
      hasSender: hasSender,
      fixedLetterCount: letters,
      tooGeneric: false,
      reasons: const [],
      hits: hits,
    );
  }
}
