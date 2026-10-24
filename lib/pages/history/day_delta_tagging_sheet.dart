import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:money_traker/model/tag.dart';
import 'package:money_traker/store/money_storage.dart';
import 'package:money_traker/pages/widgets/amount_calculator_sheet.dart';
import 'package:money_traker/pages/widgets/obscurable_amount.dart';

class DayDeltaTaggingResult {
  final Map<int, double> tagIdToAmount;

  const DayDeltaTaggingResult({required this.tagIdToAmount});
}

class DayDeltaTaggingSheet extends StatefulWidget {
  final int dayId;
  final double delta; // today - previous
  final DateTime? entryDate;
  final bool showAmounts;

  const DayDeltaTaggingSheet({
    super.key,
    required this.dayId,
    required this.delta,
    this.entryDate,
    this.showAmounts = true,
  });

  @override
  State<DayDeltaTaggingSheet> createState() => _DayDeltaTaggingSheetState();
}

class _DayDeltaTaggingSheetState extends State<DayDeltaTaggingSheet> {
  final MoneyStorage _storage = MoneyStorage();

  bool _loading = true;
  late Tag _incomeOthers;
  late Tag _expenseOthers;
  bool _ready = false;

  // Manual amounts only. Auto-balance rows are derived at render/persist time.
  final Map<int, double> _incomeManual = {};
  final Map<int, double> _expenseManual = {};
  List<Tag> _incomeTags = [];
  List<Tag> _expenseTags = [];

  bool _saving = false;

  double _sum(Map<int, double> values) {
    double total = 0;
    for (final v in values.values) {
      total += v;
    }
    return total;
  }

  double get _manualIncomeTotal => _sum(_incomeManual);

  double get _manualExpenseTotal => _sum(_expenseManual);

  double get _autoIncome {
    final needed = widget.delta + _manualExpenseTotal - _manualIncomeTotal;
    return math.max(0.0, needed);
  }

  double get _autoExpense {
    final needed = _manualIncomeTotal - _manualExpenseTotal - widget.delta;
    return math.max(0.0, needed);
  }

  double get _totalIncome => _manualIncomeTotal + _autoIncome;

  double get _totalExpenses => _manualExpenseTotal + _autoExpense;

  double get _unallocated => widget.delta - (_totalIncome - _totalExpenses);

  String _fmtAmount(double amount) => amount.toStringAsFixed(2);

  String _fmtSigned(double amount) {
    if (amount > 0) return '+${_fmtAmount(amount)}';
    if (amount < 0) return '-${_fmtAmount(amount.abs())}';
    return _fmtAmount(0);
  }

  String _fmtDateTime() {
    final d = widget.entryDate;
    if (d == null) return 'Entry details';
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$y-$m-$day · $hh:$mm';
  }

  @override
  void initState() {
    super.initState();
    // Defer load until after first frame to avoid blocking the opening animation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final incomeOthers = await _storage.ensureTag(name: 'Others', type: TagType.income);
    final expenseOthers = await _storage.ensureTag(name: 'Others', type: TagType.expense);

    // Initialize late fields early so any subsequent persist can't crash.
    _incomeOthers = incomeOthers;
    _expenseOthers = expenseOthers;

    final incomeTags = await _storage.getTags(type: TagType.income);
    final expenseTags = await _storage.getTags(type: TagType.expense);
    if (!incomeTags.any((t) => t.id == incomeOthers.id)) {
      incomeTags.add(incomeOthers);
    }
    if (!expenseTags.any((t) => t.id == expenseOthers.id)) {
      expenseTags.add(expenseOthers);
    }

    final existingEntries = await _storage.getDeltaEntriesForDayDetailed(widget.dayId);

    _incomeManual.clear();
    _expenseManual.clear();
    for (final row in existingEntries) {
      final tagId = row['tagId'] as int;
      final amount = ((row['amount'] as num?) ?? 0).toDouble();
      final type = TagTypeDb.fromDb(row['tagType'] as String);
      final autoBalanced = ((row['autoBalanced'] as num?) ?? 0) > 0;
      if (amount <= 0 || autoBalanced) continue;

      if (type == TagType.income) {
        _incomeManual[tagId] = amount;
      } else {
        _expenseManual[tagId] = amount;
      }
    }

    if (!mounted) return;
    setState(() {
      _incomeTags = incomeTags..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _expenseTags = expenseTags..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _loading = false;
      _ready = true;
    });
  }

