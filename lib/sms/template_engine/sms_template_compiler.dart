import 'package:money_traker/sms/template_engine/sms_amount_parser.dart';
import 'package:money_traker/sms/template_engine/sms_direction_pattern.dart';
import 'package:money_traker/sms/template_engine/sms_normalizer.dart';
import 'package:money_traker/sms/template_engine/sms_placeholder_patterns.dart';
import 'package:money_traker/sms/template_engine/template_models.dart';

class CompiledSmsTemplate {
  final SmsTemplate template;
  final int specificity;
  final RegExp _matcher;
  final SmsDirectionPattern _direction;
  final List<SmsPlaceholderKind> _groups;

  const CompiledSmsTemplate._({
    required this.template,
    required this.specificity,
    required RegExp matcher,
    required SmsDirectionPattern direction,
    required List<SmsPlaceholderKind> groups,
  }) : _matcher = matcher,
       _direction = direction,
       _groups = groups;

  SmsParsedResult? match(String message) {
    if (!_direction.matches(message)) return null;
    final body = SmsNormalizer.normalize(message).text;
    final match = _matcher.firstMatch(body);
    if (match == null) return null;

    double? amount;
    double? balance;
    String? merchant;
    for (var i = 0; i < _groups.length; i++) {
      final raw = match.group(i + 1);
      if (raw == null) return null;
      switch (_groups[i]) {
        case SmsPlaceholderKind.amount:
          amount = SmsAmountParser.parse(raw);
          if (amount == null) return null;
        case SmsPlaceholderKind.balance:
          balance = SmsAmountParser.parse(raw);
          if (balance == null) return null;
        case SmsPlaceholderKind.merchant:
          final value = raw.trim();
          if (value.isEmpty) return null;
          merchant = value;
        case SmsPlaceholderKind.date:
        case SmsPlaceholderKind.time:
        case SmsPlaceholderKind.cardDigits:
        case SmsPlaceholderKind.reference:
        case SmsPlaceholderKind.other:
          break;
      }
    }
    if (template.amount.kind == SmsPlaceholderKind.balance) {
      if (balance == null) return null;
      return SmsParsedResult(
        templateId: template.id,
        amount: balance,
        type: template.type,
        merchant: merchant,
        balance: balance,
        usesBalance: true,
      );
    }
    if (amount == null) return null;

    return SmsParsedResult(
      templateId: template.id,
      amount: amount,
      type: template.type,
      merchant: merchant,
      balance: balance,
    );
  }
}

class SmsTemplateCompiler {
  const SmsTemplateCompiler._();

