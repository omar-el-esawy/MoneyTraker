import 'package:flutter/material.dart';

import 'package:money_traker/constants/app_constants.dart';
import 'package:money_traker/data/database_helper.dart';
import 'package:money_traker/model/tag.dart';
import 'package:money_traker/pages/sms/category_rule_sheet.dart';
import 'package:money_traker/pages/sms/rule_tester_page.dart';
import 'package:money_traker/services/sync_service.dart';
import 'package:money_traker/sms/sms_models.dart';
import 'package:money_traker/sms/sms_rule_engine.dart';
import 'package:money_traker/sms/sms_strings.dart';
import 'package:money_traker/store/money_storage.dart';

class _NumberMark {
  final SmsNumberSpan span;
  final SmsField field;

  const _NumberMark({required this.span, required this.field});
}

class MessageMarkerPage extends StatefulWidget {
  final SmsCopy copy;
  final bool arabic;
  final String bankName;

  const MessageMarkerPage({
    super.key,
    required this.copy,
    required this.arabic,
    required this.bankName,
  });

  @override
  State<MessageMarkerPage> createState() => _MessageMarkerPageState();
}

class _MessageMarkerPageState extends State<MessageMarkerPage> {
  final Map<int, _NumberMark> _numberMarks = {};
  final Map<int, String> _wordTypes = {};
  final Map<int, int> _categoryMarks = {};
  List<SmsTypeWord> _savedWords = [];
  List<SmsCategoryRule> _savedCategoryRules = [];
  Map<int, Tag> _tagsById = {};
  bool _saving = false;
  bool _loading = true;

  SmsStrings get _s => SmsStrings(widget.arabic);

  @override
  void initState() {
    super.initState();
    _loadSavedWords();
  }

  Future<void> _loadSavedWords() async {
    final words = await DatabaseHelper.instance.getSmsTypeWords(bankId: widget.copy.bankId);
    final categoryRules = await DatabaseHelper.instance.getSmsCategoryRules(bankId: widget.copy.bankId);
    final tags = await MoneyStorage().getTags();
    if (!mounted) return;
    setState(() {
      _savedWords = words;
      _savedCategoryRules = categoryRules;
      _tagsById = {for (final tag in tags) if (tag.id != null) tag.id!: tag};
      for (final token in SmsRuleEngine.tokenize(widget.copy.body)) {
        if (token.isNumber) continue;
        final type = _savedTypeFor(token.text);
        if (type != null) _wordTypes[token.start] = type;
        final category = _savedCategoryFor(token.text);
        if (category != null) _categoryMarks[token.start] = category.tagId;
      }
      _loading = false;
    });
  }

  String? _savedTypeFor(String text) {
    final target = SmsRuleEngine.normalizeWord(text).toLowerCase();
    for (final word in _savedWords) {
      if (SmsRuleEngine.normalizeWord(word.word).toLowerCase() == target) {
        return word.typeHint;
      }
    }
    return null;
  }

  SmsCategoryRule? _savedCategoryFor(String text) {
    final target = SmsRuleEngine.normalizeWord(text).toLowerCase();
    for (final rule in _savedCategoryRules) {
      if (SmsRuleEngine.normalizeWord(rule.word).toLowerCase() == target) return rule;
    }
    return null;
  }

  Future<void> _pickToken(SmsToken token) async {
    if (token.isNumber) {
      await _pickNumber(SmsNumberSpan(start: token.start, end: token.end, text: token.text));
    } else {
      await _pickWord(token);
    }
  }