  Future<void> _persistNow() async {
    if (!_ready) return;
    if (_saving) return;
    _saving = true;
    try {
      // Always write a consistent, balanced snapshot.
      final snap = <int, double>{};
      final autoBalancedTagIds = <int>{};

      for (final e in _incomeManual.entries) {
        if (e.value > 0.0000001) snap[e.key] = e.value;
      }
      for (final e in _expenseManual.entries) {
        if (e.value > 0.0000001) snap[e.key] = e.value;
      }

      if (_autoIncome > 0.0000001) {
        snap[_incomeOthers.id!] = _autoIncome;
        autoBalancedTagIds.add(_incomeOthers.id!);
      }
      if (_autoExpense > 0.0000001) {
        snap[_expenseOthers.id!] = _autoExpense;
        autoBalancedTagIds.add(_expenseOthers.id!);
      }

      await _storage.replaceDeltaEntriesForDay(
        dayId: widget.dayId,
        tagIdToAmount: snap,
        autoBalancedTagIds: autoBalancedTagIds,
      );
    } finally {
      _saving = false;
    }
  }

  Future<void> _addAllocation(TagType type) async {
    final draft = await _showAddAllocationDialog(type);
    if (draft == null) return;

    Tag selectedTag;
    if (draft.tagId != null) {
      final source = type == TagType.income ? _incomeTags : _expenseTags;
      selectedTag = source.firstWhere((t) => t.id == draft.tagId);
    } else {
      selectedTag = await _storage.ensureTag(name: draft.newCategoryName!, type: type);
    }

    if (!mounted) return;
    setState(() {
      final target = type == TagType.income ? _incomeManual : _expenseManual;
      // If category already exists for this day, treat this as an edit/replace.
      target[selectedTag.id!] = draft.amount;

      final tags = type == TagType.income ? _incomeTags : _expenseTags;
      if (!tags.any((t) => t.id == selectedTag.id)) {
        tags.add(selectedTag);
        tags.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }
    });

    await _persistNow();
  }

  Future<void> _editAllocation(TagType type, _SectionAllocation row) async {
    if (row.autoBalanced) return;

    final edited = await showAmountCalculatorSheet(
      context,
      title: row.name,
      prefixText: type == TagType.income ? '+' : '-',
      initialValue: row.amount,
      allowZero: false,
    );
    if (edited == null) return;

    setState(() {
      final target = type == TagType.income ? _incomeManual : _expenseManual;
      target[row.tagId] = edited;
    });

    await _persistNow();
  }

