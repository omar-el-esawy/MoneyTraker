import 'package:flutter/material.dart';

import 'package:money_traker/constants/app_constants.dart';
import 'package:money_traker/data/database_helper.dart';
import 'package:money_traker/model/tag.dart';
import 'package:money_traker/services/sms_category_applier.dart';
import 'package:money_traker/services/sms_feature_store.dart';
import 'package:money_traker/services/sync_service.dart';
import 'package:money_traker/sms/sms_models.dart';
import 'package:money_traker/sms/sms_rule_engine.dart';
import 'package:money_traker/sms/sms_strings.dart';
import 'package:money_traker/store/money_storage.dart';

class RuleTesterPage extends StatefulWidget {
  final String bankId;
  final bool arabic;
  final List<SmsReadRule> draftRules;
  final List<SmsTypeWord> draftTypeWords;
  final List<SmsTypeWord> wordsToDelete;
  final List<SmsCategoryRule> draftCategoryRules;
  final List<SmsCategoryRule> categoryRulesToDelete;
  final SmsCopy? focusCopy;

  const RuleTesterPage({
    super.key,
    required this.bankId,
    required this.arabic,
    required this.draftRules,
    required this.draftTypeWords,
    this.wordsToDelete = const [],
    this.draftCategoryRules = const [],
    this.categoryRulesToDelete = const [],
    this.focusCopy,
  });

  @override
  State<RuleTesterPage> createState() => _RuleTesterPageState();
}

class _RuleTesterPageState extends State<RuleTesterPage> {
  SmsRuleTestReport? _report;
  SmsReading? _focusReading;
  String? _sourceName;
  List<SmsCategoryRule> _categoryRules = [];
  List<Tag> _tags = [];
  bool _loading = true;
  bool _saving = false;

