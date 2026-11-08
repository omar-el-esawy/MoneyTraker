import 'package:flutter/material.dart';

import 'package:money_traker/constants/app_constants.dart';
import 'package:money_traker/sms/template_engine/sms_amount_parser.dart';
import 'package:money_traker/sms/template_engine/sms_normalizer.dart';
import 'package:money_traker/sms/template_engine/sms_template_engine.dart';
import 'package:money_traker/sms/template_engine/template_models.dart';
import 'package:money_traker/sms/template_engine/web_demo_data.dart';

class WebSmsTemplateDemoPage extends StatelessWidget {
  const WebSmsTemplateDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final banks = WebSmsDemoCatalog.build();
    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      appBar: AppBar(title: const Text('Bank messages')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _DemoBanner(),
          const SizedBox(height: 20),
          Text('Banks', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final bank in banks)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppConstants.primarySurface,
                    child: Icon(
                      Icons.account_balance_outlined,
                      color: AppConstants.primaryColor,
                    ),
                  ),
                  title: Text(bank.name),
                  subtitle: Text(
                    '${bank.messages.length} fake messages · '
                    '${bank.templates.length} templates · '
                    '${bank.senders.join(', ')}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _WebSmsBankDemoPage(bank: bank),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD98A)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.science_outlined, color: Color(0xFF9A6700)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Web demo only\n'
              'All SMS, balances, and results on this page are fake and kept '
              'in memory. Nothing is read from or written to the app database.',
            ),
          ),
        ],
      ),
    );
  }
}

class _WebSmsBankDemoPage extends StatefulWidget {
  final WebSmsDemoBank bank;

  const _WebSmsBankDemoPage({required this.bank});

  @override
  State<_WebSmsBankDemoPage> createState() => _WebSmsBankDemoPageState();
}

class _WebSmsBankDemoPageState extends State<_WebSmsBankDemoPage> {
  late final TextEditingController _message;
  late List<SmsTemplate> _templates;
  late SmsBankTemplateSet _templateSet;
  SmsParsedResult? _customResult;
  bool _customTested = false;

