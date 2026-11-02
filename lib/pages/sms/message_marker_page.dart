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

class _WordMark {
  final int start;
  final int end;
  final String typeHint;

  const _WordMark({
    required this.start,
    required this.end,
    required this.typeHint,
  });
}

class _CategoryMark {
  final int start;
  final int end;
  final int tagId;

  const _CategoryMark({
    required this.start,
    required this.end,
    required this.tagId,
  });
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
  final Map<int, _WordMark> _wordMarks = {};
  final Map<int, _CategoryMark> _categoryMarks = {};
  List<SmsTypeWord> _savedWords = [];
  List<SmsCategoryRule> _savedCategoryRules = [];
  Map<int, Tag> _tagsById = {};
  String? _markMode;
  int? _activeCategoryTagId;
  bool _saving = false;
  bool _loading = true;

  SmsStrings get _s => SmsStrings(widget.arabic);

  @override
  void initState() {
    super.initState();
    _loadSavedWords();
  }

  Future<void> _loadSavedWords() async {
    final words = await DatabaseHelper.instance.getSmsTypeWords(
      bankId: widget.copy.bankId,
    );
    final categoryRules = await DatabaseHelper.instance.getSmsCategoryRules(
      bankId: widget.copy.bankId,
    );
    final tags = await MoneyStorage().getTags();
    if (!mounted) return;
    setState(() {
      _savedWords = words;
      _savedCategoryRules = categoryRules;
      _tagsById = {
        for (final tag in tags)
          if (tag.id != null) tag.id!: tag,
      };
      final savedTypes = [...words]
        ..sort((a, b) => b.word.length.compareTo(a.word.length));
      for (final saved in savedTypes) {
        final pattern = saved.pattern;
        if (pattern != null && pattern.tokenCount == SmsRuleEngine.tokenize(widget.copy.body).length) {
          final tokens = SmsRuleEngine.tokenize(widget.copy.body);
          for (final selected in pattern.words) {
            final token = tokens[selected.index];
            _wordMarks[token.start] = _WordMark(
              start: token.start,
              end: token.end,
              typeHint: saved.typeHint,
            );
          }
          continue;
        }
        final hit = SmsRuleEngine.locateText(widget.copy.body, saved.word);
        if (hit == null) continue;
        final covered = _wordMarks.values.any(
          (mark) =>
              hit.start >= mark.start &&
              hit.end <= mark.end &&
              mark.end - mark.start > hit.end - hit.start,
        );
        if (covered) continue;
        _wordMarks.removeWhere(
          (_, mark) => mark.start >= hit.start && mark.end <= hit.end,
        );
        _wordMarks[hit.start] = _WordMark(
          start: hit.start,
          end: hit.end,
          typeHint: saved.typeHint,
        );
      }
      final savedCategories = [...categoryRules]
        ..sort((a, b) => b.word.length.compareTo(a.word.length));
      for (final saved in savedCategories) {
        final pattern = saved.pattern;
        if (pattern != null && pattern.tokenCount == SmsRuleEngine.tokenize(widget.copy.body).length) {
          final tokens = SmsRuleEngine.tokenize(widget.copy.body);
          for (final selected in pattern.words) {
            final token = tokens[selected.index];
            _categoryMarks[token.start] = _CategoryMark(
              start: token.start,
              end: token.end,
              tagId: saved.tagId,
            );
          }
          continue;
        }
        final hit = SmsRuleEngine.locateText(widget.copy.body, saved.word);
        if (hit == null) continue;
        final covered = _categoryMarks.values.any(
          (mark) =>
              hit.start >= mark.start &&
              hit.end <= mark.end &&
              mark.end - mark.start > hit.end - hit.start,
        );
        if (covered) continue;
        _categoryMarks.removeWhere(
          (_, mark) => mark.start >= hit.start && mark.end <= hit.end,
        );
        _categoryMarks[hit.start] = _CategoryMark(
          start: hit.start,
          end: hit.end,
          tagId: saved.tagId,
        );
      }

      _loading = false;
    });
  }