  Future<_AllocationDraft?> _showAddAllocationDialog(TagType type) async {
    final tags = (type == TagType.income ? _incomeTags : _expenseTags)
        .where((t) => t.name.trim().toLowerCase() != 'others')
        .toList();
    int? selectedTagId = tags.isNotEmpty ? tags.first.id : null;
    bool addingNew = tags.isEmpty;
    final existingForType = type == TagType.income ? _incomeManual : _expenseManual;
    double? amount = selectedTagId == null ? null : existingForType[selectedTagId];
    final categoryController = TextEditingController();

    return showDialog<_AllocationDraft>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(type == TagType.income ? 'Add Income' : 'Add Expense'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Category',
                  style: Theme.of(ctx).textTheme.labelMedium?.copyWith(color: const Color(0xFF6B7280)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...tags.map(
                      (tag) => ChoiceChip(
                        label: Text(tag.name),
                        selected: !addingNew && selectedTagId == tag.id,
                        onSelected: (_) {
                          setLocal(() {
                            addingNew = false;
                            selectedTagId = tag.id;
                            // Reuse existing value when this category is already used.
                            amount = existingForType[tag.id];
                          });
                        },
                      ),
                    ),
                    ActionChip(
                      label: const Text('New'),
                      avatar: const Icon(Icons.add, size: 16),
                      onPressed: () {
                        setLocal(() {
                          addingNew = true;
                          selectedTagId = null;
                          amount = null;
                        });
                      },
                    ),
                  ],
                ),
                if (addingNew) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: categoryController,
                    decoration: const InputDecoration(labelText: 'New category name'),
                    autofocus: true,
                  ),
                ],
                const SizedBox(height: 16),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final v = await showAmountCalculatorSheet(
                      ctx,
                      title: 'Amount',
                      prefixText: type == TagType.income ? '+' : '-',
                      initialValue: amount,
                      allowZero: false,
                    );
                    if (v == null) return;
                    setLocal(() => amount = v);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      border: const OutlineInputBorder(),
                      prefixText: type == TagType.income ? '+' : '-',
                    ),
                    child:
                        amount == null
                            ? Text(
                              'Tap to enter',
                              style: TextStyle(
                                color: Theme.of(ctx).hintColor,
                                fontWeight: FontWeight.w800,
                              ),
                            )
                            : ObscurableAmount(
                              amount: amount!.toStringAsFixed(2),
                              visible: widget.showAmounts,
                              style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final parsed = amount;
                if (parsed == null || parsed <= 0) return;

                if (addingNew) {
                  final name = categoryController.text.trim();
                  if (name.isEmpty) return;
                  Navigator.of(ctx).pop(_AllocationDraft(amount: parsed, newCategoryName: name));
                  return;
                }

                if (selectedTagId == null) return;
                Navigator.of(ctx).pop(_AllocationDraft(amount: parsed, tagId: selectedTagId));
              },
              child: Text((!addingNew && selectedTagId != null && existingForType.containsKey(selectedTagId)) ? 'Update' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _removeAllocation(TagType type, int tagId) {
    setState(() {
      if (type == TagType.income) {
        _incomeManual.remove(tagId);
      } else {
        _expenseManual.remove(tagId);
      }
    });
    _persistNow();
  }

  List<_SectionAllocation> _buildSectionAllocations(TagType type) {
    final tags = type == TagType.income ? _incomeTags : _expenseTags;
    final manual = type == TagType.income ? _incomeManual : _expenseManual;
    final othersTag = type == TagType.income ? _incomeOthers : _expenseOthers;
    final autoAmount = type == TagType.income ? _autoIncome : _autoExpense;

    final rows = <_SectionAllocation>[];
    for (final e in manual.entries) {
      if (e.value <= 0.0000001) continue;
      final tag = tags.where((t) => t.id == e.key).cast<Tag?>().firstWhere(
            (t) => t != null,
            orElse: () => null,
          );
      rows.add(
        _SectionAllocation(
          tagId: e.key,
          name: tag?.name ?? 'Category #${e.key}',
          amount: e.value,
          autoBalanced: false,
        ),
      );
    }

    if (autoAmount > 0.0000001) {
      rows.add(
        _SectionAllocation(
          tagId: othersTag.id!,
          name: othersTag.name,
          amount: autoAmount,
          autoBalanced: true,
        ),
      );
    }

    rows.sort((a, b) => b.amount.compareTo(a.amount));
    return rows;
  }

  Widget _buildSummaryHeader() {
    final netPositive = widget.showAmounts && widget.delta >= 0;
    final netNegative = widget.showAmounts && widget.delta < 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _fmtDateTime(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF9CA3AF)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pill(
                label:
                    widget.showAmounts
                        ? 'Net: ${_fmtSigned(widget.delta)}'
                        : 'Net: $kHiddenAmount',
                bg:
                    netPositive
                        ? const Color(0xFFE8F5E9)
                        : (netNegative
                            ? const Color(0xFFFFEBEE)
                            : const Color(0xFFF3F4F6)),
                fg:
                    netPositive
                        ? const Color(0xFF1B5E20)
                        : (netNegative
                            ? const Color(0xFFD32F2F)
                            : const Color(0xFF6B7280)),
              ),
              _pill(
                label:
                    widget.showAmounts
                        ? 'In: +${_fmtAmount(_totalIncome)}'
                        : 'In: $kHiddenAmount',
                bg:
                    widget.showAmounts
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFF3F4F6),
                fg:
                    widget.showAmounts
                        ? const Color(0xFF1B5E20)
                        : const Color(0xFF6B7280),
              ),
              _pill(
                label:
                    widget.showAmounts
                        ? 'Out: -${_fmtAmount(_totalExpenses)}'
                        : 'Out: $kHiddenAmount',
                bg:
                    widget.showAmounts
                        ? const Color(0xFFFFEBEE)
                        : const Color(0xFFF3F4F6),
                fg:
                    widget.showAmounts
                        ? const Color(0xFFD32F2F)
                        : const Color(0xFF6B7280),
              ),
            ],
          ),
          if (_unallocated.abs() > 0.01) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFE0B2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFE65100)),
                  const SizedBox(width: 8),
                  Text(
                    widget.showAmounts
                        ? 'Unallocated: ${_fmtSigned(_unallocated)}'
                        : 'Unallocated: $kHiddenAmount',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFE65100),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pill({required String label, required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildSection(TagType type) {
    final isIncome = type == TagType.income;
    final title = isIncome ? 'Income' : 'Expenses';
    final accent = isIncome ? const Color(0xFF1B5E20) : const Color(0xFFD32F2F);
    final chipBg = isIncome ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE);
    final total = isIncome ? _totalIncome : _totalExpenses;
    final rows = _buildSectionAllocations(type);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                widget.showAmounts
                    ? '${isIncome ? '+' : '-'}${_fmtAmount(total)}'
                    : kHiddenAmount,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: widget.showAmounts ? accent : const Color(0xFF6B7280),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(8)),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.add, size: 16, color: accent),
                  onPressed: () => _addAllocation(type),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  const Icon(Icons.add_circle_outline, size: 24, color: Color(0xFFD0D0D0)),
                  const SizedBox(height: 4),
                  Text(
                    isIncome ? 'No income recorded' : 'No expenses recorded',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF9CA3AF)),
                  ),
                  Text(
                    'Tap + to add',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFFD0D0D0)),
                  ),
                ],
              ),
            )
          else
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: row.autoBalanced ? null : () => _editAllocation(type, row),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(8)),
                        child: Icon(
                          isIncome ? Icons.south_west : Icons.north_east,
                          size: 16,
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row.name,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (row.autoBalanced)
                              Text(
                                'Auto-balanced',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: const Color(0xFF9CA3AF)),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        widget.showAmounts
                            ? '${isIncome ? '+' : '-'}${_fmtAmount(row.amount)}'
                            : kHiddenAmount,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: widget.showAmounts ? accent : const Color(0xFF6B7280),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.close, size: 14, color: Color(0xFFD0D0D0)),
                        onPressed: row.autoBalanced ? null : () => _removeAllocation(type, row.tagId),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _loading
          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummaryHeader(),
                  const Divider(height: 1),
                  _buildSection(TagType.income),
                  const Divider(height: 1),
                  _buildSection(TagType.expense),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }
}

class _AllocationDraft {
  final int? tagId;
  final String? newCategoryName;
  final double amount;

  const _AllocationDraft({
    this.tagId,
    this.newCategoryName,
    required this.amount,
  });
}

class _SectionAllocation {
  final int tagId;
  final String name;
  final double amount;
  final bool autoBalanced;

  const _SectionAllocation({
    required this.tagId,
    required this.name,
    required this.amount,
    required this.autoBalanced,
  });
}

