import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:money_traker/constants/app_constants.dart';
import 'package:money_traker/model/money_source.dart';
import 'package:money_traker/pages/sms_templates/sms_template_detail_page.dart';
import 'package:money_traker/pages/sms_templates/sms_template_wizard_page.dart';
import 'package:money_traker/services/sms_template_sync_service.dart';
import 'package:money_traker/sms/template_engine/sms_template_mobile_store.dart';
import 'package:money_traker/sms/template_engine/template_models.dart';
import 'package:money_traker/store/money_storage.dart';

class SmsTemplateBankPage extends StatefulWidget {
  final String bankId;

  const SmsTemplateBankPage({super.key, required this.bankId});

  @override
  State<SmsTemplateBankPage> createState() => _SmsTemplateBankPageState();
}

class _SmsTemplateBankPageState extends State<SmsTemplateBankPage> {
  final _store = SmsTemplateMobileStore.instance;
  SmsTemplateBank? _bank;
  List<SmsTemplate> _templates = const [];
  List<SmsTemplateStoredMessage> _messages = const [];
  List<MoneySource> _sources = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final banks = await _store.getBanks();
    final templates = await _store.getTemplates(bankId: widget.bankId);
    final messages = await _store.getMessages(bankId: widget.bankId);
    final sources = await MoneyStorage().getMoneySources();
    SmsTemplateBank? bank;
    for (final item in banks) {
      if (item.id == widget.bankId) bank = item;
    }
    if (!mounted) return;
    if (bank == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _bank = bank;
      _templates = templates;
      _messages = messages;
      _sources = sources;
      _loading = false;
    });
  }

  Future<void> _saveBank(SmsTemplateBank bank) async {
    await _store.saveBank(bank);
    await _load();
  }

  Future<void> _chooseSource() async {
    final bank = _bank;
    if (bank == null) return;
    final sourceId = await showModalBottomSheet<int?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .75,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Money source',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('No source'),
                subtitle: const Text('Parse messages without changing money'),
                onTap: () => Navigator.pop(context, -1),
              ),
              for (final source in _sources)
                ListTile(
                  leading: Icon(
                    source.id == bank.sourceId
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: source.id == bank.sourceId
                        ? AppConstants.primaryColor
                        : null,
                  ),
                  title: Text(source.name),
                  subtitle: Text(source.amount.toStringAsFixed(2)),
                  onTap: () => Navigator.pop(context, source.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (sourceId == null) return;
    await _saveBank(
      sourceId == -1
          ? bank.copyWith(clearSourceId: true)
          : bank.copyWith(sourceId: sourceId),
    );
  }

  Future<void> _addSender() async {
    final bank = _bank;
    if (bank == null) return;
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _AddSenderSheet(),
    );
    if (value == null ||
        value.isEmpty ||
        bank.senders.any((item) => item.toLowerCase() == value.toLowerCase())) {
      return;
    }
    await _saveBank(bank.copyWith(senders: [...bank.senders, value]));
  }

  Future<void> _openWizard([SmsTemplateStoredMessage? message]) async {
    var bank = _bank;
    if (bank == null) return;
    if (bank.sourceId == null) {
      final chooseSource = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Money source required'),
          content: const Text(
            'Connect this bank to a money source before creating a rule.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Choose money source'),
            ),
          ],
        ),
      );
      if (chooseSource != true || !mounted) return;
      await _chooseSource();
      if (!mounted) return;
      bank = _bank;
      if (bank == null || bank.sourceId == null) return;
    }
    final readyBank = bank;
    if (readyBank.sourceId == null) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SmsTemplateWizardPage(bank: readyBank, initialMessage: message),
      ),
    );
    if (saved == true) {
      setState(() => _busy = true);
      await SmsTemplateSyncService.instance.reprocessBank(readyBank.id);
      await _load();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync() async {
    setState(() => _busy = true);
    final result = await SmsTemplateSyncService.instance.sync(
      bankId: widget.bankId,
    );
    await _load();
    if (!mounted) return;
    setState(() => _busy = false);
    final message = result.disabled
        ? 'Turn on SMS Templates from the previous page first.'
        : result.permissionGranted
        ? '${result.applied} applied • ${result.unrecognized} need teaching'
        : 'SMS permission was not granted.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _deleteTemplate(SmsTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete template?'),
        content: const Text(
          'Old balance changes stay saved. Future messages will no longer use this template.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.deleteTemplate(template.id);
    await _load();
  }

  Future<void> _deleteBank() async {
    final bank = _bank;
    if (bank == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete bank?'),
        content: Text(
          'This will delete ${bank.name}, its templates, and its saved '
          'messages. Existing balance changes will not be reversed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppConstants.errorColor,
            ),
            child: const Text('Delete bank'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    await _store.deleteBank(bank.id);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _openTemplate(SmsTemplate template) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SmsTemplateDetailPage(
          template: template,
          templates: _templates,
          messages: _messages,
        ),
      ),
    );
  }

  String _sourceName(int? id) {
    for (final source in _sources) {
      if (source.id == id) return source.name;
    }
    return 'No source selected';
  }

  @override
  Widget build(BuildContext context) {
    final bank = _bank;
    if (_loading || bank == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final unrecognized = _messages
        .where((item) => item.status == SmsTemplateMessageStatus.unrecognized)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(bank.name),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
        actions: [
          IconButton(
            tooltip: 'Delete bank',
            onPressed: _busy ? null : _deleteBank,
            icon: const Icon(Icons.delete_outline),
          ),
          IconButton(
            tooltip: 'Read messages',
            onPressed: _busy ? null : _sync,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _openWizard(),
        icon: const Icon(Icons.add),
        label: const Text('New template'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.account_balance_wallet_outlined,
                    color: AppConstants.primaryColor,
                  ),
                  title: const Text('Money source'),
                  subtitle: Text(_sourceName(bank.sourceId)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _chooseSource,
                ),
                const Divider(height: 1, indent: 56),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Sender IDs',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _addSender,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add'),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (final sender in bank.senders)
                            InputChip(
                              label: Text(sender),
                              onDeleted: bank.senders.length == 1
                                  ? null
                                  : () => _saveBank(
                                      bank.copyWith(
                                        senders: bank.senders
                                            .where((item) => item != sender)
                                            .toList(),
                                      ),
                                    ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _SectionHeader(title: 'TEMPLATES', count: _templates.length),
          if (_templates.isEmpty)
            _ActionCard(
              icon: Icons.auto_awesome_motion_outlined,
              title: 'Teach the first format',
              subtitle:
                  'Choose a real SMS and mark its changing parts step by step.',
              action: 'Create template',
              onTap: () => _openWizard(),
            )
          else
            for (final template in _templates)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: template.type == SmsTemplateType.debit
                          ? AppConstants.errorColor.withValues(alpha: .1)
                          : const Color(0xFF15803D).withValues(alpha: .1),
                      child: Icon(
                        template.type == SmsTemplateType.debit
                            ? Icons.north_east
                            : Icons.south_west,
                        color: template.type == SmsTemplateType.debit
                            ? AppConstants.errorColor
                            : const Color(0xFF15803D),
                      ),
                    ),
                    title: Text(
                      template.type == SmsTemplateType.debit
                          ? 'Debit template'
                          : 'Credit template',
                    ),
                    subtitle: Text(
                      '${template.placeholders.length} marked parts',
                    ),
                    onTap: () => _openTemplate(template),
                    trailing: IconButton(
                      tooltip: 'Delete',
                      onPressed: () => _deleteTemplate(template),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                ),
              ),
          _SectionHeader(title: 'NEEDS TEACHING', count: unrecognized.length),
          if (unrecognized.isEmpty)
            const _StatusCard(
              icon: Icons.check_circle_outline,
              text: 'No unrecognized messages for this bank.',
            )
          else
            for (final message in unrecognized.take(10))
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
                    title: Text(
                      message.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      DateFormat('d MMM, HH:mm').format(message.date),
                    ),
                    trailing: const Icon(
                      Icons.school_outlined,
                      color: AppConstants.primaryColor,
                    ),
                    onTap: () => _openWizard(message),
                  ),
                ),
              ),
          _SectionHeader(title: 'RECENT MESSAGES', count: _messages.length),
          if (_messages.isEmpty)
            const _StatusCard(
              icon: Icons.sms_outlined,
              text: 'Read messages to see this bank’s inbox here.',
            )
          else
            for (final message in _messages.take(15))
              _MessageRow(message: message),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppConstants.textSecondary,
                fontWeight: FontWeight.w700,
                letterSpacing: .7,
                fontSize: 12,
              ),
            ),
          ),
          Text('$count', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Icon(icon, size: 38, color: AppConstants.primaryColor),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(subtitle, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton(onPressed: onTap, child: Text(action)),
          ],
        ),
      ),
    );
  }
}