  SmsRulePattern? _patternForMarks(Iterable<dynamic> marks) {
    final tokens = SmsRuleEngine.tokenize(widget.copy.body);
    final selected = <SmsPatternWord>[];
    for (var index = 0; index < tokens.length; index++) {
      final token = tokens[index];
      final included = marks.any(
        (mark) => _overlaps(token.start, token.end, mark.start, mark.end),
      );
      if (!included) continue;
      final word = SmsRuleEngine.normalizeWord(token.text);
      if (word.isNotEmpty) {
        selected.add(SmsPatternWord(index: index, word: word));
      }
    }
    if (selected.isEmpty) return null;
    return SmsRulePattern(tokenCount: tokens.length, words: selected);
  }

  Future<void> _openTokenAction(SmsToken token) async {
    if (_markMode == 'debit' || _markMode == 'credit') {
      setState(() {
        final existing = _wordMarks[token.start];
        if (existing?.typeHint == _markMode) {
          _wordMarks.remove(token.start);
          return;
        }
        _categoryMarks.removeWhere(
          (_, mark) => _overlaps(token.start, token.end, mark.start, mark.end),
        );
        _wordMarks[token.start] = _WordMark(
          start: token.start,
          end: token.end,
          typeHint: _markMode!,
        );
      });
      return;
    }
    if (_markMode == 'category') {
      if (_activeCategoryTagId == null) {
        final tag = await showSmsCategoryPicker(
          context: context,
          arabic: widget.arabic,
          word: token.text,
        );
        if (!mounted || tag?.id == null) return;
        final picked = tag!;
        _tagsById[picked.id!] = picked;
        _activeCategoryTagId = picked.id;
      }
      setState(() {
        final existing = _categoryMarks[token.start];
        if (existing?.tagId == _activeCategoryTagId) {
          _categoryMarks.remove(token.start);
          return;
        }
        _wordMarks.removeWhere(
          (_, mark) => _overlaps(token.start, token.end, mark.start, mark.end),
        );
        _categoryMarks[token.start] = _CategoryMark(
          start: token.start,
          end: token.end,
          tagId: _activeCategoryTagId!,
        );
      });
      return;
    }
    await _openSelectionSheet(token.start, token.end);
  }

  bool _overlaps(int start, int end, int otherStart, int otherEnd) {
    return start < otherEnd && otherStart < end;
  }

  bool _selectionOverlapsMark(int start, int end) {
    for (final mark in _numberMarks.values) {
      if (_overlaps(start, end, mark.span.start, mark.span.end)) return true;
    }
    for (final mark in _wordMarks.values) {
      if (_overlaps(start, end, mark.start, mark.end)) return true;
    }
    for (final mark in _categoryMarks.values) {
      if (_overlaps(start, end, mark.start, mark.end)) return true;
    }
    return false;
  }

  void _removeOverlapping(int start, int end) {
    _numberMarks.removeWhere(
      (_, mark) => _overlaps(start, end, mark.span.start, mark.span.end),
    );
    _wordMarks.removeWhere(
      (_, mark) => _overlaps(start, end, mark.start, mark.end),
    );
    _categoryMarks.removeWhere(
      (_, mark) => _overlaps(start, end, mark.start, mark.end),
    );
  }

  ({int start, int end, String text})? _textInSelection(int start, int end) {
    final raw = widget.copy.body.substring(start, end);
    final text = SmsRuleEngine.normalizeWord(raw);
    final hit = SmsRuleEngine.locateText(raw, text);
    if (hit == null) return null;
    return (start: start + hit.start, end: start + hit.end, text: text);
  }

