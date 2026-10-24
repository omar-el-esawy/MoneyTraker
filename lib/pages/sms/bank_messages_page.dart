import 'package:flutter/material.dart';

import 'package:money_traker/constants/app_constants.dart';
import 'package:money_traker/data/database_helper.dart';
import 'package:money_traker/model/money_source.dart';
import 'package:money_traker/pages/sms/bank_detail_page.dart';
import 'package:money_traker/services/sms_feature_store.dart';
import 'package:money_traker/services/sync_service.dart';
import 'package:money_traker/sms/sms_models.dart';
import 'package:money_traker/sms/sms_strings.dart';
import 'package:money_traker/store/money_storage.dart';

class BankMessagesPage extends StatefulWidget {
  const BankMessagesPage({super.key});

  @override
  State<BankMessagesPage> createState() => _BankMessagesPageState();
}

class _BankMessagesPageState extends State<BankMessagesPage> {
  final _store = SmsFeatureStore.instance;
  final _db = DatabaseHelper.instance;

  SmsFeatureConfig? _config;
  List<SmsCopy> _copies = [];
  List<SmsReadRule> _rules = [];
  List<SmsTypeWord> _typeWords = [];
  List<SmsCategoryRule> _categoryRules = [];
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
    final typeWords = await _db.getSmsTypeWords();
    final categoryRules = await _db.getSmsCategoryRules();
    final sources = await MoneyStorage().getMoneySources();
    if (!mounted) return;
    setState(() {
      _config = config;
      _copies = copies;
      _rules = rules;
      _typeWords = typeWords;
      _categoryRules = categoryRules;
      _sources = sources;
      _loading = false;
    });
  }

  Future<void> _save(SmsFeatureConfig config) async {
    await _store.save(config);
    if (!mounted) return;
    setState(() => _config = config);
  }

  Future<void> _pickDate() async {
    final config = _config;
    if (config == null) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: config.startDate ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    await _save(config.copyWith(startDate: picked));
  }

  Future<void> _applyFromStart() async {
    final config = _config;
    final strings = SmsStrings(config?.arabic ?? false);
    if (config?.startDate == null) {
      _snack(strings.pickDate);
      return;
    }
    setState(() => _busy = true);
    final result = await SyncService.instance.sync(fromStartDate: true);
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

  Future<void> _addBank() async {
    final config = _config;
    if (config == null) return;
    final strings = SmsStrings(config.arabic);
    final nameEn = TextEditingController();
    final nameAr = TextEditingController();
    final sender = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: strings.ar ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          title: Text(strings.addBank),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameEn, decoration: InputDecoration(labelText: strings.nameEn)),
              TextField(controller: nameAr, decoration: InputDecoration(labelText: strings.nameAr)),
              TextField(controller: sender, decoration: InputDecoration(labelText: strings.senderHint)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(strings.cancel)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(strings.save)),
          ],
        ),
      ),
    );
    final en = nameEn.text.trim();
    final ar = nameAr.text.trim();
    final senderName = sender.text.trim();
    nameEn.dispose();
    nameAr.dispose();
    sender.dispose();
    if (saved != true || en.isEmpty || senderName.isEmpty) return;
    await _save(config.copyWith(banks: [
      ...config.banks,
      BankConfig(
        id: 'bank_${DateTime.now().millisecondsSinceEpoch}',
        nameEn: en,
        nameAr: ar.isEmpty ? en : ar,
        senders: [senderName],
      ),
    ]));
  }

  Future<void> _openBank(BankConfig bank) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BankDetailPage(bankId: bank.id)),
    );
    await _load();
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
    if (_loading || config == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final strings = SmsStrings(config.arabic);

    return Directionality(
      textDirection: strings.ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppConstants.backgroundColor,
        appBar: AppBar(
          title: Text(strings.title),
          actions: [
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _save(config.copyWith(languageCode: config.arabic ? 'en' : 'ar')),
              child: Text(strings.language),
            ),
          ],
        ),
        body: AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(strings.intro, style: const TextStyle(color: AppConstants.textSecondary)),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(strings.startDate),
                subtitle: Text(config.startDate == null ? strings.pickDate : _fmt(config.startDate!)),
                onTap: _pickDate,
              ),
              const SizedBox(height: 8),
              Text(strings.applyFromStartHint, style: const TextStyle(color: AppConstants.textSecondary)),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ? null : _applyFromStart,
                child: Text(strings.applyFromStart),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              const SizedBox(height: 20),
              Text(strings.banks, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final bank in config.banks) _bankRow(strings, bank),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _addBank,
                  icon: const Icon(Icons.add),
                  label: Text(strings.addBank),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bankRow(SmsStrings strings, BankConfig bank) {
    final messageCount = _copies.where((copy) => copy.bankId == bank.id).length;
    final ruleCount = _rules.where((rule) => rule.bankId == bank.id).length +
        _typeWords.where((word) => word.bankId == bank.id).length +
        _categoryRules.where((rule) => rule.bankId == bank.id).length;
    String? sourceName;
    for (final source in _sources) {
      if (source.id == bank.sourceId) sourceName = source.name;
    }

    return Card(
      child: ListTile(
        title: Text(bank.nameFor(strings.ar)),
        subtitle: Text(
          [
            if (!bank.enabled) strings.off,
            sourceName ?? strings.noMoneySource,
            strings.messagesCount(messageCount),
            strings.rulesCount(ruleCount),
          ].join(' · '),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openBank(bank),
      ),
    );
  }
}
