import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:money_traker/constants/app_constants.dart';
import 'package:money_traker/data/database_helper.dart';
import 'package:money_traker/pages/sms/category_rule_sheet.dart';
import 'package:money_traker/services/sms_template_sync_service.dart';
import 'package:money_traker/sms/sms_models.dart';
import 'package:money_traker/sms/sms_rule_engine.dart';
import 'package:money_traker/sms/template_engine/sms_amount_parser.dart';
import 'package:money_traker/sms/template_engine/sms_template_compiler.dart';
import 'package:money_traker/sms/template_engine/sms_template_mobile_store.dart';
import 'package:money_traker/sms/template_engine/template_models.dart';
import 'package:money_traker/store/money_storage.dart';

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

TextDirection _scriptDirection(String text) {
  return RegExp(
        r'[\u0590-\u08FF\uFB1D-\uFDFD\uFE70-\uFEFC]',
      ).hasMatch(text)
      ? TextDirection.rtl
      : TextDirection.ltr;
}

class SmsTemplateDraft {
  final SmsTemplateType? type;
  final SmsTextRange? amountRange;

  const SmsTemplateDraft({this.type, this.amountRange});

  bool get canSave => type != null && amountRange != null;
}

enum _WizardPhase {
  message,
  inbox,
  type,
  money,
  changing,
  askCategories,
  categories,
  preview,
  done,
}