class _AddSenderSheet extends StatefulWidget {
  const _AddSenderSheet();

  @override
  State<_AddSenderSheet> createState() => _AddSenderSheetState();
}

class _AddSenderSheetState extends State<_AddSenderSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add sender ID',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('It must exactly match the sender shown by Android.'),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Example: MYBANK'),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final value = _controller.text.trim();
                  FocusManager.instance.primaryFocus?.unfocus();
                  Navigator.pop(context, value);
                },
                child: const Text('Add sender'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final String text;

  const _StatusCard({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: AppConstants.textTertiary),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  final SmsTemplateStoredMessage message;

  const _MessageRow({required this.message});

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (message.status) {
      SmsTemplateMessageStatus.parsed => (
        Icons.check_circle_outline,
        const Color(0xFF15803D),
        'Matched',
      ),
      SmsTemplateMessageStatus.unrecognized => (
        Icons.help_outline,
        AppConstants.errorColor,
        'Needs teaching',
      ),
      SmsTemplateMessageStatus.duplicate => (
        Icons.content_copy,
        AppConstants.textTertiary,
        'Duplicate',
      ),
      SmsTemplateMessageStatus.pending => (
        Icons.schedule,
        AppConstants.textTertiary,
        'Pending',
      ),
      SmsTemplateMessageStatus.sample => (
        Icons.school_outlined,
        AppConstants.textTertiary,
        'Example',
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '$label • ${DateFormat('d MMM, HH:mm').format(message.date)}',
                      style: TextStyle(color: color, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
