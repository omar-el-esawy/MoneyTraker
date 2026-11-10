import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:money_traker/constants/app_constants.dart';
import 'package:money_traker/data/database_helper.dart';
import 'package:money_traker/pages/sms/category_rule_sheet.dart';
import 'package:money_traker/services/sms_template_sync_service.dart';
import 'package:money_traker/sms/sms_models.dart';
import 'package:money_traker/sms/sms_rule_engine.dart';
import 'package:money_traker/store/money_storage.dart';
import 'package:money_traker/sms/template_engine/sms_amount_parser.dart';
import 'package:money_traker/sms/template_engine/sms_template_compiler.dart';
import 'package:money_traker/sms/template_engine/sms_template_mobile_store.dart';
import 'package:money_traker/sms/template_engine/template_models.dart';

TextDirection _messageDirection(String text) {
  final firstStrong = RegExp(
    r'[A-Za-z\u0590-\u08FF\uFB1D-\uFDFD\uFE70-\uFEFC]',
  ).firstMatch(text);
  if (firstStrong == null) return TextDirection.ltr;

  final character = firstStrong.group(0)!;
  return RegExp(
        r'[\u0590-\u08FF\uFB1D-\uFDFD\uFE70-\uFEFC]',
      ).hasMatch(character)
      ? TextDirection.rtl
      : TextDirection.ltr;
}

class SmsTemplateDraft {
  final SmsTemplateType? type;
  final SmsTextRange? amountRange;
  final List<SmsTextRange> directionRanges;

  const SmsTemplateDraft({
    this.type,
    this.amountRange,
    this.directionRanges = const [],
  });

  bool get canSave =>
      type != null && amountRange != null && directionRanges.isNotEmpty;
}

class SmsTemplateWizardPage extends StatefulWidget {
  final SmsTemplateBank bank;
  final SmsTemplateStoredMessage? initialMessage;

  const SmsTemplateWizardPage({
    super.key,
    required this.bank,
    this.initialMessage,
  });

  @override
  State<SmsTemplateWizardPage> createState() => _SmsTemplateWizardPageState();
}

