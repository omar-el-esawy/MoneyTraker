import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:money_traker/constants/app_constants.dart';
import 'package:money_traker/model/money_source.dart';
import 'package:money_traker/pages/sms_templates/sms_template_bank_page.dart';
import 'package:money_traker/pages/sms_templates/sms_template_operations_page.dart';
import 'package:money_traker/services/sms_template_sync_service.dart';
import 'package:money_traker/sms/template_engine/sms_template_bank_presets.dart';
import 'package:money_traker/sms/template_engine/sms_template_mobile_store.dart';
import 'package:money_traker/store/money_storage.dart';

class SmsTemplatesPage extends StatefulWidget {
  const SmsTemplatesPage({super.key});

  @override
  State<SmsTemplatesPage> createState() => _SmsTemplatesPageState();
}

class _SmsTemplatesPageState extends State<SmsTemplatesPage> {
  final _store = SmsTemplateMobileStore.instance;
  bool _loading = true;
  bool _busy = false;
  bool _enabled = false;
  DateTime? _activatedAt;
  List<SmsTemplateBank> _banks = const [];
  List<SmsTemplateStoredMessage> _messages = const [];
  List<SmsTemplateApplication> _applications = const [];
  List<MoneySource> _sources = const [];
  Map<String, int> _templateCounts = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await _store.isEnabled();
    final activatedAt = enabled
        ? await _store.ensureActivatedAt()
        : await _store.activatedAt();
    final banks = await _store.getBanks();
    final templates = await _store.getTemplates();
    final messages = await _store.getMessages();
    final applications = await _store.getApplications();
    final sources = await MoneyStorage().getMoneySources();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _activatedAt = activatedAt;
      _banks = banks;
      _messages = messages;
      _applications = applications;
      _sources = sources;
      _templateCounts = {
        for (final bank in banks)
          bank.id: templates
              .where((template) => template.bankId == bank.id)
              .length,
      };
      _loading = false;
    });
  }

  String _activationLabel() {
    final date = _activatedAt;
    if (date == null) return 'today';
    return DateFormat('d MMM yyyy').format(date);
  }

  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    final result = await SmsTemplateSyncService.instance.setEnabled(value);
    if (!mounted) return;
    final activatedAt = result == SmsTemplateEnableResult.enabled
        ? await _store.activatedAt()
        : _activatedAt;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _enabled = result == SmsTemplateEnableResult.enabled;
      _activatedAt = activatedAt;
    });
    if (result == SmsTemplateEnableResult.oldSystemActive) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bank messages is still active',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              const Text(
                'Turn off every bank in the old Bank messages section first. '
                'This prevents the same SMS from changing your balance twice.',
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _sync() async {
    setState(() => _busy = true);
    final result = await SmsTemplateSyncService.instance.sync();
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.statusMessage)));
  }

  Future<void> _addBank() async {
    final availablePresets = SmsTemplateBankPreset.all.where((preset) {
      return !_banks.any(
        (bank) =>
            bank.id == 'sms_v2_${preset.id}' ||
            bank.name.trim().toLowerCase() == preset.name.toLowerCase(),
      );
    }).toList();

    final result = await showModalBottomSheet<_AddBankResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _AddBankSheet(
        presets: availablePresets,
        sources: _sources,
        initialPresetId: availablePresets.isEmpty
            ? SmsTemplateBankPreset.customId
            : null,
      ),
    );
    if (result == null || !mounted) return;
    final preset = availablePresets
        .where((item) => item.id == result.presetId)
        .firstOrNull;
    final isCustom = result.presetId == SmsTemplateBankPreset.customId;
    if (preset == null &&
        (!isCustom || result.name.isEmpty || result.sender.isEmpty)) {
      return;
    }
    final bank = SmsTemplateBank(
      id: preset == null
          ? 'sms_v2_${DateTime.now().microsecondsSinceEpoch}'
          : 'sms_v2_${preset.id}',
      name: preset?.name ?? result.name,
      senders: preset?.senders ?? [result.sender],
      sourceId: result.sourceId,
      createdAt: DateTime.now(),
    );
    final conflict = await _store.saveBank(bank);
    if (conflict != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(conflict.message)));
      return;
    }
    await _load();
    if (!mounted) return;
    await _openBank(bank);
  }

  Future<void> _openBank(SmsTemplateBank bank) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SmsTemplateBankPage(bankId: bank.id)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final unrecognized = _messages
        .where((item) => item.status == SmsTemplateMessageStatus.unrecognized)
        .length;
    final activeApplications = _applications
        .where((item) => !item.undone)
        .length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Templates'),
        actions: [
          IconButton(
            tooltip: 'Balance changes',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SmsTemplateOperationsPage(),
                ),
              );
              await _load();
            },
            icon: const Icon(Icons.receipt_long_outlined),
          ),
        ],
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _addBank,
        icon: const Icon(Icons.add),
        label: const Text('Add bank'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            if (kIsWeb)
              const _NoticeCard(
                icon: Icons.phone_android,
                text:
                    'This mobile section reads real SMS on Android. Use an Android device to test it.',
              ),
            Card(
              color: _enabled
                  ? AppConstants.primarySurface
                  : AppConstants.surfaceColor,
              child: SwitchListTile(
                value: _enabled,
                onChanged: _busy || kIsWeb ? null : _toggle,
                secondary: Icon(
                  _enabled
                      ? Icons.mark_email_read_outlined
                      : Icons.sms_failed_outlined,
                  color: _enabled
                      ? AppConstants.primaryColor
                      : AppConstants.textSecondary,
                ),
                title: Text(_enabled ? 'Reading is on' : 'Reading is off'),
                subtitle: Text(
                  _enabled
                      ? 'Reading messages from ${_activationLabel()}. New matches can update their money source.'
                      : 'No SMS is read or applied while this is off.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    value:
                        '${_templateCounts.values.fold<int>(0, (a, b) => a + b)}',
                    label: 'Templates',
                    icon: Icons.auto_awesome_motion_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricCard(
                    value: '$unrecognized',
                    label: 'Need teaching',
                    icon: Icons.school_outlined,
                    alert: unrecognized > 0,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricCard(
                    value: '$activeApplications',
                    label: 'Changes',
                    icon: Icons.swap_vert,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy || !_enabled ? null : _sync,
                icon: const Icon(Icons.sync),
                label: const Text('Read new messages now'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 24, 4, 10),
              child: Text(
                'YOUR BANKS',
                style: TextStyle(
                  color: AppConstants.textSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8,
                  fontSize: 12,
                ),
              ),
            ),
            if (_banks.isEmpty)
              const _NoticeCard(
                icon: Icons.account_balance_outlined,
                text: 'Add a bank, then teach its first message template.',
              ),
            for (final bank in _banks) ...[
              _BankCard(
                bank: bank,
                templateCount: _templateCounts[bank.id] ?? 0,
                needTeaching: _messages
                    .where(
                      (message) =>
                          message.bankId == bank.id &&
                          message.status ==
                              SmsTemplateMessageStatus.unrecognized,
                    )
                    .length,
                onTap: () => _openBank(bank),
              ),
              const SizedBox(height: 10),
            ],
            if (_applications.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 18, 4, 10),
                child: Text(
                  'RECENT BALANCE CHANGES',
                  style: TextStyle(
                    color: AppConstants.textSecondary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .8,
                    fontSize: 12,
                  ),
                ),
              ),
              for (final item in _applications.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      leading: Icon(
                        item.delta > 0 ? Icons.south_west : Icons.north_east,
                        color: item.undone
                            ? AppConstants.textTertiary
                            : item.delta > 0
                            ? const Color(0xFF15803D)
                            : AppConstants.errorColor,
                      ),
                      title: Text('${item.bankName} • ${item.sourceName}'),
                      subtitle: Text(
                        item.undone
                            ? 'Undone'
                            : '${item.beforeAmount.toStringAsFixed(2)} → ${item.afterAmount.toStringAsFixed(2)}',
                      ),
                      trailing: Text(
                        '${item.delta > 0 ? '+' : ''}${item.delta.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SmsTemplateOperationsPage(),
                          ),
                        );
                        await _load();
                      },
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final bool alert;

  const _MetricCard({
    required this.value,
    required this.label,
    required this.icon,
    this.alert = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 19,
              color: alert
                  ? AppConstants.errorColor
                  : AppConstants.primaryColor,
            ),
            const SizedBox(height: 10),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _BankCard extends StatelessWidget {
  final SmsTemplateBank bank;
  final int templateCount;
  final int needTeaching;
  final VoidCallback onTap;

  const _BankCard({
    required this.bank,
    required this.templateCount,
    required this.needTeaching,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppConstants.primarySurface,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.account_balance_outlined,
                  color: AppConstants.primaryColor,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bank.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${bank.senders.join(', ')} • $templateCount template${templateCount == 1 ? '' : 's'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (needTeaching > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '$needTeaching message${needTeaching == 1 ? '' : 's'} need teaching',
                          style: const TextStyle(
                            color: AppConstants.errorColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppConstants.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddBankResult {
  final String presetId;
  final int sourceId;
  final String name;
  final String sender;

  const _AddBankResult({
    required this.presetId,
    required this.sourceId,
    required this.name,
    required this.sender,
  });
}

class _AddBankSheet extends StatefulWidget {
  final List<SmsTemplateBankPreset> presets;
  final List<MoneySource> sources;
  final String? initialPresetId;

  const _AddBankSheet({
    required this.presets,
    required this.sources,
    required this.initialPresetId,
  });

  @override
  State<_AddBankSheet> createState() => _AddBankSheetState();
}

class _AddBankSheetState extends State<_AddBankSheet> {
  final _name = TextEditingController();
  final _sender = TextEditingController();
  String? _presetId;
  int? _sourceId;

  @override
  void initState() {
    super.initState();
    _presetId = widget.initialPresetId;
  }

  @override
  void dispose() {
    _name.dispose();
    _sender.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCustom = _presetId == SmsTemplateBankPreset.customId;
    final selectedPreset = widget.presets
        .where((item) => item.id == _presetId)
        .firstOrNull;
    final name = _name.text.trim();
    final sender = _sender.text.trim();
    final canSave =
        _sourceId != null &&
        _presetId != null &&
        (selectedPreset != null ||
            (isCustom && name.isNotEmpty && sender.isNotEmpty));
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxHeight = (screenHeight - bottomInset - 24).clamp(
      0.0,
      screenHeight * .75,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset + 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add a bank', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _presetId,
                decoration: const InputDecoration(
                  labelText: 'Bank',
                  helperText: 'Choose a known bank or create a custom one.',
                ),
                items: [
                  for (final preset in widget.presets)
                    DropdownMenuItem(
                      value: preset.id,
                      child: Text(preset.name),
                    ),
                  const DropdownMenuItem(
                    value: SmsTemplateBankPreset.customId,
                    child: Text('Custom bank'),
                  ),
                ],
                onChanged: (value) => setState(() => _presetId = value),
              ),
              if (selectedPreset != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Sender IDs: ${selectedPreset.senders.join(', ')}',
                  style: const TextStyle(color: AppConstants.textSecondary),
                ),
              ],
              if (isCustom) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _name,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Bank name',
                    hintText: 'Example: My Bank',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _sender,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Exact sender ID',
                    hintText: 'Example: MYBANK',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _sourceId,
                decoration: InputDecoration(
                  labelText: 'Money source',
                  helperText: widget.sources.isEmpty
                      ? 'Create a money source before adding a bank.'
                      : 'Required before rules can be created.',
                ),
                items: [
                  for (final source in widget.sources)
                    if (source.id != null)
                      DropdownMenuItem(
                        value: source.id,
                        child: Text(
                          '${source.name} • ${source.amount.toStringAsFixed(2)}',
                        ),
                      ),
                ],
                onChanged: widget.sources.isEmpty
                    ? null
                    : (value) => setState(() => _sourceId = value),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: canSave
                      ? () {
                          final sourceId = _sourceId;
                          final presetId = _presetId;
                          if (sourceId == null || presetId == null) return;
                          FocusManager.instance.primaryFocus?.unfocus();
                          Navigator.pop(
                            context,
                            _AddBankResult(
                              presetId: presetId,
                              sourceId: sourceId,
                              name: _name.text.trim(),
                              sender: _sender.text.trim(),
                            ),
                          );
                        }
                      : null,
                  child: const Text('Add bank'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final IconData icon;
  final String text;

  const _NoticeCard({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: AppConstants.textSecondary),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
