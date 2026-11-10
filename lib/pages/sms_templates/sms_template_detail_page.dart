import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:money_traker/constants/app_constants.dart';
import 'package:money_traker/sms/template_engine/sms_template_compiler.dart';
import 'package:money_traker/sms/template_engine/sms_template_mobile_store.dart';
import 'package:money_traker/sms/template_engine/template_models.dart';

class SmsTemplateDetailPage extends StatelessWidget {
  final SmsTemplate template;
  final List<SmsTemplate> templates;
  final List<SmsTemplateStoredMessage> messages;

  const SmsTemplateDetailPage({
    super.key,
    required this.template,
    required this.templates,
    required this.messages,
  });

  @override
  Widget build(BuildContext context) {
    final compiled = SmsTemplateCompiler.compile(template);
    final compiledTemplates = {
      for (final item in templates) item.id: SmsTemplateCompiler.compile(item),
    };
    final orderedMessages = [...messages]
      ..sort((a, b) => b.date.compareTo(a.date));
    final results = [
      for (final message in orderedMessages)
        (
          message: message,
          result: compiled?.match(message.body),
          otherMatches: [
            for (final item in templates)
              if (item.id != template.id &&
                  compiledTemplates[item.id]?.match(message.body) != null)
                item,
          ],
        ),
    ];
    final matchedCount = results.where((item) => item.result != null).length;
    final debit = template.type == SmsTemplateType.debit;

    return Scaffold(
      appBar: AppBar(title: Text(debit ? 'Debit rule' : 'Credit rule')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _SectionTitle('RULE SHAPE'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Fixed text must stay the same. Colored text shows what '
                    'the rule reads from each message.',
                    style: const TextStyle(color: AppConstants.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppConstants.backgroundColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text.rich(
                      TextSpan(
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.65,
                          color: AppConstants.textPrimary,
                        ),
                        children: _ruleSpans(template),
                      ),
                      textDirection: _messageDirection(template.sampleText),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Legend(
                        label: template.amount.kind == SmsPlaceholderKind.balance
                            ? 'Balance'
                            : 'Amount',
                        color: Color(0xFFDBEAFE),
                      ),
                      _Legend(label: 'Direction', color: Color(0xFFDCFCE7)),
                      _Legend(label: 'Changing', color: Color(0xFFFFEDD5)),
                      _Legend(
                        label: 'Direction + changing',
                        color: Color(0xFFF3E8FF),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const _SectionTitle('MESSAGE RESULTS'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    compiled == null
                        ? Icons.error_outline
                        : Icons.rule_outlined,
                    color: compiled == null
                        ? AppConstants.errorColor
                        : AppConstants.primaryColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      compiled == null
                          ? 'This rule is invalid and cannot match messages.'
                          : '$matchedCount of ${results.length} messages match this rule.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (results.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No messages have been read for this bank yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            for (final item in results)
              _MessageResultCard(
                message: item.message,
                result: item.result,
                debit: debit,
                otherMatches: item.otherMatches,
                ruleLabel: (item) => _ruleLabel(item, templates),
                onOpenRule: (item) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SmsTemplateDetailPage(
                        template: item,
                        templates: templates,
                        messages: messages,
                      ),
                    ),
                  );
                },
              ),
        ],
      ),
    );
  }
}

class _MessageResultCard extends StatelessWidget {
  final SmsTemplateStoredMessage message;
  final SmsParsedResult? result;
  final bool debit;
  final List<SmsTemplate> otherMatches;
  final String Function(SmsTemplate template) ruleLabel;
  final ValueChanged<SmsTemplate> onOpenRule;

  const _MessageResultCard({
    required this.message,
    required this.result,
    required this.debit,
    required this.otherMatches,
    required this.ruleLabel,
    required this.onOpenRule,
  });

