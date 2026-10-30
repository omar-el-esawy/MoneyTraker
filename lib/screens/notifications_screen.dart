import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:money_traker/constants/app_constants.dart';
import 'package:money_traker/pages/app_update_prompt.dart';
import 'package:money_traker/services/app_update.dart';
import 'package:money_traker/services/app_update_logic.dart';
import 'package:money_traker/services/category_suggestions.dart';
import 'package:money_traker/services/inbox_logic.dart';
import 'package:money_traker/services/inbox_store.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _money = NumberFormat('#,##0.00');
  final _when = DateFormat('d MMM, HH:mm');

  bool _loading = true;
  String? _savingId;
  Set<String> _openedUnread = const {};

  bool get _arabic => Localizations.localeOf(context).languageCode == 'ar';

  @override
  void initState() {
    super.initState();
    InboxStore.instance.addListener(_onInbox);
    _open();
  }

  @override
  void dispose() {
    InboxStore.instance.removeListener(_onInbox);
    super.dispose();
  }

  void _onInbox() {
    if (mounted) setState(() {});
  }

  Future<void> _open() async {
    await InboxStore.instance.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _openedUnread = {
        for (final item in InboxStore.instance.items)
          if (!item.read) item.id,
      };
      _loading = false;
    });
    await InboxStore.instance.markAllRead();
  }

  Future<void> _choose(InboxItem item, SuggestedCategory choice) async {
    if (_savingId != null) return;
    setState(() => _savingId = item.id);
    try {
      await InboxStore.instance.chooseCategory(item.id, choice);
    } catch (e) {
      debugPrint('Category choice failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_arabic ? 'متعذر حفظ التصنيف.' : 'Could not save that category.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  Future<void> _openUpdate(InboxItem item) async {
    final url = item.downloadUrl;
    final version = item.version;
    if (url == null || url.isEmpty || version == null || version.isEmpty) return;
    await showOptionalUpdateDialog(
      context,
      UpdateOffer(
        version: version,
        buildNumber: item.buildNumber,
        force: item.force,
        downloadUrl: url,
        changelog: item.changelog ?? '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final arabic = _arabic;
    final items = InboxStore.instance.items;
    return Directionality(
      textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppConstants.backgroundColor,
        appBar: AppBar(title: Text(arabic ? 'الإشعارات' : 'Notifications')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        arabic
                            ? 'مفيش إشعارات. تحويلات البنك والتحديثات بتظهر هنا.'
                            : 'No notifications yet. Bank transfers and app updates show up here.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: AppConstants.textSecondary,
                            ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _card(items[index]),
                  ),
      ),
    );
  }

  Widget _card(InboxItem item) {
    final fresh = _openedUnread.contains(item.id);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppConstants.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: fresh ? AppConstants.primaryLight : AppConstants.dividerColor,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: item.kind == InboxKind.update ? _updateBody(item) : _transactionBody(item),
      ),
    );
  }

  Widget _transactionBody(InboxItem item) {
    final arabic = _arabic;
    final debit = item.debit == true;
    final amount = item.amount ?? 0;
    final when = item.occurredAt ?? item.createdAt;
    final bank = item.bank ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              debit ? Icons.arrow_upward : Icons.arrow_downward,
              color: debit ? AppConstants.errorColor : AppConstants.primaryLight,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                debit
                    ? (arabic ? 'فلوس خرجت' : 'Money out')
                    : (arabic ? 'فلوس وصلت' : 'Money in'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              _when.format(when),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${debit ? '-' : '+'}${_money.format(amount.abs())}${bank.isEmpty ? '' : ' · $bank'}',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: debit ? AppConstants.errorColor : AppConstants.primaryColor,
                fontWeight: FontWeight.w700,
              ),
        ),
        if ((item.preview ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            item.preview!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        if (item.chosenName != null) ...[
          const SizedBox(height: 10),
          Text(
            arabic ? 'اتحفظت في ${item.chosenName}' : 'Saved in ${item.chosenName}',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppConstants.primaryColor,
                ),
          ),
        ] else if (item.needsCategory && item.suggestions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            arabic
                ? 'مفيش قاعدة تصنيف للتحويل ده. اختار واحدة:'
                : 'No category rule for this transfer. Pick one:',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in item.suggestions)
                ActionChip(
                  label: Text(choice.name),
                  onPressed: _savingId == null ? () => _choose(item, choice) : null,
                  backgroundColor: AppConstants.primarySurface,
                  side: const BorderSide(color: AppConstants.primaryLight),
                ),
            ],
          ),
          if (_savingId == item.id) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(
              minHeight: 3,
              color: AppConstants.primaryColor,
              backgroundColor: AppConstants.primarySurface,
            ),
          ],
        ],
      ],
    );
  }

  Widget _updateBody(InboxItem item) {
    final arabic = _arabic;
    final version = item.version == null
        ? ''
        : releaseLabel(item.version!, item.buildNumber);
    final changelog = item.changelog?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.system_update_alt, color: AppConstants.primaryColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.force
                    ? (arabic ? 'لازم تحدّث التطبيق' : 'Update required')
                    : (arabic ? 'في تحديث جديد' : 'Update available'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        if (version.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            arabic ? 'آخر إصدار هو $version.' : 'The latest is $version.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
        if (changelog.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(changelog, style: Theme.of(context).textTheme.bodyMedium),
        ],
        if ((item.downloadUrl ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(
              onPressed: () => _openUpdate(item),
              style: FilledButton.styleFrom(
                backgroundColor: AppConstants.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: Text(arabic ? 'تحديث' : 'Update'),
            ),
          ),
        ],
      ],
    );
  }
}