  static CompiledSmsTemplate? compile(SmsTemplate template) {
    if (template.id.trim().isEmpty ||
        template.bankId.trim().isEmpty ||
        template.sampleText.trim().isEmpty ||
        (template.amount.kind != SmsPlaceholderKind.amount &&
            template.amount.kind != SmsPlaceholderKind.balance)) {
      return null;
    }

    final allPlaceholders = [
      template.amount,
      ..._mergeAdjacentGenericPlaceholders(
        template.sampleText,
        template.placeholders,
      ),
    ];
    final amountCount = allPlaceholders
        .where((item) => item.kind == SmsPlaceholderKind.amount)
        .length;
    final balanceCount = allPlaceholders
        .where((item) => item.kind == SmsPlaceholderKind.balance)
        .length;
    final moneyIsBalance = template.amount.kind == SmsPlaceholderKind.balance;
    if (moneyIsBalance) {
      if (balanceCount != 1 || amountCount != 0) return null;
    } else if (amountCount != 1 || balanceCount > 1) {
      return null;
    }
    if (allPlaceholders
            .where((item) => item.kind == SmsPlaceholderKind.merchant)
            .length >
        1) {
      return null;
    }
    if (!_validPlaceholders(template.sampleText, allPlaceholders)) return null;
    if (!_validDirections(template)) return null;

    final normalized = SmsNormalizer.normalize(template.sampleText);
    final slots = <_NormalizedSlot>[];
    for (final placeholder in allPlaceholders) {
      final range = normalized.normalizedRange(
        placeholder.range.start,
        placeholder.range.end,
      );
      if (range == null) return null;
      final sampleValue = normalized.text.substring(range.start, range.end);
      if (!SmsPlaceholderPatterns.matches(placeholder.kind, sampleValue)) {
        return null;
      }
      slots.add(
        _NormalizedSlot(
          kind: placeholder.kind,
          start: range.start,
          end: range.end,
        ),
      );
    }
    slots.sort((a, b) => a.start.compareTo(b.start));

    final pattern = StringBuffer('^');
    final groups = <SmsPlaceholderKind>[];
    final fixedText = StringBuffer();
    var cursor = 0;
    for (final slot in slots) {
      final fixed = normalized.text.substring(cursor, slot.start);
      pattern.write(RegExp.escape(fixed));
      fixedText.write(fixed);
      final source = slot.kind == SmsPlaceholderKind.merchant
          ? r'.+'
          : SmsPlaceholderPatterns.sourceFor(slot.kind);
      pattern.write('($source)');
      groups.add(slot.kind);
      cursor = slot.end;
    }
    final tail = normalized.text.substring(cursor);
    pattern
      ..write(RegExp.escape(tail))
      ..write(r'$');
    fixedText.write(tail);

    final direction = template.directionRanges.isEmpty
        ? const SmsDirectionPattern.any()
        : SmsDirectionPattern.compile(
            template.sampleText,
            template.directionRanges,
          );
    if (direction == null) return null;

    return CompiledSmsTemplate._(
      template: template,
      specificity: fixedText
          .toString()
          .replaceAll(RegExp(r'\s+', unicode: true), '')
          .length,
      matcher: RegExp(pattern.toString(), caseSensitive: false, unicode: true),
      direction: direction,
      groups: List.unmodifiable(groups),
    );
  }

  static bool _validPlaceholders(
    String sample,
    List<SmsPlaceholder> placeholders,
  ) {
    if (placeholders.isEmpty) return false;
    final ordered = [...placeholders]
      ..sort((a, b) => a.range.start.compareTo(b.range.start));
    for (var i = 0; i < ordered.length; i++) {
      final range = ordered[i].range;
      if (!range.isValid || range.end > sample.length) return false;
      if (i > 0 && ordered[i - 1].range.end > range.start) return false;
    }
    return true;
  }

  static List<SmsPlaceholder> _mergeAdjacentGenericPlaceholders(
    String sample,
    List<SmsPlaceholder> placeholders,
  ) {
    final ordered = [...placeholders]
      ..sort((a, b) => a.range.start.compareTo(b.range.start));
    final merged = <SmsPlaceholder>[];
    for (final placeholder in ordered) {
      if (merged.isNotEmpty) {
        final previous = merged.last;
        final canMerge =
            previous.kind == SmsPlaceholderKind.other &&
            placeholder.kind == SmsPlaceholderKind.other &&
            previous.range.end >= 0 &&
            previous.range.end <= placeholder.range.start &&
            placeholder.range.start >= 0 &&
            placeholder.range.start <= sample.length &&
            sample
                .substring(previous.range.end, placeholder.range.start)
                .trim()
                .isEmpty;
        if (canMerge) {
          merged[merged.length - 1] = SmsPlaceholder(
            kind: SmsPlaceholderKind.other,
            range: SmsTextRange(
              start: previous.range.start,
              end: placeholder.range.end,
            ),
          );
          continue;
        }
      }
      merged.add(placeholder);
    }
    return merged;
  }

  static bool _validDirections(SmsTemplate template) {
    for (final direction in template.directionRanges) {
      if (!direction.isValid || direction.end > template.sampleText.length) {
        return false;
      }
      final overlapsAmount =
          direction.start < template.amount.range.end &&
          template.amount.range.start < direction.end;
      if (overlapsAmount) return false;
    }
    return true;
  }
}

class _NormalizedSlot {
  final SmsPlaceholderKind kind;
  final int start;
  final int end;

  const _NormalizedSlot({
    required this.kind,
    required this.start,
    required this.end,
  });
}