class _SmsTemplateWizardPageState extends State<SmsTemplateWizardPage> {
  SmsTemplateStoredMessage? _message;
  SmsTemplateType? _type;
  SmsPlaceholderKind _moneyKind = SmsPlaceholderKind.amount;
  SmsTextRange? _amount;
  List<SmsTextRange> _directions = const [];
  final List<SmsPlaceholder> _placeholders = [];
  List<_WordMapping> _wordCategories = const [];
  bool _saveWordDictionary = false;
  bool _running = false;
  String _step = 'Ready';
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _message = widget.initialMessage;
    WidgetsBinding.instance.addPostFrameCallback((_) => _runWizard());
  }

  Future<void> _runWizard() async {
    if (_running) return;
    setState(() => _running = true);
    try {
      final selected = _message ?? await _chooseMessage();
      if (selected == null || !mounted) return;
      setState(() {
        _message = selected;
        _step = 'Transaction type';
        _progress = .16;
      });

      final type = await _chooseType();
      if (type == null || !mounted) return;
      setState(() {
        _type = type;
        _step = 'Amount or balance';
        _progress = .32;
      });

      final moneyKind = await _chooseMoneyKind();
      if (moneyKind == null || !mounted) return;
      setState(() {
        _moneyKind = moneyKind;
        _step = moneyKind == SmsPlaceholderKind.balance
            ? 'Account balance'
            : 'Transaction amount';
        _progress = .48;
      });

      final amount = await _chooseMoneyValue(selected.body, moneyKind);
      if (amount == null || !mounted) return;
      final parsed = SmsAmountParser.parse(
        selected.body.substring(amount.start, amount.end),
      );
      if (parsed == null ||
          !await _confirmMoney(parsed, moneyKind) ||
          !mounted) {
        return;
      }
      setState(() {
        _amount = amount;
        _step = 'Direction words';
        _progress = .64;
      });

      final directions = await _chooseDirections(selected.body, amount);
      if (directions == null || directions.isEmpty || !mounted) return;
      setState(() {
        _directions = directions;
        _step = 'Changing parts';
        _progress = .8;
      });

      final ranges = await _chooseOtherRanges(selected.body);
      if (ranges == null || !mounted) return;
      setState(() {
        _placeholders
          ..clear()
          ..addAll(
            ranges.map(
              (range) => SmsPlaceholder(
                kind: SmsPlaceholderKind.other,
                range: range,
              ),
            ),
          );
        _step = 'Categories';
        _progress = .9;
      });

      final categorize = await _askForWordCategories();
      if (!mounted) return;
      if (categorize == true) {
        final mappings = await _chooseWordCategories(selected.body);
        if (mappings == null || !mounted) return;
        _wordCategories = mappings;
        _saveWordDictionary = true;
      } else {
        _wordCategories = const [];
      }
      if (!mounted) return;
      setState(() {
        _step = 'Preview';
        _progress = 1;
      });
      await _previewAndSave();
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<SmsTemplateStoredMessage?> _chooseMessage() async {
    final messages = await SmsTemplateMobileStore.instance.getMessages(
      bankId: widget.bank.id,
    );
    if (!mounted) return null;
    return showModalBottomSheet<SmsTemplateStoredMessage>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          _ChooseMessageSheet(bank: widget.bank, saved: messages),
    );
  }

  Future<SmsTemplateType?> _chooseType() {
    return showModalBottomSheet<SmsTemplateType>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What happened to the money?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text('Choose this before marking any words.'),
                const SizedBox(height: 18),
                _ChoiceTile(
                  icon: Icons.north_east,
                  color: AppConstants.errorColor,
                  title: 'Debit',
                  subtitle: 'Money left the account',
                  onTap: () => Navigator.pop(context, SmsTemplateType.debit),
                ),
                const SizedBox(height: 10),
                _ChoiceTile(
                  icon: Icons.south_west,
                  color: const Color(0xFF15803D),
                  title: 'Credit',
                  subtitle: 'Money entered the account',
                  onTap: () => Navigator.pop(context, SmsTemplateType.credit),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<SmsPlaceholderKind?> _chooseMoneyKind() {
    return showModalBottomSheet<SmsPlaceholderKind>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Which number should this template use?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use the transaction amount when the message says how much moved. Use the account balance when the message only tells you the new balance.',
                ),
                const SizedBox(height: 18),
                _ChoiceTile(
                  icon: Icons.payments_outlined,
                  color: AppConstants.primaryColor,
                  title: 'Transaction amount',
                  subtitle: 'Add or subtract this number',
                  onTap: () =>
                      Navigator.pop(context, SmsPlaceholderKind.amount),
                ),
                const SizedBox(height: 10),
                _ChoiceTile(
                  icon: Icons.account_balance_wallet_outlined,
                  color: const Color(0xFF15803D),
                  title: 'Account balance',
                  subtitle: 'Set the money source to this number',
                  onTap: () =>
                      Navigator.pop(context, SmsPlaceholderKind.balance),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<SmsTextRange?> _chooseMoneyValue(
    String text,
    SmsPlaceholderKind kind,
  ) {
    final balance = kind == SmsPlaceholderKind.balance;
    final candidates = _numberRanges(text);
    return showModalBottomSheet<SmsTextRange>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              balance ? 'Tap the account balance' : 'Tap the transaction amount',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 7),
            Text(
              balance
                  ? 'The money source becomes this balance. Other numbers stay separate.'
                  : 'Only the value you tap becomes the amount. Other numbers stay separate.',
            ),
            const SizedBox(height: 18),
            _MessageTokenWrap(
              text: text,
              selectableRanges: candidates,
              selectedRanges: const [],
              onTap: (range) => Navigator.pop(context, range),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmMoney(double amount, SmsPlaceholderKind kind) async {
    final balance = kind == SmsPlaceholderKind.balance;
    return await showModalBottomSheet<bool>(
          context: context,
          isDismissible: false,
          enableDrag: false,
          showDragHandle: true,
          builder: (context) => Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  balance ? 'Is this balance correct?' : 'Is this amount correct?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Text(
                  amount.toStringAsFixed(2),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppConstants.primaryColor,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('No, cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Yes, correct'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  Future<List<SmsTextRange>?> _chooseDirections(
    String text,
    SmsTextRange amount,
  ) {
    final words = _wordRanges(
      text,
    ).where((range) => !_overlap(range, amount)).toList();
    final selected = <SmsTextRange>[];
    return showModalBottomSheet<List<SmsTextRange>>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tap the direction word(s)',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 7),
              const Text(
                'Select one or several words. They may be apart, but must appear in this order.',
              ),
              const SizedBox(height: 18),
              _MessageTokenWrap(
                text: text,
                selectableRanges: words,
                selectedRanges: selected,
                onTap: (range) {
                  setSheetState(() {
                    if (selected.any((item) => _same(item, range))) {
                      selected.removeWhere((item) => _same(item, range));
                    } else {
                      selected.add(range);
                      selected.sort((a, b) => a.start.compareTo(b.start));
                    }
                  });
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(
                          context,
                          _mergeAdjacentRanges(text, selected),
                        ),
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<List<SmsTextRange>?> _chooseOtherRanges(String text) {
    final tokens = _wordLikeRanges(
      text,
    ).where((range) => _amount == null || !_overlap(range, _amount!)).toList();
    final selected = <SmsTextRange>[];
    return showModalBottomSheet<List<SmsTextRange>>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Which text changes?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 7),
              const Text(
                'Tap every part that can change between messages. If nothing else changes, press Done.',
              ),
              const SizedBox(height: 18),
              _MessageTokenWrap(
                text: text,
                selectableRanges: tokens,
                selectedRanges: selected,
                onTap: (range) {
                  setSheetState(() {
                    if (selected.any((item) => _same(item, range))) {
                      selected.removeWhere((item) => _same(item, range));
                    } else {
                      selected.add(range);
                      selected.sort((a, b) => a.start.compareTo(b.start));
                    }
                  });
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, [...selected]),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _askForWordCategories() {
    return showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Categorize by a word?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Optional. A word in the message can file that transfer under a category. You can skip this.',
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Choose words'),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<_WordMapping>?> _chooseWordCategories(String text) {
    return showModalBottomSheet<List<_WordMapping>>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _WordCategorySheet(bankId: widget.bank.id, text: text),
    );
  }

  Future<void> _saveWordCategories() async {
    if (!_saveWordDictionary) return;
    final db = DatabaseHelper.instance;
    final existing = await db.getSmsCategoryRules(bankId: widget.bank.id);
    final kept = {
      for (final item in _wordCategories) item.key,
    };
    for (final rule in existing) {
      final id = rule.id;
      final key = rule.pattern?.key ?? rule.word.toLowerCase();
      if (id != null && !kept.contains(key)) {
        await db.deleteSmsCategoryRule(id);
      }
    }
    for (final item in _wordCategories) {
      await db.insertSmsCategoryRule(
        SmsCategoryRule(
          bankId: widget.bank.id,
          word: item.word,
          tagId: item.tagId,
          pattern: item.pattern,
          createdAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> _previewAndSave() async {
    final message = _message;
    final draft = SmsTemplateDraft(
      type: _type,
      amountRange: _amount,
      directionRanges: _directions,
    );
    if (message == null || !draft.canSave) return;
    final template = SmsTemplate(
      id: 'template_${DateTime.now().microsecondsSinceEpoch}',
      bankId: widget.bank.id,
      sampleText: message.body,
      type: _type!,
      amount: SmsPlaceholder(kind: _moneyKind, range: _amount!),
      directionRanges: _directions,
      placeholders: List.unmodifiable(_placeholders),
    );
    final compiled = SmsTemplateCompiler.compile(template);
    final messages = await SmsTemplateMobileStore.instance.getMessages(
      bankId: widget.bank.id,
    );
    final matches = [
      if (compiled != null)
        for (final item in messages)
          if (compiled.match(item.body) != null) item,
    ];
    if (!mounted) return;
    final save = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              compiled == null ? 'Template needs a fix' : 'Preview',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            if (compiled == null)
              const Text(
                'One of the marked values does not match its type. Go back and mark it more precisely.',
              )
            else ...[
              Text(
                'Matched ${matches.length} of ${messages.length} saved messages',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppConstants.primaryColor,
                ),
              ),
              const SizedBox(height: 12),
              for (final item in matches.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppConstants.backgroundColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      item.body,
                      textDirection: _messageDirection(item.body),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(compiled == null ? 'Close' : 'Cancel'),
                  ),
                ),
                if (compiled != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Save template'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
    if (save != true || compiled == null) return;
    await SmsTemplateSyncService.instance.saveTaughtTemplate(
      template: template,
      message: message,
    );
    await _saveWordCategories();
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Teach a template')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: _progress,
              borderRadius: BorderRadius.circular(20),
            ),
            const SizedBox(height: 14),
            Text(_step, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 18),
            if (_message != null)
              SizedBox(
                width: double.infinity,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      _message!.body,
                      textDirection: _messageDirection(_message!.body),
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(height: 1.55),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            const Text(
              'Each question opens separately. Closing the wizard does not save a partial template.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _running ? null : _runWizard,
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChooseMessageSheet extends StatelessWidget {
  final SmsTemplateBank bank;
  final List<SmsTemplateStoredMessage> saved;

  const _ChooseMessageSheet({required this.bank, required this.saved});

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: .78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              'Choose a real message',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text('Pick one example of the format you want to teach.'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final picked =
                      await showModalBottomSheet<SmsTemplateStoredMessage>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (context) =>
                            _PreviousMessagesSheet(bank: bank),
                      );
                  if (picked != null && context.mounted) {
                    Navigator.pop(context, picked);
                  }
                },
                icon: const Icon(Icons.history),
                label: const Text('Browse inbox'),
              ),
            ),
          ),
          Expanded(
            child: saved.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Text(
                        'No saved messages yet. Browse the inbox and create a template from one message.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    itemCount: saved.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => ListTile(
                      title: Text(
                        saved[index].body,
                        textDirection: _messageDirection(saved[index].body),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        DateFormat('d MMM, HH:mm').format(saved[index].date),
                      ),
                      onTap: () => Navigator.pop(context, saved[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PreviousMessagesSheet extends StatefulWidget {
  final SmsTemplateBank bank;

  const _PreviousMessagesSheet({required this.bank});

  @override
  State<_PreviousMessagesSheet> createState() => _PreviousMessagesSheetState();
}

class _PreviousMessagesSheetState extends State<_PreviousMessagesSheet> {
  List<SmsTemplateStoredMessage> _messages = const [];
  bool _loading = false;
  bool _started = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _started = true;
      _error = null;
    });
    final result = await SmsTemplateSyncService.instance.previewInboxPage(
      bankId: widget.bank.id,
      senders: widget.bank.senders,
      offset: _messages.length,
    );
    if (!mounted) return;
    final error = !result.supported
        ? 'SMS reading is available on Android only.'
        : !result.permissionGranted
        ? 'SMS permission was not granted.'
        : result.error;
    setState(() {
      _loading = false;
      if (error != null) {
        _error = error;
        return;
      }
      _messages = [..._messages, ...result.messages];
      _hasMore = result.messages.length >= smsInboxPreviewPageSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: .86,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Inbox messages',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Ten messages load at a time and stay in memory. A message is saved only after you create a template from it.',
            ),
          ),
          if (_error != null && _messages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text(
                _error!,
                style: const TextStyle(color: AppConstants.errorColor),
              ),
            ),
          if ((!_started || _loading) && _messages.isEmpty)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_messages.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    _error ?? 'No messages from this bank were found.',
                    textAlign: TextAlign.center,
                    style: _error == null
                        ? null
                        : const TextStyle(color: AppConstants.errorColor),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: _messages.length + (_hasMore ? 1 : 0),
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (index == _messages.length) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                      child: OutlinedButton(
                        onPressed: _loading ? null : _loadMore,
                        child: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Load more'),
                      ),
                    );
                  }
                  final message = _messages[index];
                  return ListTile(
                    title: Text(
                      message.body,
                      textDirection: _messageDirection(message.body),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${message.sender} • ${DateFormat('d MMM, HH:mm').format(message.date)}',
                    ),
                    onTap: () => Navigator.pop(context, message),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageTokenWrap extends StatelessWidget {
  final String text;
  final List<SmsTextRange> selectableRanges;
  final List<SmsTextRange> selectedRanges;
  final ValueChanged<SmsTextRange> onTap;

  const _MessageTokenWrap({
    required this.text,
    required this.selectableRanges,
    required this.selectedRanges,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textDirection = _messageDirection(text);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 300),
      child: SingleChildScrollView(
        child: Wrap(
          textDirection: textDirection,
          spacing: 6,
          runSpacing: 7,
          children: [
            for (final range in selectableRanges)
              Builder(
                builder: (context) {
                  final selected = selectedRanges.any(
                    (item) =>
                        (range.start >= item.start && range.end <= item.end) ||
                        _same(item, range),
                  );
                  return Material(
                    color: selected
                        ? AppConstants.primaryColor
                        : AppConstants.primarySurface,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => onTap(range),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                        child: Text(
                          text.substring(range.start, range.end),
                          textDirection: textDirection,
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : AppConstants.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ChoiceTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .1),
          child: Icon(icon, color: color),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _WordMapping {
  final String word;
  final int tagId;
  final String categoryName;
  final SmsRulePattern? pattern;

  const _WordMapping({
    required this.word,
    required this.tagId,
    required this.categoryName,
    this.pattern,
  });

  String get key => pattern?.key ?? word.toLowerCase();
}

class _WordCategorySheet extends StatefulWidget {
  final String bankId;
  final String text;

  const _WordCategorySheet({required this.bankId, required this.text});

  @override
  State<_WordCategorySheet> createState() => _WordCategorySheetState();
}

class _WordCategorySheetState extends State<_WordCategorySheet> {
  List<_WordMapping> _mappings = const [];
  final List<SmsTextRange> _selected = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rules = await DatabaseHelper.instance.getSmsCategoryRules(
      bankId: widget.bankId,
    );
    final tags = await MoneyStorage().getTags();
    final names = {
      for (final tag in tags)
        if (tag.id != null) tag.id!: tag.name,
    };
    if (!mounted) return;
    setState(() {
      _mappings = [
        for (final rule in rules)
          if (names[rule.tagId] != null)
            _WordMapping(
              word: rule.word,
              tagId: rule.tagId,
              categoryName: names[rule.tagId]!,
              pattern: rule.pattern,
            ),
      ];
      _loading = false;
    });
  }

  void _toggle(SmsTextRange range) {
    setState(() {
      if (_selected.any((item) => _same(item, range))) {
        _selected.removeWhere((item) => _same(item, range));
      } else {
        _selected.add(range);
        _selected.sort((a, b) => a.start.compareTo(b.start));
      }
    });
  }

  SmsRulePattern? _selectedPattern() {
    if (_selected.isEmpty) return null;
    final tokens = SmsRuleEngine.tokenize(widget.text);
    final words = <SmsPatternWord>[];
    for (var index = 0; index < tokens.length; index++) {
      final token = tokens[index];
      if (!_selected.any(
        (range) => _rangesOverlap(
          token.start,
          token.end,
          range.start,
          range.end,
        ),
      )) {
        continue;
      }
      final word = SmsRuleEngine.normalizeWord(token.text);
      if (word.isNotEmpty) {
        words.add(SmsPatternWord(index: index, word: word));
      }
    }
    if (words.isEmpty) return null;
    return SmsRulePattern(tokenCount: tokens.length, words: words);
  }

  Future<void> _assignSelected() async {
    final pattern = _selectedPattern();
    if (pattern == null) return;
    final label = pattern.display;
    final tag = await showSmsCategoryPicker(
      context: context,
      arabic: Localizations.localeOf(context).languageCode == 'ar',
      word: label,
    );
    if (tag == null || tag.id == null || !mounted) return;
    setState(() {
      _mappings = [
        for (final item in _mappings)
          if (item.key != pattern.key) item,
        _WordMapping(
          word: label,
          tagId: tag.id!,
          categoryName: tag.name,
          pattern: pattern,
        ),
      ];
      _selected.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final words = _wordRanges(widget.text);
    return FractionallySizedBox(
      heightFactor: .86,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Word dictionary',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 7),
            const Text(
              'Select one or more words, then choose their category. The words can be separated; all selected positions must match.',
            ),
            const SizedBox(height: 16),
            _MessageTokenWrap(
              text: widget.text,
              selectableRanges: words,
              selectedRanges: _selected,
              onTap: _toggle,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: _selected.isEmpty ? null : _assignSelected,
                child: Text(
                  _selected.isEmpty
                      ? 'Select words'
                      : 'Categorize ${_selected.length} selected word${_selected.length == 1 ? '' : 's'}',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Dictionary',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _mappings.isEmpty
                  ? const Text('No words mapped yet. Done is ready either way.')
                  : ListView.separated(
                      itemCount: _mappings.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = _mappings[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.word),
                          subtitle: Text(item.categoryName),
                          trailing: IconButton(
                            tooltip: 'Remove',
                            onPressed: () {
                              setState(() {
                                _mappings = [
                                  for (final mapping in _mappings)
                                    if (mapping.key != item.key) mapping,
                                ];
                              });
                            },
                            icon: const Icon(Icons.close),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, [..._mappings]),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _rangesOverlap(int aStart, int aEnd, int bStart, int bEnd) =>
    aStart < bEnd && bStart < aEnd;

List<SmsTextRange> _numberRanges(String text) {
  final expression = RegExp(
    r'[0-9٠-٩۰-۹]+(?:[.,٬٫][0-9٠-٩۰-۹]+)*',
    unicode: true,
  );
  return [
    for (final match in expression.allMatches(text))
      SmsTextRange(start: match.start, end: match.end),
  ];
}

List<SmsTextRange> _wordRanges(String text) {
  final expression = RegExp(r'[\p{L}\p{N}]+', unicode: true);
  return [
    for (final match in expression.allMatches(text))
      SmsTextRange(start: match.start, end: match.end),
  ];
}

List<SmsTextRange> _wordLikeRanges(String text) {
  final expression = RegExp(r'[^\s]+', unicode: true);
  final ranges = <SmsTextRange>[];
  const edgePunctuation = '.,،;؛:!?()[]{}"“”';
  for (final match in expression.allMatches(text)) {
    var start = match.start;
    var end = match.end;
    while (start < end && edgePunctuation.contains(text[start])) {
      start++;
    }
    while (end > start && edgePunctuation.contains(text[end - 1])) {
      end--;
    }
    if (end > start) ranges.add(SmsTextRange(start: start, end: end));
  }
  return ranges;
}

bool _overlap(SmsTextRange a, SmsTextRange b) =>
    a.start < b.end && b.start < a.end;

List<SmsTextRange> _mergeAdjacentRanges(
  String text,
  List<SmsTextRange> ranges,
) {
  final ordered = [...ranges]..sort((a, b) => a.start.compareTo(b.start));
  final merged = <SmsTextRange>[];
  for (final range in ordered) {
    if (merged.isNotEmpty) {
      final previous = merged.last;
      final gap = text.substring(previous.end, range.start);
      if (gap.trim().isEmpty) {
        merged[merged.length - 1] = SmsTextRange(
          start: previous.start,
          end: range.end,
        );
        continue;
      }
    }
    merged.add(range);
  }
  return merged;
}

bool _same(SmsTextRange a, SmsTextRange b) =>
    a.start == b.start && a.end == b.end;