enum _MarkMode { money, changing, pick }

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
  late final List<_WizardPhase> _stack;
  bool _closing = false;
  SmsTemplateStoredMessage? _message;
  SmsTemplateType? _type;
  SmsPlaceholderKind _moneyKind = SmsPlaceholderKind.amount;
  SmsTextRange? _amount;
  final List<SmsTextRange> _changing = [];
  List<_WordMapping> _wordCategories = const [];
  bool _saveWordDictionary = false;
  bool _saving = false;
  bool _previewLoading = false;
  bool _previewReady = false;
  int _previewTotal = 0;
  int _previewGeneration = 0;
  List<SmsTemplateStoredMessage> _previewMatches = const [];

  _WizardPhase get _phase => _stack.last;

  @override
  void initState() {
    super.initState();
    _message = widget.initialMessage;
    _stack = [
      widget.initialMessage == null
          ? _WizardPhase.message
          : _WizardPhase.type,
    ];
  }

  void _push(_WizardPhase phase) {
    setState(() => _stack.add(phase));
    if (phase == _WizardPhase.preview) _loadPreview();
  }

  void _back() {
    if (_phase == _WizardPhase.done) {
      _closeCreated();
      return;
    }
    if (_stack.length > 1) {
      setState(() => _stack.removeLast());
      return;
    }
    Navigator.maybePop(context);
  }

  void _closeCreated() {
    if (_closing) return;
    setState(() => _closing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, true);
    });
  }

  void _chooseType(SmsTemplateType type) {
    setState(() {
      _type = type;
      _stack.add(_WizardPhase.money);
    });
  }

  void _useMessage(SmsTemplateStoredMessage message) {
    setState(() {
      final changed = _message?.hash != message.hash;
      _message = message;
      if (changed) {
        _type = null;
        _amount = null;
        _moneyKind = SmsPlaceholderKind.amount;
        _changing.clear();
        _wordCategories = const [];
        _saveWordDictionary = false;
      }
      if (_stack.last == _WizardPhase.inbox) _stack.removeLast();
      if (_stack.last != _WizardPhase.type) _stack.add(_WizardPhase.type);
    });
  }

  Future<void> _pickMoney(SmsTextRange range) async {
    final body = _message?.body;
    if (body == null) return;
    final raw = body.substring(range.start, range.end);
    final parsed = SmsAmountParser.parse(raw);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This number cannot be used as money.')),
      );
      return;
    }
    final kind = await showModalBottomSheet<SmsPlaceholderKind>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                raw,
                textDirection: TextDirection.ltr,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: const Color(0xFF15803D),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text('Reads as ${parsed.toStringAsFixed(2)}'),
              const SizedBox(height: 16),
              _ChoiceTile(
                icon: Icons.payments_outlined,
                color: AppConstants.primaryColor,
                title: 'Transaction amount',
                subtitle: 'Add or subtract this number',
                onTap: () => Navigator.pop(context, SmsPlaceholderKind.amount),
              ),
              const SizedBox(height: 10),
              _ChoiceTile(
                icon: Icons.account_balance_wallet_outlined,
                color: const Color(0xFF15803D),
                title: 'Account balance',
                subtitle: 'Set the money source to this number',
                onTap: () => Navigator.pop(context, SmsPlaceholderKind.balance),
              ),
            ],
          ),
        ),
      ),
    );
    if (kind == null || !mounted) return;
    setState(() {
      _amount = range;
      _moneyKind = kind;
      _changing.removeWhere((item) => _overlap(item, range));
    });
  }

  void _toggleChanging(SmsTextRange range) {
    if (_amount != null && _overlap(range, _amount!)) return;
    setState(() {
      if (_changing.any((item) => _same(item, range))) {
        _changing.removeWhere((item) => _same(item, range));
      } else {
        _changing.add(range);
        _changing.sort((a, b) => a.start.compareTo(b.start));
      }
    });
  }

  SmsTemplate? _buildTemplate() {
    final message = _message;
    final type = _type;
    final amount = _amount;
    if (message == null || type == null || amount == null) return null;
    return SmsTemplate(
      id: 'template_${DateTime.now().microsecondsSinceEpoch}',
      bankId: widget.bank.id,
      sampleText: message.body,
      type: type,
      amount: SmsPlaceholder(kind: _moneyKind, range: amount),
      directionRanges: const [],
      placeholders: [
        for (final range in _changing)
          SmsPlaceholder(kind: SmsPlaceholderKind.other, range: range),
      ],
    );
  }

  Future<void> _loadPreview() async {
    final generation = ++_previewGeneration;
    final template = _buildTemplate();
    final message = _message;
    if (template == null || message == null) return;
    setState(() => _previewLoading = true);
    try {
      final compiled = SmsTemplateCompiler.compile(template);
      final messages = await SmsTemplateMobileStore.instance.getMessages(
        bankId: widget.bank.id,
      );
      if (!mounted || generation != _previewGeneration) return;
      setState(() {
        _previewLoading = false;
        _previewReady = compiled != null;
        _previewTotal = messages.length;
        _previewMatches = [
          if (compiled != null)
            for (final item in messages)
              if (compiled.match(item.body) != null) item,
        ];
      });
    } catch (_) {
      if (!mounted || generation != _previewGeneration) return;
      setState(() {
        _previewLoading = false;
        _previewReady = false;
        _previewMatches = const [];
      });
    }
  }

  Future<void> _save() async {
    final message = _message;
    final template = _buildTemplate();
    final draft = SmsTemplateDraft(type: _type, amountRange: _amount);
    if (message == null || template == null || !draft.canSave || _saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      await SmsTemplateSyncService.instance.saveTaughtTemplate(
        template: template,
        message: message,
      );
      await _saveWordCategories();
      if (!mounted) return;
      setState(() => _stack.add(_WizardPhase.done));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveWordCategories() async {
    if (!_saveWordDictionary) return;
    final db = DatabaseHelper.instance;
    final existing = await db.getSmsCategoryRules(bankId: widget.bank.id);
    final kept = {for (final item in _wordCategories) item.key};
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

  double get _progress => switch (_phase) {
    _WizardPhase.message || _WizardPhase.inbox => .14,
    _WizardPhase.type => .28,
    _WizardPhase.money => .46,
    _WizardPhase.changing => .64,
    _WizardPhase.askCategories || _WizardPhase.categories => .78,
    _WizardPhase.preview => .9,
    _WizardPhase.done => 1,
  };

  String get _stepLabel => switch (_phase) {
    _WizardPhase.message => 'Example message',
    _WizardPhase.inbox => 'Inbox',
    _WizardPhase.type => 'Transaction type',
    _WizardPhase.money => 'Money',
    _WizardPhase.changing => 'Changing parts',
    _WizardPhase.askCategories || _WizardPhase.categories => 'Categories',
    _WizardPhase.preview => 'Preview',
    _WizardPhase.done => 'Template created',
  };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _closing || (_stack.length <= 1 && _phase != _WizardPhase.done),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_phase == _WizardPhase.done) {
          _closeCreated();
          return;
        }
        setState(() => _stack.removeLast());
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Teach a template'),
          leading: BackButton(onPressed: _back),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: _progress,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _stepLabel,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppConstants.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _phaseBody()),
          ],
        ),
      ),
    );
  }

  Widget _phaseBody() {
    return switch (_phase) {
      _WizardPhase.type => _typePhase(),
      _WizardPhase.message => _MessagePhase(
        bank: widget.bank,
        suggested: widget.initialMessage,
        onBrowseInbox: () => _push(_WizardPhase.inbox),
        onPick: _useMessage,
      ),
      _WizardPhase.inbox => _InboxPhase(
        bank: widget.bank,
        onPick: _useMessage,
      ),
      _WizardPhase.money => _moneyPhase(),
      _WizardPhase.changing => _changingPhase(),
      _WizardPhase.askCategories => _askCategoriesPhase(),
      _WizardPhase.categories => _WordCategoryEditor(
        bankId: widget.bank.id,
        text: _message?.body ?? '',
        onDone: (mappings) {
          _wordCategories = mappings;
          _saveWordDictionary = true;
          _push(_WizardPhase.preview);
        },
      ),
      _WizardPhase.preview => _previewPhase(),
      _WizardPhase.done => _donePhase(),
    };
  }

  Widget _typePhase() {
    final message = _message;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        if (message != null) ...[
          Text('Message', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppConstants.backgroundColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              message.body,
              textDirection: _messageDirection(message.body),
              style: _plainStyle,
            ),
          ),
          const SizedBox(height: 22),
        ],
        Text(
          'What happened to the money?',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text('Choose debit or credit for the message above.'),
        const SizedBox(height: 18),
        _ChoiceTile(
          icon: Icons.north_east,
          color: AppConstants.errorColor,
          title: 'Debit',
          subtitle: 'Money left the account',
          onTap: () => _chooseType(SmsTemplateType.debit),
        ),
        const SizedBox(height: 10),
        _ChoiceTile(
          icon: Icons.south_west,
          color: const Color(0xFF15803D),
          title: 'Credit',
          subtitle: 'Money entered the account',
          onTap: () => _chooseType(SmsTemplateType.credit),
        ),
      ],
    );
  }

  Widget _moneyPhase() {
    final message = _message;
    final parsed = _parsedAmount();
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            children: [
              if (_type != null) ...[_typeBanner(), const SizedBox(height: 14)],
              Text(
                'Choose the money',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Green numbers are tappable. After you tap one, choose whether it is the amount or the balance.',
              ),
              const SizedBox(height: 16),
              if (message != null)
                _MessageCard(
                  text: message.body,
                  mode: _MarkMode.money,
                  moneyRange: _amount,
                  onPick: _pickMoney,
                ),
              if (parsed != null) ...[
                const SizedBox(height: 14),
                Text(
                  _moneyKind == SmsPlaceholderKind.balance
                      ? 'Account balance · ${parsed.toStringAsFixed(2)}'
                      : 'Transaction amount · ${parsed.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFF15803D),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
        _continueBar(
          label: 'Continue',
          onPressed: _amount == null
              ? null
              : () => _push(_WizardPhase.changing),
        ),
      ],
    );
  }

  Widget _changingPhase() {
    final message = _message;
    final count = _changing.length;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            children: [
              if (_type != null) ...[_typeBanner(), const SizedBox(height: 14)],
              Text(
                'Which parts change?',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Tap the boxed words that can be different in other messages. The green number stays the money you already chose. Words you leave unselected have to appear the same way next time.',
              ),
              const SizedBox(height: 16),
              if (message != null)
                _MessageCard(
                  text: message.body,
                  mode: _MarkMode.changing,
                  moneyRange: _amount,
                  selected: _changing,
                  onPick: _toggleChanging,
                ),
              const SizedBox(height: 14),
              Text(
                count == 0
                    ? 'No changing parts yet. Continue is fine if only the money changes.'
                    : '$count changing part${count == 1 ? '' : 's'} selected',
                style: const TextStyle(color: AppConstants.textSecondary),
              ),
            ],
          ),
        ),
        _continueBar(
          label: 'Continue',
          onPressed: () => _push(_WizardPhase.askCategories),
        ),
      ],
    );
  }

  Widget _askCategoriesPhase() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        Text(
          'Categorize by a word?',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Optional. A word in the message can file that transfer under a category.',
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => _push(_WizardPhase.categories),
          child: const Text('Choose words'),
        ),
        TextButton(
          onPressed: () {
            setState(() {
              _wordCategories = const [];
              _saveWordDictionary = false;
            });
            _push(_WizardPhase.preview);
          },
          child: const Text('Not now'),
        ),
      ],
    );
  }

  Widget _previewPhase() {
    final template = _buildTemplate();
    final compiled = template == null
        ? null
        : SmsTemplateCompiler.compile(template);
    final ready = _previewReady && compiled != null;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            children: [
              Text(
                ready ? 'Preview' : 'Template needs a fix',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              if (_previewLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (!ready)
                const Text(
                  'The marked money value does not read as a number. Go back and choose it again.',
                )
              else ...[
                Text(
                  'Matched ${_previewMatches.length} of $_previewTotal saved messages',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppConstants.primaryColor,
                  ),
                ),
                const SizedBox(height: 12),
                if (_previewMatches.isEmpty)
                  const Text(
                    'No other saved message uses this format yet. You can still save it.',
                  ),
                for (final item in _previewMatches.take(3))
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
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (ready)
          _continueBar(
            label: _saving ? 'Saving…' : 'Save template',
            onPressed: _saving ? null : _save,
          ),
      ],
    );
  }

  Widget _donePhase() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
        child: Column(
          children: [
            const Spacer(),
            const Icon(
              Icons.check_circle,
              color: Color(0xFF15803D),
              size: 76,
            ),
            const SizedBox(height: 18),
            Text(
              'Congratulations',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'You have created a template.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, height: 1.4),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _closeCreated,
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeBanner() {
    final debit = _type == SmsTemplateType.debit;
    final color = debit ? AppConstants.errorColor : const Color(0xFF15803D);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          debit ? 'Debit' : 'Credit',
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  double? _parsedAmount() {
    final message = _message;
    final amount = _amount;
    if (message == null || amount == null) return null;
    return SmsAmountParser.parse(
      message.body.substring(amount.start, amount.end),
    );
  }

  Widget _continueBar({required String label, required VoidCallback? onPressed}) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: onPressed, child: Text(label)),
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final String text;
  final _MarkMode mode;
  final SmsTextRange? moneyRange;
  final List<SmsTextRange> selected;
  final ValueChanged<SmsTextRange> onPick;

  const _MessageCard({
    required this.text,
    required this.mode,
    required this.onPick,
    this.moneyRange,
    this.selected = const [],
  });

  @override
  Widget build(BuildContext context) {
    final direction = _messageDirection(text);
    final tokens = mode == _MarkMode.money
        ? _tokenize(text)
        : _mergeGlued(
            text,
            _tokenize(text),
            mode == _MarkMode.changing ? moneyRange : null,
          );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Directionality(
        textDirection: direction,
        child: Wrap(
          spacing: 6,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final token in tokens)
              _TokenView(
                text: text,
                token: token,
                mode: mode,
                money: _isMoneyToken(token, moneyRange),
                picked: selected.any((item) => _overlap(item, token.range)),
                onPick: onPick,
              ),
          ],
        ),
      ),
    );
  }
}