  @override
  void initState() {
    super.initState();
    _message = TextEditingController(text: widget.bank.messages.first.body);
    _templates = [...widget.bank.templates];
    _templateSet = widget.bank.templateSet;
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _testCustomMessage() {
    setState(() {
      _customResult = _templateSet.match(_message.text);
      _customTested = true;
    });
  }

  Future<void> _teachTemplate() async {
    final sample = await _pickSample();
    if (!mounted || sample == null) return;
    final type = await _pickType();
    if (!mounted || type == null) return;
    final amount = await _pickAmount(sample);
    if (!mounted || amount == null) return;
    final direction = await _pickDirection(sample, amount);
    if (!mounted || direction == null || direction.isEmpty) return;
    final changing = await _pickChangingParts(sample, amount, direction);
    if (!mounted || changing == null) return;

    final id = 'web-${widget.bank.id}-${DateTime.now().microsecondsSinceEpoch}';
    final template = SmsTemplate(
      id: id,
      bankId: widget.bank.id,
      sampleText: sample,
      type: type,
      amount: SmsPlaceholder(kind: SmsPlaceholderKind.amount, range: amount),
      directionRanges: direction,
      placeholders: [
        for (final range in changing)
          SmsPlaceholder(kind: SmsPlaceholderKind.other, range: range),
      ],
    );
    final next = SmsBankTemplateSet.compile(
      bankId: widget.bank.id,
      senderIds: widget.bank.senders,
      templates: [..._templates, template],
    );
    if (next == null) {
      _snack('Template is invalid. Check overlapping selections.');
      return;
    }
    final preview = next.preview(id, widget.bank.messages);
    setState(() {
      _templates = [..._templates, template];
      _templateSet = next;
      _message.text = sample;
      _customResult = next.match(sample);
      _customTested = true;
    });
    _snack(
      'Template added in memory · matched ${preview.matched} of ${preview.total}',
    );
  }

  Future<String?> _pickSample() {
    final options = <String>[
      if (_message.text.trim().isNotEmpty) _message.text.trim(),
      ...widget.bank.messages.map((message) => message.body),
    ].toSet().toList();
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const ListTile(
              title: Text('1. Choose a real sample message'),
              subtitle: Text('This web list contains fake messages only.'),
            ),
            for (final body in options)
              ListTile(
                title: Text(body, maxLines: 4, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(context, body),
              ),
          ],
        ),
      ),
    );
  }

  Future<SmsTemplateType?> _pickType() {
    return showModalBottomSheet<SmsTemplateType>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('2. Is this debit or credit?')),
            ListTile(
              leading: const Icon(
                Icons.arrow_upward,
                color: AppConstants.errorColor,
              ),
              title: const Text('Debit — money went out'),
              onTap: () => Navigator.pop(context, SmsTemplateType.debit),
            ),
            ListTile(
              leading: const Icon(
                Icons.arrow_downward,
                color: AppConstants.primaryColor,
              ),
              title: const Text('Credit — money came in'),
              onTap: () => Navigator.pop(context, SmsTemplateType.credit),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<SmsTextRange?> _pickAmount(String sample) {
    final normalized = SmsNormalizer.normalize(sample);
    final candidates = <({SmsTextRange range, String raw, double value})>[];
    for (final match in RegExp(
      r'\d+(?:[.,]\d+)*',
    ).allMatches(normalized.text)) {
      final source = normalized.originalRange(match.start, match.end);
      final raw = sample.substring(source.start, source.end);
      final value = SmsAmountParser.parse(raw);
      if (value == null) continue;
      candidates.add((
        range: SmsTextRange(start: source.start, end: source.end),
        raw: raw,
        value: value,
      ));
    }
    return showModalBottomSheet<SmsTextRange>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const ListTile(
              title: Text('3. Tap the transaction amount'),
              subtitle: Text('Confirm the parsed value before continuing.'),
            ),
            if (candidates.isEmpty)
              const ListTile(title: Text('No valid amount found.')),
            for (final item in candidates)
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: Text(item.raw),
                subtitle: Text('Parsed value: ${item.value}'),
                onTap: () => Navigator.pop(context, item.range),
              ),
          ],
        ),
      ),
    );
  }

  Future<List<SmsTextRange>?> _pickDirection(
    String sample,
    SmsTextRange amount,
  ) {
    final tokens = _tokens(sample);
    final selected = <int>{};
    return showModalBottomSheet<List<SmsTextRange>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('4. Tap the direction word(s)'),
                  subtitle: Text(
                    'Choose one or several words. Their order is preserved.',
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < tokens.length; i++)
                      if (!_overlaps(tokens[i].range, amount))
                        FilterChip(
                          label: Text(tokens[i].text),
                          selected: selected.contains(i),
                          onSelected: (value) => setSheetState(() {
                            value ? selected.add(i) : selected.remove(i);
                          }),
                        ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.pop(context, [
                            for (final index in selected.toList()..sort())
                              tokens[index].range,
                          ]),
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<List<SmsTextRange>?> _pickChangingParts(
    String sample,
    SmsTextRange amount,
    List<SmsTextRange> direction,
  ) {
    final tokens = _tokens(sample);
    final selected = <int>{};
    return showModalBottomSheet<List<SmsTextRange>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('5. Mark every other changing part'),
                  subtitle: Text(
                    'Select merchant, date, time, balance, card digits, and '
                    'reference values. Leave constant words unselected.',
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < tokens.length; i++)
                      if (!_overlaps(tokens[i].range, amount) &&
                          !direction.any(
                            (range) => _overlaps(tokens[i].range, range),
                          ))
                        FilterChip(
                          label: Text(tokens[i].text),
                          selected: selected.contains(i),
                          onSelected: (value) => setSheetState(() {
                            value ? selected.add(i) : selected.remove(i);
                          }),
                        ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, const []),
                        child: const Text('No other changes'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: selected.isEmpty
                            ? null
                            : () => Navigator.pop(
                                context,
                                _mergeSelectedTokens(tokens, selected),
                              ),
                        child: const Text('Save template'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final bank = widget.bank;
    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      appBar: AppBar(title: Text(bank.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _DemoBanner(),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final sender in bank.senders)
                Chip(
                  avatar: const Icon(Icons.sms_outlined, size: 18),
                  label: Text(sender),
                ),
              Chip(
                avatar: const Icon(Icons.description_outlined, size: 18),
                label: Text('${_templates.length} templates'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _teachTemplate,
              icon: const Icon(Icons.add),
              label: const Text('Teach new template'),
            ),
          ),
          const SizedBox(height: 20),
          Text('Try a message', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _message,
            minLines: 3,
            maxLines: 7,
            decoration: const InputDecoration(
              hintText: 'Paste or edit a fake bank SMS...',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _testCustomMessage,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Test template'),
          ),
          if (_customTested) ...[
            const SizedBox(height: 10),
            _ResultPanel(result: _customResult),
          ],
          const SizedBox(height: 28),
          Text('Fake inbox', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final message in bank.messages)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _MessageCard(
                message: message,
                result: _templateSet.match(message.body),
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageToken {
  final String text;
  final SmsTextRange range;

  const _MessageToken({required this.text, required this.range});
}

List<_MessageToken> _tokens(String text) {
  return [
    for (final match in RegExp(r'\S+').allMatches(text))
      _MessageToken(
        text: match.group(0)!,
        range: SmsTextRange(start: match.start, end: match.end),
      ),
  ];
}

bool _overlaps(SmsTextRange a, SmsTextRange b) {
  return a.start < b.end && b.start < a.end;
}

List<SmsTextRange> _mergeSelectedTokens(
  List<_MessageToken> tokens,
  Set<int> selected,
) {
  final indices = selected.toList()..sort();
  final ranges = <SmsTextRange>[];
  for (final index in indices) {
    final token = tokens[index];
    if (ranges.isNotEmpty && index == indices[indices.indexOf(index) - 1] + 1) {
      final previous = ranges.removeLast();
      ranges.add(SmsTextRange(start: previous.start, end: token.range.end));
    } else {
      ranges.add(token.range);
    }
  }
  return ranges;
}

class _MessageCard extends StatelessWidget {
  final SmsEnvelope message;
  final SmsParsedResult? result;

  const _MessageCard({required this.message, required this.result});

  @override
  Widget build(BuildContext context) {
    final parsed = result != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    message.sender,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                _StatusBadge(parsed: parsed),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(message.body),
            const SizedBox(height: 12),
            if (parsed)
              _ParsedSummary(result: result!)
            else
              const _UnrecognizedText(),
          ],
        ),
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  final SmsParsedResult? result;

  const _ResultPanel({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: result == null
            ? const Color(0xFFFFEEEE)
            : AppConstants.primarySurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: result == null
          ? const _UnrecognizedText()
          : _ParsedSummary(result: result!),
    );
  }
}

class _ParsedSummary extends StatelessWidget {
  final SmsParsedResult result;

  const _ParsedSummary({required this.result});

  @override
  Widget build(BuildContext context) {
    final direction = result.type == SmsTemplateType.debit ? 'Debit' : 'Credit';
    return Text(
      [
        '$direction · Amount: ${result.amount.toStringAsFixed(2)}',
        if (result.merchant != null) 'Merchant: ${result.merchant}',
        if (result.balance != null)
          'Balance: ${result.balance!.toStringAsFixed(2)}',
        'Template: ${result.templateId}',
      ].join('\n'),
      style: const TextStyle(color: AppConstants.textSecondary, height: 1.45),
    );
  }
}

class _UnrecognizedText extends StatelessWidget {
  const _UnrecognizedText();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Unrecognized — no value was guessed or recorded.',
      style: TextStyle(color: AppConstants.errorColor),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool parsed;

  const _StatusBadge({required this.parsed});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: parsed ? AppConstants.primarySurface : const Color(0xFFFFEEEE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        parsed ? 'Parsed' : 'Unrecognized',
        style: TextStyle(
          color: parsed ? AppConstants.primaryColor : AppConstants.errorColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
