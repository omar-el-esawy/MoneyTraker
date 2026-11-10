import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:money_traker/constants/app_constants.dart';
import 'package:money_traker/pages/app_update_prompt.dart';
import 'package:money_traker/services/app_update.dart';
import 'package:money_traker/services/app_update_logic.dart';
import 'package:money_traker/model/tag.dart';
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
          content: Text(
            _arabic ? 'متعذر حفظ التصنيف.' : 'Could not save that category.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  Future<void> _undoSkip(InboxItem item) async {
    if (_savingId != null) return;
    setState(() => _savingId = item.id);
    try {
      await InboxStore.instance.undoCategorySkip(item.id);
    } catch (e) {
      debugPrint('Undoing no category failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _arabic ? 'متعذر التراجع.' : 'Could not undo that choice.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  Future<void> _clearCategory(InboxItem item) async {
    if (_savingId != null) return;
    setState(() => _savingId = item.id);
    try {
      await InboxStore.instance.clearCategory(item.id);
    } catch (e) {
      debugPrint('Clearing category failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _arabic ? 'متعذر حفظ الاختيار.' : 'Could not save that choice.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  Future<void> _skip(InboxItem item) async {
    if (_savingId != null) return;
    setState(() => _savingId = item.id);
    try {
      await InboxStore.instance.skipCategory(item.id);
    } catch (e) {
      debugPrint('Skipping category failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _arabic ? 'متعذر حفظ الاختيار.' : 'Could not save that choice.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  Future<void> _openCategoryPicker(InboxItem item) async {
    if (_savingId != null) return;
    final type = categoryTypeFor(item);
    if (type == null) return;
    try {
      final categories = await InboxStore.instance.categoriesFor(item);
      if (!mounted) return;
      final choice = await showModalBottomSheet<_CategoryChoice>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => _CategoryPicker(
          arabic: _arabic,
          type: type,
          categories: categories,
          currentName: item.chosenName,
        ),
      );
      if (!mounted || choice == null) return;
      if (choice.clear) {
        await _clearCategory(item);
      } else if (choice.category != null) {
        await _choose(item, choice.category!);
      }
    } catch (e) {
      debugPrint('Category picker failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _arabic ? 'متعذر تحميل التصنيفات.' : 'Could not load categories.',
          ),
        ),
      );
    }
  }

  Future<void> _openUpdate(InboxItem item) async {
    final url = item.downloadUrl;
    final version = item.version;
    if (url == null || url.isEmpty || version == null || version.isEmpty) {
      return;
    }
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
        child: item.kind == InboxKind.update
            ? _updateBody(item)
            : _transactionBody(item),
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
              color: debit
                  ? AppConstants.errorColor
                  : AppConstants.primaryLight,
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
          Row(
            children: [
              Expanded(
                child: Text(
                  arabic
                      ? 'اتحفظت في ${item.chosenName}'
                      : 'Saved in ${item.chosenName}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppConstants.primaryColor,
                  ),
                ),
              ),
              TextButton(
                onPressed: _savingId == null
                    ? () => _openCategoryPicker(item)
                    : null,
                child: Text(arabic ? 'تعديل' : 'Edit'),
              ),
            ],
          ),
        ] else if (item.categorySkipped) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  arabic ? 'من غير تصنيف' : 'No category',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppConstants.textSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed: _savingId == null ? () => _undoSkip(item) : null,
                child: Text(arabic ? 'تراجع' : 'Undo'),
              ),
            ],
          ),
        ] else if (item.needsCategory) ...[
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
                  onPressed: _savingId == null
                      ? () => _choose(item, choice)
                      : null,
                  backgroundColor: AppConstants.primarySurface,
                  side: const BorderSide(color: AppConstants.primaryLight),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: Text(arabic ? 'تصنيف مخصص' : 'Custom category'),
                onPressed: _savingId == null
                    ? () => _openCategoryPicker(item)
                    : null,
              ),
              ActionChip(
                label: Text(arabic ? 'من غير تصنيف' : 'No category'),
                onPressed: _savingId == null ? () => _skip(item) : null,
              ),
            ],
          ),
        ],
        if (_savingId == item.id) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(
            minHeight: 3,
            color: AppConstants.primaryColor,
            backgroundColor: AppConstants.primarySurface,
          ),
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
            const Icon(
              Icons.system_update_alt,
              color: AppConstants.primaryColor,
            ),
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

class _CategoryChoice {
  final SuggestedCategory? category;
  final bool clear;

  const _CategoryChoice.category(this.category) : clear = false;

  const _CategoryChoice.clear() : category = null, clear = true;
}

class _CategoryPicker extends StatefulWidget {
  final bool arabic;
  final TagType type;
  final List<SuggestedCategory> categories;
  final String? currentName;

  const _CategoryPicker({
    required this.arabic,
    required this.type,
    required this.categories,
    this.currentName,
  });

  @override
  State<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<_CategoryPicker> {
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _saveCustom() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    if (name.toLowerCase() == 'others') {
      setState(() {
        _error = widget.arabic ? 'اسم Others محجوز.' : '"Others" is reserved.';
      });
      return;
    }
    Navigator.pop(
      context,
      _CategoryChoice.category(
        SuggestedCategory(name: name, type: widget.type),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final arabic = widget.arabic;
    final current = widget.currentName;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Directionality(
      textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                current == null
                    ? (arabic ? 'اختار تصنيف' : 'Choose a category')
                    : (arabic ? 'غيّر التصنيف' : 'Change category'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (current != null) ...[
                const SizedBox(height: 8),
                Text(
                  arabic
                      ? 'التصنيف الحالي: $current'
                      : 'Current category: $current',
                ),
              ],
              const SizedBox(height: 12),
              if (widget.categories.isEmpty && current == null)
                Text(
                  arabic
                      ? 'مفيش تصنيفات محفوظة. اكتب اسم جديد.'
                      : 'No saved categories yet. Type a new name.',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final category in widget.categories)
                      ActionChip(
                        label: Text(category.name),
                        onPressed: () => Navigator.pop(
                          context,
                          _CategoryChoice.category(category),
                        ),
                      ),
                    if (current != null)
                      ActionChip(
                        label: Text(arabic ? 'من غير تصنيف' : 'No category'),
                        onPressed: () => Navigator.pop(
                          context,
                          const _CategoryChoice.clear(),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: arabic ? 'تصنيف جديد' : 'Custom category',
                  errorText: _error,
                ),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _saveCustom(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _name.text.trim().isEmpty ? null : _saveCustom,
                style: FilledButton.styleFrom(
                  backgroundColor: AppConstants.primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: Text(arabic ? 'حفظ' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