class _TokenView extends StatelessWidget {
  final String text;
  final _Token token;
  final _MarkMode mode;
  final bool money;
  final bool picked;
  final ValueChanged<SmsTextRange> onPick;

  const _TokenView({
    required this.text,
    required this.token,
    required this.mode,
    required this.money,
    required this.picked,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final label = text.substring(token.start, token.end);
    final chosen = money;
    final tappable = switch (mode) {
      _MarkMode.money => token.number,
      _MarkMode.changing => !chosen,
      _MarkMode.pick => true,
    };
    final boxed = mode != _MarkMode.money || token.number;
    final core = boxed
        ? _WordBox(
            label: label,
            textDirection: token.number
                ? TextDirection.ltr
                : _scriptDirection(label),
            money: mode == _MarkMode.money && token.number && !chosen,
            chosen: chosen && mode != _MarkMode.pick,
            selected: picked && !chosen,
            onTap: tappable ? () => onPick(token.range) : null,
          )
        : Text(
            label,
            textDirection: _scriptDirection(label),
            style: _plainStyle,
          );
    if (token.prefix.isEmpty && token.suffix.isEmpty) return core;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (token.prefix.isNotEmpty)
          Text(token.prefix, textDirection: direction, style: _plainStyle),
        core,
        if (token.suffix.isNotEmpty)
          Text(token.suffix, textDirection: direction, style: _plainStyle),
      ],
    );
  }
}

