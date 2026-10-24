import 'package:flutter/material.dart';

import 'package:money_traker/constants/app_constants.dart';
import 'package:money_traker/data/database_helper.dart';
import 'package:money_traker/model/money_source.dart';
import 'package:money_traker/model/tag.dart';
import 'package:money_traker/domain/entities/transaction_entity.dart';
import 'package:money_traker/pages/sms/message_marker_page.dart';
import 'package:money_traker/pages/sms/rule_tester_page.dart';
import 'package:money_traker/services/sms_feature_store.dart';
import 'package:money_traker/services/sms_source_applier.dart';
import 'package:money_traker/services/sync_service.dart';
import 'package:money_traker/sms/sms_models.dart';
import 'package:money_traker/sms/sms_strings.dart';
import 'package:money_traker/store/money_storage.dart';

class BankDetailPage extends StatefulWidget {
  final String bankId;

  const BankDetailPage({super.key, required this.bankId});

  @override
  State<BankDetailPage> createState() => _BankDetailPageState();
}

class _BankDetailPageState extends State<BankDetailPage> {
  final _store = SmsFeatureStore.instance;
  final _db = DatabaseHelper.instance;

  SmsFeatureConfig? _config;
  BankConfig? _bank;
  List<SmsCopy> _copies = [];
  List<SmsReadRule> _rules = [];
  List<SmsTypeWord> _typeWords = [];
  List<SmsCategoryRule> _categoryRules = [];
  Map<int, Tag> _tags = {};
  List<MoneySource> _sources = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await _store.load();
    final copies = await _db.getSmsCopies();
    final rules = await _db.getSmsRules();
    final typeWords = await _db.getSmsTypeWords(bankId: widget.bankId);
    final categoryRules = await _db.getSmsCategoryRules(bankId: widget.bankId);
    final tags = await MoneyStorage().getTags();
    final sources = await MoneyStorage().getMoneySources();
    BankConfig? bank;
    for (final item in config.banks) {
      if (item.id == widget.bankId) bank = item;
    }
    if (!mounted) return;
    if (bank == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _config = config;
      _bank = bank;
      _copies = copies.where((copy) => copy.bankId == widget.bankId).toList();
      _rules = rules.where((rule) => rule.bankId == widget.bankId).toList();
      _typeWords = typeWords;
      _categoryRules = categoryRules;
      _tags = {for (final tag in tags) if (tag.id != null) tag.id!: tag};
      _sources = sources;
      _loading = false;
    });
  }

  Future<void> _saveConfig(SmsFeatureConfig config) async {
    await _store.save(config);
    await _load();
  }

  Future<void> _updateBank(BankConfig bank) async {
    final config = _config;
    if (config == null) return;
    await _saveConfig(config.copyWith(
      banks: [
        for (final item in config.banks) item.id == bank.id ? bank : item,
      ],
    ));
  }

  Future<void> _applyFromStart() async {
    final config = _config;
    final strings = SmsStrings(config?.arabic ?? false);
    if (config?.startDate == null) {
      _snack(strings.pickDate);
      return;
    }
    setState(() => _busy = true);
    final result = await SyncService.instance.sync(
      fromStartDate: true,
      bankId: widget.bankId,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
    if (!mounted) return;
    if (!result.supported) {
      _snack(strings.androidOnly);
    } else if (!result.permissionGranted) {
      _snack(strings.permissionDenied);
    } else {
      _snack(strings.resultLine(
        copied: result.copied,
        parsed: result.parsed,
        appliedToSource: result.appliedToSource,
        skipped: result.skipped,
        unmatched: result.unmatched,
        missingSource: result.missingSource,
        updated: result.updated,
        error: result.error,
      ));
    }
  }

  Future<void> _addSender() async {
    final bank = _bank;
    final config = _config;
    if (bank == null || config == null) return;
    final strings = SmsStrings(config.arabic);
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: strings.ar ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          title: Text(strings.addSender),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(labelText: strings.senderHint),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(strings.cancel)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(strings.save)),
          ],
        ),
      ),
    );
    final sender = controller.text.trim();
    controller.dispose();
    if (saved != true || sender.isEmpty) return;
    await _updateBank(bank.copyWith(senders: [...bank.senders, sender]));
  }

  Future<void> _deleteBank() async {
    final bank = _bank;
    final config = _config;
    if (bank == null || config == null) return;
    final strings = SmsStrings(config.arabic);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: strings.ar ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          title: Text(strings.deleteBank),
          content: Text(strings.deleteBankConfirm(bank.nameFor(strings.ar))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(strings.cancel)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(strings.delete)),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await _store.save(config.copyWith(
      banks: config.banks.where((item) => item.id != bank.id).toList(),
    ));
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _deleteRule(SmsReadRule rule) async {
    final id = rule.id;
    if (id == null) return;
    await _db.deleteSmsRule(id);
    await SmsFeatureStore.instance.bumpRuleVersion(rule.bankId);
    await _db.reopenUnreadable(rule.bankId);
    await _load();
  }

  Future<void> _markNotApplied(SmsCopy copy) async {
    final id = copy.id;
    if (id == null || !copy.sourceApplied) return;
    final bank = _bank;
    final existing = await _db.getTransactionBySmsId(copy.smsId);
    if (bank?.sourceId != null && existing != null) {
      await SmsSourceApplier.instance.apply(
        sourceId: bank!.sourceId!,
        amount: existing.amount,
        debit: existing.type != TransactionType.debit,
        date: copy.date,
        note: bank.nameEn,
      );
    }
    await _db.markSourceApplied(id, applied: false);
    await SyncService.instance.syncCategories(bankId: copy.bankId);
    await _load();
  }

  Future<void> _deleteCategoryRule(SmsCategoryRule rule) async {
    final id = rule.id;
    if (id == null) return;
    await _db.deleteSmsCategoryRule(id);
    await SyncService.instance.syncCategories(bankId: rule.bankId);
    await _load();
  }

  Future<void> _deleteTypeWord(SmsTypeWord word) async {
    final id = word.id;
    if (id == null) return;
    await _db.deleteSmsTypeWord(id);
    await SmsFeatureStore.instance.bumpRuleVersion(word.bankId);
    await _db.reopenUnreadable(word.bankId);
    await _load();
  }

  Future<void> _openTester() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RuleTesterPage(
          bankId: widget.bankId,
          arabic: _config?.arabic ?? false,
          draftRules: const [],
          draftTypeWords: const [],
        ),
      ),
    );
    await _load();
  }

  Future<void> _reprocess() async {
    final strings = SmsStrings(_config?.arabic ?? false);
    setState(() => _busy = true);
    final result = await SyncService.instance.reprocessFromRaw(bankId: widget.bankId);
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
    if (!mounted) return;
    _snack(strings.resultLine(
      copied: result.copied,
      parsed: result.parsed,
      appliedToSource: result.appliedToSource,
      skipped: result.skipped,
      unmatched: result.unmatched,
      missingSource: result.missingSource,
      updated: result.updated,
      error: result.error,
    ));
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _fmt(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final bank = _bank;
    if (_loading || config == null || bank == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final strings = SmsStrings(config.arabic);
    MoneySource? source;
    for (final item in _sources) {
      if (item.id == bank.sourceId) source = item;
    }

    return Directionality(
      textDirection: strings.ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppConstants.backgroundColor,
        appBar: AppBar(
          title: Text(bank.nameFor(strings.ar)),
          actions: [
            IconButton(
              tooltip: strings.deleteBank,
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteBank,
            ),
          ],
        ),
        body: AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(bank.nameFor(strings.ar)),
                value: bank.enabled,
                onChanged: (value) => _updateBank(bank.copyWith(enabled: value)),
              ),
              Text(strings.banksHint, style: const TextStyle(color: AppConstants.textSecondary)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final sender in bank.senders)
                    InputChip(
                      label: Text(sender),
                      onDeleted: () => _updateBank(
                        bank.copyWith(senders: bank.senders.where((item) => item != sender).toList()),
                      ),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: Text(strings.addSender),
                    onPressed: _addSender,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int?>(
                key: ValueKey('source-${bank.id}-${bank.sourceId}'),
                initialValue: _sources.any((item) => item.id == bank.sourceId) ? bank.sourceId : null,
                decoration: InputDecoration(labelText: strings.moneySource),
                items: [
                  DropdownMenuItem<int?>(
                    value: null,
                    child: Text(strings.noMoneySource),
                  ),
                  for (final item in _sources)
                    if (item.id != null)
                      DropdownMenuItem<int?>(
                        value: item.id,
                        child: Text('${item.name} (${item.amount})'),
                      ),
                ],
                onChanged: _sources.isEmpty
                    ? null
                    : (value) async {
                        await _updateBank(
                          value == null ? bank.copyWith(clearSourceId: true) : bank.copyWith(sourceId: value),
                        );
                        if (value != null) {
                          await _applyFromStart();
                        }
                      },
              ),
              if (_sources.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(strings.noSourcesYet, style: const TextStyle(color: AppConstants.textSecondary, fontSize: 12)),
                )
              else if (source != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('${source.name}: ${source.amount}'),
                ),
              const SizedBox(height: 16),
              Text(strings.applyFromStartHint, style: const TextStyle(color: AppConstants.textSecondary)),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ? null : _applyFromStart,
                child: Text(strings.applyFromStart),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy || (_rules.isEmpty && _typeWords.isEmpty) ? null : _openTester,
                child: Text(strings.testRules),
              ),
              const SizedBox(height: 8),
              Text(strings.reprocessHint, style: const TextStyle(color: AppConstants.textSecondary)),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : _reprocess,
                child: Text(strings.reprocess),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('${strings.ruleVersion}: ${bank.ruleVersion}'),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              const SizedBox(height: 24),
              Text(strings.rules, style: Theme.of(context).textTheme.titleMedium),
              if (_rules.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(strings.openToMark, style: const TextStyle(color: AppConstants.textSecondary)),
                ),
              for (final rule in _rules)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text([
                    strings.field(rule.field),
                    strings.typeLabel(rule.typeHint),
                  ].where((part) => part.isNotEmpty).join(' · ')),
                  subtitle: Text('${rule.prefix}  #  ${rule.suffix}'.trim()),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteRule(rule),
                  ),
                ),
              if (_typeWords.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(strings.typeWords, style: Theme.of(context).textTheme.titleSmall),
                for (final word in _typeWords)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(word.word),
                    subtitle: Text(strings.typeLabel(word.typeHint)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteTypeWord(word),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              Text(strings.categoryRules, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(strings.categoryRulesHint, style: const TextStyle(color: AppConstants.textSecondary)),
              if (_categoryRules.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(strings.openToMark, style: const TextStyle(color: AppConstants.textSecondary)),
                ),
              for (final rule in _categoryRules)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(rule.word),
                  subtitle: Text(_categoryLabel(strings, rule)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteCategoryRule(rule),
                  ),
                ),
              const SizedBox(height: 16),
              Text(strings.messages, style: Theme.of(context).textTheme.titleMedium),
              if (_copies.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(strings.emptyMessages, style: const TextStyle(color: AppConstants.textSecondary)),
                ),
              for (final copy in _copies)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      children: [
                        ListTile(
                          title: Text(copy.sender),
                          subtitle: Text('${copy.body}\n${_status(strings, copy)} · ${_fmt(copy.date)}'),
                          isThreeLine: true,
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => MessageMarkerPage(
                                  copy: copy,
                                  arabic: config.arabic,
                                  bankName: bank.nameFor(strings.ar),
                                ),
                              ),
                            );
                            await _load();
                          },
                        ),
                        SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          title: Text(copy.sourceApplied ? strings.applied : strings.notApplied),
                          value: copy.sourceApplied,
                          onChanged: copy.sourceApplied
                              ? (value) {
                                  if (!value) _markNotApplied(copy);
                                }
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _categoryLabel(SmsStrings strings, SmsCategoryRule rule) {
    final tag = _tags[rule.tagId];
    if (tag == null) return strings.missingCategory;
    final kind = tag.type == TagType.expense ? strings.expenses : strings.income;
    return '$kind · ${tag.name}';
  }

  String _status(SmsStrings strings, SmsCopy copy) {
    return switch (copy.status) {
      SmsCopyStatus.parsed => strings.parsed,
      SmsCopyStatus.unreadable => strings.unreadable,
      SmsCopyStatus.pending => strings.pending,
    };
  }
}