  Future<void> _openSelectionSheet(int start, int end) async {
    final s = _s;
    final selected = _textInSelection(start, end);
    final raw = widget.copy.body.substring(start, end);
    final numbers = SmsRuleEngine.findNumbers(raw);
    final number = numbers.length == 1 ? numbers.single : null;
    if (selected == null && number == null) {
      _snack(s.selectSomeText);
      return;
    }
    final overlaps = _selectionOverlapsMark(start, end);
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
                  child: Text(
                    selected == null
                        ? '${s.whatIsThis}\n${number!.text}'
                        : s.selectedTextMeans(selected.text),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (selected != null) ...[
                  ListTile(
                    leading: const Icon(
                      Icons.arrow_upward,
                      color: AppConstants.errorColor,
                    ),
                    title: Text(s.wordMeansDebit),
                    onTap: () => Navigator.pop(context, 'debit'),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.arrow_downward,
                      color: AppConstants.primaryColor,
                    ),
                    title: Text(s.wordMeansCredit),
                    onTap: () => Navigator.pop(context, 'credit'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.category_outlined),
                    title: Text(s.wordMeansCategory),
                    onTap: () => Navigator.pop(context, 'category'),
                  ),
                ],
                if (number != null) ...[
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
                ],
                if (overlaps)
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
    if (choice == 'category' && selected != null) {
      await _pickCategory(selected.start, selected.end, selected.text);
      return;
    }
    setState(() {
      if (choice == 'remove') {
        _removeOverlapping(start, end);
        return;
      }
      if (choice == 'debit' || choice == 'credit') {
        if (selected == null) return;
        _wordMarks.removeWhere(
          (_, mark) =>
              _overlaps(selected.start, selected.end, mark.start, mark.end),
        );
        _wordMarks[selected.start] = _WordMark(
          start: selected.start,
          end: selected.end,
          typeHint: choice,
        );
        return;
      }
      if (number == null) return;
      final span = SmsNumberSpan(
        start: start + number.start,
        end: start + number.end,
        text: number.text,
      );
      final field = switch (choice) {
        'balance' => SmsField.balance,
        'account' => SmsField.account,
        _ => SmsField.amount,
      };
      _numberMarks[span.start] = _NumberMark(span: span, field: field);
    });
  }

  Future<void> _pickCategory(int start, int end, String text) async {
    final tag = await showSmsCategoryPicker(
      context: context,
      arabic: widget.arabic,
      word: text,
    );
    if (!mounted || tag == null || tag.id == null) return;
    setState(() {
      _tagsById[tag.id!] = tag;
      _categoryMarks.removeWhere(
        (_, mark) => _overlaps(start, end, mark.start, mark.end),
      );
      _categoryMarks[start] = _CategoryMark(
        start: start,
        end: end,
        tagId: tag.id!,
      );
    });
  }