class _WordBox extends StatelessWidget {
  final String label;
  final TextDirection textDirection;
  final bool money;
  final bool chosen;
  final bool selected;
  final VoidCallback? onTap;

  const _WordBox({
    required this.label,
    required this.textDirection,
    required this.money,
    required this.chosen,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    final Color border;
    if (chosen) {
      background = const Color(0xFF15803D);
      foreground = Colors.white;
      border = const Color(0xFF15803D);
    } else if (money) {
      background = const Color(0xFFDCFCE7);
      foreground = const Color(0xFF166534);
      border = const Color(0xFF86EFAC);
    } else if (selected) {
      background = AppConstants.primaryColor;
      foreground = Colors.white;
      border = AppConstants.primaryColor;
    } else {
      background = Colors.white;
      foreground = AppConstants.textPrimary;
      border = const Color(0xFFD1D5DB);
    }
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        label,
        textDirection: textDirection,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: border),
      ),
      child: onTap == null
          ? child
          : InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: child,
            ),
    );
  }
}

const _plainStyle = TextStyle(
  color: AppConstants.textPrimary,
  fontSize: 16,
  height: 1.35,
  fontWeight: FontWeight.w500,
);

class _MessagePhase extends StatefulWidget {
  final SmsTemplateBank bank;
  final SmsTemplateStoredMessage? suggested;
  final VoidCallback onBrowseInbox;
  final ValueChanged<SmsTemplateStoredMessage> onPick;