  @override
  Widget build(BuildContext context) {
    final matched = result != null;
    final color = matched
        ? (debit ? AppConstants.errorColor : const Color(0xFF15803D))
        : AppConstants.textTertiary;
    final signedAmount = result == null
        ? null
        : result!.usesBalance
        ? 'balance ${result!.balance?.toStringAsFixed(2) ?? result!.amount.toStringAsFixed(2)}'
        : '${debit ? '−' : '+'}${result!.amount.toStringAsFixed(2)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                message.body,
                textDirection: _messageDirection(message.body),
                style: const TextStyle(height: 1.45),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    matched
                        ? Icons.check_circle_outline
                        : Icons.cancel_outlined,
                    size: 18,
                    color: color,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      matched
                          ? 'Matched • ${debit ? 'Debit' : 'Credit'} $signedAmount'
                          : 'Does not match this rule',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    DateFormat('d MMM, HH:mm').format(message.date),
                    style: const TextStyle(
                      color: AppConstants.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              if (otherMatches.isNotEmpty) ...[
                const SizedBox(height: 7),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.call_split_outlined,
                      size: 17,
                      color: AppConstants.primaryColor,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      matched ? 'Also matches:' : 'Matches another rule:',
                      style: const TextStyle(
                        color: AppConstants.primaryColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: [
                          for (final template in otherMatches)
                            InkWell(
                              onTap: () => onOpenRule(template),
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 3,
                                ),
                                child: Text(
                                  ruleLabel(template),
                                  style: const TextStyle(
                                    color: AppConstants.primaryColor,
                                    decoration: TextDecoration.underline,
                                    decorationColor: AppConstants.primaryColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 9),
      child: Text(
        text,
        style: const TextStyle(
          color: AppConstants.textSecondary,
          fontWeight: FontWeight.w700,
          letterSpacing: .7,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final String label;
  final Color color;

  const _Legend({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF1F2937),
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

List<TextSpan> _ruleSpans(SmsTemplate template) {
  final text = template.sampleText;
  final boundaries = <int>{0, text.length};
  final ranges = [
    template.amount.range,
    ...template.directionRanges,
    ...template.placeholders.map((item) => item.range),
  ];
  for (final range in ranges) {
    if (range.start >= 0 && range.start <= text.length) {
      boundaries.add(range.start);
    }
    if (range.end >= 0 && range.end <= text.length) boundaries.add(range.end);
  }
  final points = boundaries.toList()..sort();
  final spans = <TextSpan>[];
  for (var index = 0; index < points.length - 1; index++) {
    final start = points[index];
    final end = points[index + 1];
    if (end <= start) continue;
    final amount = _overlaps(start, end, template.amount.range);
    final direction = template.directionRanges.any(
      (range) => _overlaps(start, end, range),
    );
    final changing = template.placeholders.any(
      (item) => _overlaps(start, end, item.range),
    );
    final background = switch ((amount, direction, changing)) {
      (true, _, _) => const Color(0xFFDBEAFE),
      (false, true, true) => const Color(0xFFF3E8FF),
      (false, true, false) => const Color(0xFFDCFCE7),
      (false, false, true) => const Color(0xFFFFEDD5),
      _ => Colors.transparent,
    };
    spans.add(
      TextSpan(
        text: text.substring(start, end),
        style: TextStyle(
          backgroundColor: background,
          fontWeight: background == Colors.transparent
              ? FontWeight.normal
              : FontWeight.w700,
        ),
      ),
    );
  }
  return spans;
}

bool _overlaps(int start, int end, SmsTextRange range) {
  return start < range.end && range.start < end;
}

TextDirection _messageDirection(String text) {
  final firstStrong = RegExp(
    r'[A-Za-z\u0590-\u08FF\uFB1D-\uFDFD\uFE70-\uFEFC]',
  ).firstMatch(text);
  if (firstStrong == null) return TextDirection.ltr;
  return RegExp(
        r'[\u0590-\u08FF\uFB1D-\uFDFD\uFE70-\uFEFC]',
      ).hasMatch(firstStrong.group(0)!)
      ? TextDirection.rtl
      : TextDirection.ltr;
}

String _ruleLabel(SmsTemplate template, List<SmsTemplate> templates) {
  final sameType = [
    for (final item in templates)
      if (item.type == template.type) item,
  ];
  final type = template.type == SmsTemplateType.debit ? 'Debit' : 'Credit';
  if (sameType.length <= 1) return '$type rule';
  final index = sameType.indexWhere((item) => item.id == template.id);
  return '$type rule ${index < 0 ? '?' : index + 1}';
}