  List<SmsReadRule> _draftNumberRules() {
    final numbers = SmsRuleEngine.findNumbers(widget.copy.body);
    final types = _wordMarks.values.map((mark) => mark.typeHint).toSet();
    final typeHint = types.length == 1 ? types.first : '';
    final rules = <SmsReadRule>[];
    for (final mark in _numberMarks.values) {
      final context = SmsRuleEngine.contextFor(
        widget.copy.body,
        mark.span,
        numbers,
      );
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
    final rules = <SmsCategoryRule>[];
    final byTag = <int, List<_CategoryMark>>{};
    for (final mark in _categoryMarks.values) {
      byTag.putIfAbsent(mark.tagId, () => []).add(mark);
    }
    for (final entry in byTag.entries) {
      final pattern = _patternForMarks(entry.value);
      if (pattern == null) continue;
      rules.add(
        SmsCategoryRule(
          bankId: widget.copy.bankId,
          word: pattern.display,
          tagId: entry.key,
          pattern: pattern,
          createdAt: DateTime.now(),
        ),
      );
    }
    return rules;
  }

  List<SmsCategoryRule> _categoryRulesToDelete() {
    final keep = {
      for (final rule in _draftCategoryRules())
        rule.pattern?.key ?? rule.word.toLowerCase(),
    };
    final rules = <SmsCategoryRule>[];
    for (final saved in _savedCategoryRules) {
      final inMessage = SmsRuleEngine.locateRule(
            widget.copy.body,
            saved.pattern,
            saved.word,
          ) !=
          null;
      final key = saved.pattern?.key ?? saved.word.toLowerCase();
      if (saved.id != null &&
          inMessage &&
          !keep.contains(key)) {
        rules.add(saved);
      }
    }
    return rules;
  }

  List<SmsTypeWord> _draftTypeWords() {
    final words = <SmsTypeWord>[];
    final byType = <String, List<_WordMark>>{};
    for (final mark in _wordMarks.values) {
      byType.putIfAbsent(mark.typeHint, () => []).add(mark);
    }
    for (final entry in byType.entries) {
      final pattern = _patternForMarks(entry.value);
      if (pattern == null) continue;
      words.add(
        SmsTypeWord(
          bankId: widget.copy.bankId,
          word: pattern.display,
          typeHint: entry.key,
          pattern: pattern,
          createdAt: DateTime.now(),
        ),
      );
    }
    return words;
  }

  String _markedText(int start, int end) {
    return SmsRuleEngine.normalizeWord(widget.copy.body.substring(start, end));
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
    final hasReading = _numberMarks.isNotEmpty || _wordMarks.isNotEmpty;
    final hasCategory =
        _draftCategoryRules().isNotEmpty || _categoryRulesToDelete().isNotEmpty;
    if (!hasReading && !hasCategory) return;

    for (final mark in _numberMarks.values) {
      final context = SmsRuleEngine.contextFor(
        widget.copy.body,
        mark.span,
        numbers,
      );
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
        for (final word in drafts)
          '${word.pattern?.key ?? word.word.toLowerCase()}|${word.typeHint}',
      };
      final wordsToDelete = <SmsTypeWord>[];
      for (final saved in _savedWords) {
        final key =
            '${saved.pattern?.key ?? saved.word.toLowerCase()}|${saved.typeHint}';
        final stillInMessage =
            SmsRuleEngine.locateRule(widget.copy.body, saved.pattern, saved.word) != null;
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

  Color? _colorAt(int index) {
    for (final mark in _numberMarks.values) {
      if (index >= mark.span.start && index < mark.span.end) {
        if (mark.field == SmsField.balance) return const Color(0xFFD6E6FF);
        if (mark.field == SmsField.account) return const Color(0xFFFFE0CC);
        return AppConstants.primarySurface;
      }
    }
    for (final mark in _categoryMarks.values) {
      if (index >= mark.start && index < mark.end)
        return const Color(0xFFEDE4FF);
    }
    for (final mark in _wordMarks.values) {
      if (index < mark.start || index >= mark.end) continue;
      if (mark.typeHint == 'debit') return const Color(0xFFFFD6D6);
      if (mark.typeHint == 'credit') return AppConstants.primarySurface;
    }
    final numbers = SmsRuleEngine.findNumbers(widget.copy.body);
    for (final number in numbers) {
      if (index >= number.start && index < number.end) {
        return const Color(0xFFFFF3CD);
      }
    }
    return null;
  }

  List<TextSpan> _bodySpans(TextStyle base) {
    final body = widget.copy.body;
    if (body.isEmpty) return [TextSpan(text: '', style: base)];
    final spans = <TextSpan>[];
    var start = 0;
    var color = _colorAt(0);
    for (var i = 1; i <= body.length; i++) {
      final next = i == body.length ? null : _colorAt(i);
      if (i != body.length && next == color) continue;
      spans.add(
        TextSpan(
          text: body.substring(start, i),
          style: base.copyWith(
            backgroundColor: color,
            fontWeight: color == null ? FontWeight.w400 : FontWeight.w700,
          ),
        ),
      );
      start = i;
      color = next;
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final drafts = _draftNumberRules();
    final typeWords = _draftTypeWords();
    final categoryRules = _draftCategoryRules();
    final reading = drafts.isEmpty && typeWords.isEmpty
        ? null
        : SmsRuleEngine.parse(widget.copy.body, drafts, typeWords: typeWords);
    final canSave =
        _numberMarks.isNotEmpty ||
        _wordMarks.isNotEmpty ||
        categoryRules.isNotEmpty ||
        _categoryRulesToDelete().isNotEmpty;
    final bodyStyle =
        Theme.of(context).textTheme.bodyLarge ?? const TextStyle();

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
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _numberMarks.isEmpty && _wordMarks.isEmpty
                          ? s.saveRules
                          : s.ruleTester,
                    ),
            ),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    s.markHint,
                    style: const TextStyle(color: AppConstants.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(s.wordMeansDebit),
                        selected: _markMode == 'debit',
                        onSelected: (selected) => setState(() {
                          _markMode = selected ? 'debit' : null;
                          _activeCategoryTagId = null;
                        }),
                      ),
                      ChoiceChip(
                        label: Text(s.wordMeansCredit),
                        selected: _markMode == 'credit',
                        onSelected: (selected) => setState(() {
                          _markMode = selected ? 'credit' : null;
                          _activeCategoryTagId = null;
                        }),
                      ),
                      ChoiceChip(
                        label: Text(s.wordMeansCategory),
                        selected: _markMode == 'category',
                        onSelected: (selected) => setState(() {
                          _markMode = selected ? 'category' : null;
                          _activeCategoryTagId = null;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.copy.body.isEmpty)
                            Text(s.noNumbers)
                          else
                            Wrap(
                              spacing: 6,
                              runSpacing: 8,
                              children: [
                                for (final token in SmsRuleEngine.tokenize(widget.copy.body))
                                  _tokenChip(token),
                              ],
                            ),
                          const SizedBox(height: 16),
                          if (widget.copy.body.isNotEmpty)
                            SelectableText.rich(
                              TextSpan(
                                style: bodyStyle,
                                children: _bodySpans(bodyStyle),
                              ),
                              contextMenuBuilder: (context, editableTextState) {
                                final value =
                                    editableTextState.textEditingValue;
                                final selection = value.selection;
                                final items =
                                    editableTextState.contextMenuButtonItems;
                                if (!selection.isValid ||
                                    selection.isCollapsed) {
                                  return AdaptiveTextSelectionToolbar.buttonItems(
                                    anchors:
                                        editableTextState.contextMenuAnchors,
                                    buttonItems: items,
                                  );
                                }
                                final start = selection.start;
                                final end = selection.end;
                                return AdaptiveTextSelectionToolbar.buttonItems(
                                  anchors: editableTextState.contextMenuAnchors,
                                  buttonItems: [
                                    ContextMenuButtonItem(
                                      label: s.markThisText,
                                      onPressed: () {
                                        ContextMenuController.removeAny();
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                              if (!mounted) return;
                                              _openSelectionSheet(start, end);
                                            });
                                      },
                                    ),
                                    ...items,
                                  ],
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    s.preview,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(_previewText(s, reading, categoryRules)),
                  if (_numberMarks.isNotEmpty ||
                      _wordMarks.isNotEmpty ||
                      categoryRules.isNotEmpty) ...[
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

  Widget _tokenChip(SmsToken token) {
    final type = _wordMarks[token.start];
    final category = _categoryMarks[token.start];
    final selected = type != null || category != null;
    final color = type?.typeHint == 'debit'
        ? const Color(0xFFFFD6D6)
        : type?.typeHint == 'credit'
        ? AppConstants.primarySurface
        : category != null
        ? const Color(0xFFEDE4FF)
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    return GestureDetector(
      onTap: () => _openTokenAction(token),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          token.text,
          style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w400),
        ),
      ),
    );
  }

  String _categoryLine(SmsStrings s, int tagId, {bool? debit}) {
    final tag = _tagsById[tagId];
    if (tag == null) return s.missingCategory;
    final expense = tag.type == TagType.expense;
    if (debit != null && expense != debit) {
      return s.categoryReduced(expense, tag.name);
    }
    return s.categoryApplied(expense, tag.name);
  }

  String _previewText(
    SmsStrings s,
    SmsReading? reading,
    List<SmsCategoryRule> categoryRules,
  ) {
    final bool? debit = reading?.typeHint == 'debit'
        ? true
        : reading?.typeHint == 'credit'
        ? false
        : null;
    final categoryLines = [
      for (final rule in categoryRules)
        _categoryLine(s, rule.tagId, debit: debit),
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