  const _MessagePhase({
    required this.bank,
    required this.onBrowseInbox,
    required this.onPick,
    this.suggested,
  });

  @override
  State<_MessagePhase> createState() => _MessagePhaseState();
}

class _MessagePhaseState extends State<_MessagePhase> {
  List<SmsTemplateStoredMessage> _saved = const [];
  bool _loading = true;

  List<SmsTemplateStoredMessage> get _listed => [
    for (final item in _saved)
      if (item.hash != widget.suggested?.hash) item,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final messages = await SmsTemplateMobileStore.instance.getMessages(
      bankId: widget.bank.id,
    );
    if (!mounted) return;
    setState(() {
      _saved = messages;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Text(
            'Choose a real message',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            'Pick one example of the format you want to teach. Debit or credit comes next.',
          ),
        ),
        if (widget.suggested != null)
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            title: Text(
              widget.suggested!.body,
              textDirection: _messageDirection(widget.suggested!.body),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: const Text('Use this message'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => widget.onPick(widget.suggested!),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.onBrowseInbox,
              icon: const Icon(Icons.history),
              label: const Text('Browse inbox'),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _listed.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      widget.suggested == null
                          ? 'No saved messages yet. Browse the inbox and create a template from one message.'
                          : 'Or browse the inbox for a different message.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  itemCount: _listed.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final message = _listed[index];
                    return ListTile(
                      title: Text(
                        message.body,
                        textDirection: _messageDirection(message.body),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        DateFormat('d MMM, HH:mm').format(message.date),
                      ),
                      onTap: () => widget.onPick(message),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _InboxPhase extends StatefulWidget {
  final SmsTemplateBank bank;
  final ValueChanged<SmsTemplateStoredMessage> onPick;

  const _InboxPhase({required this.bank, required this.onPick});

  @override
  State<_InboxPhase> createState() => _InboxPhaseState();
}

class _InboxPhaseState extends State<_InboxPhase> {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Text(
            'Inbox messages',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            'Ten messages load at a time. A message is saved only after you create a template from it.',
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
                              child: CircularProgressIndicator(strokeWidth: 2),
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
                  onTap: () => widget.onPick(message),
                );
              },
            ),
          ),
      ],
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

class _WordCategoryEditor extends StatefulWidget {
  final String bankId;
  final String text;
  final ValueChanged<List<_WordMapping>> onDone;

  const _WordCategoryEditor({
    required this.bankId,
    required this.text,
    required this.onDone,
  });

  @override
  State<_WordCategoryEditor> createState() => _WordCategoryEditorState();
}

class _WordCategoryEditorState extends State<_WordCategoryEditor> {
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView(
              children: [
                Text(
                  'Word dictionary',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Select one or more boxed words, then choose their category.',
                ),
                const SizedBox(height: 16),
                _MessageCard(
                  text: widget.text,
                  mode: _MarkMode.pick,
                  selected: _selected,
                  onPick: _toggle,
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
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_mappings.isEmpty)
                  const Text('No words mapped yet. Done is ready either way.')
                else
                  for (final item in _mappings)
                    ListTile(
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
                    ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => widget.onDone([..._mappings]),
              child: const Text('Done'),
            ),
          ),
        ],
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
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

class _Token {
  final int start;
  final int end;
  final String prefix;
  final String suffix;
  final bool number;

  const _Token({
    required this.start,
    required this.end,
    this.prefix = '',
    this.suffix = '',
    required this.number,
  });

  SmsTextRange get range => SmsTextRange(start: start, end: end);

  _Token copyWith({String? prefix, String? suffix, int? end, bool? number}) {
    return _Token(
      start: start,
      end: end ?? this.end,
      prefix: prefix ?? this.prefix,
      suffix: suffix ?? this.suffix,
      number: number ?? this.number,
    );
  }
}

final _tokenPattern = RegExp(
  r'[0-9٠-٩۰-۹]+(?:[.,٬٫][0-9٠-٩۰-۹]+)*|[\p{L}]+',
  unicode: true,
);

final _numberTokenPattern = RegExp(
  r'^[0-9٠-٩۰-۹]+(?:[.,٬٫][0-9٠-٩۰-۹]+)*$',
  unicode: true,
);

List<_Token> _tokenize(String text) {
  final tokens = <_Token>[];
  var consumed = 0;
  for (final match in _tokenPattern.allMatches(text)) {
    final gap = text.substring(consumed, match.start);
    final split = _splitGap(gap);
    var prefix = split.trailing;
    if (tokens.isEmpty) {
      prefix = '${split.leading}${split.trailing}';
    } else if (split.leading.isNotEmpty) {
      final previous = tokens.removeLast();
      tokens.add(previous.copyWith(suffix: '${previous.suffix}${split.leading}'));
    }
    final value = match.group(0)!;
    tokens.add(
      _Token(
        start: match.start,
        end: match.end,
        prefix: prefix,
        number: _numberTokenPattern.hasMatch(value),
      ),
    );
    consumed = match.end;
  }
  if (tokens.isNotEmpty && consumed < text.length) {
    final split = _splitGap(text.substring(consumed));
    final previous = tokens.removeLast();
    tokens.add(
      previous.copyWith(
        suffix: '${previous.suffix}${split.leading}${split.trailing}',
      ),
    );
  }
  return tokens;
}

({String leading, String trailing}) _splitGap(String gap) {
  var start = 0;
  while (start < gap.length && gap[start].trim().isNotEmpty) {
    start++;
  }
  var end = gap.length;
  while (end > start && gap[end - 1].trim().isNotEmpty) {
    end--;
  }
  return (leading: gap.substring(0, start), trailing: gap.substring(end));
}

List<_Token> _mergeGlued(String text, List<_Token> tokens, SmsTextRange? keep) {
  final merged = <_Token>[];
  for (final token in tokens) {
    if (merged.isEmpty) {
      merged.add(token);
      continue;
    }
    final previous = merged.last;
    final gap = text.substring(previous.end, token.start);
    final glued = gap.isNotEmpty && RegExp(r'^[/:\-]+$').hasMatch(gap);
    final blocked =
        keep != null &&
        (_overlap(previous.range, keep) || _overlap(token.range, keep));
    if (!glued || blocked) {
      merged.add(token);
      continue;
    }
    merged[merged.length - 1] = _Token(
      start: previous.start,
      end: token.end,
      prefix: previous.prefix,
      suffix: token.suffix,
      number: false,
    );
  }
  return merged;
}

bool _isMoneyToken(_Token token, SmsTextRange? money) {
  if (money == null || !token.number) return false;
  return _overlap(token.range, money);
}

bool _rangesOverlap(int aStart, int aEnd, int bStart, int bEnd) =>
    aStart < bEnd && bStart < aEnd;

bool _overlap(SmsTextRange a, SmsTextRange b) =>
    a.start < b.end && b.start < a.end;

bool _same(SmsTextRange a, SmsTextRange b) =>
    a.start == b.start && a.end == b.end;