  SmsStrings get _s => SmsStrings(widget.arabic);

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final config = await SmsFeatureStore.instance.load();
    BankConfig? bank;
    for (final item in config.banks) {
      if (item.id == widget.bankId) bank = item;
    }
    final existingRules = (await DatabaseHelper.instance.getSmsRules())
        .where((rule) => rule.bankId == widget.bankId)
        .toList();
    final existingWords = await DatabaseHelper.instance.getSmsTypeWords(bankId: widget.bankId);
    final deleteKeys = {
      for (final word in widget.wordsToDelete) '${word.word.toLowerCase()}|${word.typeHint}',
    };
    final words = <SmsTypeWord>[
      ...existingWords.where((word) => !deleteKeys.contains('${word.word.toLowerCase()}|${word.typeHint}')),
      ...widget.draftTypeWords,
    ];
    final rules = [...existingRules, ...widget.draftRules];
    final deleteCategoryIds = {for (final rule in widget.categoryRulesToDelete) rule.id};
    final draftWords = {for (final rule in widget.draftCategoryRules) rule.word.toLowerCase()};
    final existingCategories = await DatabaseHelper.instance.getSmsCategoryRules(bankId: widget.bankId);
    final categoryRules = [
      ...existingCategories.where((rule) =>
          !deleteCategoryIds.contains(rule.id) && !draftWords.contains(rule.word.toLowerCase())),
      ...widget.draftCategoryRules,
    ];
    final tags = await MoneyStorage().getTags();
    final corpus = await DatabaseHelper.instance.getRawSms();
    final report = SmsRuleEngine.test(
      corpus: corpus,
      rules: rules,
      typeWords: words,
      senders: bank?.senders ?? const [],
    );
    String? sourceName;
    if (bank?.sourceId != null) {
      final sources = await MoneyStorage().getMoneySources();
      for (final source in sources) {
        if (source.id == bank!.sourceId) sourceName = source.name;
      }
    }
    if (!mounted) return;
    setState(() {
      _report = report;
      _sourceName = sourceName;
      _categoryRules = categoryRules;
      _tags = tags;
      _focusReading = widget.focusCopy == null
          ? null
          : SmsRuleEngine.parse(widget.focusCopy!.body, rules, typeWords: words);
      _loading = false;
    });
  }

  Future<void> _activate() async {
    final report = _report;
    if (report == null || report.tooGeneric) return;
    setState(() => _saving = true);
    try {
      final db = DatabaseHelper.instance;
      for (final rule in widget.draftRules) {
        await db.insertSmsRule(rule);
      }
      for (final word in widget.wordsToDelete) {
        final id = word.id;
        if (id != null) await db.deleteSmsTypeWord(id);
      }
      for (final word in widget.draftTypeWords) {
        await db.insertSmsTypeWord(word);
      }
      for (final rule in widget.categoryRulesToDelete) {
        final id = rule.id;
        if (id != null) await db.deleteSmsCategoryRule(id);
      }
      for (final rule in widget.draftCategoryRules) {
        await db.insertSmsCategoryRule(rule);
      }
      final changing = widget.draftRules.isNotEmpty ||
          widget.draftTypeWords.isNotEmpty ||
          widget.wordsToDelete.isNotEmpty;
      if (changing) {
        await SmsFeatureStore.instance.bumpRuleVersion(widget.bankId);
      }
      await db.reopenUnreadable(widget.bankId);
      await SyncService.instance.reprocessFromRaw(bankId: widget.bankId);
      await SyncService.instance.applyUnmarked(bankId: widget.bankId);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _outcome(SmsReading reading, DateTime date, String body) {
    final base = _s.outcome(
      typeHint: reading.typeHint,
      amount: reading.amount!,
      date: date,
      sourceName: _sourceName,
    );
    final category = _categoryLine(body, reading.typeHint == 'debit');
    if (category == null) return base;
    return '$base\n$category';
  }

  String? _categoryLine(String body, bool debit) {
    final choice = SmsCategoryApplier.instance.match(
      body: body,
      debit: debit,
      rules: _categoryRules,
      tags: _tags,
    );
    if (choice == null) return null;
    final expense = choice.tag.type == TagType.expense;
    if (choice.reduces) return _s.categoryReduced(expense, choice.tag.name);
    return _s.categoryApplied(expense, choice.tag.name);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final report = _report;
    final focus = widget.focusCopy;
    final others = report == null
        ? const <SmsRuleTestHit>[]
        : report.sampleHits
            .where((hit) => focus == null || hit.smsId != focus.smsId)
            .toList();
    return Directionality(
      textDirection: s.ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppConstants.backgroundColor,
        appBar: AppBar(title: Text(s.ruleTester)),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: _saving || _loading || report == null || report.tooGeneric ? null : _activate,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(s.activateRule),
            ),
          ),
        ),
        body: _loading || report == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(s.ruleTesterHint, style: const TextStyle(color: AppConstants.textSecondary)),
                  if (focus != null && _focusReading != null) ...[
                    const SizedBox(height: 16),
                    Text(s.thisMessage, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _OutcomeCard(
                      reading: _focusReading!,
                      body: focus.body,
                      sender: focus.sender,
                      outcome: _focusReading!.isComplete ? _outcome(_focusReading!, focus.date, focus.body) : s.incompleteReading(_focusReading!),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    s.matchedLine(report.matched, report.total),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (report.foreignMatches > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('${s.foreignMatches}: ${report.foreignMatches}'),
                    ),
                  if (report.tooGeneric) ...[
                    const SizedBox(height: 12),
                    Text(s.cannotActivate, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
                    for (final reason in report.reasons)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(s.genericReason(reason)),
                      ),
                  ],
                  const SizedBox(height: 16),
                  Text(s.otherMessages, style: Theme.of(context).textTheme.titleMedium),
                  if (others.isEmpty && (focus == null || _focusReading?.isComplete != true))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(s.noHits, style: const TextStyle(color: AppConstants.textSecondary)),
                    ),
                  for (final hit in others.take(20))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _OutcomeCard(
                        reading: hit.reading,
                        body: hit.body,
                        sender: hit.sender,
                        outcome: _outcome(hit.reading, hit.date, hit.body),
                        compact: true,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _OutcomeCard extends StatelessWidget {
  final SmsReading reading;
  final String body;
  final String sender;
  final String outcome;
  final bool compact;

  const _OutcomeCard({
    required this.reading,
    required this.body,
    required this.sender,
    required this.outcome,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final debit = reading.typeHint == 'debit';
    final complete = reading.isComplete;
    final color = !complete
        ? AppConstants.textSecondary
        : debit
            ? AppConstants.errorColor
            : AppConstants.primaryColor;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              outcome,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 16 : 18,
                  ),
            ),
            const SizedBox(height: 8),
            Text(sender, style: const TextStyle(color: AppConstants.textSecondary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(body, style: const TextStyle(color: AppConstants.textPrimary)),
          ],
        ),
      ),
    );
  }
}