  Future<void> _pickNumber(SmsNumberSpan span) async {
    final s = _s;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Directionality(
          textDirection: s.ar ? TextDirection.rtl : TextDirection.ltr,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(s.whatIsThis, style: Theme.of(context).textTheme.titleMedium),
                ),
                ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: Text(s.amount),
                  onTap: () => Navigator.pop(context, 'amount'),
                ),
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: Text(s.balance),
                  onTap: () => Navigator.pop(context, 'balance'),
                ),
                ListTile(
                  leading: const Icon(Icons.tag),
                  title: Text(s.account),
                  onTap: () => Navigator.pop(context, 'account'),
                ),
                if (_numberMarks.containsKey(span.start))
                  ListTile(
                    leading: const Icon(Icons.clear),
                    title: Text(s.removeMark),
                    onTap: () => Navigator.pop(context, 'remove'),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (choice == null) return;
    setState(() {
      if (choice == 'remove') {
        _numberMarks.remove(span.start);
        return;
      }
      final field = switch (choice) {
        'balance' => SmsField.balance,
        'account' => SmsField.account,
        _ => SmsField.amount,
      };
      _numberMarks[span.start] = _NumberMark(span: span, field: field);
    });
  }

  Future<void> _pickWord(SmsToken token) async {
    final s = _s;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Directionality(
          textDirection: s.ar ? TextDirection.rtl : TextDirection.ltr,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(s.whatIsWord, style: Theme.of(context).textTheme.titleMedium),
                ),
                ListTile(
                  leading: const Icon(Icons.arrow_upward, color: AppConstants.errorColor),
                  title: Text(s.wordMeansDebit),
                  onTap: () => Navigator.pop(context, 'debit'),
                ),
                ListTile(
                  leading: const Icon(Icons.arrow_downward, color: AppConstants.primaryColor),
                  title: Text(s.wordMeansCredit),
                  onTap: () => Navigator.pop(context, 'credit'),
                ),
                ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: Text(s.wordMeansCategory),
                  subtitle: _categorySubtitle(s, token),
                  onTap: () => Navigator.pop(context, 'category'),
                ),
                if (_wordTypes.containsKey(token.start) || _categoryMarks.containsKey(token.start))
                  ListTile(
                    leading: const Icon(Icons.clear),
                    title: Text(s.removeMark),
                    onTap: () => Navigator.pop(context, 'remove'),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (choice == null || !mounted) return;
    if (choice == 'category') {
      await _pickCategory(token);
      return;
    }
    setState(() {
      if (choice == 'remove') {
        _wordTypes.remove(token.start);
        _categoryMarks.remove(token.start);
      } else {
        _wordTypes[token.start] = choice;
      }
    });
  }

  Widget? _categorySubtitle(SmsStrings s, SmsToken token) {
    final tag = _tagsById[_categoryMarks[token.start]];
    if (tag == null) return null;
    return Text(s.categoryApplied(tag.type == TagType.expense, tag.name));
  }

  Future<void> _pickCategory(SmsToken token) async {
    final word = SmsRuleEngine.normalizeWord(token.text);
    if (RegExp(r'\p{L}', unicode: true).allMatches(word).length < 3) {
      _snack(_s.categoryWordTooShort);
      return;
    }
    final tag = await showSmsCategoryPicker(
      context: context,
      arabic: widget.arabic,
      word: word,
    );
    if (!mounted || tag == null || tag.id == null) return;
    setState(() {
      _tagsById[tag.id!] = tag;
      _categoryMarks[token.start] = tag.id!;
    });
  }

  List<SmsReadRule> _draftNumberRules() {
    final numbers = SmsRuleEngine.findNumbers(widget.copy.body);
    final types = _wordTypes.values.toSet();
    final typeHint = types.length == 1 ? types.first : '';
    final rules = <SmsReadRule>[];
    for (final mark in _numberMarks.values) {
      final context = SmsRuleEngine.contextFor(widget.copy.body, mark.span, numbers);
      if (!context.isUseful) continue;
      rules.add(
        SmsReadRule(
          bankId: widget.copy.bankId,
          field: mark.field,
          typeHint: mark.field == SmsField.amount ? typeHint : '',
          prefix: context.prefix,
          suffix: context.suffix,
          sampleSmsId: widget.copy.smsId,
          createdAt: DateTime.now(),
        ),
      );
    }
    return rules;
  }

  List<SmsCategoryRule> _draftCategoryRules() {
    final seen = <String>{};
    final rules = <SmsCategoryRule>[];
    for (final entry in _categoryMarks.entries) {
      final word = SmsRuleEngine.normalizeWord(
        widget.copy.body.substring(entry.key, _tokenEnd(entry.key)),
      );
      if (word.isEmpty) continue;
      if (!seen.add(word.toLowerCase())) continue;
      rules.add(
        SmsCategoryRule(
          bankId: widget.copy.bankId,
          word: word,
          tagId: entry.value,
          createdAt: DateTime.now(),
        ),
      );
    }
    return rules;
  }

  List<SmsCategoryRule> _categoryRulesToDelete() {
    final keep = {for (final rule in _draftCategoryRules()) rule.word.toLowerCase()};
    final rules = <SmsCategoryRule>[];
    for (final saved in _savedCategoryRules) {
      final inMessage = SmsRuleEngine.firstExactWordIndex(widget.copy.body, saved.word) >= 0;
      if (saved.id != null && inMessage && !keep.contains(saved.word.toLowerCase())) {
        rules.add(saved);
      }
    }
    return rules;
  }

  List<SmsTypeWord> _draftTypeWords() {
    final seen = <String>{};
    final words = <SmsTypeWord>[];
    for (final entry in _wordTypes.entries) {
      final word = SmsRuleEngine.normalizeWord(
        widget.copy.body.substring(entry.key, _tokenEnd(entry.key)),
      );
      if (word.isEmpty) continue;
      final key = '${word.toLowerCase()}|${entry.value}';
      if (!seen.add(key)) continue;
      words.add(
        SmsTypeWord(
          bankId: widget.copy.bankId,
          word: word,
          typeHint: entry.value,
          createdAt: DateTime.now(),
        ),
      );
    }
    return words;
  }

  int _tokenEnd(int start) {
    for (final token in SmsRuleEngine.tokenize(widget.copy.body)) {
      if (token.start == start) return token.end;
    }
    return start;
  }

  Future<void> _persistCategoryRules() async {
    final db = DatabaseHelper.instance;
    for (final rule in _categoryRulesToDelete()) {
      final id = rule.id;
      if (id != null) await db.deleteSmsCategoryRule(id);
    }
    for (final rule in _draftCategoryRules()) {
      await db.insertSmsCategoryRule(rule);
    }
    await SyncService.instance.syncCategories(bankId: widget.copy.bankId);
  }

  Future<void> _save() async {
    final s = _s;
    final numbers = SmsRuleEngine.findNumbers(widget.copy.body);
    final hasReading = _numberMarks.isNotEmpty || _wordTypes.isNotEmpty;
    final hasCategory = _draftCategoryRules().isNotEmpty || _categoryRulesToDelete().isNotEmpty;
    if (!hasReading && !hasCategory) return;

    for (final mark in _numberMarks.values) {
      final context = SmsRuleEngine.contextFor(widget.copy.body, mark.span, numbers);
      if (!context.isUseful) {
        _snack(s.weakRule);
        return;
      }
    }

    if (!hasReading) {
      setState(() => _saving = true);
      try {
        await _persistCategoryRules();
        if (!mounted) return;
        _snack(s.categorySaved);
        Navigator.pop(context, true);
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }

    setState(() => _saving = true);
    try {
      final drafts = _draftTypeWords();
      final keep = {
        for (final word in drafts) '${word.word.toLowerCase()}|${word.typeHint}',
      };
      final wordsToDelete = <SmsTypeWord>[];
      for (final saved in _savedWords) {
        final key = '${saved.word.toLowerCase()}|${saved.typeHint}';
        final stillInMessage = SmsRuleEngine.firstIndexOfWord(widget.copy.body, saved.word) >= 0;
        if (saved.id != null && stillInMessage && !keep.contains(key)) {
          wordsToDelete.add(saved);
        }
      }
      final activated = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => RuleTesterPage(
            bankId: widget.copy.bankId,
            arabic: widget.arabic,
            draftRules: _draftNumberRules(),
            draftTypeWords: drafts,
            wordsToDelete: wordsToDelete,
            draftCategoryRules: _draftCategoryRules(),
            categoryRulesToDelete: _categoryRulesToDelete(),
            focusCopy: widget.copy,
          ),
        ),
      );
      if (!mounted) return;
      if (activated == true) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Color _colorFor(SmsToken token) {
    if (token.isNumber) {
      final mark = _numberMarks[token.start];
      if (mark == null) return const Color(0xFFFFF3CD);
      if (mark.field == SmsField.balance) return const Color(0xFFD6E6FF);
      if (mark.field == SmsField.account) return const Color(0xFFFFE0CC);
      return AppConstants.primarySurface;
    }
    if (_categoryMarks.containsKey(token.start)) return const Color(0xFFEDE4FF);
    final type = _wordTypes[token.start];
    if (type == 'debit') return const Color(0xFFFFD6D6);
    if (type == 'credit') return AppConstants.primarySurface;
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final tokens = SmsRuleEngine.tokenize(widget.copy.body);
    final drafts = _draftNumberRules();
    final typeWords = _draftTypeWords();
    final categoryRules = _draftCategoryRules();
    final reading = drafts.isEmpty && typeWords.isEmpty
        ? null
        : SmsRuleEngine.parse(widget.copy.body, drafts, typeWords: typeWords);
    final canSave = _numberMarks.isNotEmpty ||
        _wordTypes.isNotEmpty ||
        categoryRules.isNotEmpty ||
        _categoryRulesToDelete().isNotEmpty;

    return Directionality(
      textDirection: s.ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppConstants.backgroundColor,
        appBar: AppBar(title: Text(widget.bankName)),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: _saving || _loading || !canSave ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_numberMarks.isEmpty && _wordTypes.isEmpty ? s.saveRules : s.ruleTester),
            ),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(s.markHint, style: const TextStyle(color: AppConstants.textSecondary)),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: tokens.isEmpty
                          ? Text(s.noNumbers)
                          : _MessageText(
                              body: widget.copy.body,
                              tokens: tokens,
                              colorFor: _colorFor,
                              onTap: _pickToken,
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(s.preview, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(_previewText(s, reading, categoryRules)),
                  if (_numberMarks.isNotEmpty || _wordTypes.isNotEmpty || categoryRules.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    for (final mark in _numberMarks.values)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(mark.span.text),
                        subtitle: Text(s.field(mark.field)),
                      ),
                    for (final word in typeWords)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(word.word),
                        subtitle: Text(s.typeLabel(word.typeHint)),
                      ),
                    for (final rule in categoryRules)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(rule.word),
                        subtitle: Text(_categoryLine(s, rule.tagId)),
                      ),
                  ],
                ],
              ),
      ),
    );
  }

  String _categoryLine(SmsStrings s, int tagId, {bool? debit}) {
    final tag = _tagsById[tagId];
    if (tag == null) return s.missingCategory;
    final expense = tag.type == TagType.expense;
    if (debit != null && expense != debit) return s.categoryReduced(expense, tag.name);
    return s.categoryApplied(expense, tag.name);
  }

  String _previewText(SmsStrings s, SmsReading? reading, List<SmsCategoryRule> categoryRules) {
    final bool? debit = reading?.typeHint == 'debit'
        ? true
        : reading?.typeHint == 'credit'
            ? false
            : null;
    final categoryLines = [
      for (final rule in categoryRules) _categoryLine(s, rule.tagId, debit: debit),
    ].where((line) => line.isNotEmpty);
    if (reading == null || reading.amount == null) {
      if (categoryLines.isEmpty) return s.none;
      return categoryLines.join('\n');
    }
    final type = s.typeLabel(reading.typeHint);
    final parts = <String>[
      '${s.amount}: ${reading.amount}${type.isEmpty ? '' : ' ($type)'}',
    ];
    if (reading.balance != null) parts.add('${s.balance}: ${reading.balance}');
    if (reading.account != null) parts.add('${s.account}: ${reading.account}');
    parts.addAll(categoryLines);
    return parts.join('\n');
  }
}

class _MessageText extends StatelessWidget {
  final String body;
  final List<SmsToken> tokens;
  final Color Function(SmsToken token) colorFor;
  final ValueChanged<SmsToken> onTap;

  const _MessageText({
    required this.body,
    required this.tokens,
    required this.colorFor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    var cursor = 0;
    for (final token in tokens) {
      if (token.start > cursor) {
        children.add(Text(body.substring(cursor, token.start)));
      }
      children.add(
        Material(
          color: colorFor(token),
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: () => onTap(token),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                token.text,
                style: TextStyle(fontWeight: token.isNumber || colorFor(token) != Colors.transparent ? FontWeight.w700 : FontWeight.w400),
              ),
            ),
          ),
        ),
      );
      cursor = token.end;
    }
    if (cursor < body.length) {
      children.add(Text(body.substring(cursor)));
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}
